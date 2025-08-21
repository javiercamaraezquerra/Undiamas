import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/diary_entry.dart';

class BackupResult<T> {
  final bool ok;
  final String? message;
  final T? data;
  const BackupResult.success([this.data]) : ok = true, message = null;
  const BackupResult.failure(this.message) : ok = false, data = null;
}

class DriveBackupService {
  static const _fileName = 'udm_backup.json';

  static const List<String> _scopes = <String>[
    drive.DriveApi.driveFileScope,
    drive.DriveApi.driveAppdataScope,
  ];

  static final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: _scopes);

  /* ───────────────────── Helpers de errores ───────────────────── */

  static bool _isDeveloperError(PlatformException e) {
    // GoogleSignIn lanza PlatformException con code 'sign_in_failed'.
    // El DEVELOPER_ERROR suele dejar "status: 10" en message/details.
    final msg = (e.message ?? '') + ' ' + (e.details ?? '').toString();
    return e.code == 'sign_in_failed' && msg.contains('status: 10');
  }

  static BackupResult<T> _mapAuthError<T>(Object e) {
    if (e is PlatformException) {
      if (_isDeveloperError(e)) {
        return const BackupResult.failure(
            'Configuración OAuth inválida: revisa SHA‑1 y package en Google Cloud.');
      }
      if (e.code == GoogleSignIn.kSignInCanceledError) {
        return const BackupResult.failure('Autenticación cancelada.');
      }
      return BackupResult.failure(
          'Error de autenticación: ${e.code} ${(e.message ?? '').trim()}');
    }
    return BackupResult.failure('Error de autenticación: $e');
  }

  /* ───────────────────── Autenticación + scopes ───────────────── */

  static Future<drive.DriveApi> _driveApi() async {
    GoogleSignInAccount? acc;

    // 1) Reutiliza sesión si existe
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
      // usuario canceló
      throw const PlatformException(
        code: GoogleSignIn.kSignInCanceledError,
        message: 'cancelled',
      );
    }

    // 3) Asegura/eleva scopes (caso típico: sesión previa sin Drive)
    try {
      final granted = await acc.requestScopes(_scopes);
      if (!granted) {
        throw const PlatformException(
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

  static Future<bool> isSignedIn() async =>
      _googleSignIn.currentUser != null || await _googleSignIn.isSignedIn();

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
      Map<String, dynamic> json) async {
    try {
      final api = await _driveApi();

      final dir = await getTemporaryDirectory();
      final tmp =
          File('${dir.path}/$_fileName')..writeAsStringSync(jsonEncode(json));

      final media = drive.Media(tmp.openRead(), await tmp.length(),
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

      final data =
          jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>? ?? {};
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
      Map<String, dynamic> data, Box udm, Box<DiaryEntry> diary) async {
    try {
      if (data['udm'] is Map) {
        await udm.putAll(Map<String, dynamic>.from(data['udm']));
      }
      if (data['diary'] is List) {
        final list = List<Map<String, dynamic>>.from(data['diary']);
        await diary.clear();
        await diary.addAll(list.map(_mapToDiaryEntry));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static DiaryEntry _mapToDiaryEntry(Map<String, dynamic> m) => DiaryEntry(
        text: m['text'] ?? '',
        mood: m['mood'] ?? 2,
        createdAt: DateTime.parse(m['createdAt']),
      );

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

/* ── cliente autenticado ─ */
class _AuthenticatedClient extends http.BaseClient {
  final http.Client _inner;
  final Map<String, String> _headers;
  _AuthenticatedClient(this._inner, this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request..headers.addAll(_headers));
}
