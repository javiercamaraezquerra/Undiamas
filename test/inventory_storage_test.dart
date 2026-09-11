import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:un_dia_mas/models/diary_entry.dart';
import 'package:un_dia_mas/services/inventory_storage.dart';

DiaryEntry _entry(String text, {int mood = 2, bool utc = false}) => DiaryEntry(
      text: text,
      mood: mood,
      createdAt: utc
          ? DateTime.utc(2026, 8, 11, 18, 20, 5, 123)
          : DateTime(2026, 8, 12, 19, 30, 6, 234),
    );

DiaryEntry _clone(DiaryEntry entry) => DiaryEntry(
      text: entry.text,
      mood: entry.mood,
      createdAt: entry.createdAt,
    );

Map<dynamic, dynamic> _snapshot(Box<DiaryEntry> box) => {
      for (final key in box.keys)
        key: {
          'text': box.get(key)!.text,
          'mood': box.get(key)!.mood,
          'createdAt': box.get(key)!.createdAt.millisecondsSinceEpoch,
          'isUtc': box.get(key)!.createdAt.isUtc,
        },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cipher = HiveAesCipher(List<int>.generate(32, (index) => index));
  late Directory directory;

  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('udm_inventory_migration_');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(DiaryEntryAdapter());
    }
  });

  tearDown(() async {
    await Hive.close();
    final actual = await directory.resolveSymbolicLinks();
    final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
    final prefix = '$temporaryRoot${Platform.pathSeparator}'.toLowerCase();
    final name =
        directory.uri.pathSegments.where((part) => part.isNotEmpty).last;
    if (!actual.toLowerCase().startsWith(prefix) ||
        !name.startsWith('udm_inventory_migration_')) {
      throw StateError('Refusing to delete an unexpected fixture directory.');
    }
    await directory.delete(recursive: true);
  });

  Future<({Box<dynamic> settings, Box<DiaryEntry> diary})> seedLegacy() async {
    final settings = await Hive.openBox<dynamic>('udm', crashRecovery: false);
    final diary = await Hive.openBox<DiaryEntry>('diary', crashRecovery: false);
    await settings.putAll({
      'startDate': '2025-04-03T10:15:00.000',
      'substance': 'Tabaco',
      99: 'Ajuste ficticio con clave entera',
      'nested': {
        'choices': [true, 7, null],
      },
    });
    await diary.putAll({
      2: _entry('Entrada ficticia A', mood: 1, utc: true),
      42: _entry('Entrada ficticia B', mood: 3),
      'legacy-entry': _entry('Entrada ficticia C', mood: 4),
    });
    await settings.flush();
    await diary.flush();
    return (settings: settings, diary: diary);
  }

  Future<void> reopenStorage() async {
    await Hive.close();
    Hive.init(directory.path);
  }

  test('fresh storage creates only encrypted destinations', () async {
    final opened = await InventoryStorage.open(cipher);
    expect(opened.settings.isEmpty, isTrue);
    expect(opened.diary.isEmpty, isTrue);
    expect(await Hive.boxExists('udm'), isFalse);
    expect(await Hive.boxExists('diary'), isFalse);
  });

  test('migration clones attached entries, preserves sparse keys and persists',
      () async {
    final legacy = await seedLegacy();
    final settingsBefore = legacy.settings.toMap();
    final diaryBefore = _snapshot(legacy.diary);
    final sourceEntry = legacy.diary.get(2)!;
    final opened = await InventoryStorage.open(cipher);
    expect(opened.settings.toMap(), settingsBefore);
    expect(_snapshot(opened.diary), diaryBefore);
    expect(identical(opened.diary.get(2), sourceEntry), isFalse);
    expect(await Hive.boxExists('udm'), isFalse);
    expect(await Hive.boxExists('diary'), isFalse);
    await reopenStorage();
    final persisted = await InventoryStorage.open(cipher);
    expect(persisted.settings.toMap(), settingsBefore);
    expect(_snapshot(persisted.diary), diaryBefore);
  });

  test('compatible partial destination resumes missing keys without duplicates',
      () async {
    final legacy = await seedLegacy();
    final settingsBefore = legacy.settings.toMap();
    final diaryBefore = _snapshot(legacy.diary);
    final partialSettings = await Hive.openBox<dynamic>('udm_secure',
        encryptionCipher: cipher, crashRecovery: false);
    final partialDiary = await Hive.openBox<DiaryEntry>('diary_secure',
        encryptionCipher: cipher, crashRecovery: false);
    await partialSettings.put('startDate', legacy.settings.get('startDate'));
    await partialDiary.put(42, _clone(legacy.diary.get(42)!));
    await partialSettings.flush();
    await partialDiary.flush();
    await reopenStorage();
    final opened = await InventoryStorage.open(cipher);
    expect(opened.settings.toMap(), settingsBefore);
    expect(_snapshot(opened.diary), diaryBefore);
    expect(opened.diary.length, 3);
    expect(await Hive.boxExists('diary'), isFalse);
  });

  test('conflicting settings preserve both sources and write neither pair',
      () async {
    final legacy = await seedLegacy();
    final legacySettingsBefore = legacy.settings.toMap();
    final legacyDiaryBefore = _snapshot(legacy.diary);
    final destination = await Hive.openBox<dynamic>('udm_secure',
        encryptionCipher: cipher, crashRecovery: false);
    await destination.put('startDate', '2024-01-01T00:00:00.000');
    final destinationBefore = destination.toMap();
    await expectLater(InventoryStorage.open(cipher), throwsStateError);
    expect(destination.toMap(), destinationBefore);
    expect(legacy.settings.toMap(), legacySettingsBefore);
    expect(_snapshot(legacy.diary), legacyDiaryBefore);
    expect(Hive.box<DiaryEntry>('diary_secure').isEmpty, isTrue);
    expect(await Hive.boxExists('udm'), isTrue);
    expect(await Hive.boxExists('diary'), isTrue);
  });

  test('diary conflict is found before even the settings migration starts',
      () async {
    final legacy = await seedLegacy();
    final sourceBefore = _snapshot(legacy.diary);
    final destination = await Hive.openBox<DiaryEntry>('diary_secure',
        encryptionCipher: cipher, crashRecovery: false);
    await destination.put(2, _entry('Otro texto ficticio: no sobrescribir'));
    final destinationBefore = _snapshot(destination);
    await expectLater(InventoryStorage.open(cipher), throwsStateError);
    expect(_snapshot(destination), destinationBefore);
    expect(_snapshot(legacy.diary), sourceBefore);
    expect(Hive.box<dynamic>('udm_secure').isEmpty, isTrue);
    expect(await Hive.boxExists('udm'), isTrue);
    expect(await Hive.boxExists('diary'), isTrue);
  });

  test('extra destination key is a conflict, never a reason to delete source',
      () async {
    await seedLegacy();
    final destination = await Hive.openBox<DiaryEntry>('diary_secure',
        encryptionCipher: cipher, crashRecovery: false);
    await destination.put(900, _entry('Entrada cifrada adicional'));
    final before = _snapshot(destination);
    await expectLater(InventoryStorage.open(cipher), throwsStateError);
    expect(_snapshot(destination), before);
    expect(await Hive.boxExists('diary'), isTrue);
  });

  test('empty old boxes leave an existing encrypted inventory intact',
      () async {
    await Hive.openBox<dynamic>('udm', crashRecovery: false);
    await Hive.openBox<DiaryEntry>('diary', crashRecovery: false);
    final settings = await Hive.openBox<dynamic>('udm_secure',
        encryptionCipher: cipher, crashRecovery: false);
    final diary = await Hive.openBox<DiaryEntry>('diary_secure',
        encryptionCipher: cipher, crashRecovery: false);
    await settings.put('startDate', '2025-04-03T10:15:00.000');
    await diary.put('keep', _entry('Entrada cifrada a conservar'));
    final before = _snapshot(diary);
    final opened = await InventoryStorage.open(cipher);
    expect(_snapshot(opened.diary), before);
    expect(opened.settings.get('startDate'), '2025-04-03T10:15:00.000');
    expect(await Hive.boxExists('udm'), isFalse);
    expect(await Hive.boxExists('diary'), isFalse);
  });

  test('interrupted diary flush retains source and next launch finishes safely',
      () async {
    final legacy = await seedLegacy();
    final expectedSettings = legacy.settings.toMap();
    final expectedDiary = _snapshot(legacy.diary);
    await expectLater(
      InventoryStorage.open(cipher, beforeStep: (step) async {
        if (step == 'diary.flush') {
          throw const FileSystemException('Simulated flush interruption');
        }
      }),
      throwsA(isA<FileSystemException>()),
    );
    expect(await Hive.boxExists('diary'), isTrue,
        reason: 'The unverified source must survive the failed flush.');
    expect(_snapshot(legacy.diary), expectedDiary);
    // Settings completed first and are already durable. The next launch must
    // handle one completed pair and one pair still awaiting verification.
    await reopenStorage();
    final resumed = await InventoryStorage.open(cipher);
    expect(resumed.settings.toMap(), expectedSettings);
    expect(_snapshot(resumed.diary), expectedDiary);
    expect(await Hive.boxExists('diary'), isFalse);
  });

  test('failure removing a verified source can retry without adding duplicates',
      () async {
    final legacy = await seedLegacy();
    final expectedDiary = _snapshot(legacy.diary);
    await expectLater(
      InventoryStorage.open(cipher, beforeStep: (step) async {
        if (step == 'diary.deleteSource') {
          throw const FileSystemException('Simulated source removal failure');
        }
      }),
      throwsA(isA<FileSystemException>()),
    );
    expect(await Hive.boxExists('diary'), isTrue);
    expect(_snapshot(Hive.box<DiaryEntry>('diary_secure')), expectedDiary);
    await reopenStorage();
    final resumed = await InventoryStorage.open(cipher);
    expect(_snapshot(resumed.diary), expectedDiary);
    expect(resumed.diary.length, 3);
    expect(await Hive.boxExists('diary'), isFalse);
  });

  test('unreadable legacy source is rejected without truncating its bytes',
      () async {
    final corrupt = File('${directory.path}${Platform.pathSeparator}udm.hive');
    final original = List<int>.generate(32, (index) => 255 - index);
    await corrupt.writeAsBytes(original, flush: true);
    await expectLater(InventoryStorage.open(cipher), throwsA(isA<HiveError>()));
    expect(await corrupt.readAsBytes(), original);
    expect(Hive.box<dynamic>('udm_secure').isEmpty, isTrue);
    expect(Hive.box<DiaryEntry>('diary_secure').isEmpty, isTrue);
  });
}
