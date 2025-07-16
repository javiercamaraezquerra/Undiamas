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

  static final _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope], // acceso solo a archivos creados
  );

  /* ───── helpers de autenticación ───── */
  static Future<GoogleSignInAccount?> _signIn() async {
    var account = _googleSignIn.currentUser;
    account ??= await _googleSignIn.signInSilently();
    account ??= await _googleSignIn.signIn();
    return account;
  }

  static Future<drive.DriveApi?> _driveApi() async {
    final account = await _signIn();
    if (account == null) return null;

    final headers = await account.authHeaders;
    final client = _AuthenticatedClient(IOClient(), headers);
    return drive.DriveApi(client);
  }

  /* ───── BACKUP (subida) ───── */
  static Future<bool> uploadBackup(Map<String, dynamic> json) async {
    final api = await _driveApi();
    if (api == null) return false;

    final dir = await getTemporaryDirectory();
    final tmp = File('${dir.path}/$_fileName')..writeAsStringSync(jsonEncode(json));

    final media =
        drive.Media(tmp.openRead(), await tmp.length(), contentType: 'application/json');
    final fileMeta = drive.File()
      ..name = _fileName
      ..parents = ['appDataFolder'];

    /* ¿existe copia previa? */
    final prev = await api.files.list(
      spaces: 'appDataFolder',
      q: "name='$_fileName' and trashed=false",
      $fields: 'files(id)',
    );

    if (prev.files?.isNotEmpty == true) {
      await api.files.update(fileMeta, prev.files!.first.id!, uploadMedia: media);
    } else {
      await api.files.create(fileMeta, uploadMedia: media);
    }
    return true;
  }

  /* ───── RESTORE (descarga) ───── */
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

    final fileId = res.files!.first.id!;
    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final bytes = <int>[];
    await media.stream.forEach(bytes.addAll);
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  /* ───── Exporta / importa las cajas Hive ───── */
  static Map<String, dynamic> exportHive(Box udm, Box<DiaryEntry> diary) {
    return {
      'udm': udm.toMap(),
      'diary': diary.values
          .map((e) => {'text': e.text, 'mood': e.mood, 'date': e.date.toIso8601String()})
          .toList(),
    };
  }

  static Future<void> importHive(
      Map<String, dynamic> data, Box udm, Box<DiaryEntry> diary) async {
    if (data['udm'] is Map) await udm.putAll(Map<String, dynamic>.from(data['udm']));

    if (data['diary'] is List) {
      await diary.clear();
      final list = List<Map<String, dynamic>>.from(data['diary']);
      await diary.addAll(list.map(_mapToDiaryEntry));
    }
  }

  /* ───── util privado ───── */
  static DiaryEntry _mapToDiaryEntry(Map<String, dynamic> m) => DiaryEntry(
        text: m['text'] as String? ?? '',
        mood: m['mood'] as int? ?? 2,
        date: DateTime.parse(m['date'] as String),
      );
}

/* ───── cliente autenticado ───── */
class _AuthenticatedClient extends http.BaseClient {
  final http.Client _inner;
  final Map<String, String> _headers;
  _AuthenticatedClient(this._inner, this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request..headers.addAll(_headers));
  }
}
