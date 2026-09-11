import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:un_dia_mas/models/diary_entry.dart';
import 'package:un_dia_mas/models/post.dart';
import 'package:un_dia_mas/services/app_lock_controller.dart';
import 'package:un_dia_mas/services/encryption_service.dart';
import 'package:un_dia_mas/services/hive_restore_service.dart';
import 'package:un_dia_mas/services/inventory_storage.dart';
import 'package:un_dia_mas/services/safe_hive_open.dart';

import 'fixtures/production15_storage.dart';

// This is an on-disk format upgrade test with isolated synthetic data. Native
// Keystore/signature continuity still needs an Android in-place installation.
const _secureChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
final _fixtureKey = List<int>.generate(32, (index) => index + 31);
final _fixtureStart = DateTime(2024, 2, 29, 9, 30, 5, 123);

Map<String, Object> _productionPreferences() => {
      'isDarkMode': true,
      'notifyDailyReflection': false,
      'notifyMilestones': true,
      'autoBackup': true,
      'fav_resources': <String>['breathing', 'support-fixture'],
      'tutorialFirstRunShown': true,
      'seenTutorial': true,
      'miuiHelpShown': true,
    };

dynamic _valueSnapshot(dynamic value) {
  if (value is DateTime) {
    return {'milliseconds': value.millisecondsSinceEpoch, 'utc': value.isUtc};
  }
  if (value is Map) {
    return {
      for (final entry in value.entries) entry.key: _valueSnapshot(entry.value)
    };
  }
  if (value is List) return value.map(_valueSnapshot).toList();
  return value;
}

Map<String, dynamic> _entrySnapshot(DateTime date, int mood, String text) => {
      'date': _valueSnapshot(date),
      'mood': mood,
      'text': text,
    };

Map<dynamic, dynamic> _currentDiarySnapshot(Box<DiaryEntry> diary) => {
      for (final key in diary.keys)
        key: _entrySnapshot(diary.get(key)!.createdAt, diary.get(key)!.mood,
            diary.get(key)!.text),
    };

Map<dynamic, dynamic> _oldDiarySnapshot(Box<Production15DiaryEntry> diary) => {
      for (final key in diary.keys)
        key: _entrySnapshot(diary.get(key)!.createdAt, diary.get(key)!.mood,
            diary.get(key)!.text),
    };

Future<Map<String, dynamic>> _preferencesSnapshot() async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  return {
    for (final key in preferences.getKeys())
      key: _valueSnapshot(preferences.get(key)),
  };
}

class _NoAuthenticationDuringUpgrade implements AppLockAuthenticator {
  int calls = 0;

