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

/// Excepción controlada para errores de autenticación
class BackupAuthException implements Exception {
  final String message;
  BackupAuthException(this.message);
  @override
  String toString() => message;
}

class DriveBackupService {
  static const _fileName = 'udm_backup.json';

  static const List<String> _requiredScopes = [
    drive.DriveApi.driveFileScope,
    drive.DriveApi.driveAppdataScope,
  ];

  static final _googleSignIn = GoogleSignIn(scopes: _requiredScopes);

  /* ── autenticación (con diagnóstico) ── */
  static Future<drive.DriveApi> _driveApi() async {
    try {
      // 1) Cuenta actual o login (silencioso → interactivo)
      var acc = _googleSignIn.currentUser
          ?? await _googleSignIn.signInSilently()
          ?? await _googleSignIn.signIn();

      if (acc == null) {
        throw BackupAuthException('Autenticación cancelada por el usuario.');
      }

      // 2) Asegurar los scopes de Drive (incremental auth)
      final granted = await _googleSignIn.requestScopes(_requiredScopes);
      if (!granted) {
        throw BackupAuthException(
            'Permisos de Google Drive no concedidos por el usuario.');
      }

      // 3) Cliente autenticado
      final headers = await acc.authHeaders;
      return drive.DriveApi(_AuthenticatedClient(IOClient(), headers));
    } on PlatformException catch (e) {
      throw BackupAuthException(_explainSignInError(e));
    } catch (e) {
      throw BackupAuthException('No se pudo iniciar sesión: $e');
    }
  }

  static String _explainSignInError(PlatformException e) {
    final blob =
        '${e.code}|${e.message}|${e.details}'.toUpperCase().replaceAll(' ', '');
    // 12501 / SIGN_IN_CANCELLED → usuario cancela
    if (blob.contains('12501') || blob.contains('CANCEL')) {
      return 'Autenticación cancelada por el usuario.';
    }
    // 10 / DEVELOPER_ERROR → SHA‑1 o package no coinciden en el cliente OAuth Android
    if (blob.contains('DEVELOPER_ERROR') || blob.contains('10')) {
      return 'Configuración OAuth inválida: revisa SHA‑1 y package en Google Cloud.';
    }
    // 12500 / SIGN_IN_FAILED
    if (blob.contains('12500') || blob.contains('FAILED')) {
      return 'Fallo en el inicio de sesión de Google. Reinténtalo más tarde.';
    }
    // 7 / NETWORK_ERROR
    if (blob.contains('7') || blob.contains('NETWORK')) {
      return 'Sin conexión de red o sin Google Play Services.';
    }
    return 'Error de autenticación de Google: ${e.code}';
  }

  /* ──────────── PÚBLICO ──────────── */

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
    try {
      final api = await _driveApi();
      final res = await api.files.list(
        spaces: 'appDataFolder',
        q: "name='$_fileName' and trashed=false",
        $fields: 'files(id)',
      );
      for (final f in res.files ?? <drive.File>[]) {
        await api.files.delete(f.id!);
      }
    } on BackupAuthException {
      // sin auth -> ignoramos (best effort)
      return;
    } catch (_) {
      // silencioso
    }
  }

  /* ── SUBIR / ACTUALIZAR ─ */
  static Future<BackupResult<void>> uploadBackup(
      Map<String, dynamic> json) async {
    try {
      final api = await _driveApi();

      final dir = await getTemporaryDirectory();
      final tmp =
          File('${dir.path}/$_fileName')..writeAsStringSync(jsonEncode(json));

      final media = drive.Media(tmp.openRead(), await tmp.length(),
          contentType: 'application/json');
      final metaCreate = drive.File()..name = _fileName;

      final prev = await api.files.list(
        spaces: 'appDataFolder',
        q: "name='$_fileName' and trashed=false",
        $fields: 'files(id)',
      );

      if (prev.files?.isNotEmpty == true) {
        await api.files.update(metaCreate, prev.files!.first.id!,
            uploadMedia: media);
      } else {
        metaCreate.parents = ['appDataFolder'];
        await api.files.create(metaCreate, uploadMedia: media);
      }
      return const BackupResult.success();
    } on BackupAuthException catch (e) {
      return BackupResult.failure(e.message);
    } catch (e) {
      return BackupResult.failure('Error al subir: $e');
    }
  }

  /* ── DESCARGAR ─ */
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
    } on BackupAuthException catch (e) {
      return BackupResult.failure(e.message);
    } catch (e) {
      return BackupResult.failure('Error al descargar: $e');
    }
  }

  /* ── EXPORT / IMPORT (sin cambios) ─ */
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
