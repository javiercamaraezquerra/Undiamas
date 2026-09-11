"""Small synthetic APK/AAB fixtures; no private certificates or user data."""
import io
import unittest
import zipfile

import verify_release as release


def varint(value):
    result = bytearray()
    while value >= 128:
        result.append((value & 127) | 128)
        value >>= 7
    result.append(value)
    return bytes(result)


def field(number, value):
    if isinstance(value, str):
        value = value.encode("utf-8")
    if isinstance(value, int):
        return varint(number << 3) + varint(value)
    return varint(number << 3 | 2) + varint(len(value)) + value


def message(*values):
    return b"".join(field(number, value) for number, value in values)


def xml(name, attributes, children=()):
    encoded = field(3, name)
    for key, value in attributes.items():
        attribute = field(2, key)
        if isinstance(value, int):
            # The application label is a compiled resource reference.
            attribute += field(6, field(1, field(2, value)))
        else:
            attribute += field(3, value)
        encoded += field(4, attribute)
    encoded += b"".join(field(5, child) for child in children)
    return field(1, encoded)


def resources(labels):
    entry = message((1, field(1, 28)), (2, "app_name"))
    for locale, label in labels.items():
        entry += field(6, message(
            (1, field(3, locale)), (2, field(4, field(2, field(1, label))))))
    resource_type = message((1, field(1, 15)), (2, "string"), (3, entry))
    package = message((1, field(1, 127)), (2, release.PACKAGE), (3, resource_type))
    return field(2, package)


def archive(files):
    data = io.BytesIO()
    with zipfile.ZipFile(data, "w") as output:
        for name, content in files.items():
            output.writestr(name, content)
    data.seek(0)
    return zipfile.ZipFile(data)


def bundle_fixture(*, package=release.PACKAGE, target="36", version="23",
                   name=release.LABEL, english=release.ENGLISH_LABEL,
                   ads=release.APP_ID, debug="false"):
    app = xml("application", {"label": 0x7F0F001C, "debuggable": debug}, [
        xml("meta-data", {"name": "com.google.android.gms.ads.APPLICATION_ID", "value": ads})])
    manifest = xml("manifest", {"package": package, "versionCode": version,
                               "versionName": "1.0.3"}, [
        xml("uses-sdk", {"minSdkVersion": "24", "targetSdkVersion": target}), app])
    return archive({"base/manifest/AndroidManifest.xml": manifest,
                    "base/resources.pb": resources({"": name, "en": english})})


def payload_files():
    files = {"assets/flutter_assets/assets/reflections.json": b'["original text"]'}
    for abi in release.ABIS:
        files[f"lib/{abi}/libapp.so"] = b"fixture:" + release.BANNER_ID.encode()
        files[f"lib/{abi}/libflutter.so"] = b"fixture engine"
    return files


class ProtobufTest(unittest.TestCase):
    def test_repeated_fields_and_multibyte_varint(self):
        self.assertEqual(release.protobuf(message((2, "one"), (2, "two"), (9, 123456))),
                         {2: [b"one", b"two"], 9: [123456]})

    def test_malformed_wire_values_rejected(self):
        for data in (b"\x00", b"\x80", b"\x08" + b"\x80" * 10,
                     b"\x12\x04ab", b"\x09ab", b"\x0dab", b"\x0b"):
            with self.subTest(data=data), self.assertRaises(ValueError):
                release.protobuf(data)

    def test_resource_reference_and_locales(self):
        labels = {"": release.LABEL, "en": release.ENGLISH_LABEL}
        self.assertEqual(release.resource_strings(resources(labels), 0x7F0F001C), labels)
        with self.assertRaises(ValueError):
            release.resource_strings(resources(labels), 0x7F0F001D)

    def test_compiled_numeric_manifest_attribute(self):
        encoded = message((3, "uses-sdk"), (4, message(
            (2, "targetSdkVersion"), (6, field(7, field(6, 36))))))
        self.assertEqual(release.attribute(release.manifest_element(field(1, encoded)),
                                           "targetSdkVersion"), "36")

    def test_duplicate_manifest_attribute_rejected(self):
        attribute = message((2, "package"), (3, release.PACKAGE))
        with self.assertRaises(ValueError):
            release.manifest_element(field(1, message((3, "manifest"),
                                                     (4, attribute), (4, attribute))))


