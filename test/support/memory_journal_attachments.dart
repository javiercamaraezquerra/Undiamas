import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:un_dia_mas/services/journal_composer_controller.dart';
import 'package:un_dia_mas/services/journal_draft_store.dart';

class MemoryJournalAttachments implements JournalAttachmentGateway {
  JournalDraft? draft;
  final photos = <String, Uint8List>{};
  final deleted = <String>[];
  XFile? selected;
  XFile? lost;
  int recoverCalls = 0;
  int pickCalls = 0;
  final registeredPicks = <XFile>[];
  final releasedPicks = <XFile>[];
  int _next = 0;
  bool failDraftWrite = false;
  bool failDraftClear = false;
  bool failImport = false;
  Future<XFile?> Function(ImageSource)? pickOverride;
  @override
  Future<JournalDraft?> loadDraft() async => draft;
  @override
  Future<void> saveDraft(JournalDraft value) async {
    if (failDraftWrite) throw StateError('Disk full');
    draft = value;
  }

  @override
  Future<void> clearDraft() async {
    if (failDraftClear) throw StateError('Disk full');
    draft = null;
  }

  @override
  Future<XFile?> pick(ImageSource source) async {
    pickCalls++;
    return pickOverride == null ? selected : await pickOverride!(source);
  }

  @override
  Future<XFile?> recoverLostPhoto() async {
    recoverCalls++;
    return lost;
  }

  @override
  Future<String> importPhoto(Uint8List bytes) async {
    if (failImport) throw StateError('Invalid image');
    final id = (++_next).toRadixString(16).padLeft(64, '0');
    photos[id] = bytes;
    return id;
  }

  @override
  Future<Uint8List> readPhoto(String id) async =>
      photos[id] ?? (throw StateError('Photo missing'));
  @override
  Future<void> deletePhoto(String id) async {
    deleted.add(id);
    photos.remove(id);
  }

  @override
  Future<void> registerPickedPhoto(XFile file) async =>
      registeredPicks.add(file);
  @override
  Future<void> releasePickedPhoto(XFile file) async => releasedPicks.add(file);
  @override
  Future<void> cleanupPickerCache() async {}
}
