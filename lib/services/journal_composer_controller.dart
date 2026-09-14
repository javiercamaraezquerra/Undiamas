import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart' as hashes;
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';

import '../models/diary_entry.dart';
import 'hive_restore_service.dart';
import 'inventory_photo_store.dart';
import 'journal_draft_store.dart';
import 'picker_photo_cache_cleaner.dart';
import 'android_photo_preparer.dart';
import 'journal_photo_issue.dart';

export 'journal_photo_issue.dart';

/// The boundary used by the editor. Tests replace this, never the user's files.
abstract class JournalAttachmentGateway {
  Future<JournalDraft?> loadDraft();
  Future<void> saveDraft(JournalDraft draft);
  Future<void> clearDraft();
  Future<XFile?> pick(ImageSource source);
  Future<XFile?> recoverLostPhoto();
  Future<String> importPhoto(Uint8List bytes);
  Future<Uint8List> readPhoto(String id);
  Future<void> deletePhoto(String id);
  Future<void> registerPickedPhoto(XFile file);
  Future<void> releasePickedPhoto(XFile file);
  Future<void> cleanupPickerCache();

  Future<Uint8List> preparePickedPhoto(XFile file) async {
    if (await file.length() > InventoryPhotoStore.maxSourceBytes) {
      throw const InventoryPhotoSizeException();
    }
    return file.readAsBytes();
  }

  Future<String> importPreparedPhoto(Uint8List bytes) => importPhoto(bytes);
}

class DeviceJournalAttachmentGateway extends JournalAttachmentGateway {
  DeviceJournalAttachmentGateway(
      {ImagePicker? picker,
      AndroidPhotoPreparer? photoPreparer,
      bool? useAndroidPhotoPreparer})
      : _picker = picker ?? ImagePicker(),
        _preparer = photoPreparer ?? const AndroidPhotoPreparer(),
        _useAndroid = useAndroidPhotoPreparer ?? Platform.isAndroid;
  final ImagePicker _picker;
  final AndroidPhotoPreparer _preparer;
  final bool _useAndroid;
  static final _activePicks = <String>{};
  @override
  Future<JournalDraft?> loadDraft() => JournalDraftStore.instance.load();
  @override
  Future<void> saveDraft(JournalDraft draft) =>
      JournalDraftStore.instance.save(draft);
  @override
  Future<void> clearDraft() => JournalDraftStore.instance.clear();
  @override
  Future<XFile?> pick(ImageSource source) =>
      _picker.pickImage(source: source, imageQuality: 100);
  @override
  Future<XFile?> recoverLostPhoto() async {
    final result = await _picker.retrieveLostData();
    if (result.exception != null) throw result.exception!;
    return result.files?.firstOrNull;
  }

  @override
  Future<String> importPhoto(Uint8List bytes) =>
      InventoryPhotoStore.instance.importImage(bytes);
  @override
  Future<Uint8List> preparePickedPhoto(XFile file) =>
      _useAndroid ? _preparer.prepare(file) : super.preparePickedPhoto(file);
  @override
  Future<String> importPreparedPhoto(Uint8List bytes) async {
    if (!_useAndroid) return importPhoto(bytes);
    final id = hashes.sha256.convert(bytes).toString();
    await InventoryPhotoStore.instance.importPrepared(id, bytes);
    return id;
  }

  @override
  Future<Uint8List> readPhoto(String id) =>
      InventoryPhotoStore.instance.read(id);
  @override
  Future<void> deletePhoto(String id) =>
      InventoryPhotoStore.instance.delete(id);
  @override
  Future<void> registerPickedPhoto(XFile file) async {
    _activePicks.add(file.path);
    await PickerPhotoCacheCleaner.instance.registerPickedPath(file.path);
  }

  @override
  Future<void> releasePickedPhoto(XFile file) async {
    try {
      await PickerPhotoCacheCleaner.instance.cleanupPickedPath(file.path);
    } finally {
      _activePicks.remove(file.path);
    }
  }

  @override
  Future<void> cleanupPickerCache() => PickerPhotoCacheCleaner.instance
      .cleanupStale(retainedPaths: Set<String>.of(_activePicks));
}

/// Owns only a draft. Photos are never entries until the user presses Save.
/// Stable keys make the flush-entry / clear-draft crash window idempotent.
class JournalComposerController extends ChangeNotifier {
  // A departing tab may still be flushing its last keystrokes. Every new
  // editor waits for those commits before reading the durable draft.
  static Future<void>? _draftCommits;
  JournalComposerController({
    required this.box,
    required this.gateway,
    HiveRestoreService? restore,
  }) : restore = restore ?? HiveRestoreService.instance {
    _generation = this.restore.generation;
    this.restore.addListener(_restoreChanged);
  }

