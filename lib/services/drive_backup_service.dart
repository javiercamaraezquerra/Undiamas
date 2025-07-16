import 'dart:convert';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

class DriveBackupService {
  static const _fileName = 'udm_backup.json';

  static final _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
  );

  static Future<GoogleSignInAccount?> _signIn() async {
    var account = _googleSignIn.currentUser;
    account ??= await _googleSignIn.signInSilently();
    account ??= await _googleSignIn.signIn();
    return account;
  }

  static Future<drive.DriveApi?> _driveApi() async {
    final account = await _signIn();
    if (account == null) return null;

    final authHeaders = await account.authHeaders;
    final client =
        IOClient(HttpClient()..badCertificateCallback = (_, __, ___) => true);
    final authenticatedClient = _AuthenticatedClient(client, authHeaders);
    return drive.DriveApi(authenticatedClient);
  }

  /* ── BACKUP ── */
  static Future<bool> uploadBackup(Map<String, dynamic> json) async {
    final api = await _driveApi();
    if (api == null) return false;

    // Guarda JSON en archivo temporal
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$_fileName');
    await file.writeAsString(jsonEncode(json));

    // Comprueba si existe backup previo
    final existing = await api.files.list(
      spaces: 'appDataFolder',
      q: "name='$_fileName' and trashed=false",
      $fields: 'files(id)',
    );

    drive.File gfile = drive.File()
      ..name = _fileName
      ..parents = ['appDataFolder'];

    drive.Media media = drive.Media(file.openRead(), await file.length(),
        contentType: 'application/json');

    if (existing.files?.isNotEmpty == true) {
      // Actualiza
      await api.files.update(gfile, existing.files!.first.id!,
          uploadMedia: media);
    } else {
      await api.files.create(gfile, uploadMedia: media);
    }
    return true;
  }

  /* ── RESTORE ── */
  static Future<Map<String, dynamic>?> downloadBackup() async {
    final api = await _driveApi();
    if (api == null) return null;

    final res = await api.files.list(
      spaces: 'appDataFolder',
      q: "name='$_fileName' and trashed=false",
      orderBy: 'modifiedTime desc',
      $fields: 'files(id,modifiedTime)',
      pageSize: 1,
    );
    if (res.files?.isEmpty ?? true) return null;

    final fileId = res.files!.first.id!;
    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final bytes = <int>[];
    await media.stream.forEach(bytes.addAll);
    final content = utf8.decode(bytes);
    return jsonDecode(content) as Map<String, dynamic>;
  }

  /* ── Export/Import cajas Hive ── */
  static Map<String, dynamic> exportHive(Box<dynamic> udm, Box diary) {
    return {
      'udm': udm.toMap(),
      'diary': diary.values.map((e) => e.toMap()).toList(),
    };
  }

  static Future<void> importHive(
      Map<String, dynamic> data, Box udm, Box diary) async {
    if (data['udm'] is Map) {
      await udm.putAll(Map<String, dynamic>.from(data['udm']));
    }
    if (data['diary'] is List) {
      await diary.clear();
      await diary.addAll(
          List<Map>.from(data['diary']).map((e) => DiaryEntry.fromMap(e)));
    }
  }
}

class _AuthenticatedClient extends http.BaseClient {
  final http.Client _inner;
  final Map<String, String> _headers;
  _AuthenticatedClient(this._inner, this._headers);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request..headers.addAll(_headers));
  }
}
