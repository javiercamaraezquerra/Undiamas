import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:un_dia_mas/models/diary_entry.dart';
import 'package:un_dia_mas/screens/profile_screen.dart';
import 'package:un_dia_mas/services/drive_backup_service.dart';
import 'package:un_dia_mas/services/hive_restore_service.dart';
import 'package:un_dia_mas/services/notification_preferences_controller.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const signInChannel = MethodChannel('plugins.flutter.io/google_sign_in');
  final authCalls = <String>[];
  PlatformException? signInError;
  Completer<void>? authGate;

  setUp(() async {
    signInError = null;
    authGate = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(signInChannel,
        (call) async {
      authCalls.add(call.method);
      switch (call.method) {
        case 'init':
        case 'disconnect':
        case 'signOut':
        case 'signInSilently':
          return null;
        case 'signIn':
          await authGate?.future;
          if (signInError != null) throw signInError!;
          return null;
        case 'isSignedIn':
          return false;
        default:
          throw StateError('Unexpected authentication step: ${call.method}');
      }
    });
    await DriveBackupService.disconnect();
    authCalls.clear();
  });

  tearDown(() async {
    await DriveBackupService.disconnect();
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(signInChannel, null);
  });

  final backupSwitch = find.descendant(
      of: find.widgetWithText(ListTile, 'Copias automáticas en Drive'),
      matching: find.byType(Switch));

  Future<SharedPreferences> mountProfile(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SharedPreferences.setMockInitialValues({
      'notifyDailyReflection': false,
      'notifyMilestones': false,
      'autoBackup': false,
      'fixture_untouched': 'conservar',
    });
    final prefs = await SharedPreferences.getInstance();
    final key = List<int>.generate(32, (index) => index);
    FlutterSecureStorage.setMockInitialValues(
        {'hive_key': base64UrlEncode(key)});
    final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('udm_profile_backup_test_')))!;
    addTearDown(() async {
      await Hive.close();
      final actual = await directory.resolveSymbolicLinks();
      final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
      final prefix = '$temporaryRoot${Platform.pathSeparator}'.toLowerCase();
      final name =
          directory.uri.pathSegments.where((part) => part.isNotEmpty).last;
      if (!actual.toLowerCase().startsWith(prefix) ||
          !name.startsWith('udm_profile_backup_test_')) {
        throw StateError('Refusing to delete an unexpected fixture directory.');
      }
      await directory.delete(recursive: true);
    });
    await tester.runAsync(() async {
      Hive.init(directory.path);
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(DiaryEntryAdapter());
      }
      final settings = await Hive.openBox<dynamic>('udm_secure',
          encryptionCipher: HiveAesCipher(key), crashRecovery: false);
      await settings.put('startDate', '2025-04-03T10:15:00.000');
      await settings.flush();
      final diary = await Hive.openBox<DiaryEntry>('diary_secure',
          encryptionCipher: HiveAesCipher(key), crashRecovery: false);
      await diary.put(
          'fixture-entry',
          DiaryEntry(
              text: 'Mi entrada permanece aquí.',
              mood: 3,
              createdAt: DateTime(2025, 4, 4)));
      await diary.flush();
    });
    final notifications = NotificationsController(
      readPermission: () async => true,
      requestPermission: () async => true,
      openSettings: () async {},
    );
    addTearDown(notifications.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ProfileScreen(notificationsController: notifications),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(backupSwitch);
    return prefs;
  }

  Future<void> waitUntil(WidgetTester tester, bool Function() finished) async {
    final elapsed = Stopwatch()..start();
    while (!finished()) {
      if (elapsed.elapsed > const Duration(seconds: 5)) {
        throw StateError('The backup UI did not finish its fixture operation.');
      }
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
  }

  Future<void> expectLocalStatePreserved(
      WidgetTester tester, SharedPreferences prefs) async {
    await prefs.reload();
    expect(prefs.getBool('autoBackup'), isFalse);
    expect(prefs.getString('fixture_untouched'), 'conservar');
    expect(tester.widget<Switch>(backupSwitch).value, isFalse);
    expect(tester.widget<Switch>(backupSwitch).onChanged, isNotNull);
    final diary = Hive.box<DiaryEntry>('diary_secure');
    expect(diary.length, 1);
    expect(diary.get('fixture-entry')!.text, 'Mi entrada permanece aquí.');
    expect(diary.get('fixture-entry')!.mood, 3);
    expect(Hive.box<dynamic>('udm_secure').get('startDate'),
        '2025-04-03T10:15:00.000');
    expect(authCalls, isNot(contains('getTokens')));
    expect(find.textContaining('Subiendo copia inicial'), findsNothing);
    expect(tester.takeException(), isNull);
  }

  testWidgets('cancelling Drive disclosure keeps backup off without login',
      (tester) async {
    final prefs = await mountProfile(tester);
    await tester.tap(backupSwitch);
    await tester.pumpAndSettle();
    expect(find.textContaining('incluidas sus fotos'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();
    expect(authCalls, isEmpty);
    await expectLocalStatePreserved(tester, prefs);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final failure in ['null cancellation', 'native cancellation', 'OAuth']) {
    testWidgets('$failure keeps backup off and shows no success',
        (tester) async {
      final prefs = await mountProfile(tester);
      if (failure == 'OAuth') {
        signInError = PlatformException(
            code: 'sign_in_failed',
            message: 'Synthetic ApiException: 10 fixture only');
      } else if (failure == 'native cancellation') {
        signInError = PlatformException(code: 'sign_in_canceled');
      }
      // GoogleSignIn keeps its serialized Future between calls. Start the
      // complete action in real async time so teardown can drain that queue.
      await tester.runAsync(() async {
        authGate = Completer<void>();
        await tester.tap(backupSwitch);
      });
      await tester.pumpAndSettle();
      await tester.runAsync(
          () => tester.tap(find.widgetWithText(ElevatedButton, 'Permitir')));
      await waitUntil(tester, () => authCalls.contains('signIn'));
      expect(prefs.getBool('autoBackup'), isFalse);
      expect(tester.widget<Switch>(backupSwitch).value, isFalse);
      expect(tester.widget<Switch>(backupSwitch).onChanged, isNull);
      expect(HiveRestoreService.instance.busy, isTrue);
      authGate!.complete();
      await waitUntil(
          tester,
          () =>
              !HiveRestoreService.instance.busy &&
              tester.widget<Switch>(backupSwitch).onChanged != null);
      await tester.pumpAndSettle();
      expect(
          find.text(failure == 'OAuth'
              ? 'No se puede conectar con Google Drive en esta versión. Puedes seguir usando la app.'
              : 'Conexión con Google cancelada.'),
          findsOneWidget);
      expect(find.textContaining('ApiException'), findsNothing);
      await expectLocalStatePreserved(tester, prefs);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