  @override
  Future<bool> isDeviceSupported() async {
    calls++;
    return false;
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    calls++;
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Map<String, String> secureValues;
  late List<MethodCall> secureCalls;

  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('udm_production15_upgrade_');
    Hive.init(directory.path);
    // A closed old/new app cannot share registered adapters. In this one test
    // process, override only after closing all boxes to simulate that boundary.
    Hive.registerAdapter(Production15DiaryEntryAdapter(),
        override: Hive.isAdapterRegistered(1));
    Hive.registerAdapter(Production15PostAdapter(),
        override: Hive.isAdapterRegistered(2));
    SharedPreferences.setMockInitialValues(_productionPreferences());
    secureValues = {'hive_key': base64UrlEncode(_fixtureKey)};
    secureCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, (call) async {
      secureCalls.add(call);
      final arguments = call.arguments as Map;
      switch (call.method) {
        case 'read':
          return secureValues[arguments['key']];
        case 'containsKey':
          return secureValues.containsKey(arguments['key']);
        case 'readAll':
          return Map<String, String>.from(secureValues);
        case 'write':
          secureValues[arguments['key'] as String] =
              arguments['value'] as String;
          return null;
        case 'delete':
          secureValues.remove(arguments['key']);
          return null;
        case 'deleteAll':
          secureValues.clear();
          return null;
        default:
          throw StateError(
              'Unexpected secure-storage fixture call: ${call.method}');
      }
    });
  });

  tearDown(() async {
    await Hive.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, null);
    final actual = await directory.resolveSymbolicLinks();
    final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
    final name =
        directory.uri.pathSegments.where((part) => part.isNotEmpty).last;
    if (!actual.toLowerCase().startsWith(
            '$temporaryRoot${Platform.pathSeparator}'.toLowerCase()) ||
        !name.startsWith('udm_production15_upgrade_')) {
      throw StateError(
          'Refusing to remove an unexpected upgrade fixture directory.');
    }
    await directory.delete(recursive: true);
  });

  Future<({Box<dynamic> settings, Box<Production15DiaryEntry> diary})> seed15(
      {bool plaintext = false, bool jsonCompatible = false}) async {
    final cipher = plaintext ? null : HiveAesCipher(_fixtureKey);
    final settings = await Hive.openBox<dynamic>(
        plaintext ? 'udm' : 'udm_secure',
        encryptionCipher: cipher,
        crashRecovery: false);
    final diary = await Hive.openBox<Production15DiaryEntry>(
        plaintext ? 'diary' : 'diary_secure',
        encryptionCipher: cipher,
        crashRecovery: false);
    await settings.putAll({
      'startDate': _fixtureStart.toIso8601String(),
      'substance': 'Tabaco',
      'unknown-setting': {
        'choices': [true, 7, null, 'ficticio']
      },
      if (!jsonCompatible) 99: 'Ajuste histórico ficticio',
    });
    await diary.putAll({
      42: Production15DiaryEntry(
          createdAt: DateTime(2025, 10, 26, 2, 30, 0, 456),
          mood: 2,
          text: 'Primera entrada a la misma hora'),
      2: Production15DiaryEntry(
          createdAt: DateTime.utc(2024, 2, 29, 23, 59, 59, 123),
          mood: 0,
          text: '  Texto ficticio\nLínea dos: ñ, 中文, 🙂  '),
      43: Production15DiaryEntry(
          createdAt: DateTime(2025, 10, 26, 2, 30, 0, 456),
          mood: 2,
          text: 'Segunda entrada distinta con la misma fecha y ánimo'),
      'legacy-entry': Production15DiaryEntry(
          createdAt: DateTime(2025, 3, 30, 1, 59, 59, 789),
          mood: 4,
          text:
              'Clave de texto; no convertir ni volver a numerar al actualizar.'),
    });
    await settings.flush();
    await diary.flush();
    return (settings: settings, diary: diary);
  }

  Future<void> switchToCandidateAdapters() async {
    await Hive.close();
    Hive.init(directory.path);
    Hive.registerAdapter(DiaryEntryAdapter(), override: true);
    Hive.registerAdapter(PostAdapter(), override: true);
  }

  Future<({Box<dynamic> settings, Box<DiaryEntry> diary})>
      candidateStartup() async {
    final authenticator = _NoAuthenticationDuringUpgrade();
    final lock = AppLockController(authenticator: authenticator);
    try {
      await lock.initialize();
      expect(lock.initialized, isTrue);
      expect(lock.enabled, isFalse,
          reason:
              'An existing installation must not acquire an unsolicited lock.');
      expect(lock.covered, isFalse);
      expect(authenticator.calls, 0);
    } finally {
      lock.dispose();
    }
    final opened =
        await InventoryStorage.open(await EncryptionService.getCipher());
    final recovery = HiveRestoreService();
    try {
      final result =
          await recovery.recoverInterrupted(opened.settings, opened.diary);
      expect(result.ok, isTrue, reason: result.message);
      expect(result.recoveryRequired, isFalse);
    } finally {
      recovery.dispose();
    }
    return opened;
  }

  void expectUnchangedKey() {
    expect(secureValues, {'hive_key': base64UrlEncode(_fixtureKey)});
    expect(
        secureCalls.where((call) =>
            const ['write', 'delete', 'deleteAll'].contains(call.method)),
        isEmpty,
        reason:
            'Updating or restoring must not rotate or wipe the existing key.');
    expect(secureCalls.where((call) => call.method == 'read'), isNotEmpty);
  }

  test(
      'encrypted version 15 inventory and preferences survive three candidate startups',
      () async {
    final old = await seed15();
    final expectedSettings = _valueSnapshot(old.settings.toMap());
    final expectedDiary = _oldDiarySnapshot(old.diary);
    final expectedKeys = old.diary.keys.toList();
    final expectedPreferences = await _preferencesSnapshot();
    final oldPosts = await Hive.openBox<Production15Post>(
        'production_post_fixture',
        encryptionCipher: HiveAesCipher(_fixtureKey),
        crashRecovery: false);
    await oldPosts.put(
        'unchanged-post',
        Production15Post(
            id: 'ficticio-15',
            text: 'Post de prueba',
            createdAt: _fixtureStart,
            likes: 17));
    await oldPosts.flush();
    await switchToCandidateAdapters();

    for (var launch = 0; launch < 3; launch++) {
      final opened = await candidateStartup();
      expect(_valueSnapshot(opened.settings.toMap()), expectedSettings);
      expect(_currentDiarySnapshot(opened.diary), expectedDiary);
      expect(opened.diary.keys.toList(), expectedKeys);
      expect(await _preferencesSnapshot(), expectedPreferences);
      expectUnchangedKey();
      final posts = await openHiveBoxSafely<Post>('production_post_fixture',
          encryptionCipher: await EncryptionService.getCipher());
      final post = posts.get('unchanged-post')!;
      expect([post.id, post.text, post.likes],
          ['ficticio-15', 'Post de prueba', 17]);
      expect(_valueSnapshot(post.createdAt), _valueSnapshot(_fixtureStart));
      expect(await Hive.boxExists('udm'), isFalse);
      expect(await Hive.boxExists('diary'), isFalse);
      await Hive.close();
      Hive.init(directory.path);
    }
  });

  test(
      'old plaintext files migrate with their original keys and remain stable on restart',
      () async {
    final old = await seed15(plaintext: true);
    final expectedSettings = _valueSnapshot(old.settings.toMap());
    final expectedDiary = _oldDiarySnapshot(old.diary);
    final expectedPreferences = await _preferencesSnapshot();
    await switchToCandidateAdapters();
    for (var launch = 0; launch < 2; launch++) {
      final opened = await candidateStartup();
      expect(_valueSnapshot(opened.settings.toMap()), expectedSettings);
      expect(_currentDiarySnapshot(opened.diary), expectedDiary);
      expect(await _preferencesSnapshot(), expectedPreferences);
      expectUnchangedKey();
      expect(await Hive.boxExists('udm'), isFalse);
      expect(await Hive.boxExists('diary'), isFalse);
      await Hive.close();
      Hive.init(directory.path);
    }
  });

  test('a compatible partial old migration completes once without duplicates',
      () async {
    final old = await seed15(plaintext: true);
    final expectedSettings = _valueSnapshot(old.settings.toMap());
    final expectedDiary = _oldDiarySnapshot(old.diary);
    final expectedPreferences = await _preferencesSnapshot();
    final partialSettings = await Hive.openBox<dynamic>('udm_secure',
        encryptionCipher: HiveAesCipher(_fixtureKey), crashRecovery: false);
    final partialDiary = await Hive.openBox<Production15DiaryEntry>(
        'diary_secure',
        encryptionCipher: HiveAesCipher(_fixtureKey),
        crashRecovery: false);
    await partialSettings.put('startDate', old.settings.get('startDate'));
    final original = old.diary.get(42)!;
    await partialDiary.put(
        42,
        Production15DiaryEntry(
            createdAt: original.createdAt,
            mood: original.mood,
            text: original.text));
    await partialSettings.flush();
    await partialDiary.flush();
    await switchToCandidateAdapters();
    for (var launch = 0; launch < 2; launch++) {
      final opened = await candidateStartup();
      expect(_valueSnapshot(opened.settings.toMap()), expectedSettings);
      expect(_currentDiarySnapshot(opened.diary), expectedDiary);
      expect(opened.diary.length, 4);
      expect(await _preferencesSnapshot(), expectedPreferences);
      expectUnchangedKey();
      await Hive.close();
      Hive.init(directory.path);
    }
  });

  test(
      'version 15 JSON restores exact entries and preserves current local preferences',
      () async {
    final old = await seed15(jsonCompatible: true);
    final expectedEntries = _oldDiarySnapshot(old.diary).values.toList();
    final encoded =
        jsonEncode(exportProduction15Backup(old.settings, old.diary));
    await switchToCandidateAdapters();
    final opened = await candidateStartup();
    final preferences = await SharedPreferences.getInstance();
    // This setting was enabled locally after upgrading and is deliberately
    // absent from the version 15 cloud format.
    await preferences.setBool(AppLockController.preferenceKey, true);
    final expectedPreferences = await _preferencesSnapshot();
    await opened.settings.put('only-local', 'Conservar este ajuste');
    await opened.settings.put('startDate', DateTime(2026).toIso8601String());
    await opened.diary.clear();
    await opened.diary.put(
        'current',
        DiaryEntry(
            createdAt: DateTime(2026),
            mood: 1,
            text: 'Entrada ficticia reemplazable'));
    final downloaded = jsonDecode(encoded) as Map<String, dynamic>;
    final prepared = HiveRestoreService.prepare(downloaded);
    expect(prepared.entryCount, 4);
    expect(prepared.startDate, _fixtureStart);
    (downloaded['diary'] as List).clear();
    (downloaded['udm'] as Map)['substance'] = 'No debe alterar lo preparado';
    final service = HiveRestoreService();
    addTearDown(service.dispose);
    final restored =
        await service.restore(prepared, opened.settings, opened.diary);
    expect(restored.ok, isTrue, reason: restored.message);
    expect(
        _currentDiarySnapshot(opened.diary).values.toList(), expectedEntries);
    // Legacy JSON never contained Hive keys. Only an explicit restore renumbers
    // entries, as version 15 did; a normal update never does (tests above).
    expect(opened.diary.keys.toList(), [0, 1, 2, 3]);
    expect(opened.settings.get('substance'), 'Tabaco');
    expect(opened.settings.get('startDate'), _fixtureStart.toIso8601String());
    expect(opened.settings.get('only-local'), 'Conservar este ajuste');
    expect(await _preferencesSnapshot(), expectedPreferences);
    expectUnchangedKey();
    await Hive.close();
    Hive.init(directory.path);
    final reopened =
        await InventoryStorage.open(await EncryptionService.getCipher());
    final recovery =
        await service.recoverInterrupted(reopened.settings, reopened.diary);
    expect(recovery.ok, isTrue, reason: recovery.message);
    expect(
        _currentDiarySnapshot(reopened.diary).values.toList(), expectedEntries);
    expect(await _preferencesSnapshot(), expectedPreferences);
    final lock =
        AppLockController(authenticator: _NoAuthenticationDuringUpgrade());
    addTearDown(lock.dispose);
    await lock.initialize();
    expect(lock.enabled, isTrue);
    expect(lock.covered, isTrue);
    expectUnchangedKey();
  });

  test('malformed version 15 JSON is rejected before touching upgraded data',
      () async {
    final old = await seed15(jsonCompatible: true);
    final encoded =
        jsonEncode(exportProduction15Backup(old.settings, old.diary));
    final expectedSettings = _valueSnapshot(old.settings.toMap());
    final expectedDiary = _oldDiarySnapshot(old.diary);
    final expectedPreferences = await _preferencesSnapshot();
    await switchToCandidateAdapters();
    final opened = await candidateStartup();
    final malformed = jsonDecode(encoded) as Map<String, dynamic>;
    (malformed['diary'] as List).last['createdAt'] = '2025-02-30T12:00:00.000';
    expect(() => HiveRestoreService.prepare(malformed), throwsFormatException);
    expect(_valueSnapshot(opened.settings.toMap()), expectedSettings);
    expect(_currentDiarySnapshot(opened.diary), expectedDiary);
    expect(await _preferencesSnapshot(), expectedPreferences);
    expectUnchangedKey();
    await Hive.close();
    Hive.init(directory.path);
    final reopened = await candidateStartup();
    expect(_currentDiarySnapshot(reopened.diary), expectedDiary);
    expect(_valueSnapshot(reopened.settings.toMap()), expectedSettings);
  });

  test(
      'an explicitly empty old JSON copy clears only the inventory after restore',
      () async {
    final old = await seed15(jsonCompatible: true);
    final expectedSettings = _valueSnapshot(old.settings.toMap());
    final expectedPreferences = await _preferencesSnapshot();
    final emptySettings = await Hive.openBox<dynamic>('empty15_settings');
    final emptyDiary =
        await Hive.openBox<Production15DiaryEntry>('empty15_diary');
    final encoded =
        jsonEncode(exportProduction15Backup(emptySettings, emptyDiary));
    await switchToCandidateAdapters();
    final opened = await candidateStartup();
    final prepared =
        HiveRestoreService.prepare(jsonDecode(encoded) as Map<String, dynamic>);
    expect(prepared.isEmptyInventory, isTrue);
    final service = HiveRestoreService();
    addTearDown(service.dispose);
    final result =
        await service.restore(prepared, opened.settings, opened.diary);
    expect(result.ok, isTrue, reason: result.message);
    expect(opened.diary.isEmpty, isTrue);
    expect(_valueSnapshot(opened.settings.toMap()), expectedSettings);
    expect(await _preferencesSnapshot(), expectedPreferences);
    await Hive.close();
    Hive.init(directory.path);
    final reopened = await candidateStartup();
    expect(reopened.diary.isEmpty, isTrue);
    expect(_valueSnapshot(reopened.settings.toMap()), expectedSettings);
    expect(await _preferencesSnapshot(), expectedPreferences);
    expectUnchangedKey();
  });
}
