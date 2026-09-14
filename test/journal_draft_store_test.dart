import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:un_dia_mas/services/inventory_encrypted_file.dart';
import 'package:un_dia_mas/services/journal_draft_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late JournalDraftStore store;
  final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
  final id = 'a' * 64;
  const entryKey = 'photo-draft-0123456789abcdef';

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('udm_draft_store_test_');
    store = JournalDraftStore(directory: directory, key: key);
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
            .startsWith('udm_draft_store_test_')) {
      throw StateError('Unexpected fixture path');
    }
    await directory.delete(recursive: true);
  });

  File draftFile() =>
      File('${directory.path}${Platform.pathSeparator}draft.udm');

  test('empty store returns null without creating a file', () async {
    expect(await store.load(), isNull);
    expect(await directory.list().length, 0);
  });

  test('survives new instance with all draft fields and no plaintext on disk',
      () async {
    final original = JournalDraft(
        text: 'Un mensaje íntimo 🌄\nSin perder espacios. ',
        mood: 3,
        photoId: id,
        awaitingPhoto: true,
        entryKey: entryKey);
    await store.save(original);
    final bytes = await draftFile().readAsBytes();
    expect(latin1.decode(bytes), isNot(contains('Un mensaje')));
    final restored =
        (await JournalDraftStore(directory: directory, key: key).load())!;
    expect(restored.text, original.text);
    expect(restored.mood, 3);
    expect(restored.photoId, id);
    expect(restored.awaitingPhoto, isTrue);
    expect(restored.entryKey, entryKey);
  });

  test('supports empty, photo-only and mood-not-yet-selected draft', () async {
    await store.save(JournalDraft(text: '', photoId: id));
    final restored = (await store.load())!;
    expect(restored.text, '');
    expect(restored.mood, isNull);
    expect(restored.photoId, id);
    expect(restored.awaitingPhoto, isFalse);
    expect(restored.entryKey, isNull);
  });

  test('preserves a long existing-editor draft without truncation', () async {
    final text = '${'Un recuerdo largo. ' * 25000}🌄';
    await store.save(JournalDraft(text: text, mood: 2));
    expect((await store.load())!.text, text);
  });

  test('failed replacement preserves last committed draft and cleans temp',
      () async {
    await store.save(const JournalDraft(text: 'Original', mood: 2));
    final before = await draftFile().readAsBytes();
    final failing = JournalDraftStore(
        directory: directory,
        key: key,
        beforeStep: (step) async {
          if (step == 'beforeCommit') {
            throw const FileSystemException('Simulated disk failure');
          }
        });
    await expectLater(failing.save(const JournalDraft(text: 'New')),
        throwsA(isA<FileSystemException>()));
    expect(await draftFile().readAsBytes(), before);
    expect((await store.load())!.text, 'Original');
    expect(await directory.list().length, 1);
  });

  test('serializes concurrent writes and clear in caller order', () async {
    final first = store.save(const JournalDraft(text: 'First'));
    final second = store.save(const JournalDraft(text: 'Second'));
    final clear = store.clear();
    await Future.wait([first, second, clear]);
    expect(await store.load(), isNull);
  });

  test('failed operation does not poison later operations', () async {
    var fail = true;
    final temporaryFailure = JournalDraftStore(
        directory: directory,
        key: key,
        beforeStep: (_) async {
          if (fail) throw const FileSystemException('Temporary failure');
        });
    await expectLater(temporaryFailure.save(const JournalDraft(text: 'First')),
        throwsA(isA<FileSystemException>()));
    fail = false;
    await temporaryFailure.save(const JournalDraft(text: 'Second'));
    expect((await store.load())!.text, 'Second');
  });

  test(
      'fresh random nonce prevents identical drafts having identical ciphertext',
      () async {
    const draft = JournalDraft(text: 'Same private text');
    await store.save(draft);
    final first = await draftFile().readAsBytes();
    await store.save(draft);
    expect(await draftFile().readAsBytes(), isNot(first));
    expect((await store.load())!.text, draft.text);
  });

  test('tampering and wrong key fail without silently clearing draft',
      () async {
    await store.save(const JournalDraft(text: 'Preserve me'));
    final wrongKey =
        JournalDraftStore(directory: directory, key: Uint8List(32));
    await expectLater(wrongKey.load(), throwsA(anything));
    final bytes = await draftFile().readAsBytes();
    bytes[bytes.length - 1] ^= 1;
    await draftFile().writeAsBytes(bytes, flush: true);
    await expectLater(store.load(), throwsA(anything));
    expect(await draftFile().readAsBytes(), bytes);
  });

  test('draft and photo cryptographic purposes cannot be substituted',
      () async {
    final photoPurpose = InventoryEncryptedFile(
        directoryProvider: () async => directory,
        keyProvider: () async => key,
        purpose: 'inventory-photo');
    await photoPurpose.write(
        'draft.udm', Uint8List.fromList(utf8.encode('{}')));
    await expectLater(store.load(), throwsA(anything));
  });

  test('rejects invalid draft state before replacing previous state', () async {
    await store.save(const JournalDraft(text: 'Valid'));
    for (final draft in [
      const JournalDraft(text: '', mood: -1),
      const JournalDraft(text: '', mood: 5),
      const JournalDraft(text: '', photoId: '../outside'),
      const JournalDraft(text: '', entryKey: 'unexpected Hive key'),
      JournalDraft(text: 'x' * (JournalDraftStore.maxTextLength + 1))
    ]) {
      expect(() => store.save(draft), throwsFormatException);
    }
    expect((await store.load())!.text, 'Valid');
  });

  test('rejects malformed encrypted JSON instead of discarding it', () async {
    final helper = InventoryEncryptedFile(
        directoryProvider: () async => directory,
        keyProvider: () async => key,
        purpose: 'journal-draft');
    for (final value in [
      [],
      {'version': 99},
      {
        'version': 1,
        'text': 'bad',
        'mood': 7,
        'photoId': null,
        'awaitingPhoto': false,
      }
    ]) {
      await helper.write(
          'draft.udm', Uint8List.fromList(utf8.encode(jsonEncode(value))));
      await expectLater(store.load(), throwsFormatException);
      expect(await draftFile().exists(), isTrue);
    }
  });

  test('reads first draft schema without optional entryKey', () async {
    final helper = InventoryEncryptedFile(
        directoryProvider: () async => directory,
        keyProvider: () async => key,
        purpose: 'journal-draft');
    await helper.write(
        'draft.udm',
        Uint8List.fromList(utf8.encode(jsonEncode({
          'version': 1,
          'text': 'Compatible',
          'mood': 2,
          'photoId': null,
          'awaitingPhoto': false,
        }))));
    expect((await store.load())!.text, 'Compatible');
    expect((await store.load())!.entryKey, isNull);
  });

  test('clear removes committed draft and its encrypted abandoned temps only',
      () async {
    await store.save(const JournalDraft(text: 'Remove me'));
    final abandoned = File('${draftFile().path}.${'a' * 24}.tmp');
    await abandoned.writeAsBytes(await draftFile().readAsBytes());
    final unrelated =
        File('${directory.path}${Platform.pathSeparator}keep.txt');
    await unrelated.writeAsString('untouched');
    await store.clear();
    expect(await store.load(), isNull);
    expect(await abandoned.exists(), isFalse);
    expect(await unrelated.readAsString(), 'untouched');
  });
}
