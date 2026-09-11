import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:un_dia_mas/models/diary_entry.dart';
import 'package:un_dia_mas/services/drive_backup_service.dart';
import 'package:un_dia_mas/services/hive_restore_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Box<dynamic> settings;
  late Box<DiaryEntry> diary;
  late Box<dynamic> journal;
  final key = List<int>.generate(32, (index) => index);

  Future<void> openBoxes() async {
    Hive.init(directory.path);
    settings = await Hive.openBox<dynamic>('udm_secure',
        encryptionCipher: HiveAesCipher(key));
    diary = await Hive.openBox<DiaryEntry>('diary_secure',
        encryptionCipher: HiveAesCipher(key));
    journal = await Hive.openBox<dynamic>(HiveRestoreService.recoveryBoxName,
        encryptionCipher: HiveAesCipher(key));
  }

  HiveRestoreService service({Future<void> Function(String)? beforeStep}) =>
      HiveRestoreService(
          openRecoveryBox: () async => journal, beforeStep: beforeStep);

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'privacyAppLockEnabled': true,
      'autoBackup': false,
      'fav_resources': ['fixture-only'],
    });
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(DiaryEntryAdapter());
    directory = await Directory.systemTemp.createTemp('udm_restore_test_');
    await openBoxes();
    await settings.putAll({
      'startDate': '2024-04-03T10:15:00.000',
      'substance': 'Tabaco',
      'unknown': {
        'keep': true,
        'values': [1, 'fixture']
      },
      99: 'local integer key',
    });
    await diary.putAll({
      7: DiaryEntry(
          text: 'Original A',
          mood: 0,
          createdAt: DateTime.utc(2024, 2, 29, 9, 30)),
      42: DiaryEntry(
          text: '  Original B\n',
          mood: 4,
          createdAt: DateTime(2025, 3, 30, 1, 59)),
      'legacy-key': DiaryEntry(
          text: 'Original C', mood: 2, createdAt: DateTime(2026, 9, 10)),
    });
    await settings.flush();
    await diary.flush();
  });

  tearDown(() async {
    await Hive.close();
    final actual = await directory.resolveSymbolicLinks();
    final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
    final name =
        directory.uri.pathSegments.where((part) => part.isNotEmpty).last;
    if (!actual.toLowerCase().startsWith(
            '$temporaryRoot${Platform.pathSeparator}'.toLowerCase()) ||
        !name.startsWith('udm_restore_test_')) {
      throw StateError('Refusing to remove an unexpected fixture directory.');
    }
    await directory.delete(recursive: true);
  });

  final invalidCopies = <String, Map<String, dynamic>>{
    'missing both sections': {},
    'missing inventory': {'udm': {}},
    'wrong settings type': {'udm': [], 'diary': []},
    'wrong inventory type': {'udm': {}, 'diary': {}},
    'late invalid entry': _copy(entries: [
      _entry(),
      {'text': 'bad'}
    ]),
    'null text': _copy(entries: [
      {..._entry(), 'text': null}
    ]),
    'string mood': _copy(entries: [
      {..._entry(), 'mood': '2'}
    ]),
    'fractional mood': _copy(entries: [
      {..._entry(), 'mood': 2.0}
    ]),
    'negative mood': _copy(entries: [
      {..._entry(), 'mood': -1}
    ]),
    'high mood': _copy(entries: [
      {..._entry(), 'mood': 5}
    ]),
    'missing date': _copy(entries: [
      {'text': 'a', 'mood': 2}
    ]),
    'date normalization': _copy(entries: [
      {..._entry(), 'createdAt': '2025-02-29T12:00:00.000'}
    ]),
    'month normalization': _copy(entries: [
      {..._entry(), 'createdAt': '2025-13-01T12:00:00.000'}
    ]),
    'hour normalization': _copy(entries: [
      {..._entry(), 'createdAt': '2025-01-01T25:00:00.000'}
    ]),
    'out of range date': _copy(entries: [
      {..._entry(), 'createdAt': '+999999-01-01T12:00:00.000'}
    ]),
    'bad counter date': _copy(settings: {'startDate': 'tomorrow'}),
    'null counter date': _copy(settings: {'startDate': null}),
    'wrong substance': _copy(settings: {'substance': 42}),
    'non JSON setting': _copy(settings: {'unknown': DateTime(2026)}),
    'non finite setting': _copy(settings: {'unknown': double.nan}),
    'non string nested key': _copy(settings: {
      'unknown': {1: 'bad'}
    }),
  };

  for (final fixture in invalidCopies.entries) {
    test('${fixture.key}: rejects before writing any data or recovery',
        () async {
      final before = _snapshot(settings, diary);
      final result = await DriveBackupService.importHiveSafely(
          fixture.value, settings, diary);
      expect(result.ok, isFalse);
      expect(result.recoveryRequired, isFalse);
      expect(_snapshot(settings, diary), before);
      expect(journal.isEmpty, isTrue);
      await Hive.close();
      await openBoxes();
      expect(_snapshot(settings, diary), before);
    });
  }

  test(
      'valid export JSON roundtrip replaces inventory, merges unknown settings, leaves preferences',
      () async {
    // The production exporter expects string UDM keys because JSON does too.
    await settings.delete(99);
    final exported =
        jsonDecode(jsonEncode(DriveBackupService.exportHive(settings, diary)))
            as Map<String, dynamic>;
    final expectedEntries = _snapshot(settings, diary)['diary'] as List;
    final prepared = HiveRestoreService.prepare(exported);
    expect(prepared.entryCount, 3);
    expect(prepared.isEmptyInventory, isFalse);
    expect(prepared.startDate, DateTime(2024, 4, 3, 10, 15));
    // A detached prepared copy cannot be changed by the downloaded mutable map.
    (exported['diary'] as List).clear();
    (exported['udm'] as Map)['substance'] = 'Changed externally';
    await diary.clear();
    await diary.add(DiaryEntry(
        text: 'Will be replaced', mood: 1, createdAt: DateTime(2026)));
    await settings.put('onlyLocal', true);
    final preferences = await SharedPreferences.getInstance();
    final preferencesBefore = {
      for (final key in preferences.getKeys()) key: preferences.get(key)
    };
    final result = await service().restore(prepared, settings, diary);
    expect(result.ok, isTrue);
    expect(result.recoveryRequired, isFalse);
    expect(diary.keys.toList(), [0, 1, 2]);
    expect(settings.get('substance'), 'Tabaco');
    expect(settings.get('onlyLocal'), isTrue);
    expect(journal.isEmpty, isTrue);
    final restored = (_snapshot(settings, diary)['diary'] as List)
        .map((entry) => Map.of(entry as Map)..remove('key'))
        .toList();
    expect(
        restored,
        expectedEntries
            .map((entry) => Map.of(entry as Map)..remove('key'))
            .toList());
    expect({for (final key in preferences.getKeys()) key: preferences.get(key)},
        preferencesBefore);
    await Hive.close();
    await openBoxes();
    expect(diary.length, 3);
    expect(settings.get('substance'), 'Tabaco');
    expect(journal.isEmpty, isTrue);
  });

  test('explicit empty inventory is valid and substitutes only inventory',
      () async {
    final prepared = HiveRestoreService.prepare({'udm': {}, 'diary': []});
    expect(prepared.isEmptyInventory, isTrue);
    expect(prepared.startDate, isNull);
    final beforeSettings = settings.toMap();
    final result = await service().restore(prepared, settings, diary);
    expect(result.ok, isTrue);
    expect(diary.isEmpty, isTrue);
    expect(settings.toMap(), beforeSettings);
    await Hive.close();
    await openBoxes();
    expect(diary.isEmpty, isTrue);
  });

  for (final failure in [
    'apply.settings',
    'apply.diary',
    'apply.flush.settings',
    'apply.flush.diary'
  ]) {
    test('$failure rolls back exact sparse keys, timestamps and text on disk',
        () async {
      final before = _snapshot(settings, diary);
      final result = await service(beforeStep: (step) async {
        if (step == failure) {
          throw const FileSystemException('Injected write failure');
        }
      }).restore(HiveRestoreService.prepare(_copy()), settings, diary);
      expect(result.ok, isFalse);
      expect(result.recovered, isTrue);
      expect(result.recoveryRequired, isFalse);
      expect(_snapshot(settings, diary), before);
      await Hive.close();
      await openBoxes();
      expect(_snapshot(settings, diary), before);
      expect(journal.isEmpty, isTrue);
    });
  }

  for (final rollbackFailure in [
    'rollback.settings',
    'rollback.diary',
    'rollback.flush.settings',
    'rollback.flush.diary'
  ]) {
    test(
        '$rollbackFailure keeps durable pending; next startup recovers before editing',
        () async {
      final before = _snapshot(settings, diary);
      final restorer = service(beforeStep: (step) async {
        if (step == 'apply.diary' || step == rollbackFailure) {
          throw const FileSystemException('Injected write failure');
        }
      });
      final result = await restorer.restore(
          HiveRestoreService.prepare(_copy()), settings, diary);
      expect(result.ok, isFalse);
      expect(result.recovered, isFalse);
      expect(result.recoveryRequired, isTrue);
      expect((journal.get('transaction') as Map)['phase'], 'pending');
      expect(
          restorer.runExclusive(() async => diary.clear()), throwsStateError);
      final failureAgain = await restorer.recoverInterrupted(settings, diary);
      expect(failureAgain.ok, isFalse);
      expect(failureAgain.recoveryRequired, isTrue);
      await Hive.close();
      await openBoxes();
      final recovered = await service().recoverInterrupted(settings, diary);
      expect(recovered.ok, isTrue);
      expect(recovered.recovered, isTrue);
      expect(_snapshot(settings, diary), before);
      await Hive.close();
      await openBoxes();
      expect(_snapshot(settings, diary), before);
      expect(journal.isEmpty, isTrue);
    });
  }

  test(
      'completion failure keeps undo durable; restart restores original rather than claiming success',
      () async {
    final before = _snapshot(settings, diary);
    final result = await service(beforeStep: (step) async {
      if (step == 'journal.complete') {
        throw const FileSystemException('Disk unavailable');
      }
    }).restore(HiveRestoreService.prepare(_copy()), settings, diary);
    expect(result.ok, isFalse);
    expect(result.recoveryRequired, isTrue);
    expect((journal.get('transaction') as Map)['phase'], 'pending');
    await Hive.close();
    await openBoxes();
    expect((await service().recoverInterrupted(settings, diary)).recovered,
        isTrue);
    expect(_snapshot(settings, diary), before);
  });

  test('recovery journal preparation error never starts the substitution',
      () async {
    final before = _snapshot(settings, diary);
    final restorer = service(beforeStep: (step) async {
      if (step == 'journal.prepare') {
        throw const FileSystemException('Disk unavailable');
      }
    });
    final result = await restorer.restore(
        HiveRestoreService.prepare(_copy()), settings, diary);
    expect(result.ok, isFalse);
    expect(_snapshot(settings, diary), before);
    expect((await restorer.recoverInterrupted(settings, diary)).ok, isTrue);
    expect(restorer.recoveryRequired, isFalse);
  });

  test(
      'failed completion flush must be confirmed before new writes or a new restore',
      () async {
    var failSettle = true;
    final restorer = service(beforeStep: (step) async {
      if (step == 'journal.complete.flush' ||
          (step == 'journal.settle.flush' && failSettle)) {
        throw const FileSystemException('Injected marker flush failure');
      }
    });
    final result = await restorer.restore(
        HiveRestoreService.prepare(_copy()), settings, diary);
    expect(result.ok, isFalse);
    expect(result.recoveryRequired, isTrue);
    expect((journal.get('transaction') as Map)['phase'], 'complete',
        reason:
            'This is the ambiguous memory-cache state after put but before flush.');
    final retry = await restorer.recoverInterrupted(settings, diary);
    expect(retry.ok, isFalse);
    expect(retry.recoveryRequired, isTrue);
    await expectLater(
        restorer.runExclusive(() async => diary.clear()), throwsStateError);
    final otherRestore = await restorer.restore(
        HiveRestoreService.prepare(_copy()), settings, diary);
    expect(otherRestore.ok, isFalse);
    failSettle = false;
    expect((await restorer.recoverInterrupted(settings, diary)).ok, isTrue);
    expect(restorer.recoveryRequired, isFalse);
    await restorer.runExclusive(() async {
      await diary.put(
          80,
          DiaryEntry(
              text: 'New edit after settlement',
              mood: 4,
              createdAt: DateTime(2026, 9, 10)));
      await diary.flush();
    });
    await Hive.close();
    await openBoxes();
    expect((await service().recoverInterrupted(settings, diary)).recovered,
        isFalse);
    expect(diary.get(80)!.text, 'New edit after settlement');
  });

  test(
      'unconfirmed prepare snapshot cannot begin rollback writes until flushed',
      () async {
    final before = _snapshot(settings, diary);
    final steps = <String>[];
    final restorer = service(beforeStep: (step) async {
      steps.add(step);
      if (step == 'journal.prepare.flush' || step == 'recovery.journal.flush') {
        throw const FileSystemException('Injected journal flush failure');
      }
    });
    final result = await restorer.restore(
        HiveRestoreService.prepare(_copy()), settings, diary);
    expect(result.recoveryRequired, isTrue);
    expect((await restorer.recoverInterrupted(settings, diary)).ok, isFalse);
    expect(steps.any((step) => step.startsWith('rollback.')), isFalse);
    expect(_snapshot(settings, diary), before);
    expect((await service().recoverInterrupted(settings, diary)).recovered,
        isTrue);
    expect(_snapshot(settings, diary), before);
  });

  test('corrupt recovery record prevents any mutation and is retained',
      () async {
    final before = _snapshot(settings, diary);
    final corrupt = {
      'version': 1,
      'phase': 'pending',
      'before': {
        'udm': {},
        'diary': {7: 'bad'}
      }
    };
    await journal.put('transaction', corrupt);
    await journal.flush();
    final restorer = service();
    final result = await restorer.recoverInterrupted(settings, diary);
    expect(result.ok, isFalse);
    expect(result.recoveryRequired, isTrue);
    expect(_snapshot(settings, diary), before);
    expect(journal.get('transaction'), corrupt);
  });

  test(
      'a second restore or mutation cannot interleave; stale confirmation rejected afterwards',
      () async {
    final barrier = Completer<void>();
    final entered = Completer<void>();
    final restorer = service(beforeStep: (step) async {
      if (step == 'apply.diary') {
        entered.complete();
        await barrier.future;
      }
    });
    final generation = restorer.generation;
    final first =
        restorer.restore(HiveRestoreService.prepare(_copy()), settings, diary);
    await entered.future;
    expect(restorer.busy, isTrue);
    final second = await restorer.restore(
        HiveRestoreService.prepare(_copy()), settings, diary);
    expect(second.ok, isFalse);
    await expectLater(
        restorer.runExclusive(() async => diary.clear()), throwsStateError);
    barrier.complete();
    expect((await first).ok, isTrue);
    expect(restorer.busy, isFalse);
    await expectLater(
        restorer.runExclusive(() async => diary.clear(),
            expectedGeneration: generation),
        throwsStateError);
    expect(diary.length, 1);
  });

  test(
      'confirmed total deletion can clear a pending recovery without reviving it',
      () async {
    final restorer = service(beforeStep: (step) async {
      if (step == 'apply.diary' || step == 'rollback.diary') {
        throw StateError('Disk error');
      }
    });
    await restorer.restore(
        HiveRestoreService.prepare(_copy()), settings, diary);
    expect(restorer.recoveryRequired, isTrue);
    await restorer.runDeletion(() async {
      await settings.clear();
      await diary.clear();
      await journal.clear();
      await settings.flush();
      await diary.flush();
      await journal.flush();
    });
    expect(restorer.recoveryRequired, isFalse);
    expect((await restorer.recoverInterrupted(settings, diary)).recovered,
        isFalse);
    expect(diary.isEmpty, isTrue);
  });
}

Map<String, dynamic> _copy(
        {Map<String, dynamic>? settings, List<dynamic>? entries}) =>
    {
      'udm': settings ??
          {'startDate': '2026-09-01T11:12:13.000', 'substance': 'Nueva'},
      'diary': entries ?? [_entry()],
    };

Map<String, dynamic> _entry() => {
      'text': '  Entrada importada\n',
      'mood': 3,
      'createdAt': '2024-02-29T22:15:31.012345Z',
    };

Map<String, dynamic> _snapshot(Box settings, Box<DiaryEntry> diary) => {
      'udm': settings.toMap(),
      'diary': [
        for (final key in diary.keys)
          {
            'key': key,
            'text': diary.get(key)!.text,
            'mood': diary.get(key)!.mood,
            'createdAt': diary.get(key)!.createdAt.millisecondsSinceEpoch,
          }
      ],
    };
