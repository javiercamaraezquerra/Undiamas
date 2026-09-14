import 'dart:io';

import 'package:flutter/services.dart';

import 'inventory_photo_store.dart';

enum JournalPhotoStage { draft, picker, recovery, prepare, commit }

enum JournalPhotoIssueKind {
  permission,
  unavailable,
  unsupported,
  unreadable,
  tooLarge,
  storage,
  unknown
}

/// Only app-authored messages reach the UI; platform errors can contain paths.
class JournalPhotoIssue {
  const JournalPhotoIssue({
    required this.title,
    required this.message,
    required this.kind,
    this.canRetry = true,
    this.canChooseOther = true,
  });

  final String title;
  final String message;
  final JournalPhotoIssueKind kind;
  final bool canRetry;
  final bool canChooseOther;

  static bool isCancellation(Object failure) =>
      failure is PlatformException &&
      const {'cancelled', 'canceled', 'camera_cancelled', 'photo_cancelled'}
          .contains(failure.code);

  factory JournalPhotoIssue.fromFailure(
    Object failure, {
    required JournalPhotoStage stage,
    required bool hasPreviousPhoto,
    required bool hasText,
    required bool canRetry,
    required bool camera,
  }) {
    var kind = JournalPhotoIssueKind.unknown;
    var title = hasPreviousPhoto
        ? 'No se pudo cambiar la foto'
        : 'No se pudo añadir la foto';
    var detail = 'Vuelve a intentarlo o elige otra imagen.';
    var retry = canRetry;
    var other = true;
    final code = failure is PlatformException ? failure.code : null;

    if (stage == JournalPhotoStage.draft ||
        stage == JournalPhotoStage.commit ||
        code == 'photo_storage' ||
        (failure is FileSystemException && failure.osError?.errorCode == 28)) {
      kind = JournalPhotoIssueKind.storage;
      title = 'No se pudo guardar el adjunto';
      detail = failure is FileSystemException &&
              failure.osError?.errorCode == 28
          ? 'El móvil no tiene espacio disponible. Libera un poco y reintenta.'
          : 'Comprueba el espacio disponible y vuelve a intentarlo.';
      other = false;
    } else if (const {
      'camera_access_denied',
      'camera_access_restricted',
      'photo_access_denied',
      'photo_access_restricted'
    }.contains(code)) {
      kind = JournalPhotoIssueKind.permission;
      title = camera
          ? 'No se pudo acceder a la cámara'
          : 'No se pudo acceder a la foto';
      detail = camera
          ? 'El móvil no ha permitido usar la cámara. Puedes elegir una foto de la galería.'
          : 'La galería no permitió abrir esa imagen. Vuelve a seleccionarla.';
    } else if (code == 'no_available_camera' || code == 'camera_unavailable') {
      kind = JournalPhotoIssueKind.unavailable;
      title = 'La cámara no está disponible';
      detail = 'Puedes volver a intentarlo o elegir una foto de la galería.';
    } else if (failure is InventoryPhotoSizeException ||
        code == 'photo_too_large') {
      kind = JournalPhotoIssueKind.tooLarge;
      detail = 'Esta imagen es demasiado grande. Elige una copia más pequeña.';
      retry = false;
    } else if (failure is InventoryPhotoUnsupportedException ||
        code == 'photo_unsupported') {
      kind = JournalPhotoIssueKind.unsupported;
      detail = 'Este móvil no puede abrir ese formato. Prueba con otra foto.';
      retry = false;
    } else if (failure is InventoryPhotoUnreadableException ||
        failure is InventoryPhotoException ||
        failure is FileSystemException ||
        code == 'photo_unreadable') {
      kind = JournalPhotoIssueKind.unreadable;
      detail =
          'No se pudo leer la imagen. Ábrela en tu galería y vuelve a elegirla.';
    } else if (code == 'already_active') {
      detail =
          'Hay una selección de fotos pendiente. Termínala y vuelve a intentarlo.';
    } else if (stage == JournalPhotoStage.recovery) {
      title = 'La foto quedó pendiente';
      detail = 'No se pudo recuperar la selección. Vuelve a elegir la foto.';
    } else if (stage == JournalPhotoStage.picker && camera) {
      title = 'No se pudo abrir la cámara';
      detail = 'Prueba de nuevo o elige una foto de la galería.';
    }
    final retained = hasPreviousPhoto
        ? (hasText
            ? 'La foto anterior y tu texto se conservan.'
            : 'La foto anterior se conserva.')
        : (hasText ? 'Tu texto sigue aquí.' : 'Puedes continuar sin foto.');
    return JournalPhotoIssue(
        title: title,
        message: '$detail $retained',
        kind: kind,
        canRetry: retry,
        canChooseOther: other);
  }
}
