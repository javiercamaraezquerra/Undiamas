import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/diary_entry.dart';
import 'encryption_service.dart';

class BackupResult<T> {
  final bool ok;
  final String? message;
  final T? data;
  const BackupResult.success([this.data]) : ok = true, message = null;
  const BackupResult.failure(this.message) : ok = false, data = null;
}

class DriveBackupService {
  static const _fileName = 'udm_backup.json';
  static final _googleSignIn =
      GoogleSignIn(scopes: [drive.DriveApi.driveAppdataScope]);

  /* ───────── autenticación ───────── */
  static Future<drive.DriveApi?> _driveApi() async {
    try {
      var acc = _googleSignIn.currentUser ??
          await _googleSignIn.signInSilently() ??
          await _googleSignIn.signIn();
      if (acc == null) return null;

      final headers = await acc.authHeaders;
      return drive.DriveApi(_AuthenticatedClient(IOClient(), headers));
    } catch (_) {
      return null;
    }
  }

  /* ───────── cifrado AES‑256 ───────── */
  static Future<String> _encryptJson(Map<String, dynamic> json) async {
    final keyBytes = await EncryptionService.getRawKey();
    final key = enc.Key(keyBytes);
    final iv = enc.IV.fromSecureRandom(16);
    final encr = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final ct = encr.encrypt(jsonEncode(json), iv: iv);
    return jsonEncode({
      'iv': base64.encode(iv.bytes),
      'data': ct.base64,
    });
  }

  static Future<Map<String, dynamic>> _decryptJson(String txt) async {
    final map = jsonDecode(txt) as Map<String, dynamic>;
    final keyBytes = await EncryptionService.getRawKey();
    final key = enc.Key(keyBytes);
    final iv = enc.IV(base64.decode(map['iv'] as String));
    final encr = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final clear =
        encr.decrypt(enc.Encrypted.fromBase64(map['data'] as String), iv: iv);
    return jsonDecode(clear) as Map<String, dynamic>;
  }

  /* ───────── SUBIDA ───────── */
  static Future<BackupResult<void>> uploadBackup(
      Map<String, dynamic> json) async {
    try {
      final api = await _driveApi();
      if (api == null) {
        return const BackupResult.failure('Autenticación cancelada.');
      }

      final dir = await getTemporaryDirectory();
      final tmp = File('${dir.path}/$_fileName')
        ..writeAsStringSync(await _encryptJson(json));

      final media =
          drive.Media(tmp.openRead(), tmp.lengthSync(), contentType: 'application/json');

      // Buscar copia previa
      final prev = await api.files.list(
        spaces: 'appDataFolder',
        q: "name='$_fileName' and trashed=false",
        $fields: 'files(id)',
      );

      if (prev.files?.isNotEmpty == true) {
        // update SIN modificar parents
        await api.files
            .update(drive.File()..name = _fileName, prev.files!.first.id!,
                uploadMedia: media);
      } else {
        final meta = drive.File()
          ..name = _fileName
          ..parents = ['appDataFolder'];
        await api.files.create(meta, uploadMedia: media);
      }
      return const BackupResult.success();
    } catch (e) {
      return BackupResult.failure('Error al subir: $e');
    }
  }

  /* ───────── DESCARGA ───────── */
  static Future<BackupResult<Map<String, dynamic>>> downloadBackup() async {
    try {
      final api = await _driveApi();
      if (api == null) {
        return const BackupResult.failure('Autenticación cancelada.');
      }

      final res = await api.files.list(
        spaces: 'appDataFolder',
        q: "name='$_fileName' and trashed=false",
        orderBy: 'modifiedTime desc',
        pageSize: 1,
        $fields: 'files(id)',
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
      final data = await _decryptJson(utf8.decode(bytes));
      return BackupResult.success(data);
    } catch (e) {
      return BackupResult.failure('Error al descargar: $e');
    }
  }

  /* ───────── export / import Hive ───────── */
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

/* ───────── cliente HTTP con auth ───────── */
class _AuthenticatedClient extends http.BaseClient {
  final http.Client _inner;
  final Map<String, String> _headers;
  _AuthenticatedClient(this._inner, this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request..headers.addAll(_headers));
}
