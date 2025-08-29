// lib/services/drive_backup_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/diary_entry.dart';

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
    // El DEVELOPER_ERROR suele dejar "status: 10" en message/details.
    final msg = ((e.message ?? '') + ' ' + (e.details ?? '').toString()).trim();
    return e.code == 'sign_in_failed' && msg.contains('status: 10');
  }

  static BackupResult<T> _mapAuthError<T>(Object e) {
    if (e is PlatformException) {
      if (_isDeveloperError(e)) {
        return const BackupResult.failure(
          'Configuración OAuth inválida: revisa SHA‑1 y package en Google Cloud.',
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
    return BackupResult.failure('Error de autenticación: $e');
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
        // Propagamos para que upload/download muestren el motivo exacto
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
      // IMPORTANTE: requestScopes es un método de GoogleSignIn,
      // no de GoogleSignInAccount.
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
      return _googleSignIn.currentUser != null || await _googleSignIn.isSignedIn();
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
    final api = await _safeDriveApi();
    if (api == null) return;

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
    Map<String, dynamic> json,
  ) async {
    try {
      final api = await _driveApi();

      final dir = await getTemporaryDirectory();
      final tmpPath = '${dir.path}/$_fileName';
      final tmp = File(tmpPath)..writeAsStringSync(jsonEncode(json));

      final media = drive.Media(
        tmp.openRead(),
        await tmp.length(),
        contentType: 'application/json',
      );
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

      final fileId = res.files!.first.id!;
      final media = await api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final bytes = <int>[];
      await media.stream.forEach(bytes.addAll);

      if (bytes.isEmpty) {
        return const BackupResult.failure('La copia está vacía.');
      }

      try {
        final decoded = utf8.decode(bytes);
        final dynamic parsed = jsonDecode(decoded);
        if (parsed is! Map<String, dynamic>) {
          return const BackupResult.failure('Formato de copia inválido (no es un objeto JSON).');
        }
        return BackupResult.success(parsed);
      } on FormatException {
        return const BackupResult.failure('JSON de la copia inválido o corrupto.');
      }
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
    Map<String, dynamic> data,
    Box udm,
    Box<DiaryEntry> diary,
  ) async {
    try {
      if (data['udm'] is Map) {
        // JSON garantiza keys String, por lo que el cast es seguro aquí.
        await udm.putAll(Map<String, dynamic>.from(data['udm'] as Map));
      }
      if (data['diary'] is List) {
        final list = List<Map<String, dynamic>>.from(data['diary'] as List);
        await diary.clear();
        await diary.addAll(list.map(_mapToDiaryEntry));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static DiaryEntry _mapToDiaryEntry(Map<String, dynamic> m) {
    DateTime created;
    final raw = m['createdAt'];
    try {
      created = raw is String ? DateTime.parse(raw) : DateTime.now();
    } catch (_) {
      created = DateTime.now();
    }
    return DiaryEntry(
      text: m['text'] ?? '',
      mood: m['mood'] ?? 2,
      createdAt: created,
    );
  }

  /* ──────────────────────── Internos ──────────────────────────── */

  // Igual que _driveApi, pero no propaga errores (para deleteBackup).
  static Future<drive.DriveApi?> _safeDriveApi() async {
    try {
      return await _driveApi();
    } catch (_) {
      return null;
    }
  }
}

/* ── Cliente HTTP autenticado que añade los auth headers de Google ─ */
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
