import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:un_dia_mas/models/diary_entry.dart';
import 'package:un_dia_mas/screens/journal_screen.dart';
import 'package:un_dia_mas/screens/profile_screen.dart';
import 'package:un_dia_mas/services/hive_restore_service.dart';
import 'package:un_dia_mas/services/notification_preferences_controller.dart';
import 'package:un_dia_mas/widgets/mood_trend_chart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cipherKey = List<int>.generate(32, (i) => i);
  late Box<DiaryEntry> diary;
  late Box<dynamic> settings;
  late NotificationsController notifications;

  Map<dynamic, Object> snapshot() => {
        for (final key in diary.keys)
          key: {
            'text': diary.get(key)!.text,
            'mood': diary.get(key)!.mood,
            'date': diary.get(key)!.createdAt.toIso8601String(),
          },
      };

  Future<void> mountProfile(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ProfileScreen(notificationsController: notifications),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(MoodTrendChart), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  Future<void> openEntries(WidgetTester tester) async {
    final open = find.byKey(const ValueKey('mood-view-entries'));
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mood-entry-0')));
    await tester.pumpAndSettle();
  }

  Future<void> fixture(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 1100);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    FlutterSecureStorage.setMockInitialValues(
        {'hive_key': base64UrlEncode(cipherKey)});
    SharedPreferences.setMockInitialValues({
      'notifyDailyReflection': false,
      'notifyMilestones': false,
      'autoBackup': false,
      'fav_resources': ['conservar'],
    });
    notifications = NotificationsController(
      readPermission: () async => true,
      requestPermission: () async => true,
      openSettings: () async {},
    );
    addTearDown(notifications.dispose);
    final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('udm_profile_graph_test_')))!;
    addTearDown(() async {
      await Hive.close();
      final actual = await directory.resolveSymbolicLinks();
      final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
      final name = directory.uri.pathSegments.where((p) => p.isNotEmpty).last;
      if (!actual.toLowerCase().startsWith(
              '$temporaryRoot${Platform.pathSeparator}'.toLowerCase()) ||
          !name.startsWith('udm_profile_graph_test_')) {
        throw StateError('Unexpected fixture path; refusing deletion.');
      }
      await directory.delete(recursive: true);
    });
    await tester.runAsync(() async {
      Hive.init(directory.path);
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(DiaryEntryAdapter());
      }
      diary = await Hive.openBox<DiaryEntry>('diary_secure',
          encryptionCipher: HiveAesCipher(cipherKey), crashRecovery: false);
      settings = await Hive.openBox<dynamic>('udm_secure',
          encryptionCipher: HiveAesCipher(cipherKey), crashRecovery: false);
      await settings.putAll({
        'startDate':
            DateTime.now().subtract(const Duration(days: 35)).toIso8601String(),
        'substance': 'Tabaco',
        'preservedSetting': {'nested': true},
      });
      final today = DateTime.now();
      // Sparse keys, reverse chronological insertion, and exact text spacing.
      await diary.putAll({
        19: DiaryEntry(
            createdAt: DateTime(today.year, today.month, today.day, 14, 30),
            mood: 2,
            text: '  Entrada eliminable\ncon su texto original.  '),
        4: DiaryEntry(
            createdAt: DateTime(today.year, today.month, today.day, 8, 15),
            mood: 1,
            text: 'Entrada conservada de la mañana.'),
      });
      await diary.flush();
      await settings.flush();
    });
    await mountProfile(tester);
  }

  Future<void> deleteThroughInventory(WidgetTester tester, Object key) async {
    await tester.pumpWidget(const MaterialApp(home: JournalScreen()));
    await tester.pumpAndSettle();
    final menu = find.byKey(ValueKey('entry-menu-$key'));
    await tester.ensureVisible(menu);
    await tester.runAsync(() => tester.tap(menu));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('Eliminar entrada')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Eliminar'));
      final storage = HiveRestoreService.instance;
      if (storage.busy) {
        final completed = Completer<void>();
        void changed() {
          if (!storage.busy && !completed.isCompleted) completed.complete();
        }

        storage.addListener(changed);
        try {
          changed();
          await completed.future.timeout(const Duration(seconds: 10));
        } finally {
          storage.removeListener(changed);
        }
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
      'reading profile preserves encrypted data; Inventory deletion updates last point and empty chart',
      (tester) async {
    await fixture(tester);
    final before = snapshot();
    final settingsBefore = settings.toMap();
    await openEntries(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(snapshot(), before);
    expect(settings.toMap(), settingsBefore);
    expect(
        (await SharedPreferences.getInstance()).getStringList('fav_resources'),
        ['conservar']);
    await deleteThroughInventory(tester, 19);
    expect(diary.keys.toList(), [4]);
    expect(snapshot()[4], before[4]);
    await mountProfile(tester);
    final chart = tester.widget<MoodTrendChart>(find.byType(MoodTrendChart));
    expect(chart.entries.single.text, 'Entrada conservada de la mañana.');
    await deleteThroughInventory(tester, 4);
    await mountProfile(tester);
    expect(tester.widget<MoodTrendChart>(find.byType(MoodTrendChart)).entries,
        isEmpty);
    expect(settings.toMap(), settingsBefore);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await diary.close();
      diary = await Hive.openBox<DiaryEntry>('diary_secure',
          encryptionCipher: HiveAesCipher(cipherKey), crashRecovery: false);
    });
    expect(diary.isEmpty, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'box removal invalidates a visible detail without changing remaining keys',
      (tester) async {
    await fixture(tester);
    await openEntries(tester);
    final before = snapshot();
    await tester.runAsync(() async {
      await diary.delete(19);
      await diary.flush();
    });
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.textContaining('Entrada eliminable', skipOffstage: false),
        findsNothing);
    expect(snapshot(), {4: before[4]!});
    expect(
        tester
            .widget<MoodTrendChart>(find.byType(MoodTrendChart))
            .entries
            .length,
        1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'busy data invalidates detail beneath another route without closing that route',
      (tester) async {
    await fixture(tester);
    await openEntries(tester);
    final context = tester.element(find.byType(MoodTrendChart));
    unawaited(showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Otra operación de prueba'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cerrar prueba'))
              ],
            )));
    await tester.pumpAndSettle();
    final before = snapshot();
    final completion = Completer<void>();
    late Future<void> pending;
    await tester.runAsync(() async {
      pending =
          HiveRestoreService.instance.runExclusive(() => completion.future);
    });
    addTearDown(() async {
      if (!completion.isCompleted) completion.complete();
      await pending;
    });
    await tester.pumpAndSettle();
    expect(find.text('Otra operación de prueba'), findsOneWidget);
    expect(find.byType(BottomSheet, skipOffstage: false), findsNothing);
    expect(find.textContaining('Entrada eliminable', skipOffstage: false),
        findsNothing);
    completion.complete();
    await tester.runAsync(() => pending);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerrar prueba'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet, skipOffstage: false), findsNothing);
    expect(snapshot(), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'real encrypted restore replaces plotted data and dismisses obsolete detail',
      (tester) async {
    await fixture(tester);
    await openEntries(tester);
    final date = DateTime.now();
    final prepared = HiveRestoreService.prepare({
      'udm': {'startDate': settings.get('startDate'), 'substance': 'Tabaco'},
      'diary': [
        {
          'createdAt': date.toIso8601String(),
          'mood': 3,
          'text': 'Entrada recuperada de una copia ficticia.',
        }
      ],
    });
    final result = await tester.runAsync(
        () => HiveRestoreService.instance.restore(prepared, settings, diary));
    expect(result!.ok, isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet, skipOffstage: false), findsNothing);
    final chart = tester.widget<MoodTrendChart>(find.byType(MoodTrendChart));
    expect(
        chart.entries.single.text, 'Entrada recuperada de una copia ficticia.');
    expect(chart.entries.single.mood, 3);
    expect(chart.entries.single.createdAt, date);
    expect(diary.keys.toList(), [0]);
    expect(settings.get('preservedSetting'), {'nested': true});
    expect(find.textContaining('Entrada eliminable', skipOffstage: false),
        findsNothing);
    expect(tester.takeException(), isNull);
  });
}
