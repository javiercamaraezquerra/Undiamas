import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:un_dia_mas/services/inventory_photo_store.dart';
import 'package:un_dia_mas/services/journal_photo_issue.dart';

JournalPhotoIssue issue(
  Object failure, {
  JournalPhotoStage stage = JournalPhotoStage.prepare,
  bool previous = true,
  bool text = true,
  bool camera = false,
}) =>
    JournalPhotoIssue.fromFailure(failure,
        stage: stage,
        hasPreviousPhoto: previous,
        hasText: text,
        canRetry: true,
        camera: camera);

void main() {
  test('unknown failures expose no platform message or private file path', () {
    final result = issue(
        PlatformException(code: 'unknown', message: '/private/sensitive.jpg'));
    expect(result.title, 'No se pudo cambiar la foto');
    expect(
        result.message, contains('La foto anterior y tu texto se conservan.'));
    expect(result.message, isNot(contains('/private')));
    expect(result.canRetry, isTrue);
    expect(result.canChooseOther, isTrue);
  });

  test(
      'unsupported format and size offer another photo rather than the same retry',
      () {
    for (final (failure, kind) in <(Object, JournalPhotoIssueKind)>[
      (
        PlatformException(code: 'photo_unsupported'),
        JournalPhotoIssueKind.unsupported
      ),
      (
        const InventoryPhotoUnsupportedException(),
        JournalPhotoIssueKind.unsupported
      ),
      (
        PlatformException(code: 'photo_too_large'),
        JournalPhotoIssueKind.tooLarge
      ),
      (const InventoryPhotoSizeException(), JournalPhotoIssueKind.tooLarge),
    ]) {
      final result = issue(failure);
      expect(result.kind, kind);
      expect(result.canRetry, isFalse);
      expect(result.canChooseOther, isTrue);
      expect(result.message, isNot(contains('espacio')));
    }
  });

  test('unreadable image is distinct from unavailable camera and permission',
      () {
    expect(issue(const InventoryPhotoUnreadableException()).kind,
        JournalPhotoIssueKind.unreadable);
    expect(issue(PlatformException(code: 'photo_unreadable')).kind,
        JournalPhotoIssueKind.unreadable);
    final camera =
        issue(PlatformException(code: 'no_available_camera'), camera: true);
    expect(camera.title, 'La cámara no está disponible');
    expect(camera.canChooseOther, isTrue);
    final denied =
        issue(PlatformException(code: 'camera_access_denied'), camera: true);
    expect(denied.kind, JournalPhotoIssueKind.permission);
    expect(denied.message, contains('galería'));
  });

  test(
      'disk full has actionable wording and no misleading choose another action',
      () {
    final result = issue(const FileSystemException(
        'private details', '/private/file', OSError('full', 28)));
    expect(result.kind, JournalPhotoIssueKind.storage);
    expect(result.message, contains('Libera un poco'));
    expect(result.canRetry, isTrue);
    expect(result.canChooseOther, isFalse);
    expect(result.message, isNot(contains('/private')));
    expect(issue(StateError('disk'), stage: JournalPhotoStage.commit).kind,
        JournalPhotoIssueKind.storage);
  });

  test('retained content is described accurately in all draft states', () {
    final failure = StateError('failed');
    expect(issue(failure, previous: false).message,
        endsWith('Tu texto sigue aquí.'));
    expect(issue(failure, text: false).message,
        endsWith('La foto anterior se conserva.'));
    expect(issue(failure, previous: false, text: false).message,
        endsWith('Puedes continuar sin foto.'));
  });

  test('only cancellation codes are treated as quiet cancellation', () {
    expect(
        JournalPhotoIssue.isCancellation(
            PlatformException(code: 'camera_cancelled')),
        isTrue);
    expect(
        JournalPhotoIssue.isCancellation(
            PlatformException(code: 'photo_unreadable')),
        isFalse);
    expect(JournalPhotoIssue.isCancellation(StateError('cancelled')), isFalse);
  });
}
