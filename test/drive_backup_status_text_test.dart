import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:un_dia_mas/models/diary_entry.dart';
import 'package:un_dia_mas/services/drive_backup_service.dart';
import 'package:un_dia_mas/services/drive_backup_status_store.dart';
import 'package:un_dia_mas/services/hive_restore_service.dart';
import 'package:un_dia_mas/widgets/drive_backup_status_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Box<dynamic> settings;
  late Box<DiaryEntry> diary;
  late DriveBackupStatusStore store;
  late HiveRestoreService restore;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'autoBackup': false});
    directory = await Directory.systemTemp.createTemp('udm_backup_status_');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(DiaryEntryAdapter());
    settings = await Hive.openBox<dynamic>('status_settings');
    diary = await Hive.openBox<DiaryEntry>('status_diary');
    await settings.put('startDate', '2026-01-03T10:30:00.000');
    await diary.put(
        'key-before-restore',
        DiaryEntry(
            text: 'Texto que permanece íntegro',
            mood: 3,
            createdAt: DateTime(2026, 10, 1),
            photoId: List.filled(64, 'b').join()));
    store = DriveBackupStatusStore(now: () => DateTime(2026, 10, 1, 15, 30));
    restore = HiveRestoreService();
  });

  tearDown(() async {
    store.dispose();
    restore.dispose();
    await Hive.close();
    final root = await Directory.systemTemp.resolveSymbolicLinks();
    final actual = await directory.resolveSymbolicLinks();
    if (!actual.toLowerCase().startsWith(
        '${root.toLowerCase()}${Platform.pathSeparator}udm_backup_status_')) {
      throw StateError('Unexpected fixture directory.');
    }
    await directory.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester, {double scale = 1}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: ListView(children: [
            DriveBackupStatusText(
              settings: settings,
              diary: diary,
              foreground: Colors.black,
              statusStore: store,
              restoreService: restore,
            ),
          ]),
        ),
      ),
    ));
  }

  Future<void> waitFor(WidgetTester tester, String expected) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.pump(const Duration(milliseconds: 40));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      if (find.textContaining(expected).evaluate().isNotEmpty) return;
    }
    fail('Status did not show: $expected');
  }

  Future<void> recordCurrentCopy() async {
    await store.selectAccount('fixture');
    await store.recordSuccess(
        'fixture',
        backupContentFingerprint(
            DriveBackupService.exportHive(settings, diary)));
  }

  testWidgets('old installs show unknown date without claiming no Drive copy',
      (tester) async {
    await mount(tester);
    await waitFor(tester, 'Sin fecha de copia registrada en este móvil.');
    expect(find.textContaining('No hay copia'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('backup off still shows receipt and detects edits/reset/deletion',
      (tester) async {
    await tester.runAsync(recordCurrentCopy);
    await mount(tester, scale: 2);
    await waitFor(tester, '01/10/2026, 15:30');
    expect(find.textContaining('pendientes'), findsNothing);
    final previousPhoto = diary.values.single.photoId;
    await tester
        .runAsync(() => settings.put('startDate', '2026-10-01T15:35:00.000'));
    await waitFor(tester, 'pendientes de copiar');
    expect(find.textContaining('01/10/2026, 15:30'), findsOneWidget);
    expect(diary.values.single.text, 'Texto que permanece íntegro');
    expect(diary.values.single.photoId, previousPhoto);
    await tester.runAsync(() => diary.clear());
    await waitFor(tester, 'pendientes de copiar');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('equivalent restore with new Hive key preserves receipt',
      (tester) async {
    await tester.runAsync(recordCurrentCopy);
    final previous = diary.values.single;
    await tester.runAsync(() async {
      await diary.clear();
      await diary.put('new-key-after-restore', previous);
    });
    await mount(tester);
    await waitFor(tester, '01/10/2026, 15:30');
    expect(find.textContaining('pendientes'), findsNothing);
    expect(DriveBackupService.exportHive(settings, diary).keys,
        unorderedEquals(['version', 'udm', 'diary']));
    expect(diary.values.single.photoId, List.filled(64, 'b').join());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed last attempt preserves date and account switch hides it',
      (tester) async {
    await tester.runAsync(recordCurrentCopy);
    await mount(tester);
    await waitFor(tester, '01/10/2026, 15:30');
    await tester.runAsync(() => store.recordFailure(accountId: 'fixture'));
    await waitFor(tester, 'No se pudo completar el último intento');
    expect(find.textContaining('01/10/2026, 15:30'), findsOneWidget);
    await tester.runAsync(() => store.selectAccount('different-account'));
    await waitFor(tester, 'Sin fecha de copia registrada');
    expect(find.textContaining('01/10/2026'), findsNothing);
    expect(find.textContaining('último intento'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
