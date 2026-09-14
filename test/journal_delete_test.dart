import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:un_dia_mas/models/diary_entry.dart';
import 'package:un_dia_mas/screens/journal_screen.dart';
import 'package:un_dia_mas/services/drive_backup_service.dart';
import 'package:un_dia_mas/services/hive_restore_service.dart';
import 'support/memory_journal_attachments.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({Directory directory, Box<DiaryEntry> diary, Box settings})> fixture(
    WidgetTester tester, {
    Future<BackupResult<void>> Function(Map<String, dynamic>)? uploadBackup,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final cipherKey = List<int>.generate(32, (i) => i);
    FlutterSecureStorage.setMockInitialValues(
        {'hive_key': base64UrlEncode(cipherKey)});
    SharedPreferences.setMockInitialValues({
      'autoBackup': false,
      'privacyAppLockEnabled': true,
      'fav_resources': ['kept'],
    });
    final directory = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('udm_delete_test_')))!;
    addTearDown(() async {
      await Hive.close();
      final actual = await directory.resolveSymbolicLinks();
      final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
      final prefix = '$temporaryRoot${Platform.pathSeparator}'.toLowerCase();
      final name = directory.uri.pathSegments.where((p) => p.isNotEmpty).last;
      if (!actual.toLowerCase().startsWith(prefix) ||
          !name.startsWith('udm_delete_test_')) {
        throw StateError(
            'Unexpected fixture path; refusing recursive deletion.');
      }
      await directory.delete(recursive: true);
    });
    late Box<DiaryEntry> diary;
    late Box settings;
    await tester.runAsync(() async {
      Hive.init(directory.path);
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(DiaryEntryAdapter());
      }
      diary = await Hive.openBox<DiaryEntry>('diary_secure',
          encryptionCipher: HiveAesCipher(cipherKey), crashRecovery: false);
      settings = await Hive.openBox('udm_secure',
          encryptionCipher: HiveAesCipher(cipherKey), crashRecovery: false);
      await settings.putAll({
        'startDate': '2025-01-02T10:00:00.000',
        'substance': 'Tabaco',
      });
      // Nonconsecutive keys and duplicate text catch index-based deletion bugs.
      await diary.putAll({
        4: DiaryEntry(
            createdAt: DateTime(2026, 8, 1), mood: 1, text: 'Anterior'),
        19: DiaryEntry(
            createdAt: DateTime(2026, 8, 2), mood: 4, text: 'Anterior'),
      });
    });
    await tester.pumpWidget(MaterialApp(
        home: JournalScreen(
            uploadBackup: uploadBackup,
            attachmentGateway: MemoryJournalAttachments())));
    await tester.pumpAndSettle();
    return (directory: directory, diary: diary, settings: settings);
  }

  Future<void> askToDelete(WidgetTester tester, Object key) async {
    final menu = find.byKey(ValueKey('entry-menu-$key'));
    await tester.ensureVisible(menu);
    // PopupMenuButton itself awaits its menu before invoking onSelected, so
    // start that first async continuation in the real zone as well.
    await tester.runAsync(() => tester.tap(menu));
    await tester.pumpAndSettle();
    // Start the async deletion flow (including the dialog Future) in the real
    // zone. Moving only the final confirmation tap to runAsync is too late:
    // its awaiting continuation otherwise still initiates Hive IO in FakeAsync.
    await tester.runAsync(() => tester.tap(find.text('Eliminar entrada')));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar esta entrada?'), findsOneWidget);
    expect(find.textContaining('No se puede deshacer'), findsNothing);
    expect(find.textContaining('copias automáticas'), findsNothing);
  }

  Future<void> waitForMutation(
      WidgetTester tester, bool Function() completed) async {
    final elapsed = Stopwatch()..start();
    while (!completed() || HiveRestoreService.instance.busy) {
      if (elapsed.elapsed > const Duration(seconds: 5)) {
        throw StateError('The real inventory IO did not finish.');
      }
      // Draft persistence and Hive IO cross both zones. Advance UI microtasks
      // as well as real disk completion; do not infer success from box.put alone.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
  }

  testWidgets(
      'cancel preserves everything; confirmed deletion removes only the '
      'selected stable key and survives encrypted reopen', (tester) async {
    final f = await fixture(tester);
    final prefs = await SharedPreferences.getInstance();
    final settingsBefore = f.settings.toMap();
    final survivor = f.diary.get(19)!;
    await tester.enterText(find.byType(TextField), 'Borrador que se conserva');
    await tester.tap(find.text('🙂'));
    await tester.pumpAndSettle();
    await askToDelete(tester, 4);
    await tester.runAsync(() async {
      await tester.tap(find.text('Cancelar'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(f.diary.keys.toList(), [4, 19]);
    expect(find.text('Borrador que se conserva'), findsOneWidget);

    await askToDelete(tester, 4);
    await tester.runAsync(() async {
      await tester.tap(find.text('Eliminar'));
    });
    await waitForMutation(tester, () => !f.diary.containsKey(4));
    await tester.pumpAndSettle();
    expect(f.diary.keys.toList(), [19]);
    expect(identical(f.diary.get(19), survivor), isTrue);
    expect(find.text('Borrador que se conserva'), findsOneWidget);
    expect(
        tester
            .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Guardar mi día'))
            .onPressed,
        isNotNull);
    expect(f.settings.toMap(), settingsBefore);
    expect(prefs.getBool('privacyAppLockEnabled'), isTrue);
    expect(prefs.getStringList('fav_resources'), ['kept']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await f.diary.close();
      final reopened = await Hive.openBox<DiaryEntry>('diary_secure',
          encryptionCipher: HiveAesCipher(List<int>.generate(32, (i) => i)),
          crashRecovery: false);
      expect(reopened.keys.toList(), [19]);
      expect(reopened.get(19)!.text, survivor.text);
      expect(reopened.get(19)!.mood, survivor.mood);
      expect(reopened.get(19)!.createdAt, survivor.createdAt);
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('a just-saved entry can be removed without deleting earlier days',
      (tester) async {
    final f = await fixture(tester);
    await tester.enterText(find.byType(TextField), 'Recién guardada');
    await tester.tap(find.text('🙂'));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(ElevatedButton, 'Guardar mi día');
    await tester.runAsync(() async {
      // Two rapid presses must not create two entries while a write is pending.
      final callback = tester.widget<ElevatedButton>(save).onPressed!;
      callback();
      callback();
    });
    await waitForMutation(tester, () => f.diary.length == 3);
    await tester.pumpAndSettle();
    expect(f.diary.length, 3);
    final savedKey = f.diary.keys
        .singleWhere((key) => f.diary.get(key)!.text == 'Recién guardada');
    await askToDelete(tester, savedKey);
    await tester.runAsync(() async {
      await tester.tap(find.text('Eliminar'));
    });
    await waitForMutation(tester, () => !f.diary.containsKey(savedKey));
    await tester.pumpAndSettle();
    expect(f.diary.keys.toList(), [4, 19]);
    expect(find.text('Recién guardada'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'an outdated confirmation cannot delete an entry after restore '
      'generation changes', (tester) async {
    final f = await fixture(tester);
    await askToDelete(tester, 19);
    await HiveRestoreService.instance.runDeletion(() async {});
    await tester.runAsync(() async {
      await tester.tap(find.text('Eliminar'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(f.diary.keys.toList(), [4, 19]);
    expect(find.textContaining('No se pudo completar la eliminación'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'automatic backup receives the remaining entries; a Drive failure '
      'does not resurrect the deleted entry or discard the draft',
      (tester) async {
    Map<String, dynamic>? uploaded;
    final f = await fixture(tester, uploadBackup: (payload) async {
      uploaded = payload;
      return const BackupResult.failure('Simulated offline transport');
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoBackup', true);
    await tester.enterText(find.byType(TextField), 'Otro borrador');
    await askToDelete(tester, 19);
    await tester.runAsync(() async {
      await tester.tap(find.text('Eliminar'));
    });
    await waitForMutation(tester, () => !f.diary.containsKey(19));
    await tester.pumpAndSettle();
    expect(f.diary.keys.toList(), [4]);
    expect(uploaded, isNotNull);
    expect(uploaded!['udm'], f.settings.toMap());
    final entries = uploaded!['diary'] as List;
    expect(entries, hasLength(1));
    expect(entries.single['mood'], 1);
    expect(entries.single['createdAt'], '2026-08-01T00:00:00.000');
    expect(find.text('Otro borrador'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('no se pudo actualizar Drive'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
