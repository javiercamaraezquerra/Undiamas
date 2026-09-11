// lib/services/drive_backup_service.dart
import 'dart:convert';

import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;
import 'package:hive/hive.dart';

import '../models/diary_entry.dart';
import 'hive_restore_service.dart';

class BackupResult<T> {
  final bool ok;
  final String? message;
  final T? data;

  const BackupResult.success([this.data])
      : ok = true,
        message = null;

  const BackupResult.failure(this.message)
      : ok = false,
        data = null;
}

class DriveBackupService {
  static const _fileName = 'udm_backup.json';

  static const List<String> _scopes = <String>[
    drive.DriveApi.driveFileScope,
    drive.DriveApi.driveAppdataScope,
  ];

  // Código de error estándar que devuelve GoogleSignIn al cancelar
  static const String _signInCanceledCode = 'sign_in_canceled';

  static final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: _scopes);

  /* ───────────────────── Helpers de errores ───────────────────── */

  static bool _isDeveloperError(PlatformException e) {
    // GoogleSignIn lanza PlatformException con code 'sign_in_failed'.
    // El DEVELOPER_ERROR suele dejar "status: 10" o "ApiException: 10" en message/details.
    final msg =
        ((e.message ?? '') + ' ' + (e.details ?? '').toString()).toLowerCase();
    if (e.code != 'sign_in_failed') return false;
    return msg.contains('status: 10') ||
        msg.contains('apiexception: 10') ||
        RegExp(r'\b10:?(\s|$)').hasMatch(msg) ||
        msg.contains('developer_error');
  }

  static BackupResult<T> _mapAuthError<T>(Object e) {
    if (e is PlatformException) {
      if (_isDeveloperError(e)) {
        return const BackupResult.failure(
          'Configuración OAuth inválida: revisa SHA‑1 (debug/release/Play) y el package '
          'en Google Cloud para com.celsoriaapps.undiamas.',
        );
      }
      if (e.code == _signInCanceledCode) {
        return const BackupResult.failure('Autenticación cancelada.');
      }
      final details = (e.message ?? '').trim();
      return BackupResult.failure(
        'Error de autenticación: ${e.code}${details.isNotEmpty ? ' $details' : ''}',
      );
    }
    return const BackupResult.failure('Error de autenticación desconocido.');
  }

  /* ───────────────────── Autenticación + scopes ───────────────── */

  static Future<drive.DriveApi> _driveApi() async {
    GoogleSignInAccount? acc;

    // 1) Reutiliza sesión si existe o intenta silenciosamente
    try {
      acc = _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
    } on PlatformException {
      acc = null; // ignoramos fallos silenciosos
    }

    // 2) Pide login si no había sesión
    if (acc == null) {
      try {
        acc = await _googleSignIn.signIn();
      } on PlatformException catch (e) {
        // propagamos para que upload/download muestren el motivo exacto
        throw e;
      }
    }

    if (acc == null) {
      // Usuario canceló
      throw PlatformException(
        code: _signInCanceledCode,
        message: 'cancelled',
      );
    }

    // 3) Asegura/eleva scopes (caso típico: sesión previa sin Drive)
    try {
      // IMPORTANTE: requestScopes es un método de GoogleSignIn, no de GoogleSignInAccount.
      final granted = await _googleSignIn.requestScopes(_scopes);
      if (!granted) {
        throw PlatformException(
          code: 'scopes_denied',
          message: 'Permisos de Google Drive denegados por el usuario.',
        );
      }
    } on PlatformException catch (e) {
      throw e;
    }

    final headers = await acc.authHeaders;
    return drive.DriveApi(_AuthenticatedClient(IOClient(), headers));
  }

  /* ─────────────────────────── PÚBLICO ────────────────────────── */

  static Future<bool> isSignedIn() async {
    try {
      return _googleSignIn.currentUser != null ||
          await _googleSignIn.isSignedIn();
    } catch (_) {
      return false;
    }
  }

  static Future<void> disconnect() async {
    try {
      await _googleSignIn.disconnect();
    } catch (_) {
      await _googleSignIn.signOut();
    }
  }

  static Future<void> deleteBackup() async {
    // Authentication failure/cancellation must reach the caller before it
    // deletes local data or reports that the cloud copy was removed.
    final api = await _driveApi();

    final res = await api.files.list(
      spaces: 'appDataFolder',
      q: "name='$_fileName' and trashed=false",
      $fields: 'files(id)',
    );
    for (final f in res.files ?? <drive.File>[]) {
      await api.files.delete(f.id!);
    }
  }

  /* ─────────────────────── SUBIR / ACTUALIZAR ─────────────────── */

  static Future<BackupResult<void>> uploadBackup(
      Map<String, dynamic> json) async {
    try {
      final api = await _driveApi();

      // Preserve the legacy UTF-8 JSON format without leaving a plaintext
      // Inventory copy in the application's temporary directory.
      final bytes = utf8.encode(jsonEncode(json));
      final media = drive.Media(Stream<List<int>>.value(bytes), bytes.length,
          contentType: 'application/json');
      final meta = drive.File()..name = _fileName;

      final prev = await api.files.list(
        spaces: 'appDataFolder',
        q: "name='$_fileName' and trashed=false",
        $fields: 'files(id)',
      );

      if (prev.files?.isNotEmpty == true) {
        await api.files.update(meta, prev.files!.first.id!, uploadMedia: media);
      } else {
        meta.parents = ['appDataFolder'];
        await api.files.create(meta, uploadMedia: media);
      }
      return const BackupResult.success();
    } on PlatformException catch (e) {
      return _mapAuthError<void>(e);
    } catch (e) {
      return BackupResult.failure('Error al subir: $e');
    }
  }

  /* ─────────────────────────── DESCARGAR ──────────────────────── */

  static Future<BackupResult<Map<String, dynamic>>> downloadBackup() async {
    try {
      final api = await _driveApi();

      final res = await api.files.list(
        spaces: 'appDataFolder',
        q: "name='$_fileName' and trashed=false",
        orderBy: 'modifiedTime desc',
        pageSize: 1,
        $fields: 'files(id,size)',
      );
      if (res.files?.isEmpty ?? true) {
        return const BackupResult.failure('No hay copia en Drive.');
      }

      final media = await api.files.get(
        res.files!.first.id!,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final bytes = <int>[];
      await media.stream.forEach(bytes.addAll);
      if (bytes.isEmpty) {
        return const BackupResult.failure('La copia está vacía.');
      }

      final decoded = utf8.decode(bytes);
      final data = jsonDecode(decoded) as Map<String, dynamic>? ?? {};
      return BackupResult.success(data);
    } on PlatformException catch (e) {
      return _mapAuthError<Map<String, dynamic>>(e);
    } catch (e) {
      return BackupResult.failure('Error al descargar: $e');
    }
  }

  /* ────────────────────── EXPORT / IMPORT ─────────────────────── */

  static Map<String, dynamic> exportHive(Box udm, Box<DiaryEntry> diary) => {
        'udm': udm.toMap(),
        'diary': diary.values
            .map((e) => {
                  'text': e.text,
                  'mood': e.mood,
                  'createdAt': e.createdAt.toIso8601String(),
                })
            .toList(),
      };

  static Future<bool> importHive(
          Map<String, dynamic> data, Box udm, Box<DiaryEntry> diary) async =>
      (await importHiveSafely(data, udm, diary)).ok;

  /// Callers should present this structured result instead of assuming that
  /// every failed import means the copy was empty or that nothing was changed.
  static Future<HiveRestoreResult> importHiveSafely(
      Map<String, dynamic> data, Box udm, Box<DiaryEntry> diary) async {
    final PreparedHiveBackup prepared;
    try {
      prepared = HiveRestoreService.prepare(data);
    } on FormatException catch (error) {
      return HiveRestoreResult(
          ok: false,
          message: '${error.message} No se han modificado tus datos.');
    }
    return HiveRestoreService.instance.restore(prepared, udm, diary);
  }
}

/* ── cliente autenticado ─ */
class _AuthenticatedClient extends http.BaseClient {
  final http.Client _inner;
  final Map<String, String> _headers;

  _AuthenticatedClient(this._inner, this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
