import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:un_dia_mas/services/drive_backup_service.dart';
import 'package:un_dia_mas/services/hive_restore_service.dart';

const _signInChannel = MethodChannel('plugins.flutter.io/google_sign_in');
const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');
const _account = {
  'email': 'fixture@example.invalid',
  'id': 'synthetic-account'
};

Map<String, dynamic> _legacyJson() => {
      'udm': {
        'startDate': '2024-02-29T09:30:00.123',
        'substance': 'Tabaco',
        'unknown-setting': {'keep': true},
      },
      'diary': [
        {
          'text': '  Texto ficticio\nUnicode: ñ, 中文, 🙂  ',
          'mood': 0,
          'createdAt': '2024-02-29T23:59:59.123Z',
        },
        {
          'text': 'Segunda entrada ficticia',
          'mood': 4,
          'createdAt': '2025-03-30T01:59:59.789',
        },
      ],
    };

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> authCalls;
  late List<MethodCall> pathCalls;
  Object? interactiveError;
  Object? tokenError;
  bool cancelWithNull = false;
  bool scopesGranted = true;
  late _MemoryHttpClient transport;

  setUp(() async {
    authCalls = [];
    pathCalls = [];
    interactiveError = null;
    tokenError = null;
    cancelWithNull = false;
    scopesGranted = true;
    transport = _MemoryHttpClient();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_signInChannel,
        (call) async {
      authCalls.add(call);
      switch (call.method) {
        case 'init':
        case 'disconnect':
        case 'signOut':
        case 'signInSilently':
          return null;
        case 'signIn':
          if (interactiveError != null) throw interactiveError!;
          return cancelWithNull ? null : _account;
        case 'requestScopes':
          return scopesGranted;
        case 'getTokens':
          if (tokenError != null) throw tokenError!;
          return {'accessToken': 'fixture-token-not-real'};
        case 'isSignedIn':
          return false;
        default:
          throw StateError(
              'Unexpected authentication fixture call: ${call.method}');
      }
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_pathChannel,
        (call) async {
      pathCalls.add(call);
      throw StateError('Drive uploads must not request a temporary directory.');
    });
    // The service singleton retains the GoogleSignIn object between tests.
    // Clear only that simulated session through its public API.
    await DriveBackupService.disconnect();
    authCalls.clear();
  });

  tearDown(() async {
    await DriveBackupService.disconnect();
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_signInChannel, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_pathChannel, null);
  });

  Future<T> withFakeNetwork<T>(Future<T> Function() action) =>
      HttpOverrides.runZoned(action, createHttpClient: (_) => transport);

  for (final cancellation in ['null', 'platform error']) {
    test('delete propagates sign-in cancellation ($cancellation) before HTTP',
        () async {
      if (cancellation == 'null') {
        cancelWithNull = true;
      } else {
        interactiveError = PlatformException(code: 'sign_in_canceled');
      }
      await expectLater(
          withFakeNetwork(DriveBackupService.deleteBackup),
          throwsA(isA<PlatformException>()
              .having((error) => error.code, 'code', 'sign_in_canceled')));
      expect(transport.requests, isEmpty);
      expect(authCalls.map((call) => call.method), contains('signIn'));
    });
  }

  test('delete propagates OAuth configuration failure before any HTTP',
      () async {
    interactiveError = PlatformException(
        code: 'sign_in_failed', message: 'Synthetic ApiException: 10');
    await expectLater(
        withFakeNetwork(DriveBackupService.deleteBackup),
        throwsA(isA<PlatformException>()
            .having((error) => error.code, 'code', 'sign_in_failed')));
    expect(transport.requests, isEmpty);
  });

  test('delete propagates denied Drive scopes instead of reporting success',
      () async {
    scopesGranted = false;
    await expectLater(
        withFakeNetwork(DriveBackupService.deleteBackup),
        throwsA(isA<PlatformException>()
            .having((error) => error.code, 'code', 'scopes_denied')));
    expect(transport.requests, isEmpty);
    expect(authCalls.where((call) => call.method == 'getTokens'), isEmpty);
  });

  test('delete propagates an expired-token failure without deleting anything',
      () async {
    tokenError =
        PlatformException(code: 'network_error', message: 'Fixture only');
    await expectLater(
        withFakeNetwork(DriveBackupService.deleteBackup),
        throwsA(isA<PlatformException>()
            .having((error) => error.code, 'code', 'network_error')));
    expect(transport.requests, isEmpty);
  });

  test('authorized delete removes each returned backup and confirms empty list',
      () async {
    transport.existingIds = ['fixture-a', 'fixture-b'];
    await withFakeNetwork(DriveBackupService.deleteBackup);
    expect(transport.requests.map((request) => request.method),
        ['GET', 'DELETE', 'DELETE']);
    expect(transport.requests.skip(1).map((request) => request.uri.path),
        ['/drive/v3/files/fixture-a', '/drive/v3/files/fixture-b']);
    transport.requests.clear();
    transport.existingIds = [];
    await withFakeNetwork(DriveBackupService.deleteBackup);
    expect(transport.requests.map((request) => request.method), ['GET']);
  });

  test('remote deletion HTTP error remains an error for the Profile caller',
      () async {
    transport.existingIds = ['fixture-a'];
    transport.failDelete = true;
    await expectLater(
        withFakeNetwork(DriveBackupService.deleteBackup), throwsException);
    expect(
        transport.requests.map((request) => request.method), ['GET', 'DELETE']);
  });

  for (final update in [false, true]) {
    test(
        '${update ? 'update' : 'create'} uploads unchanged UTF-8 JSON15 from memory',
        () async {
      transport.existingIds = update ? ['fixture-existing'] : [];
      final json15 = _legacyJson();
      final expected = utf8.encode(jsonEncode(json15));
      final result =
          await withFakeNetwork(() => DriveBackupService.uploadBackup(json15));
      expect(result.ok, isTrue, reason: result.message);
      expect(pathCalls, isEmpty);
      final listing = transport.requests.first;
      expect(listing.uri.queryParameters['spaces'], 'appDataFolder');
      expect(listing.uri.queryParameters['q'],
          "name='udm_backup.json' and trashed=false");
      final upload = transport.requests.last;
      expect(upload.method, update ? 'PATCH' : 'POST');
      expect(upload.headers.value('authorization'),
          'Bearer fixture-token-not-real');
      expect(upload.uri.queryParameters['uploadType'], 'multipart');
      final body = utf8.decode(upload.body);
      final boundary = upload.headers
          .value('content-type')!
          .split('boundary=')
          .last
          .replaceAll('"', '');
      final parts = body.split('--$boundary');
      final metadataPart = parts.firstWhere((part) => part.contains('"name"'));
      final metadata =
          jsonDecode(metadataPart.split('\r\n\r\n').last.trim()) as Map;
      expect(metadata['name'], 'udm_backup.json');
      expect(metadata['parents'], update ? isNull : ['appDataFolder']);
      final mediaPart = parts.firstWhere(
          (part) => part.contains('Content-Transfer-Encoding: base64'));
      final payload = mediaPart.substring(mediaPart.indexOf('\r\n\r\n') + 4);
      expect(payload.endsWith('\r\n'), isTrue);
      // Google APIs encodes the media part as base64 for multipart transport;
      // decode that envelope to compare the actual stored JSON bytes.
      final exactBytes =
          base64.decode(payload.substring(0, payload.length - 2));
      expect(exactBytes, expected,
          reason:
              'UTF-8 bytes, spaces inside text and legacy fields must be unchanged.');
      final exactJson = utf8.decode(exactBytes);
      final decoded = jsonDecode(exactJson) as Map<String, dynamic>;
      expect(decoded, json15);
      final compatible = HiveRestoreService.prepare(decoded);
      expect(compatible.entryCount, 2);
      expect(compatible.startDate, DateTime(2024, 2, 29, 9, 30, 0, 123));
      final scopes =
          authCalls.lastWhere((call) => call.method == 'requestScopes');
      expect((scopes.arguments as Map)['scopes'], [
        'https://www.googleapis.com/auth/drive.file',
        'https://www.googleapis.com/auth/drive.appdata',
      ]);
    });
  }

  test(
      'upload network failure leaves no temporary-file request and is reported',
      () async {
    transport.failUpload = true;
    final result = await withFakeNetwork(
        () => DriveBackupService.uploadBackup(_legacyJson()));
    expect(result.ok, isFalse);
    expect(result.message, contains('Error al subir'));
    expect(pathCalls, isEmpty);
    expect(transport.requests, hasLength(2));
  });

  test(
      'upload cancellation retains its failure result and performs no HTTP or temp IO',
      () async {
    cancelWithNull = true;
    final result = await withFakeNetwork(
        () => DriveBackupService.uploadBackup(_legacyJson()));
    expect(result.ok, isFalse);
    expect(result.message, 'Autenticación cancelada.');
    expect(transport.requests, isEmpty);
    expect(pathCalls, isEmpty);
  });
}