  final Box<DiaryEntry> box;
  final JournalAttachmentGateway gateway;
  final HiveRestoreService restore;
  late int _generation;
  bool _disposed = false;
  bool ready = false;
  bool busy = false;
  String text = '';
  int? mood;
  String? photoId;
  String? error;
  String? progress;
  JournalPhotoIssue? photoIssue;
  ImageSource? lastPhotoSource;
  String _entryKey = _newKey();
  bool _awaitingPhoto = false;
  Future<void> _writes = Future<void>.value();
  Timer? _draftTimer;

  bool get canSave =>
      ready &&
      !busy &&
      !restore.busy &&
      mood != null &&
      (text.trim().isNotEmpty || photoId != null);
  bool get canAttach => ready && !busy && !restore.busy;

  static String _newKey() {
    final random = Random.secure();
    final suffix = List.generate(
            16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    return 'photo-draft-$suffix';
  }

  JournalDraft _snapshot() => JournalDraft(
      text: text,
      mood: mood,
      photoId: photoId,
      awaitingPhoto: _awaitingPhoto,
      entryKey: _entryKey);

  bool _current(int generation) =>
      !_disposed && generation == restore.generation;

  Future<void> initialize() async {
    final generation = _generation;
    try {
      final pending = _draftCommits;
      if (pending != null) await pending;
      final draft = await _withStorage(gateway.loadDraft, generation);
      if (!_current(generation)) return;
      if (draft != null) {
        final existing =
            draft.entryKey == null ? null : box.get(draft.entryKey);
        if (existing != null &&
            existing.text == draft.text.trim() &&
            existing.mood == draft.mood &&
            existing.photoId == draft.photoId) {
          // A committed entry wins over its stale, not-yet-cleared draft.
          await restore.runExclusive(gateway.clearDraft,
              expectedGeneration: generation);
        } else {
          text = draft.text;
          mood = draft.mood;
          photoId = draft.photoId;
          _entryKey =
              existing != null ? _newKey() : draft.entryKey ?? _newKey();
          _awaitingPhoto = draft.awaitingPhoto;
        }
      }
      if (!_current(generation)) return;
      ready = true;
      _notify();
      if (_awaitingPhoto) await _recoverPhoto(generation, _entryKey);
      if (_current(generation)) {
        try {
          await gateway.cleanupPickerCache();
        } catch (_) {
          // Retry registered stale picker files the next time Inventory opens.
        }
      }
    } catch (_) {
      if (_current(generation)) {
        error =
            'No se pudo recuperar el borrador. Vuelve a abrir el Inventario; '
            'tus entradas se conservan.';
        _notify();
      }
    }
  }

  void updateText(String value) {
    if (!ready || busy || text == value) return;
    text = value;
    _persistInBackground();
    _notify();
  }

  void updateMood(int value) {
    if (!ready || busy) return;
    mood = value;
    _persistInBackground();
    _notify();
  }

  Future<void> _persist(JournalDraft draft, int generation) {
    _draftTimer?.cancel();
    _draftTimer = null;
    Future<void> write() async {
      if (generation != restore.generation) return;
      await _withStorage(() => gateway.saveDraft(draft), generation);
    }

    final pending = _draftCommits;
    final next = pending == null ? write() : pending.then((_) => write());
    // Keep the serialization queue usable after a disk failure.
    _writes = next.catchError((Object _) {});
    _draftCommits = _writes;
    final registered = _writes;
    unawaited(registered.then((_) {
      if (identical(_draftCommits, registered)) _draftCommits = null;
    }));
    return next;
  }

  Future<T> _withStorage<T>(
      Future<T> Function() operation, int generation) async {
    while (true) {
      if (generation != restore.generation) {
        throw StateError(
            'The inventory was replaced while this draft was pending.');
      }
      if (!restore.busy) {
        return restore.runExclusive(operation, expectedGeneration: generation);
      }
      final idle = Completer<void>();
      void changed() {
        if ((!restore.busy || generation != restore.generation) &&
            !idle.isCompleted) {
          idle.complete();
        }
      }

      restore.addListener(changed);
      changed();
      try {
        await idle.future;
      } finally {
        restore.removeListener(changed);
      }
    }
  }

  void _persistInBackground() {
    final generation = _generation;
    final draft = _snapshot();
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 200), () {
      unawaited(_persist(draft, generation).then((_) {
        if (_current(generation) && !busy) {
          error = null;
          _notify();
        }
      }, onError: (Object _) {
        if (_current(generation)) {
          error = 'No se pudo conservar el borrador. El texto sigue aquí; '
              'comprueba el espacio disponible antes de salir.';
          _notify();
        }
      }));
    });
  }

  Future<void> choosePhoto(ImageSource source) async {
    if (!canAttach) return;
    final generation = _generation;
    final key = _entryKey;
    busy = true;
    error = null;
    photoIssue = null;
    lastPhotoSource = source;
    progress =
        source == ImageSource.camera ? 'Abriendo cámara…' : 'Abriendo galería…';
    _awaitingPhoto = true;
    _notify();
    XFile? selected;
    var stage = JournalPhotoStage.draft;
    try {
      // The durable marker is committed BEFORE opening another Android activity.
      await _persist(_snapshot(), generation);
      if (!_current(generation)) return;
      stage = JournalPhotoStage.picker;
      selected = await gateway.pick(source);
      stage = JournalPhotoStage.prepare;
      if (_current(generation) && selected != null) {
        await gateway.registerPickedPhoto(selected);
      }
      await _acceptPhoto(selected, generation, key,
          onCommit: () => stage = JournalPhotoStage.commit);
    } catch (failure) {
      await _photoFailed(generation, failure, stage);
    } finally {
      await _releasePicked(selected);
      if (_current(generation)) {
        busy = false;
        progress = null;
        _notify();
      }
    }
  }

  Future<void> _recoverPhoto(int generation, String key) async {
    busy = true;
    progress = 'Recuperando foto…';
    _notify();
    XFile? selected;
    var stage = JournalPhotoStage.recovery;
    try {
      selected = await gateway.recoverLostPhoto();
      stage = JournalPhotoStage.prepare;
      if (_current(generation) && selected != null) {
        await gateway.registerPickedPhoto(selected);
      }
      await _acceptPhoto(selected, generation, key,
          onCommit: () => stage = JournalPhotoStage.commit);
    } catch (failure) {
      await _photoFailed(generation, failure, stage);
    } finally {
      await _releasePicked(selected);
      if (_current(generation)) {
        busy = false;
        progress = null;
        _notify();
      }
    }
  }

  Future<void> _acceptPhoto(XFile? selected, int generation, String key,
      {required void Function() onCommit}) async {
    if (!_current(generation) || key != _entryKey || !_awaitingPhoto) return;
    Uint8List? bytes;
    if (selected != null) {
      progress = 'Preparando foto…';
      _notify();
      bytes = await gateway.preparePickedPhoto(selected);
    }
    if (!_current(generation) || key != _entryKey) return;
    await _withStorage(() async {
      final oldId = photoId;
      String? newId = oldId;
      if (bytes != null) {
        try {
          newId = await gateway.importPreparedPhoto(bytes);
        } on FileSystemException {
          // Reading the picker file has already finished. I/O here belongs
          // to the encrypted private store, not to the chosen image format.
          onCommit();
          rethrow;
        }
      }
      onCommit();
      // Keep the old attachment usable if writing the new draft fails.
      final next = JournalDraft(
          text: text,
          mood: mood,
          photoId: newId,
          awaitingPhoto: false,
          entryKey: _entryKey);
      await gateway.saveDraft(next);
      photoId = newId;
      photoIssue = null;
      _awaitingPhoto = false;
      if (oldId != newId) {
        try {
          await _deleteUnused(oldId);
        } catch (_) {
          // Startup pruning retries an unreferenced encrypted file.
        }
      }
    }, generation);
  }

  Future<void> _releasePicked(XFile? file) async {
    if (file == null) return;
    try {
      await gateway.releasePickedPhoto(file);
    } catch (_) {
      // The encrypted registry retains the path for cleanup at next startup.
      // A cache cleanup failure must not undo a committed private attachment.
    }
  }

  Future<void> _photoFailed(
      int generation, Object failure, JournalPhotoStage stage) async {
    if (!_current(generation)) return;
    _awaitingPhoto = false;
    try {
      await _persist(_snapshot(), generation);
    } catch (_) {
      // A durable pending marker can be safely retried at the next startup.
    }
    if (_current(generation)) {
      if (JournalPhotoIssue.isCancellation(failure)) {
        photoIssue = null;
        return;
      }
      photoIssue = JournalPhotoIssue.fromFailure(failure,
          stage: stage,
          hasPreviousPhoto: photoId != null,
          hasText: text.isNotEmpty,
          canRetry: lastPhotoSource != null,
          camera: lastPhotoSource == ImageSource.camera);
      dev.log(
          'Photo operation failed (${stage.name}/${photoIssue!.kind.name}).',
          name: 'UnDiaMas');
    }
  }

  Future<void> retryPhoto() async {
    final source = lastPhotoSource;
    if (source != null && photoIssue?.canRetry == true) {
      await choosePhoto(source);
    }
  }

  void dismissPhotoIssue() {
    photoIssue = null;
    _notify();
  }

  Future<void> removePhoto() async {
    if (!canAttach || photoId == null) return;
    final generation = _generation;
    busy = true;
    error = null;
    photoIssue = null;
    _draftTimer?.cancel();
    _draftTimer = null;
    _notify();
    await _writes;
    try {
      await restore.runExclusive(() async {
        final oldId = photoId;
        await gateway.saveDraft(
            JournalDraft(text: text, mood: mood, entryKey: _entryKey));
        photoId = null;
        try {
          await _deleteUnused(oldId);
        } catch (_) {
          // The new draft is committed; retaining a file is safe to retry.
        }
      }, expectedGeneration: generation);
    } catch (_) {
      if (_current(generation)) {
        error = 'No se pudo quitar la foto. Inténtalo de nuevo.';
      }
    } finally {
      if (_current(generation)) {
        busy = false;
        _notify();
      }
    }
  }

  /// Call only while holding the shared mutation lock, after a Hive flush.
  Future<void> deleteUnusedPhoto(String? id) async => _deleteUnused(id);

  Future<void> _deleteUnused(String? id) async {
    if (id == null ||
        photoId == id ||
        box.values.any((entry) => entry.photoId == id)) {
      return;
    }
    // Another mounted editor is unusual, but must not lose its durable photo.
    if ((await gateway.loadDraft())?.photoId == id) return;
    await gateway.deletePhoto(id);
  }

  Future<void> flushDraft() =>
      _draftTimer == null ? _writes : _persist(_snapshot(), _generation);

  Future<bool> saveEntry({Future<void> Function()? afterSave}) async {
    if (!canSave) return false;
    final generation = _generation;
    busy = true;
    error = null;
    photoIssue = null;
    progress = 'Guardando…';
    _notify();
    var committed = false;
    try {
      await _persist(_snapshot(), generation);
      if (!_current(generation)) return false;
      await restore.runExclusive(() async {
        if (photoId != null) await gateway.readPhoto(photoId!);
        final previous = box.get(_entryKey);
        // A failed flush may leave an earlier put in Hive's memory cache.
        // Retrying must write the current draft under the same stable key.
        await box.put(
            _entryKey,
            DiaryEntry(
                createdAt: previous?.createdAt ?? DateTime.now(),
                mood: mood!,
                text: text.trim(),
                photoId: photoId));
        await box.flush();
        committed = true;
        _resetDraft();
        _notify();
        await gateway.clearDraft();
        if (previous?.photoId != null) {
          try {
            await _deleteUnused(previous!.photoId);
          } catch (_) {}
        }
        // Keep edits disabled until the optional backup releases its shared
        // lock, so new text is never presented as a durable draft while queued.
        progress = 'Entrada guardada. Actualizando copia…';
        _notify();
        if (afterSave != null) await afterSave();
      }, expectedGeneration: generation);
      return true;
    } catch (_) {
      if (_current(generation)) {
        error = committed
            ? 'La entrada está guardada. No se pudo limpiar el borrador; '
                'al volver a abrir se comprobará sin duplicarla.'
            : 'No se pudo guardar la entrada. Comprueba el espacio disponible '
                'y espera a que termine cualquier restauración.';
      }
      return committed;
    } finally {
      if (_current(generation)) {
        busy = false;
        progress = null;
        _notify();
      }
    }
  }

  void _resetDraft() {
    text = '';
    mood = null;
    photoId = null;
    _awaitingPhoto = false;
    _entryKey = _newKey();
    photoIssue = null;
  }

  void _restoreChanged() {
    if (_disposed) return;
    if (_generation == restore.generation) {
      _notify();
      return;
    }
    _generation = restore.generation;
    _draftTimer?.cancel();
    _draftTimer = null;
    _resetDraft();
    busy = false;
    ready = true;
    error = null;
    progress = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    // Tab changes dispose this editor. Commit the last keystrokes immediately.
    if (_draftTimer != null) {
      unawaited(_persist(_snapshot(), _generation).catchError((Object _) {}));
    }
    _disposed = true;
    restore.removeListener(_restoreChanged);
    super.dispose();
  }
}
