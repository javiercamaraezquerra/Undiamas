import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:un_dia_mas/services/inventory_backup_archive.dart';
import 'package:un_dia_mas/services/inventory_photo_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Uint8List photo;
  late String id;
  late Map<String, Uint8List> imported;
  late InventoryBackupArchive archives;

  Map<String, dynamic> manifest({String? photoId, int version = 2}) => {
        'version': version,
        'udm': {
          'unknown': {'keep': true}
        },
        'diary': <dynamic>[
          <String, dynamic>{
            'text': '  Recuerdo 🙂\n',
            'mood': 2,
            'createdAt': '2026-09-14T19:20:00.000',
            'photoId': photoId
          }
        ]
      };

  Future<File> fixture(List<ArchiveFile> files) async {
    final output = OutputMemoryStream();
    final encoder = ZipEncoder()..startEncode(output);
    for (final file in files) {
      encoder.add(file);
    }
    encoder.endEncode();
    return File('${directory.path}${Platform.pathSeparator}fixture.zip')
      ..writeAsBytesSync(output.getBytes());
  }

  ArchiveFile jsonFile(Map<String, dynamic> data) {
    final bytes = utf8.encode(jsonEncode(data));
    return ArchiveFile('manifest.json', bytes.length, bytes)
      ..compression = CompressionType.none;
  }

  ArchiveFile imageFile({String? name, Uint8List? bytes}) => ArchiveFile(
      name ?? 'photos/$id.jpg', (bytes ?? photo).length, bytes ?? photo)
    ..compression = CompressionType.none;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('udm_archive_test_');
    photo = Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 6)));
    id = sha256.convert(photo).toString();
    imported = {};
    archives = InventoryBackupArchive(
      temporaryDirectory: () async => directory,
      readPhoto: (key) async {
        if (key != id) {
          throw const FileSystemException('Synthetic missing photo');
        }
        return photo;
      },
      validatePhoto: InventoryPhotoStore.validatePrepared,
      importPhoto: (key, bytes) async {
        imported[key] = bytes;
      },
    );
  });

  tearDown(() async {
    final root = await Directory.systemTemp.resolveSymbolicLinks();
    final actual = await directory.resolveSymbolicLinks();
    expect(
        actual.toLowerCase(),
        startsWith(
            '${root.toLowerCase()}${Platform.pathSeparator}udm_archive_test_'));
    await directory.delete(recursive: true);
  });

  test('photo and Unicode text round trip; immutable ID deduplicates files',
      () async {
    final data = manifest(photoId: id);
    (data['diary'] as List).add({...((data['diary'] as List).first as Map)});
    await archives.withWorkspace((workspace) async {
      final file = await archives.create(data, workspace);
      final result = await archives.read(file);
      expect(result, data);
      expect(imported.keys, [id]);
      expect(imported[id], photo);
      final input = InputFileStream(file.path);
      final zip = ZipDirectory()..read(input);
      expect(zip.fileHeaders, hasLength(2));
      expect(zip.fileHeaders.every((header) => header.compressionMethod == 0),
          isTrue);
      await input.close();
    });
    expect(await directory.list().toList(), isEmpty);
  });

  test('legacy map is converted without losing dates, text or unknown settings',
      () async {
    final legacy = manifest()..remove('version');
    ((legacy['diary'] as List).first as Map).remove('photoId');
    final before = jsonDecode(jsonEncode(legacy));
    await archives.withWorkspace((workspace) async {
      final result =
          await archives.read(await archives.create(legacy, workspace));
      expect(result['version'], 2);
      expect(result['udm'], legacy['udm']);
      expect((result['diary'] as List).first,
          {...((legacy['diary'] as List).first as Map), 'photoId': null});
      expect(imported, isEmpty);
    });
    expect(legacy, before);
  });

  test('restore on a new device encrypts the same photo with its own key',
      () async {
    final first = InventoryPhotoStore(
        directory: Directory('${directory.path}${Platform.pathSeparator}first'),
        key: Uint8List.fromList(List.generate(32, (i) => i)));
    final second = InventoryPhotoStore(
        directory:
            Directory('${directory.path}${Platform.pathSeparator}second'),
        key: Uint8List.fromList(List.generate(32, (i) => 255 - i)));
    await first.importPrepared(id, photo);
    final uploader = InventoryBackupArchive(
        readPhoto: first.read, temporaryDirectory: () async => directory);
    final downloader = InventoryBackupArchive(
        importPhoto: second.importPrepared,
        temporaryDirectory: () async => directory);
    await uploader.withWorkspace((workspace) async {
      final data = manifest(photoId: id);
      final copy = await uploader.create(data, workspace);
      await first.clear();
      expect(await downloader.read(copy), data);
      expect(await second.read(id), photo);
    });
  });

  test('photo-only entry preserves empty text', () async {
    final data = manifest(photoId: id);
    ((data['diary'] as List).first as Map)['text'] = '';
    await archives.withWorkspace((workspace) async {
      expect(await archives.read(await archives.create(data, workspace)), data);
    });
  });

  test('missing photo refuses archive before importing anything', () async {
    final file = await fixture([jsonFile(manifest(photoId: id))]);
    await expectLater(archives.read(file), throwsFormatException);
    expect(imported, isEmpty);
  });

  test('unreferenced photo is rejected, not silently ignored', () async {
    final file = await fixture([jsonFile(manifest()), imageFile()]);
    await expectLater(archives.read(file), throwsFormatException);
    expect(imported, isEmpty);
  });

  test('all photo hashes are checked before first immutable import', () async {
    final otherId = List.filled(64, 'f').join();
    final data = manifest(photoId: id);
    (data['diary'] as List)
        .add({...((data['diary'] as List).first as Map), 'photoId': otherId});
    final file = await fixture(
        [jsonFile(data), imageFile(), imageFile(name: 'photos/$otherId.jpg')]);
    await expectLater(
        archives.read(file), throwsA(isA<InventoryPhotoException>()));
    expect(imported, isEmpty);
  });

  test('JPEG validation is required even with matching ID and ZIP CRC',
      () async {
    final invalid = Uint8List.fromList(utf8.encode('not a photograph'));
    final invalidId = sha256.convert(invalid).toString();
    final file = await fixture([
      jsonFile(manifest(photoId: invalidId)),
      imageFile(name: 'photos/$invalidId.jpg', bytes: invalid)
    ]);
    await expectLater(
        archives.read(file), throwsA(isA<InventoryPhotoException>()));
    expect(imported, isEmpty);
  });

  for (final badName in [
    '../outside.jpg',
    '/outside.jpg',
    'photos\\bad.jpg',
    'manifest.json'
  ]) {
    test('rejects traversal or duplicate entry: $badName', () async {
      final file = await fixture(
          [jsonFile(manifest(photoId: id)), imageFile(name: badName)]);
      await expectLater(archives.read(file), throwsFormatException);
      expect(imported, isEmpty);
    });
  }

  test('symlink and compressed members are unsupported before decoding',
      () async {
    var file = await fixture(
        [jsonFile(manifest(photoId: id)), imageFile()..mode = 0xa1ff]);
    await expectLater(archives.read(file), throwsFormatException);
    file = await fixture([
      jsonFile(manifest(photoId: id)),
      imageFile()..compression = CompressionType.deflate
    ]);
    await expectLater(archives.read(file), throwsFormatException);
    expect(imported, isEmpty);
  });

  for (final badVersion in [null, 1, 3, 2.0, '2']) {
    test('rejects unsupported manifest version $badVersion', () async {
      final data = manifest();
      if (badVersion == null) {
        data.remove('version');
      } else {
        data['version'] = badVersion;
      }
      final file = await fixture([jsonFile(data)]);
      await expectLater(archives.read(file), throwsFormatException);
      expect(imported, isEmpty);
    });
  }

  test('truncated and tampered archives are rejected', () async {
    final file = await fixture([jsonFile(manifest(photoId: id)), imageFile()]);
    final bytes = await file.readAsBytes();
    await file.writeAsBytes(bytes.sublist(0, bytes.length - 4));
    await expectLater(archives.read(file), throwsFormatException);
    bytes[30 + 'manifest.json'.length + 3] ^= 1;
    await file.writeAsBytes(bytes);
    await expectLater(archives.read(file), throwsFormatException);
    expect(imported, isEmpty);
  });

  test('temporary plaintext is cleaned on failed create and abandoned startup',
      () async {
    await expectLater(
        archives.withWorkspace((workspace) => archives.create(
            manifest(photoId: List.filled(64, '0').join()), workspace)),
        throwsA(isA<FileSystemException>()));
    expect(await directory.list().toList(), isEmpty);
    await Directory(
            '${directory.path}${Platform.pathSeparator}udm_backup_work_abandoned')
        .create();
    final unrelated =
        await Directory('${directory.path}${Platform.pathSeparator}unrelated')
            .create();
    await archives.cleanAbandonedWorkspaces();
    expect(await directory.list().map((entity) => entity.path).toList(),
        [unrelated.path]);
  });
}
