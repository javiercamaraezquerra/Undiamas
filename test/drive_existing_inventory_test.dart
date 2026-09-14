import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:image/image.dart' as img;
import 'package:un_dia_mas/models/diary_entry.dart';
import 'package:un_dia_mas/services/drive_backup_service.dart';
import 'package:un_dia_mas/services/hive_restore_service.dart';
import 'package:un_dia_mas/services/inventory_photo_store.dart';
import 'package:un_dia_mas/services/journal_composer_controller.dart';
import 'package:un_dia_mas/services/journal_draft_store.dart';

const _google = MethodChannel('plugins.flutter.io/google_sign_in');
const _paths = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final key = Uint8List.fromList(List.generate(32, (index) => index));
  late Directory directory;
  late Directory temporary;
  late Box<dynamic> settings;
  late Box<DiaryEntry> diary;
  late _FixtureDrive transport;
  final photos = <String, Uint8List>{};

  Future<void> openBoxes() async {
    Hive.init('${directory.path}/hive');
    settings =
        await Hive.openBox('udm_secure', encryptionCipher: HiveAesCipher(key));
    diary = await Hive.openBox<DiaryEntry>('diary_secure',
        encryptionCipher: HiveAesCipher(key));
  }

  Future<String> photograph(int red, int green, int blue) async {
    final picture = img.Image(width: 12, height: 8);
    img.fill(picture, color: img.ColorRgb8(red, green, blue));
    final jpeg = Uint8List.fromList(img.encodeJpg(picture));
    final id = sha256.convert(jpeg).toString();
    await InventoryPhotoStore.instance.importPrepared(id, jpeg);
    photos[id] = jpeg;
    return id;
  }

  Future<T> withDrive<T>(Future<T> Function() operation) =>
      HttpOverrides.runZoned(operation, createHttpClient: (_) => transport);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('udm_existing_drive_');
    temporary = await Directory('${directory.path}/cache').create();
    photos.clear();
    transport = _FixtureDrive();
    FlutterSecureStorage.setMockInitialValues(
        {'hive_key': base64UrlEncode(key)});
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_paths,
        (call) async {
      if (call.method == 'getTemporaryDirectory') return temporary.path;
      if (call.method == 'getApplicationSupportDirectory') {
        return '${directory.path}/support';
      }
      throw StateError('Unexpected fixture path method ${call.method}');
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_google,
        (call) async {
      switch (call.method) {
        case 'init':
        case 'disconnect':
        case 'signOut':
        case 'signInSilently':
          return null;
        case 'signIn':
          return {'email': 'synthetic@example.invalid', 'id': 'fixture'};
        case 'requestScopes':
          return true;
        case 'getTokens':
          return {'accessToken': 'synthetic-token-not-real'};
        default:
          throw StateError('Unexpected fixture sign-in method ${call.method}');
      }
    });
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(DiaryEntryAdapter());
    await openBoxes();
    await DriveBackupService.disconnect();
  });

  tearDown(() async {
    await DriveBackupService.disconnect();
    await Hive.close();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_google, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_paths, null);
    FlutterSecureStorage.setMockInitialValues({});
    final actual = await directory.resolveSymbolicLinks();
    final root = await Directory.systemTemp.resolveSymbolicLinks();
    expect(
        actual.toLowerCase(),
        startsWith(
            '${root.toLowerCase()}${Platform.pathSeparator}udm_existing_drive_'));
    await directory.delete(recursive: true);
  });

  test(
      'first Drive copy includes persisted inventory; later save and download keep every entry and photo',
      () async {
    final landscape = await photograph(150, 60, 20);
    final sunset = await photograph(200, 110, 10);
    final pendingPhoto = await photograph(20, 80, 150);
    final priorSettings = {
      'startDate': '2024-02-29T09:30:00.000',
      'substance': 'Tabaco',
      'unknown': {
        'keep': true,
        'values': [1, 'ñ 🙂']
      },
    };
    final existing = <DiaryEntry>[
      DiaryEntry(
          text: '  Guardado antes de activar Drive\nñ 🙂 中文  ',
          mood: 0,
          createdAt: DateTime.utc(2020, 2, 29, 9, 30)),
      DiaryEntry(
          text: 'Recuerdo antiguo con fotografía',
          mood: 2,
          createdAt: DateTime(2024, 3, 31, 1, 59, 59, 123),
          photoId: landscape),
      DiaryEntry(
          text: '',
          mood: 4,
          createdAt: DateTime.utc(2025, 10, 26, 2, 30),
          photoId: sunset),
      DiaryEntry(
          text: 'Otra entrada con la misma fotografía',
          mood: 1,
          createdAt: DateTime(2026, 1, 2),
          photoId: landscape),
    ];
    await settings.putAll(priorSettings);
    await diary.putAll({
      7: existing[0],
      91: existing[1],
      'old-photo-only': existing[2],
      'another-existing': existing[3]
    });
    await settings.flush();
    await diary.flush();
    // Close/reopen before the first backup: these are already saved entries,
    // not records constructed by the backup UI or a pending composer snapshot.
    await Hive.close();
    await openBoxes();
    await JournalDraftStore.instance.save(JournalDraft(
        text: 'Entrada nueva todavía sin guardar',
        mood: 3,
        photoId: pendingPhoto,
        entryKey: 'photo-draft-0123456789abcdef'));
    final expectedPrior = existing.map(_entry).toList();
    final result = await withDrive(() => DriveBackupService.uploadBackup(
        DriveBackupService.exportHive(settings, diary)));
    expect(result.ok, isTrue, reason: result.message);
    expect(transport.uploads, hasLength(1));
    final firstCopy = _readCopy(transport.uploads.first);
    expect(firstCopy.manifest['version'], 2);
    expect(firstCopy.manifest['udm'], priorSettings);
    expect(firstCopy.manifest['diary'], unorderedEquals(expectedPrior));
    expect(firstCopy.photos.keys, unorderedEquals([landscape, sunset]));
    for (final photo in firstCopy.photos.entries) {
      expect(photo.value, photos[photo.key]);
      expect(sha256.convert(photo.value).toString(), photo.key);
    }
    // Unsaved drafts and their photos are excluded until Save succeeds.
    expect(firstCopy.photos.containsKey(pendingPhoto), isFalse);
    expect((await JournalDraftStore.instance.load())!.photoId, pendingPhoto);

    final controller = JournalComposerController(
        box: diary,
        gateway: DeviceJournalAttachmentGateway(useAndroidPhotoPreparer: false),
        restore: HiveRestoreService());
    try {
      await controller.initialize();
      expect(controller.text, 'Entrada nueva todavía sin guardar');
      final saved = await controller.saveEntry(afterSave: () async {
        // Same ordering as JournalScreen: committed Hive -> full exporter ->
        // Drive upload while the shared mutation lock remains held.
        expect(diary.length, 5);
        final updated = await withDrive(() => DriveBackupService.uploadBackup(
            DriveBackupService.exportHive(settings, diary)));
        expect(updated.ok, isTrue, reason: updated.message);
      });
      expect(saved, isTrue);
    } finally {
      controller.dispose();
    }
    final newEntry = diary.get('photo-draft-0123456789abcdef')!;
    final expectedAll = [...expectedPrior, _entry(newEntry)];
    final secondCopy = _readCopy(transport.uploads.last);
    expect(secondCopy.manifest['version'], 2);
    expect(secondCopy.manifest['udm'], priorSettings);
    expect(secondCopy.manifest['diary'], unorderedEquals(expectedAll));
    expect(secondCopy.photos.keys, unorderedEquals(photos.keys));
    for (final photo in secondCopy.photos.entries) {
      expect(photo.value, photos[photo.key]);
      expect(sha256.convert(photo.value).toString(), photo.key);
    }
    expect(transport.requests.map((request) => request.method),
        ['GET', 'POST', 'GET', 'PATCH']);
    for (final request in transport.requests.where((r) => r.method == 'GET')) {
      expect(request.uri.queryParameters['q'],
          "name='${DriveBackupService.archiveFileName()}' and trashed=false");
    }
    expect(await JournalDraftStore.instance.load(), isNull);

    // Exercise the real download/ZIP-validation/import path against that exact
    // stored body. Only synthetic local photos are removed, to prove download
    // restores their bytes instead of succeeding thanks to an existing cache.
    await InventoryPhotoStore.instance.clear();
    final downloaded = await withDrive(DriveBackupService.downloadBackup);
    expect(downloaded.ok, isTrue, reason: downloaded.message);
    expect(downloaded.data, secondCopy.manifest);
    expect(HiveRestoreService.prepare(downloaded.data!).entryCount, 5);
    for (final photo in photos.entries) {
      expect(await InventoryPhotoStore.instance.read(photo.key), photo.value);
    }
    await Hive.close();
    await openBoxes();
    // Hive's DateTime adapter persists milliseconds. The ZIP above preserves
    // the full exported value, while the reopened local entry follows Hive's
    // existing precision (a newly created DateTime.now can have microseconds).
    final persistedExpected = expectedAll.map((entry) {
      final date = DateTime.parse(entry['createdAt'] as String);
      return {
        ...entry,
        'createdAt': DateTime.fromMillisecondsSinceEpoch(
                date.millisecondsSinceEpoch,
                isUtc: date.isUtc)
            .toIso8601String(),
      };
    });
    expect(
        diary.values.map(_entry).toList(), unorderedEquals(persistedExpected));
    expect(settings.toMap(), priorSettings);
    expect(await temporary.list().toList(), isEmpty);
  });

  test('missing old photograph cannot replace a complete existing Drive copy',
      () async {
    final id = await photograph(30, 60, 90);
    await diary.put(
        'existing',
        DiaryEntry(
            text: 'Ya guardada',
            mood: 2,
            createdAt: DateTime.utc(2024, 1, 1),
            photoId: id));
    await diary.flush();
    final original = DriveBackupService.exportHive(settings, diary);
    final initial =
        await withDrive(() => DriveBackupService.uploadBackup(original));
    expect(initial.ok, isTrue, reason: initial.message);
    final retainedRemote = Uint8List.fromList(transport.uploads.single);
    await InventoryPhotoStore.instance.delete(id);
    final requestCount = transport.requests.length;
    final failed = await withDrive(() => DriveBackupService.uploadBackup(
        DriveBackupService.exportHive(settings, diary)));
    expect(failed.ok, isFalse);
    expect(transport.requests.length, requestCount);
    expect(transport.uploads, hasLength(1));
    expect(transport.uploads.single, retainedRemote);
    expect(DriveBackupService.exportHive(settings, diary), original);
    expect(await temporary.list().toList(), isEmpty);
  });
}

