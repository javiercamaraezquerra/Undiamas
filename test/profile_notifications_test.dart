import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:un_dia_mas/models/diary_entry.dart';
import 'package:un_dia_mas/screens/profile_screen.dart';
import 'package:un_dia_mas/services/notification_preferences_controller.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> mountProfile(
      WidgetTester tester, NotificationsController notifications) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SharedPreferences.setMockInitialValues({
      'notifyDailyReflection': false,
      'notifyMilestones': true,
      'autoBackup': false,
      'fixture_untouched': 'conservar',
    });
    final prefs = await SharedPreferences.getInstance();
    final key = List<int>.generate(32, (index) => index);
    FlutterSecureStorage.setMockInitialValues(
        {'hive_key': base64UrlEncode(key)});
    final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('udm_profile_notif_test_')))!;
    addTearDown(() async {
      await Hive.close();
      final actual = await directory.resolveSymbolicLinks();
      final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
      final prefix = '$temporaryRoot${Platform.pathSeparator}'.toLowerCase();
      final name =
          directory.uri.pathSegments.where((part) => part.isNotEmpty).last;
      if (!actual.toLowerCase().startsWith(prefix) ||
          !name.startsWith('udm_profile_notif_test_')) {
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
      await Hive.openBox<DiaryEntry>('diary_secure',
          encryptionCipher: HiveAesCipher(key), crashRecovery: false);
    });
    await tester.pumpWidget(MaterialApp(
      home: ProfileScreen(notificationsController: notifications),
    ));
    await tester.pumpAndSettle();
    return prefs;
  }

  Finder preferenceSwitch(String title) => find.descendant(
      of: find.widgetWithText(ListTile, title), matching: find.byType(Switch));

  testWidgets(
      'denied activation leaves switch off and opens settings only on tap',
      (tester) async {
    var requests = 0;
    var settingsOpened = 0;
    final notifications = NotificationsController(
      readPermission: () async => false,
      requestPermission: () async {
        requests++;
        return false;
      },
      openSettings: () async {
        settingsOpened++;
      },
    );
    addTearDown(notifications.dispose);
    final prefs = await mountProfile(tester, notifications);
    final daily = preferenceSwitch('Notificación diaria de reflexión');
    expect(tester.widget<Switch>(daily).value, isFalse);
    await tester.tap(daily);
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(settingsOpened, 0);
    expect(prefs.getBool('notifyDailyReflection'), isFalse);
    expect(tester.widget<Switch>(daily).value, isFalse);
    expect(find.textContaining('No se ha activado este aviso'), findsOneWidget);
    await tester.tap(find.text('Abrir ajustes'));
    await tester.pumpAndSettle();
    expect(settingsOpened, 1);
    expect(prefs.getString('fixture_untouched'), 'conservar');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'resume updates permission subtitle without rewriting desired switches',
      (tester) async {
    var allowed = false;
    var requests = 0;
    final notifications = NotificationsController(
      readPermission: () async => allowed,
      requestPermission: () async {
        requests++;
        return allowed;
      },
      openSettings: () async {},
    );
    addTearDown(notifications.dispose);
    final prefs = await mountProfile(tester, notifications);
    expect(find.text('Bloqueadas por Android. Toca para abrir ajustes.'),
        findsNWidgets(2));
    expect(
        tester
            .widget<Switch>(preferenceSwitch('Notificaciones de logros'))
            .value,
        isTrue);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused
    ]) {
      binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    allowed = true;
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed
    ]) {
      binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Bloqueadas por Android. Toca para abrir ajustes.'),
        findsNothing);
    expect(prefs.getBool('notifyDailyReflection'), isFalse);
    expect(prefs.getBool('notifyMilestones'), isTrue);
    expect(
        tester
            .widget<Switch>(preferenceSwitch('Notificaciones de logros'))
            .value,
        isTrue);
    expect(requests, 0);
    expect(tester.takeException(), isNull);
  });
}
