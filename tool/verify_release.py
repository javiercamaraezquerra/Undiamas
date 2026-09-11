"""Verify production artifacts with Python stdlib, Android SDK and JDK17.

Checks the UPLOAD certificate, not Google's separate Play app-signing key.
Does not upload artifacts, contact Google, or read a private keystore.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

PACKAGE = "com.celsoriaapps.undiamas"
LABEL = "Un Día Más"
ENGLISH_LABEL = "One More Day"
APP_ID = "ca-app-pub-4402835110551152~8514445452"
BANNER_ID = "ca-app-pub-4402835110551152/9099084606"
TEST_BANNER_ID = "ca-app-pub-3940256099942544/6300978111"
ABIS = {"armeabi-v7a", "arm64-v8a", "x86_64"}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def run(arguments: list[str]) -> str:
    completed = subprocess.run(arguments, capture_output=True, text=True, encoding="utf-8")
    require(completed.returncode == 0,
            f"{Path(arguments[0]).name} failed: {completed.stderr.strip() or completed.stdout.strip()}")
    return completed.stdout


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_digest(path: Path) -> str:
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def protobuf(data: bytes) -> dict[int, list[bytes | int]]:
    """Read AAPT protobuf wire fields; reject malformed/truncated input."""
    position = 0

    def varint() -> int:
        nonlocal position
        value = 0
        for shift in range(0, 70, 7):
            require(position < len(data), "Truncated protobuf varint")
            byte = data[position]
            position += 1
            value |= (byte & 127) << shift
            if not byte & 128:
                return value
        raise ValueError("Oversized protobuf varint")

    fields: dict[int, list[bytes | int]] = {}
    while position < len(data):
        tag = varint()
        number, wire = tag >> 3, tag & 7
        require(number > 0, "Invalid protobuf field")
        if wire == 0:
            value: bytes | int = varint()
        else:
            require(wire in (1, 2, 5), "Unsupported protobuf wire type")
            size = varint() if wire == 2 else (8 if wire == 1 else 4)
            require(position + size <= len(data), "Truncated protobuf value")
            value = data[position:position + size]
            position += size
        fields.setdefault(number, []).append(value)
    return fields


def raw(fields: dict, number: int, default: bytes = b"") -> bytes:
    value = fields.get(number, [default])[0]
    require(isinstance(value, bytes), "Expected a protobuf message/string")
    return value


def text(fields: dict, number: int) -> str:
    return raw(fields, number).decode("utf-8")


def manifest_element(node: bytes) -> dict:
    fields = protobuf(raw(protobuf(node), 1))
    require(bool(fields), "Missing AAB XML element")
    attributes = {}
    for encoded in fields.get(4, []):
        attribute = protobuf(encoded)
        name = text(attribute, 2)
        value = text(attribute, 3)
        compiled = protobuf(raw(attribute, 6))
        reference = protobuf(raw(compiled, 1))
        primitive = protobuf(raw(compiled, 7))
        if not value:
            for number in (6, 7, 8):
                if number in primitive:
                    value = str(primitive[number][0])
                    break
        require(name not in attributes, f"Duplicate manifest attribute: {name}")
        attributes[name] = {"value": value, "reference": reference.get(2, [None])[0]}
    children = []
    for child_node in fields.get(5, []):
        if 1 in protobuf(child_node):
            children.append(manifest_element(child_node))
    return {"name": text(fields, 3), "attributes": attributes, "children": children}


def child(element: dict, name: str) -> dict:
    matches = [value for value in element["children"] if value["name"] == name]
    require(len(matches) == 1, f"Expected one AAB {name} element")
    return matches[0]


def attribute(element: dict, name: str) -> str:
    require(name in element["attributes"], f"Missing AAB attribute: {name}")
    return element["attributes"][name]["value"]


def resource_strings(data: bytes, resource_id: int) -> dict[str, str]:
    """Resolve the application-name reference in AAPT ResourceTable protobuf."""
    strings = {}
    for encoded_package in protobuf(data).get(2, []):
        package = protobuf(encoded_package)
        package_id = protobuf(raw(package, 1)).get(1, [0])[0]
        for encoded_type in package.get(3, []):
            resource_type = protobuf(encoded_type)
            type_id = protobuf(raw(resource_type, 1)).get(1, [0])[0]
            for encoded_entry in resource_type.get(3, []):
                entry = protobuf(encoded_entry)
                entry_id = protobuf(raw(entry, 1)).get(1, [0])[0]
                if (package_id << 24 | type_id << 16 | entry_id) != resource_id:
                    continue
                for encoded_value in entry.get(6, []):
                    config_value = protobuf(encoded_value)
                    configuration = protobuf(raw(config_value, 1))
                    locale = text(configuration, 3)
                    value = protobuf(raw(config_value, 2))
                    item = protobuf(raw(value, 4))
                    string = protobuf(raw(item, 2))
                    require(1 in string, "App label is not a simple compiled string")
                    strings[locale] = text(string, 1)
    require(bool(strings), "Cannot resolve the AAB application label")
    return strings


def verify_aab_metadata(bundle: zipfile.ZipFile, version_name: str, version_code: str) -> dict:
    manifest = manifest_element(bundle.read("base/manifest/AndroidManifest.xml"))
    require(manifest["name"] == "manifest", "Invalid AAB manifest root")
    require(attribute(manifest, "package") == PACKAGE, "Wrong AAB package/flavor")
    require(attribute(manifest, "versionCode") == version_code, "Wrong AAB version code")
    require(attribute(manifest, "versionName") == version_name, "Wrong AAB version name")
    sdk = child(manifest, "uses-sdk")
    require(attribute(sdk, "minSdkVersion") == "24", "Wrong AAB minimum API")
    require(attribute(sdk, "targetSdkVersion") == "36", "Wrong AAB target API")
    application = child(manifest, "application")
    require(application["attributes"].get("debuggable", {}).get("value", "0") in ("0", "false"),
            "The AAB is debuggable")
    labels = application["attributes"].get("label", {})
    if labels.get("reference") is not None:
        names = resource_strings(bundle.read("base/resources.pb"), labels["reference"])
    else:
        names = {"": labels.get("value", "")}
    require(names.get("") == LABEL, "Wrong default AAB application name")
    require(names.get("en") == ENGLISH_LABEL, "Wrong English AAB application name")
    require(not any("privacidad" in name.lower() for name in names.values()),
            "The AAB still has a preview label")
    app_ids = [attribute(item, "value") for item in application["children"]
               if item["name"] == "meta-data" and
               item["attributes"].get("name", {}).get("value") ==
               "com.google.android.gms.ads.APPLICATION_ID"]
    require(app_ids == [APP_ID], "Wrong AAB AdMob application identifier")
    return {"package": PACKAGE, "version_name": version_name, "version_code": version_code,
            "min_api": 24, "target_api": 36, "labels": names, "admob_app_id": APP_ID}


def verify_apk_metadata(badging: str, xml_tree: str, version_name: str, version_code: str) -> None:
    for expected in (f"package: name='{PACKAGE}'", f"versionCode='{version_code}'",
                     f"versionName='{version_name}'", "sdkVersion:'24'", "targetSdkVersion:'36'",
                     f"application-label:'{LABEL}'", f"application-label-en:'{ENGLISH_LABEL}'"):
        require(expected in badging, f"APK identity check failed: {expected}")
    require("application-debuggable" not in badging, "The APK is debuggable")
    require(APP_ID in xml_tree, "Wrong APK AdMob application identifier")
    require("ca-app-pub-3940256099942544~" not in xml_tree, "APK contains a preview AdMob app ID")


JAR_VERIFIER = r'''
import java.io.*;
import java.security.*;
import java.util.*;
import java.util.jar.*;
class VerifySignedBundle {
  public static void main(String[] args) throws Exception {
    int signed = 0;
    try (JarFile jar = new JarFile(args[0], true)) {
      var entries = jar.entries();
      while (entries.hasMoreElements()) {
        JarEntry entry = entries.nextElement();
        if (entry.isDirectory()) continue;
        try (InputStream input = jar.getInputStream(entry)) {
          input.transferTo(OutputStream.nullOutputStream());
        }
        if (entry.getName().startsWith("META-INF/")) continue;
        CodeSigner[] signers = entry.getCodeSigners();
        if (signers == null || signers.length != 1)
          throw new SecurityException("Unsigned or multiply signed bundle entry: " + entry.getName());
        byte[] certificate = signers[0].getSignerCertPath().getCertificates().get(0).getEncoded();
        String actual = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(certificate));
        if (!actual.equalsIgnoreCase(args[1])) throw new SecurityException("Unexpected upload certificate");
        signed++;
      }
    }
    if (signed == 0) throw new SecurityException("Bundle has no verified signed entries");
    System.out.println(signed);
  }
}
'''


def verify_bundle_signature(bundle: Path, expected: str, java: str) -> int:
    with tempfile.TemporaryDirectory(prefix="udm_public_signature_") as temporary:
        source = Path(temporary) / "VerifySignedBundle.java"
        source.write_text(JAR_VERIFIER, encoding="utf-8")
        return int(run([java, "--source", "17", str(source), str(bundle.resolve()), expected]).strip())


def verify_payloads(apk: zipfile.ZipFile, bundle: zipfile.ZipFile) -> None:
    apk_names = set(apk.namelist())
    bundle_names = set(bundle.namelist())
    require(len(apk_names) == len(apk.infolist()), "Duplicate APK ZIP entry")
    require(len(bundle_names) == len(bundle.infolist()), "Duplicate AAB ZIP entry")
    found_abis = {name.split('/')[1] for name in apk_names if name.startswith('lib/') and name.endswith('/libapp.so')}
    bundle_abis = {name.split('/')[2] for name in bundle_names if name.startswith('base/lib/') and name.endswith('/libapp.so')}
    require(found_abis == ABIS and bundle_abis == ABIS, "Release ABI set changed")
    for abi in sorted(ABIS):
        for library in ("libapp.so", "libflutter.so"):
            name = f"lib/{abi}/{library}"
            binary = apk.read(name)
            require(digest(binary) == digest(bundle.read(f"base/{name}")), f"APK/AAB native payload differs: {name}")
            if library == "libapp.so":
                require(BANNER_ID.encode() in binary, f"Production banner missing in {abi}")
                require(TEST_BANNER_ID.encode() not in binary, f"Preview advertising code in {abi}")
    apk_assets = {name for name in apk_names if name.startswith('assets/flutter_assets/') and not name.endswith('/')}
    bundle_assets = {name.removeprefix('base/') for name in bundle_names
                     if name.startswith('base/assets/flutter_assets/') and not name.endswith('/')}
    require(apk_assets == bundle_assets and bool(apk_assets), "APK/AAB Flutter asset set differs")
    for name in sorted(apk_assets):
        require(digest(apk.read(name)) == digest(bundle.read(f"base/{name}")), f"APK/AAB asset differs: {name}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--aab", type=Path, required=True)
    parser.add_argument("--certificate", type=Path, required=True, help="Public DER upload certificate, never the keystore")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected-upload-sha256", required=True, help="Independently verified Play upload-certificate digest")
    arguments = parser.parse_args()
    sdk = Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME") or "")
    tools = sdk / "build-tools/36.0.0"
    aapt = str(tools / ("aapt.exe" if os.name == "nt" else "aapt"))
    apksigner = str(tools / ("apksigner.bat" if os.name == "nt" else "apksigner"))
    java = shutil.which("java") or str(Path(os.environ["JAVA_HOME"]) / "bin/java")
    version = re.search(r"(?m)^version:\s*([0-9.]+)\+([0-9]+)", Path("pubspec.yaml").read_text(encoding="utf-8"))
    require(version is not None, "No explicit application version in pubspec.yaml")
    version_name, version_code = version.groups()
    expected = file_digest(arguments.certificate)
    normalized = re.sub(r"[^0-9a-f]", "", arguments.expected_upload_sha256.lower())
    require(len(normalized) == 64 and normalized == expected,
            "Keystore certificate differs from the verified Play upload certificate")
    signature = run([apksigner, "verify", "--verbose", "--print-certs", str(arguments.apk)])
    fingerprints = re.findall(r"Signer #\d+ certificate SHA-256 digest:\s*([0-9a-fA-F:]+)", signature)
    require(len(fingerprints) == 1 and fingerprints[0].replace(":", "").lower() == expected,
            "APK signer does not match the configured upload certificate")
    require("CN=Android Debug" not in signature, "A debug certificate cannot sign production")
    verify_apk_metadata(run([aapt, "dump", "badging", str(arguments.apk)]),
                        run([aapt, "dump", "xmltree", str(arguments.apk), "AndroidManifest.xml"]),
                        version_name, version_code)
    signed_entries = verify_bundle_signature(arguments.aab, expected, java)
    with zipfile.ZipFile(arguments.apk) as apk, zipfile.ZipFile(arguments.aab) as bundle:
        metadata = verify_aab_metadata(bundle, version_name, version_code)
        verify_payloads(apk, bundle)
    commit = run(["git", "rev-parse", "HEAD"]).strip()
    if os.environ.get("GITHUB_SHA"):
        require(commit == os.environ["GITHUB_SHA"], "Build checkout differs from the workflow commit")
    tracked = run(["git", "ls-files", "-z"]).split("\0")
    sources = {name: file_digest(Path(name)) for name in tracked if name and Path(name).is_file()}
    report = {"metadata": metadata, "upload_certificate_sha256": expected,
              "play_upload_certificate_independently_matched": True,
              "note": "This is the upload signature, not Google's installed Play app-signing certificate.",
              "aab_signed_entries_verified": signed_entries, "abis": sorted(ABIS),
              "production_banner_id": BANNER_ID, "commit": commit,
              "github_repository": os.environ.get("GITHUB_REPOSITORY"),
              "github_run_id": os.environ.get("GITHUB_RUN_ID"),
              "github_run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
              "configured_toolchain": {"flutter": "3.32.8", "java": "17", "ndk": "28.1.13356709", "android_build_tools": "36.0.0"},
              "artifacts": {arguments.apk.name: file_digest(arguments.apk), arguments.aab.name: file_digest(arguments.aab)},
              "source_sha256": sources}
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Verified production {version_name}+{version_code}; upload certificate SHA256 {expected}")


if __name__ == "__main__":
    main()
