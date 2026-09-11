import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:un_dia_mas/models/diary_entry.dart';
import 'package:un_dia_mas/screens/journal_screen.dart';
import 'package:un_dia_mas/services/app_lock_controller.dart';
import 'package:un_dia_mas/services/hive_restore_service.dart';
import 'package:un_dia_mas/widgets/app_lock_gate.dart';

import 'app_lock_widgets_test.dart' show DeviceChallenge, MemoryPrivacy;

/// Real JournalScreen + encrypted Hive in a new, verified temporary directory.
/// Only the device challenge and platform key storage are faked. This does not
/// claim to test the native biometric dialog or touch an installed application.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'privacy lock keeps real inventory, draft and mood through failed and successful unlock',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('undiamas/privacy'), (call) async => null);
    addTearDown(() => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('undiamas/privacy'), null));

    final cipherKey = List<int>.generate(32, (index) => index);
    FlutterSecureStorage.setMockInitialValues(
        {'hive_key': base64UrlEncode(cipherKey)});
    SharedPreferences.setMockInitialValues({
      'autoBackup': false, // Never start Drive/account/network operations.
      'darkMode': true,
      'notifyDailyReflection': true,
      'notificationHour': 9,
      'fav_resources': ['fixture-resource-a', 'fixture-resource-b'],
    });
    final preferences = await SharedPreferences.getInstance();
    final preferencesBefore = _preferenceSnapshot(preferences);
    final directory = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('udm_privacy_test_')))!;
    addTearDown(() async {
      await Hive.close();
      // Fail rather than recursively deleting any unverified path.
      final actual = await directory.resolveSymbolicLinks();
      final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
      final prefix = '$temporaryRoot${Platform.pathSeparator}'.toLowerCase();
      final name = directory.uri.pathSegments.where((p) => p.isNotEmpty).last;
      if (!actual.toLowerCase().startsWith(prefix) ||
          !name.startsWith('udm_privacy_test_')) {
        throw StateError('Refusing to delete an unexpected fixture directory.');
      }
      await directory.delete(recursive: true);
    });

    late Box<dynamic> settings;
    late Box<DiaryEntry> diary;
    const settingsBefore = {
      'startDate': '2024-04-03T10:15:00.000',
      'substance': 'Tabaco',
      'fixture_marker': 42,
    };
    await tester.runAsync(() async {
      Hive.init(directory.path);
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(DiaryEntryAdapter());
      }
      settings = await Hive.openBox<dynamic>('udm_secure',
          encryptionCipher: HiveAesCipher(cipherKey), crashRecovery: false);
      diary = await Hive.openBox<DiaryEntry>('diary_secure',
          encryptionCipher: HiveAesCipher(cipherKey), crashRecovery: false);
      await settings.putAll(settingsBefore);
      await diary.addAll([
        DiaryEntry(
            createdAt: DateTime(2026, 8, 11, 18, 20),
            mood: 0,
            text: 'Entrada ficticia anterior A.'),
        DiaryEntry(
            createdAt: DateTime(2026, 8, 12, 19, 30),
            mood: 2,
            text: 'Entrada ficticia anterior B.'),
      ]);
      await settings.flush();
      await diary.flush();
    });
    final entriesBefore = _entrySnapshot(diary);
    final privacy = MemoryPrivacy(true);
    final challenge = DeviceChallenge();
    final lock =
        AppLockController(preferences: privacy, authenticator: challenge);
    await lock.initialize();
    addTearDown(lock.dispose);

    await tester.pumpWidget(MaterialApp(
        builder: (_, child) => AppLockGate(controller: lock, child: child!),
        home: const JournalScreen()));
    await tester.pump();
    expect(challenge.attempts, 1);
    expect(find.byType(JournalScreen, skipOffstage: false), findsNothing);
    expect(_entrySnapshot(diary), entriesBefore);
    challenge.answer(true);
    await tester.pumpAndSettle();
    expect(find.text('Inventario'), findsOneWidget);

    const draft = 'Borrador ficticio que debe sobrevivir al bloqueo.';
    await tester.enterText(find.byType(TextField), draft);
    await tester.tap(find.text('🙂'));
    await tester.pumpAndSettle();
    final editorBefore =
        tester.widget<TextField>(find.byType(TextField)).controller!;
    final save = find.widgetWithText(ElevatedButton, 'Guardar mi día');
    expect(tester.widget<ElevatedButton>(save).onPressed, isNotNull);
    expect(_entrySnapshot(diary), entriesBefore,
        reason:
            'Typing and choosing a mood must not save an entry on their own.');

    // The full Android lifecycle path, with no paused-to-resumed shortcut.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    expect(find.text(draft), findsOneWidget,
        reason:
            'Recents may show the last authenticated screen; input stays locked.');
    expect(find.byType(JournalScreen, skipOffstage: false), findsOneWidget);
    expect(_entrySnapshot(diary), entriesBefore);
    expect(settings.toMap(), settingsBefore);

    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      binding.handleAppLifecycleStateChanged(state);
      await tester.pump(); // The challenge is pending: do not pumpAndSettle.
    }
    expect(challenge.attempts, 2);
    expect(find.text(draft), findsNothing);
    challenge.answer(false);
    await tester.pumpAndSettle();
    expect(find.text('Desbloquear'), findsOneWidget);
    expect(find.text(draft), findsNothing);
    expect(editorBefore.text, draft);
    expect(_entrySnapshot(diary), entriesBefore);
    expect(_preferenceSnapshot(preferences), preferencesBefore);

    await tester.tap(find.text('Desbloquear'));
    await tester.pump();
    expect(challenge.attempts, 3);
    challenge.answer(true);
    await tester.pumpAndSettle();
    final editorAfter =
        tester.widget<TextField>(find.byType(TextField)).controller!;
    expect(identical(editorAfter, editorBefore), isTrue);
    expect(editorAfter.text, draft);
    expect(tester.widget<ElevatedButton>(save).onPressed, isNotNull,
        reason: 'The actual selected mood must survive along with the draft.');
    expect(_entrySnapshot(diary), entriesBefore);

    // Start actual Hive IO in the real async zone, then wait for its queue.
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(save);
      final elapsed = Stopwatch()..start();
      while (diary.length != 3 || HiveRestoreService.instance.busy) {
        if (elapsed.elapsed > const Duration(seconds: 5)) {
          throw StateError('Inventory write did not complete.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(diary.length, 3);
    expect(_entrySnapshot(diary).take(2).toList(), entriesBefore);
    final saved = diary.values.singleWhere((entry) => entry.text == draft);
    expect(saved.mood, 3,
        reason:
            'Persisted mood proves the real JournalScreen retained selection.');
    expect(editorAfter.text, isEmpty);
    expect(tester.widget<ElevatedButton>(save).onPressed, isNull);
    expect(settings.toMap(), settingsBefore);
    expect(_preferenceSnapshot(preferences), preferencesBefore);
    expect(privacy.writes, isEmpty);
    final allSavedEntries = _entrySnapshot(diary);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.runAsync(() async {
      await Hive.close();
      Hive.init(directory.path);
      settings = await Hive.openBox<dynamic>('udm_secure',
          encryptionCipher: HiveAesCipher(cipherKey), crashRecovery: false);
      diary = await Hive.openBox<DiaryEntry>('diary_secure',
          encryptionCipher: HiveAesCipher(cipherKey), crashRecovery: false);
    });
    expect(_entrySnapshot(diary), allSavedEntries);
    expect(settings.toMap(), settingsBefore);
    expect(_preferenceSnapshot(preferences), preferencesBefore);
    expect(tester.takeException(), isNull);
  });
}

List<Map<String, Object?>> _entrySnapshot(Box<DiaryEntry> box) => [
      for (final key in box.keys)
        {
          'key': key,
          // Hive stores DateTime at millisecond precision. Compare exactly the
          // timestamp the existing adapter can persist, including after reopen.
          'createdAt': box.get(key)!.createdAt.millisecondsSinceEpoch,
          'mood': box.get(key)!.mood,
          'text': box.get(key)!.text,
        }
    ];

Map<String, Object?> _preferenceSnapshot(SharedPreferences preferences) => {
      for (final key in preferences.getKeys())
        key: preferences.get(key) is List
            ? List<Object?>.from(preferences.get(key) as List)
            : preferences.get(key),
    };
