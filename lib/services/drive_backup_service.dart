import 'dart:convert';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/diary_entry.dart';

class DriveBackupService {
  static const _fileName = 'udm_backup.json';
  static final _googleSignIn =
      GoogleSignIn(scopes: [drive.DriveApi.driveFileScope]);

  /* ── autenticación ── */
  static Future<drive.DriveApi?> _driveApi() async {
    var acc = _googleSignIn.currentUser ??
        await _googleSignIn.signInSilently() ??
        await _googleSignIn.signIn();
    if (acc == null) return null;

    final headers = await acc.authHeaders;
    return drive.DriveApi(_AuthenticatedClient(IOClient(), headers));
  }

  /* ── subida ── */
  static Future<bool> uploadBackup(Map<String, dynamic> json) async {
    final api = await _driveApi();
    if (api == null) return false;

    final dir = await getTemporaryDirectory();
    final tmp = File('${dir.path}/$_fileName')..writeAsStringSync(jsonEncode(json));

    final media =
        drive.Media(tmp.openRead(), await tmp.length(), contentType: 'application/json');
    final meta =
        drive.File()..name = _fileName..parents = ['appDataFolder'];

    final prev = await api.files.list(
      spaces: 'appDataFolder',
      q: "name='$_fileName' and trashed=false",
      $fields: 'files(id)',
    );

    if (prev.files?.isNotEmpty == true) {
      await api.files.update(meta, prev.files!.first.id!, uploadMedia: media);
    } else {
      await api.files.create(meta, uploadMedia: media);
    }
    return true;
  }

  /* ── descarga ── */
  static Future<Map<String, dynamic>?> downloadBackup() async {
    final api = await _driveApi();
    if (api == null) return null;

    final res = await api.files.list(
      spaces: 'appDataFolder',
      q: "name='$_fileName' and trashed=false",
      orderBy: 'modifiedTime desc',
      pageSize: 1,
      $fields: 'files(id)',
    );
    if (res.files?.isEmpty ?? true) return null;

    final media = await api.files.get(
      res.files!.first.id!,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final bytes = <int>[];
    await media.stream.forEach(bytes.addAll);
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  /* ── export / import Hive ── */
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

  /// Devuelve `true` si se restauró algo, `false` si hubo error o lista vacía.
  static Future<bool> importHive(
      Map<String, dynamic> data, Box udm, Box<DiaryEntry> diary) async {
    try {
      if (data['udm'] is Map) await udm.putAll(Map<String, dynamic>.from(data['udm']));

      if (data['diary'] is List) {
        final list = List<Map<String, dynamic>>.from(data['diary']);
        await diary.clear();
        await diary.addAll(list.map(_mapToDiaryEntry));
        return true;
      }
    } catch (_) {
      /* ignora y devuelve false */
    }
    return false;
  }

  static DiaryEntry _mapToDiaryEntry(Map<String, dynamic> m) => DiaryEntry(
        text: m['text'] ?? '',
        mood: m['mood'] ?? 2,
        createdAt: DateTime.parse(m['createdAt']),
      );
}

/* ── cliente autenticado ── */
class _AuthenticatedClient extends http.BaseClient {
  final http.Client _inner;
  final Map<String, String> _headers;
  _AuthenticatedClient(this._inner, this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request..headers.addAll(_headers));
}
