import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as paths;
import 'package:un_dia_mas/services/inventory_encrypted_file.dart';
import 'package:un_dia_mas/services/journal_draft_store.dart';
import 'package:un_dia_mas/services/picker_photo_cache_cleaner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixture;
  late Directory cache;
  late Directory state;
  late PickerPhotoCacheCleaner cleaner;
  final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
  const firstUuid = '12345678-1234-4234-9234-123456789abc';
  const secondUuid = '23456789-2345-4345-a345-23456789abcd';

  PickerPhotoCacheCleaner createCleaner(
          {Future<void> Function(String)? beforeStep}) =>
      PickerPhotoCacheCleaner(
          temporaryDirectory: cache,
          stateDirectory: state,
          key: key,
          beforeStep: beforeStep);

  Future<File> file(String relative,
      [String contents = 'private chosen photo']) async {
    final result = File(paths.join(cache.path, relative));
    await result.parent.create(recursive: true);
    await result.writeAsString(contents, flush: true);
    return result;
  }

  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('udm_picker_cache_test_');
    cache = await Directory(paths.join(fixture.path, 'cache')).create();
    state = await Directory(paths.join(fixture.path, 'state')).create();
    cleaner = createCleaner();
  });

  tearDown(() async {
    final actual = await fixture.resolveSymbolicLinks();
    final root = await Directory.systemTemp.resolveSymbolicLinks();
    if (!paths.isWithin(root, actual) ||
        !paths.basename(actual).startsWith('udm_picker_cache_test_')) {
      throw StateError('Unexpected fixture path');
    }
    await fixture.delete(recursive: true);
  });

  test(
      'deletes only registered chosen gallery copy and its empty UUID directory',
      () async {
    final chosen = await file(paths.join(firstUuid, 'Mi foto íntima.jpg'));
    expect(await cleaner.registerPickedPath(chosen.path), isTrue);
    await cleaner.cleanupPickedPath(chosen.path);
    expect(await chosen.exists(), isFalse);
    expect(await chosen.parent.exists(), isFalse);
    expect(await state.list().length, 0);
  });

  test(
      'preserves other files in the same UUID directory and all unregistered UUIDs',
      () async {
    final chosen = await file(paths.join(firstUuid, 'photo.jpg'));
    final sibling =
        await file(paths.join(firstUuid, 'other.jpg'), 'another SDK file');
    final unregistered =
        await file(paths.join(secondUuid, 'photo.jpg'), 'not selected');
    expect(await cleaner.registerPickedPath(chosen.path), isTrue);
    await cleaner.clear();
    expect(await chosen.exists(), isFalse);
    expect(await sibling.readAsString(), 'another SDK file');
    expect(await unregistered.readAsString(), 'not selected');
    expect(await chosen.parent.exists(), isTrue);
  });

  test('can delete returned camera file at cache root without removing root',
      () async {
    final camera = await file('${firstUuid}123456789012345.jpg');
    expect(await cleaner.registerPickedPath(camera.path), isTrue);
    await cleaner.cleanupPickedPath(camera.path);
    expect(await camera.exists(), isFalse);
    expect(await cache.exists(), isTrue);
  });

  test('never cleans an unregistered path even if it looks like a picker UUID',
      () async {
    final unknown = await file(paths.join(firstUuid, 'photo.jpg'));
    await cleaner.cleanupPickedPath(unknown.path);
    await cleaner.cleanupStale();
    expect(await unknown.exists(), isTrue);
  });

  test(
      'rejects gallery original outside cache, sibling-prefix paths, traversal and other cache files',
      () async {
    final outside = File(paths.join(fixture.path, 'gallery.jpg'));
    await outside.writeAsString('gallery original');
    final similarlyNamed =
        File(paths.join(fixture.path, 'cache-other', firstUuid, 'photo.jpg'));
    await similarlyNamed.parent.create(recursive: true);
    await similarlyNamed.writeAsString('other cache');
    final unrelated = await file('sdk-image.jpg');
    for (final candidate in [
      outside.path,
      similarlyNamed.path,
      unrelated.path,
      paths.join(cache.path, firstUuid, '..', '..', 'gallery.jpg'),
      'relative.jpg'
    ]) {
      expect(await cleaner.registerPickedPath(candidate), isFalse);
      await cleaner.cleanupPickedPath(candidate);
    }
    expect(await outside.readAsString(), 'gallery original');
    expect(await similarlyNamed.readAsString(), 'other cache');
    expect(await unrelated.exists(), isTrue);
    expect(await state.list().length, 0);
  });

  test('persists encrypted ownership registry across process recreation',
      () async {
    final chosen =
        await file(paths.join(firstUuid, 'Private original filename.jpg'));
    await cleaner.registerPickedPath(chosen.path);
    final registry = File(paths.join(state.path, 'picker-cache.udm'));
    expect(latin1.decode(await registry.readAsBytes()),
        isNot(contains('Private original')));
    await createCleaner().cleanupStale();
    expect(await chosen.exists(), isFalse);
    expect(await registry.exists(), isFalse);
  });

  test('retains an active recovered file and snapshots the retained set',
      () async {
    final active = await file(paths.join(firstUuid, 'active.jpg'));
    final stale = await file(paths.join(secondUuid, 'stale.jpg'));
    await cleaner.registerPickedPath(active.path);
    await cleaner.registerPickedPath(stale.path);
    final retained = {active.path};
    final cleaning = cleaner.cleanupStale(retainedPaths: retained);
    retained.clear();
    await cleaning;
    expect(await active.exists(), isTrue);
    expect(await stale.exists(), isFalse);
    await cleaner.cleanupPickedPath(active.path);
    expect(await active.exists(), isFalse);
  });

  test(
      'a missing cached file or evicted cache does not leave an orphan registry on reset',
      () async {
    final chosen = await file(paths.join(firstUuid, 'photo.jpg'));
    await cleaner.registerPickedPath(chosen.path);
    await chosen.delete();
    await chosen.parent.delete();
    await cache.delete();
    await cleaner.clear();
    expect(await state.list().length, 0);
  });

  test('draft clearing does not remove picker ownership before cache cleanup',
      () async {
    final chosen = await file(paths.join(firstUuid, 'photo.jpg'));
    final draftStore = JournalDraftStore(directory: state, key: key);
    await draftStore
        .save(const JournalDraft(text: 'Keep ownership independent'));
    await cleaner.registerPickedPath(chosen.path);
    await draftStore.clear();
    expect(await File(paths.join(state.path, 'picker-cache.udm')).exists(),
        isTrue);
    await cleaner.clear();
    expect(await chosen.exists(), isFalse);
    expect(await state.list().length, 0);
  });

  test(
      'registration failure does not delete an uncommitted path or damage prior registry',
      () async {
    final first = await file(paths.join(firstUuid, 'first.jpg'));
    final second = await file(paths.join(secondUuid, 'second.jpg'));
    await cleaner.registerPickedPath(first.path);
    final failing = createCleaner(beforeStep: (step) async {
      if (step == 'beforeCommit') {
        throw const FileSystemException('Simulated disk failure');
      }
    });
    await expectLater(failing.registerPickedPath(second.path),
        throwsA(isA<FileSystemException>()));
    await cleaner.clear();
    expect(await first.exists(), isFalse);
    expect(await second.exists(), isTrue);
  });

  test('encrypted registry tampering never triggers a guessed cache sweep',
      () async {
    final chosen = await file(paths.join(firstUuid, 'photo.jpg'));
    await cleaner.registerPickedPath(chosen.path);
    final registry = File(paths.join(state.path, 'picker-cache.udm'));
    final bytes = await registry.readAsBytes();
    bytes[bytes.length - 1] ^= 1;
    await registry.writeAsBytes(bytes, flush: true);
    await expectLater(cleaner.clear(), throwsA(anything));
    expect(await chosen.exists(), isTrue);
  });

  test('rejects encrypted registry path traversal instead of deleting it',
      () async {
    final helper = InventoryEncryptedFile(
        directoryProvider: () async => state,
        keyProvider: () async => key,
        purpose: 'picker-cache-registry');
    final outside = File(paths.join(fixture.path, 'original.jpg'));
    await outside.writeAsString('original');
    await helper.write(
        'picker-cache.udm',
        Uint8List.fromList(utf8.encode(jsonEncode({
          'version': 1,
          'paths': ['../original.jpg'],
        }))));
    await expectLater(cleaner.clear(), throwsFormatException);
    expect(await outside.readAsString(), 'original');
  });

  test('does not follow a symlinked UUID directory outside cache', () async {
    final outside =
        await Directory(paths.join(fixture.path, 'outside')).create();
    final original = File(paths.join(outside.path, 'photo.jpg'));
    await original.writeAsString('original outside cache');
    try {
      await Link(paths.join(cache.path, firstUuid)).create(outside.path);
    } on FileSystemException {
      if (Platform.isWindows) {
        markTestSkipped('Windows account cannot create symbolic links.');
        return;
      }
      rethrow;
    }
    final linked = paths.join(cache.path, firstUuid, 'photo.jpg');
    expect(await cleaner.registerPickedPath(linked), isFalse);
    await cleaner.cleanupPickedPath(linked);
    expect(await original.readAsString(), 'original outside cache');
  });

  test('does not follow a registered file replaced with a symlink', () async {
    final chosen = await file(paths.join(firstUuid, 'photo.jpg'));
    final original = File(paths.join(fixture.path, 'original.jpg'));
    await original.writeAsString('original outside cache');
    await cleaner.registerPickedPath(chosen.path);
    await chosen.delete();
    try {
      await Link(chosen.path).create(original.path);
    } on FileSystemException {
      if (Platform.isWindows) {
        markTestSkipped('Windows account cannot create symbolic links.');
        return;
      }
      rethrow;
    }
    await cleaner.clear();
    expect(await original.readAsString(), 'original outside cache');
    expect(await FileSystemEntity.type(chosen.path, followLinks: false),
        FileSystemEntityType.link);
  });
}