Map<String, dynamic> _entry(DiaryEntry entry) => {
      'text': entry.text,
      'mood': entry.mood,
      'createdAt': entry.createdAt.toIso8601String(),
      'photoId': entry.photoId,
    };

({Map<String, dynamic> manifest, Map<String, Uint8List> photos}) _readCopy(
    List<int> bytes) {
  final zip = ZipDecoder().decodeBytes(bytes, verify: true);
  final manifest =
      jsonDecode(utf8.decode(zip.findFile('manifest.json')!.content))
          as Map<String, dynamic>;
  final photographs = <String, Uint8List>{};
  for (final member
      in zip.files.where((file) => file.name != 'manifest.json')) {
    expect(member.name, matches(r'^photos/[a-f0-9]{64}\.jpg$'));
    final id = member.name.substring('photos/'.length, member.name.length - 4);
    expect(photographs.containsKey(id), isFalse);
    photographs[id] = Uint8List.fromList(member.content);
  }
  return (manifest: manifest, photos: photographs);
}

// In-memory Drive protocol fixture. No network sockets or real Google accounts.
class _FixtureDrive implements HttpClient {
  final requests = <_Request>[];
  final uploads = <Uint8List>[];
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final request = _Request(method, url, (request) {
      if (method == 'GET') {
        if (url.path != '/drive/v3/files') return _Response.bytes(uploads.last);
        return _Response.json({
          'files': uploads.isEmpty
              ? []
              : [
                  {'id': 'synthetic-existing', 'size': '${uploads.last.length}'}
                ]
        });
      }
      if (method != 'POST' && method != 'PATCH') {
        throw StateError('Unexpected fixture method $method');
      }
      final boundary = request.headers
          .value('content-type')!
          .split('boundary=')
          .last
          .replaceAll('"', '');
      final parts = utf8.decode(request.body).split('--$boundary');
      final metadata = parts.firstWhere((part) => part.contains('"name"'));
      expect(
          (jsonDecode(metadata.split('\r\n\r\n').last.trim()) as Map)['name'],
          DriveBackupService.archiveFileName());
      final media = parts.firstWhere(
          (part) => part.contains('Content-Transfer-Encoding: base64'));
      uploads.add(
          base64.decode(media.substring(media.indexOf('\r\n\r\n') + 4).trim()));
      return _Response.json({'id': 'synthetic-existing'});
    });
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.method, this.uri, this.response);
  @override
  final String method;
  @override
  final Uri uri;
  final HttpClientResponse Function(_Request) response;
  final body = <int>[];
  @override
  final headers = _Headers();
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  int contentLength = -1;
  @override
  bool persistentConnection = true;
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      body.addAll(chunk);
    }
  }

  @override
  Future<HttpClientResponse> close() async => response(this);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  final values = <String, List<String>>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = [value.toString()];
  }

  @override
  String? value(String name) => values[name.toLowerCase()]?.join(',');
  @override
  void forEach(void Function(String name, List<String> values) action) =>
      values.forEach(action);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response.json(Object value) : body = utf8.encode(jsonEncode(value)) {
    headers.set('content-type', 'application/json; charset=utf-8');
  }
  _Response.bytes(this.body) {
    headers.set('content-type', 'application/octet-stream');
  }
  final List<int> body;
  @override
  final headers = _Headers();
  @override
  int get statusCode => 200;
  @override
  int get contentLength => body.length;
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => false;
  @override
  String get reasonPhrase => 'OK';
  @override
  List<RedirectInfo> get redirects => [];
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(body).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