// Every HttpClient created in a test is replaced by this in-memory transport.
// No sockets, actual Google accounts, real tokens or user files are involved.
class _MemoryHttpClient implements HttpClient {
  final requests = <_MemoryRequest>[];
  List<String> existingIds = [];
  bool failDelete = false;
  bool failUpload = false;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final request = _MemoryRequest(method, url, () {
      if (method == 'GET') {
        return _MemoryResponse(
            200,
            jsonEncode({
              'files': [
                for (final id in existingIds) {'id': id}
              ]
            }));
      }
      if ((method == 'DELETE' && failDelete) ||
          (method != 'DELETE' && failUpload)) {
        return _MemoryResponse(
            503,
            jsonEncode({
              'error': {'code': 503, 'message': 'Synthetic unavailable'}
            }));
      }
      return method == 'DELETE'
          ? _MemoryResponse(204, '')
          : _MemoryResponse(200, jsonEncode({'id': 'fixture-uploaded'}));
    });
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryRequest implements HttpClientRequest {
  _MemoryRequest(this.method, this.uri, this.response);
  @override
  final String method;
  @override
  final Uri uri;
  final HttpClientResponse Function() response;
  final body = <int>[];
  @override
  final headers = _MemoryHeaders();
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
  Future<HttpClientResponse> close() async => response();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryHeaders implements HttpHeaders {
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

class _MemoryResponse extends Stream<List<int>> implements HttpClientResponse {
  _MemoryResponse(this.statusCode, String body) : bytes = utf8.encode(body) {
    headers.set('content-type', 'application/json; charset=utf-8');
  }
  final List<int> bytes;
  @override
  final int statusCode;
  @override
  final headers = _MemoryHeaders();
  @override
  int get contentLength => bytes.length;
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => false;
  @override
  String get reasonPhrase => statusCode < 400 ? 'OK' : 'Unavailable';
  @override
  List<RedirectInfo> get redirects => [];

  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(bytes).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
