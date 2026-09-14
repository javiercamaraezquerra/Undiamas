import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'encryption_service.dart';
import 'inventory_encrypted_file.dart';
import 'inventory_photo_store.dart';

class JournalDraft {
  const JournalDraft({
    required this.text,
    this.mood,
    this.photoId,
    this.awaitingPhoto = false,
    this.entryKey,
  });

  final String text;
  final int? mood;
  final String? photoId;
  final bool awaitingPhoto;
  final String? entryKey;
}

/// A private composer draft, flushed before handing control to camera/gallery.
/// Failures are surfaced instead of silently discarding an unreadable draft.
class JournalDraftStore {
  JournalDraftStore({
    Directory? directory,
    Future<Directory> Function()? directoryProvider,
    Uint8List? key,
    Future<Uint8List> Function()? keyProvider,
    Future<void> Function(String)? beforeStep,
  }) : _files = InventoryEncryptedFile(
          directoryProvider: directoryProvider ??
              (directory != null ? () async => directory : _defaultDirectory),
          keyProvider: keyProvider ??
              (key != null ? () async => key : EncryptionService.getRawKey),
          purpose: 'journal-draft',
          beforeStep: beforeStep,
        );

  static final instance = JournalDraftStore();
  static const maxTextLength = 1000000;
  static const maxBytes = 4 * 1024 * 1024;
  static const _filename = 'draft.udm';
  final InventoryEncryptedFile _files;
  Future<void> _pending = Future<void>.value();

  static Future<Directory> _defaultDirectory() async =>
      Directory('${(await getApplicationSupportDirectory()).path}'
          '${Platform.pathSeparator}journal_draft');

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<JournalDraft?> load() => _exclusive(() async {
        final bytes = await _files.read(_filename, maxBytes: maxBytes);
        if (bytes == null) return null;
        final value = jsonDecode(utf8.decode(bytes));
        if (value is! Map ||
            (value.length != 5 && value.length != 6) ||
            !value.keys.toSet().containsAll(const [
              'version',
              'text',
              'mood',
              'photoId',
              'awaitingPhoto'
            ]) ||
            value.keys.any((key) => !const [
                  'version',
                  'text',
                  'mood',
                  'photoId',
                  'awaitingPhoto',
                  'entryKey'
                ].contains(key)) ||
            value['version'] != 1 ||
            value['text'] is! String ||
            (value['mood'] != null && value['mood'] is! int) ||
            (value['photoId'] != null && value['photoId'] is! String) ||
            (value['entryKey'] != null && value['entryKey'] is! String) ||
            value['awaitingPhoto'] is! bool) {
          throw const FormatException(
              'El borrador guardado no tiene un formato válido.');
        }
        final draft = JournalDraft(
          text: value['text'] as String,
          mood: value['mood'] as int?,
          photoId: value['photoId'] as String?,
          awaitingPhoto: value['awaitingPhoto'] as bool,
          entryKey: value['entryKey'] as String?,
        );
        _validate(draft);
        return draft;
      });

  Future<void> save(JournalDraft draft) {
    _validate(draft);
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode({
      'version': 1,
      'text': draft.text,
      'mood': draft.mood,
      'photoId': draft.photoId,
      'awaitingPhoto': draft.awaitingPhoto,
      'entryKey': draft.entryKey,
    })));
    if (bytes.length > maxBytes) {
      throw const FormatException('El borrador es demasiado largo.');
    }
    return _exclusive(() => _files.write(_filename, bytes));
  }

  Future<void> clear() => _exclusive(() async {
        await _files.delete(_filename);
        final directory = await _files.directory();
        if (!await directory.exists()) return;
        await for (final entity in directory.list(followLinks: false)) {
          if (entity is File &&
              RegExp(r'^draft\.udm\.[0-9a-f]{24}\.tmp$')
                  .hasMatch(entity.uri.pathSegments.last)) {
            await entity.delete();
          }
        }
      });

  static void _validate(JournalDraft draft) {
    if (draft.text.length > maxTextLength ||
        (draft.mood != null && (draft.mood! < 0 || draft.mood! > 4)) ||
        (draft.photoId != null &&
            !InventoryPhotoStore.isValidId(draft.photoId!)) ||
        (draft.entryKey != null &&
            !RegExp(r'^photo-draft-[0-9a-f]{16,64}$')
                .hasMatch(draft.entryKey!))) {
      throw const FormatException('El borrador no tiene un formato válido.');
    }
  }
}
