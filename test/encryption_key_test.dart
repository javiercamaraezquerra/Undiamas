import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:un_dia_mas/models/diary_entry.dart';
import 'package:un_dia_mas/services/encryption_service.dart';
import 'package:un_dia_mas/services/hive_restore_service.dart';
import 'package:un_dia_mas/services/safe_hive_open.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secure = FlutterSecureStorage();
  final key = List<int>.generate(32, (index) => index + 10);
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('udm_key_test_');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(DiaryEntryAdapter());
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() async {
    await Hive.close();
    final actual = await directory.resolveSymbolicLinks();
    final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
    final name =
        directory.uri.pathSegments.where((part) => part.isNotEmpty).last;
    if (!actual.toLowerCase().startsWith(
            '$temporaryRoot${Platform.pathSeparator}'.toLowerCase()) ||
        !name.startsWith('udm_key_test_')) {
      throw StateError('Refusing to remove an unexpected fixture directory.');
    }
    await directory.delete(recursive: true);
  });

  test('fresh installation creates and reuses one 32-byte key', () async {
    final created = await EncryptionService.getRawKey(
        supportDirectory: () async => directory);
    expect(created, hasLength(32));
    expect(await secure.read(key: 'hive_key'), base64UrlEncode(created));
    expect(await EncryptionService.getRawKey(), created);
  });

  for (final folder in ['inventory_photos', 'journal_draft']) {
    test('missing key preserves orphaned encrypted $folder files', () async {
      final media = Directory('${directory.path}/$folder');
      await media.create();
      final encrypted = File('${media.path}/private.bin');
      await encrypted.writeAsBytes([4, 2, 8, 1]);
      await expectLater(
          EncryptionService.getRawKey(supportDirectory: () async => directory),
          throwsStateError);
      expect(await secure.read(key: 'hive_key'), isNull);
      expect(await encrypted.readAsBytes(), [4, 2, 8, 1]);
    });
  }

  for (final name in [
    'udm_secure',
    'diary_secure',
    HiveRestoreService.recoveryBoxName,
  ]) {
    test(
        'missing key with only $name never replaces key or changes encrypted bytes',
        () async {
      final box = await Hive.openBox<dynamic>(name,
          encryptionCipher: HiveAesCipher(key), crashRecovery: false);
      await box.put(
          'fixture', 'Datos ficticios cifrados que deben conservarse.');
      await box.flush();
      final file = File(box.path!);
      await box.close();
      final before = await file.readAsBytes();
      expect(before, isNotEmpty);
      await expectLater(EncryptionService.getRawKey(), throwsStateError);
      await expectLater(EncryptionService.getCipher(), throwsStateError);
      expect(await secure.read(key: 'hive_key'), isNull);
      expect(await file.readAsBytes(), before);
      final reopened = await Hive.openBox<dynamic>(name,
          encryptionCipher: HiveAesCipher(key), crashRecovery: false);
      expect(reopened.get('fixture'),
          'Datos ficticios cifrados que deben conservarse.');
    });
  }

  for (final invalid in [
    'not-base64!!!',
    base64UrlEncode([1, 2, 3])
  ]) {
    test(
        'malformed stored key is refused and never replaced: ${invalid.length} chars',
        () async {
      FlutterSecureStorage.setMockInitialValues({'hive_key': invalid});
      await expectLater(EncryptionService.getRawKey(), throwsStateError);
      expect(await secure.read(key: 'hive_key'), invalid);
    });
  }

  test(
      'corrupt encrypted recovery file remains byte-for-byte intact and blocks recovery',
      () async {
    FlutterSecureStorage.setMockInitialValues(
        {'hive_key': base64UrlEncode(key)});
    final settings = await Hive.openBox<dynamic>('udm_secure',
        encryptionCipher: HiveAesCipher(key), crashRecovery: false);
    final diary = await Hive.openBox<DiaryEntry>('diary_secure',
        encryptionCipher: HiveAesCipher(key), crashRecovery: false);
    await settings.put('startDate', '2026-09-10T12:00:00.000');
    await diary.put(
        41,
        DiaryEntry(
            text: 'Inventario ficticio conservado',
            mood: 3,
            createdAt: DateTime(2026, 9, 10, 12)));
    await settings.flush();
    await diary.flush();
    final journal = await Hive.openBox<dynamic>(
        HiveRestoreService.recoveryBoxName,
        encryptionCipher: HiveAesCipher(key),
        crashRecovery: false);
    await journal.put('transaction', {
      'version': 1,
      'phase': 'pending',
      'before': {
        'udm': settings.toMap(),
        'diary': {
          41: {
            'text': 'Inventario ficticio conservado',
            'mood': 3,
            'createdAt': DateTime(2026, 9, 10, 12),
          }
        }
      },
    });
    await journal.flush();
    final file = File(journal.path!);
    await journal.close();
    final corrupt = await file.readAsBytes();
    corrupt[corrupt.length - 1] ^=
        1; // Deliberately corrupt a fixture checksum.
    await file.writeAsBytes(corrupt, flush: true);
    final settingsBytes = await File(settings.path!).readAsBytes();
    final diaryBytes = await File(diary.path!).readAsBytes();
    final restorer =
        HiveRestoreService(); // Exercise production opener and cipher.
    for (var attempt = 0; attempt < 2; attempt++) {
      final result = await restorer.recoverInterrupted(settings, diary);
      expect(result.ok, isFalse);
      expect(result.recoveryRequired, isTrue);
      expect(await file.readAsBytes(), corrupt,
          reason:
              'Opening must never silently truncate a damaged undo journal.');
      expect(await File(settings.path!).readAsBytes(), settingsBytes);
      expect(await File(diary.path!).readAsBytes(), diaryBytes);
      expect(diary.get(41)!.text, 'Inventario ficticio conservado');
      expect(await secure.read(key: 'hive_key'), base64UrlEncode(key));
    }
    // Same-name callers must receive the same failure rather than hang across
    // the guarded zones; an independent valid box can open at the same time.
    final failedOpens = <Future<Object>>[
      for (var i = 0; i < 3; i++)
        openHiveBoxSafely<dynamic>(HiveRestoreService.recoveryBoxName,
                encryptionCipher: HiveAesCipher(key))
            .then<Object>((_) => 'Unexpected success',
                onError: (Object error) => error),
    ];
    final otherBox = openHiveBoxSafely<dynamic>('independent_valid',
        encryptionCipher: HiveAesCipher(key));
    final failures =
        await Future.wait(failedOpens).timeout(const Duration(seconds: 10));
    expect(failures, everyElement(isA<HiveError>()));
    expect(identical(failures.first, failures.last), isTrue);
    final validBox = await otherBox.timeout(const Duration(seconds: 10));
    await validBox.put('test', 'Independent valid data');
    await validBox.flush();
    expect(validBox.get('test'), 'Independent valid data');
    expect(await file.readAsBytes(), corrupt);
    await expectLater(
        openHiveBoxSafely<dynamic>(HiveRestoreService.recoveryBoxName,
                encryptionCipher: HiveAesCipher(key))
            .timeout(const Duration(seconds: 10)),
        throwsA(isA<HiveError>()));
    expect(await file.readAsBytes(), corrupt);
  });

  test('same valid box opens once concurrently without pending futures',
      () async {
    final boxes = await Future.wait([
      for (var i = 0; i < 3; i++)
        openHiveBoxSafely<dynamic>('concurrent_valid',
            encryptionCipher: HiveAesCipher(key)),
    ]).timeout(const Duration(seconds: 10));
    expect(identical(boxes.first, boxes.last), isTrue);
    await boxes.first.put('fixture', 42);
    expect(boxes.last.get('fixture'), 42);
  });
}