class MetadataTest(unittest.TestCase):
    def test_valid_production_bundle(self):
        with bundle_fixture() as bundle:
            result = release.verify_aab_metadata(bundle, "1.0.3", "23")
        self.assertEqual(result["labels"], {"": release.LABEL, "en": release.ENGLISH_LABEL})
        self.assertEqual(result["target_api"], 36)

    def test_preview_or_changed_production_identity_rejected(self):
        for changed in ({"package": release.PACKAGE + ".privacidad"}, {"target": "35"},
                        {"version": "22"}, {"name": "Un día más"}, {"english": "Privacy"},
                        {"ads": "ca-app-pub-3940256099942544~3347511713"}, {"debug": "true"}):
            with self.subTest(changed=changed), bundle_fixture(**changed) as bundle:
                with self.assertRaises(ValueError):
                    release.verify_aab_metadata(bundle, "1.0.3", "23")

    def test_missing_manifest_rejected(self):
        with archive({}) as bundle, self.assertRaises(KeyError):
            release.verify_aab_metadata(bundle, "1.0.3", "23")

    def test_apk_identity_and_debugging(self):
        badging = (f"package: name='{release.PACKAGE}' versionCode='23' versionName='1.0.3'\n"
                   f"sdkVersion:'24'\ntargetSdkVersion:'36'\napplication-label:'{release.LABEL}'\n"
                   f"application-label-en:'{release.ENGLISH_LABEL}'")
        release.verify_apk_metadata(badging, release.APP_ID, "1.0.3", "23")
        for altered in (badging.replace("'36'", "'35'"), badging + "\napplication-debuggable",
                        badging.replace(release.PACKAGE, release.PACKAGE + ".privacidad")):
            with self.subTest(altered=altered), self.assertRaises(ValueError):
                release.verify_apk_metadata(altered, release.APP_ID, "1.0.3", "23")
        with self.assertRaises(ValueError):
            release.verify_apk_metadata(badging, "wrong app ID", "1.0.3", "23")


class PayloadTest(unittest.TestCase):
    def check(self, apk_files, bundle_files):
        with archive(apk_files) as apk, archive(bundle_files) as bundle:
            release.verify_payloads(apk, bundle)

    def test_identical_flavors_and_assets_pass(self):
        files = payload_files()
        self.check(files, {"base/" + name: data for name, data in files.items()})

    def test_missing_abi_rejected(self):
        files = payload_files()
        bundle = {"base/" + name: data for name, data in files.items()}
        del files["lib/x86_64/libapp.so"]
        with self.assertRaisesRegex(ValueError, "ABI"):
            self.check(files, bundle)

    def test_changed_native_payload_rejected(self):
        files = payload_files()
        bundle = {"base/" + name: data for name, data in files.items()}
        bundle["base/lib/arm64-v8a/libflutter.so"] = b"different engine"
        with self.assertRaisesRegex(ValueError, "native payload"):
            self.check(files, bundle)

    def test_preview_banner_or_missing_production_banner_rejected(self):
        for binary in (b"no ID", release.BANNER_ID.encode() + release.TEST_BANNER_ID.encode()):
            files = payload_files()
            files["lib/arm64-v8a/libapp.so"] = binary
            with self.subTest(binary=binary), self.assertRaises(ValueError):
                self.check(files, {"base/" + name: data for name, data in files.items()})

    def test_changed_asset_or_asset_set_rejected(self):
        files = payload_files()
        for change in ("bytes", "new file"):
            bundle = {"base/" + name: data for name, data in files.items()}
            name = "base/assets/flutter_assets/" + (
                "assets/reflections.json" if change == "bytes" else "unexpected")
            bundle[name] = b"different contents"
            with self.subTest(change=change), self.assertRaisesRegex(ValueError, "asset"):
                self.check(files, bundle)


if __name__ == "__main__":
    unittest.main()
