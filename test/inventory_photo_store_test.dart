import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;
import 'package:crypto/crypto.dart' as hashes;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:un_dia_mas/services/inventory_photo_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late InventoryPhotoStore store;
  final key = Uint8List.fromList(List<int>.generate(32, (i) => i));

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('udm_photo_store_test_');
    store = InventoryPhotoStore(directory: directory, key: key);
  });

  tearDown(() async {
    final actual = await directory.resolveSymbolicLinks();
    final root = await Directory.systemTemp.resolveSymbolicLinks();
    if (!actual
            .toLowerCase()
            .startsWith('$root${Platform.pathSeparator}'.toLowerCase()) ||
        !directory.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last
            .startsWith('udm_photo_store_test_')) {
      throw StateError('Unexpected fixture path');
    }
    await directory.delete(recursive: true);
  });

  File media(String id) =>
      File('${directory.path}${Platform.pathSeparator}$id.udm');

  test(
      'copies and encrypts photo; fresh instance can read exact normalized JPEG',
      () async {
    final source = _photo();
    final original = Uint8List.fromList(source);
    final id = await store.importImage(source);
    final jpeg = await store.read(id);
    final encrypted = await media(id).readAsBytes();
    expect(InventoryPhotoStore.isValidId(id), isTrue);
    expect(hashes.sha256.convert(jpeg).toString(), id);
    expect(source, original);
    expect(encrypted, isNot(jpeg));
    expect(encrypted.length, jpeg.length + 36);
    expect(encrypted.take(8), ascii.encode('UDMAE001'));
    final reopened = InventoryPhotoStore(directory: directory, key: key);
    expect(await reopened.read(id), jpeg);
  });

  test(
      'deduplicates identical normalized content without rewriting valid ciphertext',
      () async {
    final source = _photo();
    final id = await store.importImage(source);
    final before = await media(id).readAsBytes();
    expect(await store.importImage(source), id);
    expect(await media(id).readAsBytes(), before);
    expect(await directory.list().length, 1);
  });

  test('bakes EXIF rotation and removes GPS, caption, and orientation metadata',
      () async {
    final sourceImage = img.Image(width: 40, height: 20);
    img.fillRect(sourceImage,
        x1: 0, y1: 0, x2: 19, y2: 19, color: img.ColorRgb8(240, 10, 10));
    img.fillRect(sourceImage,
        x1: 20, y1: 0, x2: 39, y2: 19, color: img.ColorRgb8(10, 10, 240));
    sourceImage.exif.imageIfd.orientation = 6;
    sourceImage.exif.imageIfd.imageDescription =
        'Private location and private caption';
    sourceImage.exif.gpsIfd
        .setGpsLocation(latitude: 40.4168, longitude: -3.7038);
    final source = img.encodeJpg(sourceImage, quality: 100);
    final id = await store.importImage(source);
    final jpeg = await store.read(id);
    final result = img.decodeJpg(jpeg)!;
    expect(result.width, 20);
    expect(result.height, 40);
    expect(result.getPixel(10, 5).r, greaterThan(200));
    expect(result.getPixel(10, 35).b, greaterThan(200));
    expect(result.exif.isEmpty, isTrue);
    expect(latin1.decode(jpeg), isNot(contains('Private location')));
    expect(latin1.decode(jpeg), isNot(contains('Exif')));
  });

  test('resizes large landscape and portrait images with aspect ratio intact',
      () async {
    for (final dimensions in [(2000, 1000), (1000, 2000)]) {
      final source = img.Image(width: dimensions.$1, height: dimensions.$2);
      final id = await store.importImage(img.encodePng(source));
      final result = img.decodeJpg(await store.read(id))!;
      expect(max(result.width, result.height), 1600);
      expect(min(result.width, result.height), 800);
      expect((await store.read(id)).length,
          lessThanOrEqualTo(InventoryPhotoStore.maxPhotoBytes));
    }
  });

  test('EXIF orientation survives an additional APP1 XMP segment', () async {
    final source = img.Image(width: 40, height: 20);
    source.exif.imageIfd.orientation = 6;
    final jpeg = img.encodeJpg(source);
    var tableOffset = -1;
    for (var i = 2; i < jpeg.length - 1; i++) {
      if (jpeg[i] == 0xff && jpeg[i + 1] == 0xdb) {
        tableOffset = i;
        break;
      }
    }
    expect(tableOffset, greaterThan(2));
    final payload =
        ascii.encode('http://ns.adobe.com/xap/1.0/\u0000private XMP');
    final app1 = Uint8List(payload.length + 4);
    app1[0] = 0xff;
    app1[1] = 0xe1;
    ByteData.sublistView(app1).setUint16(2, payload.length + 2);
    app1.setRange(4, app1.length, payload);
    final withXmp = Uint8List.fromList([
      ...jpeg.sublist(0, tableOffset),
      ...app1,
      ...jpeg.sublist(tableOffset)
    ]);
    final result =
        img.decodeJpg(await store.read(await store.importImage(withXmp)))!;
    expect(result.width, 20);
    expect(result.height, 40);
    expect(result.exif.isEmpty, isTrue);
  });

  test(
      'transparent screenshot uses white backing and strips ancillary PNG metadata',
      () async {
    final source = img.Image(width: 6, height: 6, numChannels: 4);
    final png = img.encodePng(source);
    final chunk = Uint8List(12 + 4096);
    ByteData.sublistView(chunk).setUint32(0, 4096);
    chunk.setRange(4, 8, ascii.encode('zTXt'));
    // Compressed metadata is never decompressed, including malformed payloads.
    final withMetadata = Uint8List.fromList(
        [...png.sublist(0, 33), ...chunk, ...png.sublist(33)]);
    final result =
        img.decodeJpg(await store.read(await store.importImage(withMetadata)))!;
    expect(result.getPixel(2, 2).r, greaterThan(245));
    expect(result.getPixel(2, 2).g, greaterThan(245));
    expect(result.getPixel(2, 2).b, greaterThan(245));
  });

  test('bounds PNG decompression by actual scanline size before image decode',
      () async {
    final png = img.encodePng(img.Image(width: 1, height: 1));
    final bombData = Uint8List.fromList(zlib.encode(Uint8List(64 * 1024)));
    final chunk = Uint8List(bombData.length + 12);
    ByteData.sublistView(chunk).setUint32(0, bombData.length);
    chunk.setRange(4, 8, ascii.encode('IDAT'));
    chunk.setRange(8, 8 + bombData.length, bombData);
    ByteData.sublistView(chunk).setUint32(
        chunk.length - 4, archive.getCrc32(chunk.sublist(4, chunk.length - 4)));
    final bomb = Uint8List.fromList(
        [...png.sublist(0, 33), ...chunk, ...png.sublist(png.length - 12)]);
    await expectLater(
        store.importImage(bomb), throwsA(isA<InventoryPhotoException>()));
    expect(await directory.list().length, 0);
  });

  test('imports a still WebP photograph as normalized JPEG', () async {
    final webp = base64
        .decode('UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADsD+JaQAA3AAAAAA');
    final result =
        img.decodeJpg(await store.read(await store.importImage(webp)))!;
    expect(result.width, 1);
    expect(result.height, 1);
  });

  test(
      'validates WebP frame bounds even when extended canvas claims a small size',
      () async {
    final webp = base64
        .decode('UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADsD+JaQAA3AAAAAA');
    final canvas = Uint8List(18);
    canvas.setRange(0, 4, ascii.encode('VP8X'));
    ByteData.sublistView(canvas).setUint32(4, 10, Endian.little);
    ByteData.sublistView(webp).setUint16(26, 0x3fff, Endian.little);
    final inconsistent = Uint8List.fromList(
        [...webp.sublist(0, 12), ...canvas, ...webp.sublist(12)]);
    ByteData.sublistView(inconsistent)
        .setUint32(4, inconsistent.length - 8, Endian.little);
    await expectLater(store.importImage(inconsistent),
        throwsA(isA<InventoryPhotoException>()));
    expect(await directory.list().length, 0);
  });

  test('detects tampering and preserves original bytes after failed repair',
      () async {
    final id = await store.importImage(_photo());
    final valid = await store.read(id);
    final corrupt = await media(id).readAsBytes();
    corrupt[corrupt.length - 1] ^= 1;
    await media(id).writeAsBytes(corrupt, flush: true);
    await expectLater(store.read(id), throwsA(isA<InventoryPhotoException>()));
    final failing = InventoryPhotoStore(
        directory: directory,
        key: key,
        beforeStep: (step) async {
          if (step == 'beforeCommit') {
            throw const FileSystemException('Simulated disk failure');
          }
        });
    await expectLater(
        failing.importPrepared(id, valid), throwsA(isA<FileSystemException>()));
    expect(await media(id).readAsBytes(), corrupt);
    expect(await directory.list().length, 1);
    await store.importPrepared(id, valid);
    expect(await store.read(id), valid);
  });

  test('wrong key cannot decrypt a stored photograph', () async {
    final id = await store.importImage(_photo());
    final otherKey =
        InventoryPhotoStore(directory: directory, key: Uint8List(32));
    await expectLater(
        otherKey.read(id), throwsA(isA<InventoryPhotoException>()));
    expect(await store.read(id), isNotEmpty);
  });

  test(
      'authenticated record name prevents ciphertext being swapped between IDs',
      () async {
    final first = await store.importImage(_photo());
    final second = await store.importImage(_photo(red: 20));
    await media(second)
        .writeAsBytes(await media(first).readAsBytes(), flush: true);
    await expectLater(
        store.read(second), throwsA(isA<InventoryPhotoException>()));
    expect(await store.read(first), isNotEmpty);
  });

  test('prune retains referenced photos and ignores unrelated files', () async {
    final retained = await store.importImage(_photo());
    final unreferenced = await store.importImage(_photo(red: 20));
    final unrelated =
        File('${directory.path}${Platform.pathSeparator}keep.txt');
    await unrelated.writeAsString('untouched');
    await store.prune({retained});
    expect(await media(retained).exists(), isTrue);
    expect(await media(unreferenced).exists(), isFalse);
    expect(await unrelated.readAsString(), 'untouched');
    await store.clear();
    expect(await media(retained).exists(), isFalse);
    expect(await unrelated.exists(), isTrue);
  });

  test('deleting a missing photo is safe and does not alter other records',
      () async {
    final id = await store.importImage(_photo());
    await store.delete('0' * 64);
    await store.delete(id);
    await store.delete(id);
    expect(await directory.list().length, 0);
  });

  test('prune snapshots retained IDs before asynchronous cleanup starts',
      () async {
    final id = await store.importImage(_photo());
    final retained = {id};
    final cleanup = store.prune(retained);
    retained.clear();
    await cleanup;
    expect(await store.read(id), isNotEmpty);
  });

  test('invalid IDs cannot escape private directory', () async {
    for (final id in [
      '../outside',
      '..\\outside',
      '/tmp/a',
      'A' * 64,
      'a' * 63,
      '${'a' * 64}\n'
    ]) {
      expect(InventoryPhotoStore.isValidId(id), isFalse);
      expect(() => store.read(id), throwsA(isA<InventoryPhotoException>()));
      expect(() => store.delete(id), throwsA(isA<InventoryPhotoException>()));
      expect(() => store.prune({id}), throwsA(isA<InventoryPhotoException>()));
    }
    expect(await directory.list().length, 0);
  });

  test('rejects oversized source bytes before decoding or storing', () async {
    await expectLater(
        store.importImage(Uint8List(InventoryPhotoStore.maxSourceBytes + 1)),
        throwsA(isA<InventoryPhotoException>()));
    expect(await directory.list().length, 0);
  });

  test('rejects declared huge PNG dimensions before pixel allocation',
      () async {
    final png = img.encodePng(img.Image(width: 1, height: 1));
    ByteData.sublistView(png).setUint32(16, 0x7fffffff);
    ByteData.sublistView(png).setUint32(20, 0x7fffffff);
    await expectLater(
        store.importImage(png), throwsA(isA<InventoryPhotoException>()));
    expect(await directory.list().length, 0);
  });

  test('rejects declared huge JPEG dimensions before decoder DCT allocation',
      () async {
    final jpeg = _photo();
    for (var i = 0; i + 8 < jpeg.length; i++) {
      if (jpeg[i] == 0xff && jpeg[i + 1] == 0xc0) {
        ByteData.sublistView(jpeg).setUint16(i + 5, 65535);
        ByteData.sublistView(jpeg).setUint16(i + 7, 65535);
        break;
      }
    }
    await expectLater(
        store.importImage(jpeg), throwsA(isA<InventoryPhotoException>()));
    expect(await directory.list().length, 0);
  });

  test('rejects corrupt, truncated, and non-image input without persisting',
      () async {
    for (final bytes in [
      Uint8List(0),
      Uint8List.fromList(utf8.encode('not an image')),
      _photo().sublist(0, 70),
      _photo().sublist(0, _photo().length - 2)
    ]) {
      await expectLater(
          store.importImage(bytes), throwsA(isA<InventoryPhotoException>()));
    }
    expect(await directory.list().length, 0);
  });

  test(
      'prepared import validates content hash, exact JPEG and metadata restrictions',
      () async {
    final source = img.Image(width: 10, height: 10);
    source.exif.imageIfd.imageDescription =
        'must not enter a normalized backup';
    final metadata = img.encodeJpg(source);
    final png = img.encodePng(img.Image(width: 10, height: 10));
    for (final bytes in [metadata, png]) {
      final id = hashes.sha256.convert(bytes).toString();
      await expectLater(store.importPrepared(id, bytes),
          throwsA(isA<InventoryPhotoException>()));
    }
    await expectLater(store.importPrepared('0' * 64, _photo()),
        throwsA(isA<InventoryPhotoException>()));
    expect(await directory.list().length, 0);
  });

  test('validation-only does not persist media, import preserves byte identity',
      () async {
    final jpeg = _photo();
    final id = hashes.sha256.convert(jpeg).toString();
    await InventoryPhotoStore.validatePrepared(id, jpeg);
    expect(await directory.list().length, 0);
    await store.importPrepared(id, jpeg);
    expect(await store.read(id), jpeg);
  });

  test(
      'prepared import owns its bytes during asynchronous validation and write',
      () async {
    final jpeg = _photo();
    final expected = Uint8List.fromList(jpeg);
    final id = hashes.sha256.convert(jpeg).toString();
    final importing = store.importPrepared(id, jpeg);
    jpeg[0] = 0;
    await importing;
    expect(await store.read(id), expected);
  });

  test(
      'write failure never leaves an apparently committed photo or plaintext temp',
      () async {
    final failing = InventoryPhotoStore(
        directory: directory,
        key: key,
        beforeStep: (step) async {
          if (step == 'beforeCommit') {
            throw const FileSystemException('Simulated out of space');
          }
        });
    await expectLater(
        failing.importImage(_photo()), throwsA(isA<FileSystemException>()));
    expect(await directory.list().length, 0);
    expect(await store.importImage(_photo()), isNotEmpty);
  });
}

Uint8List _photo({int red = 200}) {
  final image = img.Image(width: 16, height: 12);
  img.fill(image, color: img.ColorRgb8(red, 70, 90));
  return img.encodeJpg(image);
}
