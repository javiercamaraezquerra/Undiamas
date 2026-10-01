import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:un_dia_mas/models/diary_entry.dart';
import 'package:un_dia_mas/screens/profile_screen.dart';
import 'package:un_dia_mas/services/app_lock_controller.dart';
import 'package:un_dia_mas/services/drive_backup_service.dart';
import 'package:un_dia_mas/services/drive_backup_status_store.dart';
import 'package:un_dia_mas/services/notification_preferences_controller.dart';
import 'package:un_dia_mas/theme/app_theme.dart';
import 'package:un_dia_mas/widgets/mountain_background.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const signIn = MethodChannel('plugins.flutter.io/google_sign_in');
  var googleCalls = 0;

  setUpAll(() async {
    await initializeDateFormatting('es_ES');
    Intl.defaultLocale = 'es_ES';
    final fontRoot = Platform.environment['UDM_QA_FONT_ROOT'] ??
        '../undiamas-runtime/flutter-3.32.8/bin/cache/artifacts/material_fonts';
    for (final entry in {
      'Roboto': '$fontRoot/roboto-regular.ttf',
      'MaterialIcons': '$fontRoot/materialicons-regular.otf',
      'Emoji': 'C:/Windows/Fonts/seguiemj.ttf',
    }.entries) {
      final file = File(entry.value);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        await (FontLoader(entry.key)
              ..addFont(Future.value(ByteData.sublistView(bytes))))
            .load();
      }
    }
  });

  setUp(() {
    googleCalls = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(signIn, (_) async {
      googleCalls++;
      throw StateError('Profile rendering must not access Google.');
    });
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(signIn, null);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 16; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<GlobalKey> mount(WidgetTester tester,
      {required bool dark,
      required double width,
      required double scale}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 950);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SharedPreferences.setMockInitialValues({
      'notifyDailyReflection': false,
      'notifyMilestones': false,
      'autoBackup': true,
      'isDarkMode': dark,
    });
    final cipherKey = List<int>.generate(32, (index) => index);
    FlutterSecureStorage.setMockInitialValues(
        {'hive_key': base64UrlEncode(cipherKey)});
    await tester.runAsync(AppLockController.instance.initialize);
    final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('udm_profile_v29_layout_')))!;
    addTearDown(() async {
      await Hive.close();
      final root = await Directory.systemTemp.resolveSymbolicLinks();
      final actual = await directory.resolveSymbolicLinks();
      if (!actual.toLowerCase().startsWith(
          '${root.toLowerCase()}${Platform.pathSeparator}udm_profile_v29_layout_')) {
        throw StateError('Unexpected profile layout fixture directory.');
      }
      await directory.delete(recursive: true);
    });
    await tester.runAsync(() async {
      Hive.init(directory.path);
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(DiaryEntryAdapter());
      }
      final settings = await Hive.openBox<dynamic>('udm_secure',
          encryptionCipher: HiveAesCipher(cipherKey));
      final diary = await Hive.openBox<DiaryEntry>('diary_secure',
          encryptionCipher: HiveAesCipher(cipherKey));
      await settings.put('startDate', '2026-09-15T10:00:00.000');
      await diary.put(
          'synthetic-entry',
          DiaryEntry(
              text: 'Entrada de prueba para comprobar el diseño.',
              mood: 3,
              createdAt: DateTime(2026, 9, 30)));
      await settings.flush();
      await diary.flush();
      final status = DriveBackupStatusStore.instance;
      await status.selectAccount('synthetic-profile-layout');
      await status.recordSuccess(
          'synthetic-profile-layout',
          backupContentFingerprint(
              DriveBackupService.exportHive(settings, diary)));
      // Fixed synthetic receipt for reproducible screenshots. No cloud upload.
      final prefs = await SharedPreferences.getInstance();
      final record =
          jsonDecode(prefs.getString(DriveBackupStatusStore.preferenceKey)!)
              as Map<String, dynamic>;
      record['confirmedAt'] =
          DateTime(2026, 10, 1, 10, 30).toUtc().toIso8601String();
      await prefs.setString(
          DriveBackupStatusStore.preferenceKey, jsonEncode(record));
    });
    final notifications = NotificationsController(
      readPermission: () async => true,
      requestPermission: () async => true,
      openSettings: () async {},
    );
    addTearDown(notifications.dispose);
    final capture = GlobalKey();
    final original = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
    final theme = original.copyWith(
      textTheme: original.textTheme
          .apply(fontFamily: 'Roboto', fontFamilyFallback: const ['Emoji']),
      appBarTheme: original.appBarTheme.copyWith(
        titleTextStyle:
            original.appBarTheme.titleTextStyle?.copyWith(fontFamily: 'Roboto'),
        toolbarTextStyle: original.appBarTheme.toolbarTextStyle
            ?.copyWith(fontFamily: 'Roboto'),
      ),
    );
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: RepaintBoundary(
        key: capture,
        child: Stack(children: [
          const MountainBackground(pageIndex: 4),
          ProfileScreen(notificationsController: notifications),
        ]),
      ),
    ));
    await settle(tester);
    return capture;
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final directory = Directory('build/validation');
      await directory.create(recursive: true);
      await File('${directory.path}/profile-$name-v29.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  for (final scenario in [
    (name: 'light', dark: false, width: 400.0, scale: 1.0),
    (name: 'dark', dark: true, width: 400.0, scale: 1.0),
    (name: 'large-text', dark: false, width: 320.0, scale: 2.0),
  ]) {
    testWidgets(
        'Profile v29 ${scenario.name}: receipt and voluntary rating fit',
        (tester) async {
      final key = await mount(tester,
          dark: scenario.dark, width: scenario.width, scale: scenario.scale);
      final receipt = find.byKey(const ValueKey('drive_backup_status'));
      if (receipt.hitTestable().evaluate().isEmpty) {
        await tester.scrollUntilVisible(receipt, 150,
            scrollable: find.byType(Scrollable).first);
        await Scrollable.ensureVisible(tester.element(receipt), alignment: .4);
      }
      await settle(tester);
      expect(find.textContaining('01/10/2026, 10:30'), findsOneWidget);
      expect(find.textContaining('pendientes de copiar'), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, key, scenario.name);
      final rating = find.byKey(const ValueKey('profile-play-review'));
      await tester.scrollUntilVisible(rating, 180,
          scrollable: find.byType(Scrollable).first);
      await settle(tester);
      expect(find.text('Valorar en Google Play'), findsOneWidget);
      expect(rating.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (scenario.scale == 2) {
        await capture(tester, key, '${scenario.name}-rating');
      }
      expect(googleCalls, 0);
      expect(Hive.box<DiaryEntry>('diary_secure').length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
    });
  }
}
