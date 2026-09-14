import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';
import 'package:un_dia_mas/models/diary_entry.dart';
import 'package:un_dia_mas/services/hive_restore_service.dart';
import 'package:un_dia_mas/services/journal_composer_controller.dart';
import 'package:un_dia_mas/services/journal_draft_store.dart';

import 'support/memory_journal_attachments.dart';

class _FailFirstFlush extends Fake implements Box<DiaryEntry> {
  _FailFirstFlush(this.actual);
  final Box<DiaryEntry> actual;
  bool failed = false;
  @override
  DiaryEntry? get(dynamic key, {DiaryEntry? defaultValue}) =>
      actual.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, DiaryEntry value) => actual.put(key, value);
  @override
  Iterable<DiaryEntry> get values => actual.values;
  @override
  Future<void> flush() async {
    if (!failed) {
      failed = true;
      throw StateError('Simulated flush failure');
    }
    await actual.flush();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Box<DiaryEntry> box;
  late MemoryJournalAttachments gateway;
  late HiveRestoreService restore;
  late JournalComposerController editor;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('udm_photo_editor_');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(DiaryEntryAdapter());
    box = await Hive.openBox<DiaryEntry>('diary');
    gateway = MemoryJournalAttachments();
    restore = HiveRestoreService();
    editor =
        JournalComposerController(box: box, gateway: gateway, restore: restore);
  });

  tearDown(() async {
    await editor.flushDraft();
    editor.dispose();
    restore.dispose();
    await Hive.close();
    final actual = await directory.resolveSymbolicLinks();
    final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
    if (!actual.toLowerCase().startsWith(
            '$temporaryRoot${Platform.pathSeparator}'.toLowerCase()) ||
        !directory.uri.pathSegments
            .where((p) => p.isNotEmpty)
            .last
            .startsWith('udm_photo_editor_')) {
      throw StateError('Refusing deletion outside the verified test directory');
    }
    await directory.delete(recursive: true);
  });

  test(
      'cancel keeps text and mood, and the camera only opens after durable save',
      () async {
    await editor.initialize();
    editor.updateText('Un paseo');
    editor.updateMood(3);
    gateway.pickOverride = (_) async {
      expect(gateway.draft!.text, 'Un paseo');
      expect(gateway.draft!.mood, 3);
      expect(gateway.draft!.awaitingPhoto, isTrue);
      expect(gateway.draft!.entryKey, isNotNull);
      return null;
    };
    await editor.choosePhoto(ImageSource.camera);
    expect(editor.text, 'Un paseo');
    expect(editor.mood, 3);
    expect(editor.photoId, isNull);
    expect(gateway.draft!.awaitingPhoto, isFalse);
    expect(box.isEmpty, isTrue);
  });

  test('a photo and mood can be saved without text and survive a box reopen',
      () async {
    await editor.initialize();
    editor.updateMood(2);
    gateway.selected = XFile.fromData(Uint8List.fromList([1, 2, 3]));
    await editor.choosePhoto(ImageSource.gallery);
    final photo = editor.photoId;
    expect(gateway.registeredPicks, [gateway.selected]);
    expect(gateway.releasedPicks, [gateway.selected]);
    expect(editor.canSave, isTrue);
    expect(box.isEmpty, isTrue);
    expect(await editor.saveEntry(), isTrue);
    expect(box.length, 1);
    expect(box.values.single.photoId, photo);
    expect(box.values.single.text, '');
    expect(box.values.single.mood, 2);
    expect(gateway.draft, isNull);
    expect(gateway.photos.containsKey(photo), isTrue);
    expect(editor.photoId, isNull);
    await box.close();
    box = await Hive.openBox<DiaryEntry>('diary');
    expect(box.values.single.photoId, photo);
  });

  test('draft clear failure cannot duplicate a committed entry after restart',
      () async {
    await editor.initialize();
    editor.updateText('Guardar una sola vez');
    editor.updateMood(4);
    gateway.failDraftClear = true;
    expect(await editor.saveEntry(), isTrue);
    expect(box.length, 1);
    expect(editor.text, isEmpty);
    expect(gateway.draft, isNotNull);
    gateway.failDraftClear = false;
    final reopened =
        JournalComposerController(box: box, gateway: gateway, restore: restore);
    await reopened.initialize();
    expect(reopened.text, isEmpty);
    expect(gateway.draft, isNull);
    expect(box.length, 1);
    reopened.dispose();
  });

  test('same key with different content keeps the recovered draft', () async {
    const key = 'photo-draft-1234567890abcdef';
    gateway.draft =
        const JournalDraft(text: 'Borrador conservado', mood: 3, entryKey: key);
    await box.put(
        key, DiaryEntry(createdAt: DateTime(2026), mood: 1, text: 'Otro día'));
    await editor.initialize();
    expect(editor.text, 'Borrador conservado');
    expect(await editor.saveEntry(), isTrue);
    expect(box.length, 2);
    expect(box.get(key)!.text, 'Otro día');
  });

  test(
      'lost data is retrieved only for a pending draft and stays an attachment',
      () async {
    gateway.draft = const JournalDraft(
        text: 'Antes de la cámara',
        mood: 1,
        awaitingPhoto: true,
        entryKey: 'photo-draft-1234567890abcdef');
    gateway.lost = XFile.fromData(Uint8List.fromList([1]));
    await editor.initialize();
    expect(gateway.recoverCalls, 1);
    expect(gateway.registeredPicks, [gateway.lost]);
    expect(gateway.releasedPicks, [gateway.lost]);
    expect(editor.text, 'Antes de la cámara');
    expect(editor.photoId, isNotNull);
    expect(gateway.draft!.awaitingPhoto, isFalse);
    expect(box.isEmpty, isTrue);
  });

  test('normal startup does not consume unrelated lost picker data', () async {
    gateway.lost = XFile.fromData(Uint8List.fromList([1]));
    await editor.initialize();
    expect(gateway.recoverCalls, 0);
    expect(editor.photoId, isNull);
  });

  test('a camera return after restore cannot attach to the restored inventory',
      () async {
    await editor.initialize();
    editor.updateText('Antiguo borrador');
    final pending = Completer<XFile?>();
    final started = Completer<void>();
    gateway.pickOverride = (_) {
      started.complete();
      return pending.future;
    };
    final selecting = editor.choosePhoto(ImageSource.camera);
    await started.future;
    await restore.runDeletion(() => gateway.clearDraft());
    pending.complete(XFile.fromData(Uint8List.fromList([2])));
    await selecting;
    expect(editor.text, isEmpty);
    expect(editor.photoId, isNull);
    expect(gateway.photos, isEmpty);
    expect(gateway.draft, isNull);
  });

  test(
      'disk failure before capture prevents the external activity and preserves text',
      () async {
    await editor.initialize();
    editor.updateText('Texto importante');
    await editor.flushDraft();
    gateway.failDraftWrite = true;
    await editor.choosePhoto(ImageSource.camera);
    expect(gateway.pickCalls, 0);
    expect(editor.text, 'Texto importante');
    expect(editor.photoIssue!.kind, JournalPhotoIssueKind.storage);
  });

  test(
      'failed import preserves the previous attachment, and removing it respects other entries',
      () async {
    await editor.initialize();
    gateway.selected = XFile.fromData(Uint8List.fromList([1]));
    await editor.choosePhoto(ImageSource.gallery);
    final first = editor.photoId;
    gateway.failImport = true;
    await editor.choosePhoto(ImageSource.gallery);
    expect(editor.photoId, first);
    expect(gateway.photos.containsKey(first), isTrue);
    await box.put(
        7,
        DiaryEntry(
            createdAt: DateTime(2026), mood: 2, text: 'Otra', photoId: first));
    await editor.removePhoto();
    expect(editor.photoId, isNull);
    expect(gateway.photos.containsKey(first), isTrue);
    expect(gateway.deleted, isEmpty);
  });

  test(
      'oversized images are rejected before importing and leave no phantom entry',
      () async {
    await editor.initialize();
    gateway.selected = XFile.fromData(Uint8List(16 * 1024 * 1024 + 1));
    await editor.choosePhoto(ImageSource.gallery);
    expect(editor.photoId, isNull);
    expect(editor.photoIssue!.kind, JournalPhotoIssueKind.tooLarge);
    expect(editor.photoIssue!.canRetry, isFalse);
    expect(gateway.photos, isEmpty);
    expect(box.isEmpty, isTrue);
    expect(gateway.releasedPicks, [gateway.selected]);
  });

  test(
      'failed native replacement keeps the old photo and retries the same source',
      () async {
    await editor.initialize();
    editor.updateText('Conservar mis palabras');
    editor.updateMood(3);
    gateway.selected = XFile.fromData(Uint8List.fromList([1]));
    await editor.choosePhoto(ImageSource.gallery);
    final first = editor.photoId;
    gateway.prepareOverride = (_) async => throw PlatformException(
        code: 'photo_unreadable', message: '/private/user/image.jpg');
    await editor.choosePhoto(ImageSource.gallery);
    expect(editor.photoId, first);
    expect(editor.text, 'Conservar mis palabras');
    expect(editor.mood, 3);
    expect(editor.canSave, isTrue);
    expect(editor.photoIssue!.kind, JournalPhotoIssueKind.unreadable);
    expect(editor.photoIssue!.message,
        contains('La foto anterior y tu texto se conservan'));
    expect(editor.photoIssue!.message, isNot(contains('/private')));
    expect(gateway.draft!.photoId, first);
    expect(gateway.deleted, isEmpty);
    expect(gateway.releasedPicks.length, 2);

    final sources = <ImageSource>[];
    gateway.pickOverride = (source) async {
      sources.add(source);
      return XFile.fromData(Uint8List.fromList([2]));
    };
    gateway.prepareOverride = null;
    await editor.retryPhoto();
    expect(sources, [ImageSource.gallery]);
    expect(editor.photoIssue, isNull);
    expect(editor.photoId, isNot(first));
    expect(gateway.photos.containsKey(first), isFalse);
    expect(gateway.draft!.text, 'Conservar mis palabras');
    expect(gateway.draft!.mood, 3);
  });

  test('camera failure can be dismissed and cancellation is not an error',
      () async {
    await editor.initialize();
    editor.updateText('El borrador sigue aquí');
    editor.updateMood(2);
    gateway.pickOverride =
        (_) async => throw PlatformException(code: 'no_available_camera');
    await editor.choosePhoto(ImageSource.camera);
    expect(editor.photoIssue!.kind, JournalPhotoIssueKind.unavailable);
    expect(editor.photoIssue!.canChooseOther, isTrue);
    expect(editor.busy, isFalse);
    expect(editor.progress, isNull);
    editor.dismissPhotoIssue();
    expect(editor.photoIssue, isNull);
    expect(editor.text, 'El borrador sigue aquí');
    gateway.pickOverride =
        (_) async => throw PlatformException(code: 'camera_cancelled');
    await editor.choosePhoto(ImageSource.camera);
    expect(editor.photoIssue, isNull);
    expect(editor.error, isNull);
    expect(gateway.draft!.awaitingPhoto, isFalse);
    expect(editor.canSave, isTrue);
  });

  test('temporary storage activity during preparation queues the attachment',
      () async {
    await editor.initialize();
    gateway.selected = XFile.fromData(Uint8List.fromList([1]));
    final started = Completer<void>();
    final prepared = Completer<Uint8List>();
    gateway.prepareOverride = (_) {
      started.complete();
      return prepared.future;
    };
    final selecting = editor.choosePhoto(ImageSource.camera);
    await started.future;
    expect(editor.progress, 'Preparando foto…');
    final releaseStorage = Completer<void>();
    final storage = restore.runExclusive(() => releaseStorage.future);
    prepared.complete(Uint8List.fromList([2]));
    await Future<void>.delayed(Duration.zero);
    expect(editor.busy, isTrue);
    expect(gateway.photos, isEmpty);
    releaseStorage.complete();
    await storage;
    await selecting;
    expect(editor.photoId, isNotNull);
    expect(editor.photoIssue, isNull);
    expect(editor.busy, isFalse);
    expect(gateway.draft!.awaitingPhoto, isFalse);
  });

  test('reset while the native decoder is pending cannot resurrect a draft',
      () async {
    await editor.initialize();
    editor.updateText('Borrador anterior');
    gateway.selected = XFile.fromData(Uint8List.fromList([1]));
    final started = Completer<void>();
    final prepared = Completer<Uint8List>();
    gateway.prepareOverride = (_) {
      started.complete();
      return prepared.future;
    };
    final selecting = editor.choosePhoto(ImageSource.gallery);
    await started.future;
    await restore.runDeletion(() => gateway.clearDraft());
    prepared.complete(Uint8List.fromList([2]));
    await selecting;
    expect(editor.photoId, isNull);
    expect(editor.text, isEmpty);
    expect(gateway.draft, isNull);
    expect(gateway.photos, isEmpty);
    expect(gateway.releasedPicks, [gateway.selected]);
    expect(editor.photoIssue, isNull);
  });

  test('failed draft commit after preparation preserves the prior attachment',
      () async {
    await editor.initialize();
    editor.updateText('Antes del cambio');
    editor.updateMood(4);
    gateway.selected = XFile.fromData(Uint8List.fromList([1]));
    await editor.choosePhoto(ImageSource.gallery);
    final first = editor.photoId;
    gateway.prepareOverride = (_) async {
      gateway.failDraftWrite = true;
      return Uint8List.fromList([2]);
    };
    await editor.choosePhoto(ImageSource.gallery);
    expect(editor.photoId, first);
    expect(gateway.draft!.photoId, first);
    expect(gateway.photos.containsKey(first), isTrue);
    expect(editor.text, 'Antes del cambio');
    expect(editor.mood, 4);
    expect(editor.photoIssue!.kind, JournalPhotoIssueKind.storage);
    expect(editor.photoIssue!.canChooseOther, isFalse);
    gateway.failDraftWrite = false;
    await editor.flushDraft();
  });

  test(
      'private store write failure is storage feedback, not an unreadable source',
      () async {
    await editor.initialize();
    gateway.selected = XFile.fromData(Uint8List.fromList([1]));
    await editor.choosePhoto(ImageSource.gallery);
    final first = editor.photoId;
    gateway.importFailure = const FileSystemException(
        'Cannot write', '/private/encrypted.udm', OSError('denied', 13));
    await editor.choosePhoto(ImageSource.gallery);
    expect(editor.photoId, first);
    expect(gateway.draft!.photoId, first);
    expect(editor.photoIssue!.kind, JournalPhotoIssueKind.storage);
    expect(editor.photoIssue!.message, isNot(contains('/private')));
    expect(editor.photoIssue!.canChooseOther, isFalse);
  });

  test('Drive upload reports a committed entry and prevents an undurable draft',
      () async {
    await editor.initialize();
    editor.updateText('Primera entrada');
    editor.updateMood(3);
    final started = Completer<void>();
    final uploaded = Completer<void>();
    final saving = editor.saveEntry(afterSave: () {
      started.complete();
      return uploaded.future;
    });
    await started.future;
    expect(editor.busy, isTrue);
    expect(editor.progress, 'Entrada guardada. Actualizando copia…');
    editor.updateText('Borrador mientras se actualiza Drive');
    editor.updateMood(2);
    expect(editor.canSave, isFalse);
    final flushing = editor.flushDraft();
    expect(gateway.draft, isNull);
    uploaded.complete();
    await saving;
    await flushing;
    expect(editor.text, isEmpty);
    expect(gateway.draft, isNull);
    expect(editor.canSave, isFalse);
    expect(editor.busy, isFalse);
    expect(box.length, 1);
    expect(editor.error, isNull);
  });

  test(
      'leaving a tab commits the latest debounced draft after a temporary lock',
      () async {
    final other =
        JournalComposerController(box: box, gateway: gateway, restore: restore);
    await other.initialize();
    final release = Completer<void>();
    final operation = restore.runExclusive(() => release.future);
    other.updateText('Últimas palabras antes de cambiar de pestaña');
    other.dispose();
    release.complete();
    await operation;
    await other.flushDraft();
    expect(gateway.draft!.text, 'Últimas palabras antes de cambiar de pestaña');
  });

  test('rapid tab recreation reads the outgoing final keystrokes', () async {
    final previous =
        JournalComposerController(box: box, gateway: gateway, restore: restore);
    await previous.initialize();
    previous.updateText('Últimas letras sin esperar al temporizador');
    previous.dispose();
    await editor.initialize();
    expect(editor.text, 'Últimas letras sin esperar al temporizador');
  });

  test('removing a photo cancels an older pending debounce snapshot', () async {
    await editor.initialize();
    gateway.selected = XFile.fromData(Uint8List.fromList([1]));
    await editor.choosePhoto(ImageSource.gallery);
    final id = editor.photoId;
    editor.updateText('Este texto sí se conserva');
    editor.updateMood(2);
    await editor.removePhoto();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await editor.flushDraft();
    expect(gateway.draft!.photoId, isNull);
    expect(gateway.draft!.text, 'Este texto sí se conserva');
    expect(gateway.photos.containsKey(id), isFalse);
  });

  test(
      'retry after a failed flush saves changed text once under its stable key',
      () async {
    final writer = JournalComposerController(
        box: _FailFirstFlush(box), gateway: gateway, restore: restore);
    await writer.initialize();
    writer.updateText('Primer intento');
    writer.updateMood(1);
    expect(await writer.saveEntry(), isFalse);
    final key = box.keys.single;
    final date = box.get(key)!.createdAt;
    writer.updateText('Texto corregido después del fallo');
    writer.updateMood(4);
    expect(await writer.saveEntry(), isTrue);
    expect(box.length, 1);
    expect(box.get(key)!.text, 'Texto corregido después del fallo');
    expect(box.get(key)!.mood, 4);
    expect(box.get(key)!.createdAt, date);
    writer.dispose();
  });
}
