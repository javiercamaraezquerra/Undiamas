import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:un_dia_mas/models/diary_entry.dart';
import 'package:un_dia_mas/screens/journal_screen.dart';
import 'package:un_dia_mas/services/hive_restore_service.dart';
import 'package:un_dia_mas/theme/app_theme.dart';
import 'package:un_dia_mas/widgets/inventory_photo_attachment.dart';
import 'package:un_dia_mas/widgets/mountain_background.dart';

import 'support/memory_journal_attachments.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final root = Platform.environment['UDM_QA_FONT_ROOT'] ??
        '../undiamas-runtime/flutter-3.32.8/bin/cache/artifacts/material_fonts';
    for (final font in {
      'Roboto': '$root/roboto-regular.ttf',
      'MaterialIcons': '$root/materialicons-regular.otf',
      'Emoji': 'C:/Windows/Fonts/seguiemj.ttf',
    }.entries) {
      final file = File(font.value);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        await (FontLoader(font.key)
              ..addFont(Future.value(ByteData.sublistView(bytes))))
            .load();
      }
    }
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<
          ({
            Box<DiaryEntry> diary,
            Box settings,
            MemoryJournalAttachments gateway,
            GlobalKey capture
          })>
      fixture(WidgetTester tester,
          {double width = 400,
          double scale = 1,
          bool dark = false,
          bool background = false}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('udm_date_filter_test_')))!;
    addTearDown(() async {
      await Hive.close();
      final actual = await directory.resolveSymbolicLinks();
      final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
      final name = directory.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (!actual.toLowerCase().startsWith(
              '$temporaryRoot${Platform.pathSeparator}'.toLowerCase()) ||
          !name.startsWith('udm_date_filter_test_')) {
        throw StateError('Unexpected date-filter fixture path');
      }
      await directory.delete(recursive: true);
    });
    final cipherKey = List<int>.generate(32, (i) => i);
    FlutterSecureStorage.setMockInitialValues(
        {'hive_key': base64UrlEncode(cipherKey)});
    SharedPreferences.setMockInitialValues({'autoBackup': false});
    final gateway = MemoryJournalAttachments();
    // Synthetic landscapes keep visual fixtures recognizable and private.
    Future<String> makePhoto(int red, int green, int blue) async {
      final picture = img.Image(width: 320, height: 160);
      img.fill(picture, color: img.ColorRgb8(red, green, blue));
      img.fillRect(picture,
          x1: 0, y1: 100, x2: 319, y2: 159, color: img.ColorRgb8(78, 123, 99));
      img.fillCircle(picture,
          x: 245, y: 43, radius: 22, color: img.ColorRgb8(247, 217, 153));
      return gateway.importPhoto(Uint8List.fromList(img.encodePng(picture)));
    }

    final photoA = await makePhoto(142, 194, 206);
    final photoB = await makePhoto(189, 163, 194);
    late Box<DiaryEntry> diary;
    late Box settings;
    await tester.runAsync(() async {
      Hive.init(directory.path);
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(DiaryEntryAdapter());
      }
      diary = await Hive.openBox<DiaryEntry>('diary_secure',
          encryptionCipher: HiveAesCipher(cipherKey));
      settings = await Hive.openBox('udm_secure',
          encryptionCipher: HiveAesCipher(cipherKey));
      await settings.put('startDate', '2025-01-02T10:00:00.000');
      await diary.putAll({
        4: DiaryEntry(
            createdAt: DateTime(2026, 8, 1, 23, 59),
            mood: 3,
            text: 'Café de la tarde.',
            photoId: photoA),
        19: DiaryEntry(
            createdAt: DateTime(2026, 8, 2, 0, 1),
            mood: 4,
            text: 'Paseo junto al río.',
            photoId: photoB),
        'saved-stable-key': DiaryEntry(
            createdAt: DateTime.utc(2026, 8, 2, 23, 59),
            mood: 2,
            text: 'Café con mi familia.'),
        81: DiaryEntry(
            createdAt: DateTime(2026, 8, 3, 9),
            mood: 3,
            text: 'Un día con música.'),
      });
      await diary.flush();
    });
    final capture = GlobalKey();
    final theme = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es', 'ES'),
      supportedLocales: const [Locale('es', 'ES')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: theme.copyWith(
          appBarTheme: theme.appBarTheme.copyWith(
              titleTextStyle: theme.appBarTheme.titleTextStyle
                  ?.copyWith(fontFamily: 'Roboto'),
              toolbarTextStyle: theme.appBarTheme.toolbarTextStyle
                  ?.copyWith(fontFamily: 'Roboto')),
          textTheme: theme.textTheme.apply(
              fontFamily: 'Roboto', fontFamilyFallback: const ['Emoji'])),
      builder: (context, child) => RepaintBoundary(
          key: capture,
          child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!)),
      home: Stack(children: [
        if (background) const MountainBackground(pageIndex: 1),
        JournalScreen(attachmentGateway: gateway),
      ]),
    ));
    await settle(tester);
    return (
      diary: diary,
      settings: settings,
      gateway: gateway,
      capture: capture
    );
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
    await settle(tester);
    expect(finder.hitTestable(), findsOneWidget);
  }

  Future<void> openCalendar(WidgetTester tester) async {
    final toggle = find.byKey(const ValueKey('journal-date-toggle'));
    await reveal(tester, toggle);
    await tester.tap(toggle);
    await settle(tester);
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(find.text('Ver entradas de un día'), findsOneWidget);
    expect(find.text('Ver día'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
  }

  Future<void> enterDay(WidgetTester tester, DateTime day) async {
    final dialog = find.byType(DatePickerDialog);
    var input = find.descendant(of: dialog, matching: find.byType(TextField));
    if (input.evaluate().isEmpty) {
      final edit = find.descendant(
          of: dialog, matching: find.byIcon(Icons.edit_outlined));
      await tester.tap(edit);
      await settle(tester);
      input = find.descendant(of: dialog, matching: find.byType(TextField));
    }
    expect(input, findsOneWidget);
    final localizations = MaterialLocalizations.of(tester.element(dialog));
    await tester.enterText(input, localizations.formatCompactDate(day));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
  }

  Future<void> selectDay(WidgetTester tester, DateTime day) async {
    await openCalendar(tester);
    await enterDay(tester, day);
    await tester.tap(find.text('Ver día'));
    await settle(tester);
    expect(find.byType(DatePickerDialog), findsNothing);
  }

  void expectSelected(WidgetTester tester, DateTime day) {
    final selected = find.byKey(const ValueKey('journal-date-filter'));
    expect(selected, findsOneWidget);
    final localizations = MaterialLocalizations.of(tester.element(selected));
    final label = 'Día: ${localizations.formatShortDate(day)}';
    expect(find.descendant(of: selected, matching: find.text(label)),
        findsOneWidget);
    expect(label, contains(day.year.toString()));
  }

  Future<void> search(WidgetTester tester, String value) async {
    final field = find.byKey(const ValueKey('journal-search-field'));
    if (field.evaluate().isEmpty) {
      final toggle = find.byKey(const ValueKey('journal-search-toggle'));
      await reveal(tester, toggle);
      await tester.tap(toggle);
      await settle(tester);
    }
    await reveal(tester, field);
    await tester.enterText(field, value);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final raster = await boundary.toImage(pixelRatio: 1);
      final bytes = await raster.toByteData(format: ui.ImageByteFormat.png);
      raster.dispose();
      final output = Directory('build/validation');
      await output.create(recursive: true);
      await File('${output.path}/journal-calendar-$name-v30.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  }

  testWidgets(
      'calendar stays left of search and filters the visible calendar day',
      (tester) async {
    final f = await fixture(tester);
    final calendar = find.byKey(const ValueKey('journal-date-toggle'));
    final magnifier = find.byKey(const ValueKey('journal-search-toggle'));
    expect(tester.getCenter(calendar).dx,
        lessThan(tester.getCenter(magnifier).dx));
    await selectDay(tester, DateTime(2026, 8, 2));
    expectSelected(tester, DateTime(2026, 8, 2));
    expect(find.text('Paseo junto al río.'), findsOneWidget);
    expect(find.text('Café con mi familia.'), findsOneWidget);
    expect(find.text('Café de la tarde.'), findsNothing);
    expect(find.text('Un día con música.'), findsNothing);
    expect(
        tester
            .widget<InventoryPhotoAttachment>(
                find.byType(InventoryPhotoAttachment))
            .photoId,
        f.diary.get(19)!.photoId);
    expect(f.diary.get('saved-stable-key')!.createdAt.isUtc, isTrue);
    expect(f.diary.length, 4);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('date and words are exclusive; each mode shows its own matches',
      (tester) async {
    final f = await fixture(tester);
    await tester.enterText(find.byType(TextField), 'Borrador conservado');
    await tester.tap(find.text('🙂').first);
    await search(tester, 'cafe');
    await selectDay(tester, DateTime(2026, 8, 2));
    expectSelected(tester, DateTime(2026, 8, 2));
    expect(find.byKey(const ValueKey('journal-search-field')), findsNothing);
    // This text has no "cafe": a stale word filter must not hide it.
    expect(find.text('Paseo junto al río.'), findsOneWidget);
    expect(find.text('Café con mi familia.'), findsOneWidget);
    await search(tester, 'cafe');
    expect(find.byKey(const ValueKey('journal-date-filter')), findsNothing);
    expect(find.text('Café de la tarde.'), findsOneWidget);
    expect(find.text('Café con mi familia.'), findsOneWidget);
    expect(find.text('Paseo junto al río.'), findsNothing);
    expect(f.gateway.draft!.text, 'Borrador conservado');
    expect(f.gateway.draft!.mood, 3);
    expect(f.diary.length, 4);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets(
      'clearing a date shows all days without opening or reviving words',
      (tester) async {
    await fixture(tester);
    await search(tester, 'cafe');
    await selectDay(tester, DateTime(2026, 8, 2));
    final clear = find.byKey(const ValueKey('journal-date-clear'));
    await reveal(tester, clear);
    await tester.tap(clear);
    await settle(tester);
    expect(find.byKey(const ValueKey('journal-date-filter')), findsNothing);
    expect(find.byKey(const ValueKey('journal-search-field')), findsNothing);
    expect(find.text('Un día con música.'), findsOneWidget);
    final toggle = find.byKey(const ValueKey('journal-search-toggle'));
    await reveal(tester, toggle);
    await tester.tap(toggle);
    await settle(tester);
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('journal-search-field')))
            .controller!
            .text,
        '');
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('cancel from either mode keeps its previous filter and draft',
      (tester) async {
    final f = await fixture(tester);
    await tester.enterText(find.byType(TextField), 'No perder este borrador');
    await search(tester, 'cafe');
    await openCalendar(tester);
    await enterDay(tester, DateTime(2026, 8, 2));
    await tester.tap(find.text('Cancelar'));
    await settle(tester);
    expect(find.byKey(const ValueKey('journal-date-filter')), findsNothing);
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('journal-search-field')))
            .controller!
            .text,
        'cafe');
    expect(find.text('Café de la tarde.'), findsOneWidget);
    expect(f.gateway.draft!.text, 'No perder este borrador');
    await selectDay(tester, DateTime(2026, 8, 2));
    await openCalendar(tester);
    await enterDay(tester, DateTime(2026, 8, 3));
    await tester.tap(find.text('Cancelar'));
    await settle(tester);
    expectSelected(tester, DateTime(2026, 8, 2));
    expect(find.text('Paseo junto al río.'), findsOneWidget);
    expect(find.text('Un día con música.'), findsNothing);
    expect(f.gateway.draft!.text, 'No perder este borrador');
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets(
      'deleting a day result preserves every other key, photo and draft',
      (tester) async {
    final f = await fixture(tester);
    final survivor = f.diary.get(4)!;
    final sameDay = f.diary.get('saved-stable-key')!;
    final removedPhoto = f.diary.get(19)!.photoId;
    await tester.enterText(find.byType(TextField), 'Texto sin guardar');
    await selectDay(tester, DateTime(2026, 8, 2));
    final menu = find.byKey(const ValueKey('entry-menu-19'));
    await reveal(tester, menu);
    await tester.runAsync(() => tester.tap(menu));
    await settle(tester);
    await tester.runAsync(() => tester.tap(find.text('Eliminar entrada')));
    await settle(tester);
    await tester.runAsync(() => tester.tap(find.text('Eliminar')));
    await settle(tester);
    expect(f.diary.containsKey(19), isFalse);
    expect(f.diary.length, 3);
    expect(identical(f.diary.get(4), survivor), isTrue);
    expect(identical(f.diary.get('saved-stable-key'), sameDay), isTrue);
    expect(f.diary.containsKey(81), isTrue);
    expect(f.gateway.deleted, contains(removedPhoto));
    expect(f.gateway.photos.containsKey(survivor.photoId), isTrue);
    expect(f.gateway.draft!.text, 'Texto sin guardar');
    expectSelected(tester, DateTime(2026, 8, 2));
    expect(find.text('Paseo junto al río.'), findsNothing);
    expect(find.text('Café con mi familia.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('the selected day reacts to a real restore without stale entries',
      (tester) async {
    final f = await fixture(tester);
    await selectDay(tester, DateTime(2026, 8, 2));
    final result =
        await tester.runAsync(() => HiveRestoreService.instance.restore(
            HiveRestoreService.prepare({
              'udm': {'startDate': '2025-01-02T10:00:00.000'},
              'diary': [
                {
                  'createdAt': '2026-08-02T12:00:00.000',
                  'mood': 3,
                  'text': 'Una entrada restaurada de este día.'
                },
                {
                  'createdAt': '2026-08-03T12:00:00.000',
                  'mood': 2,
                  'text': 'Una entrada restaurada de otro día.'
                },
              ],
            }),
            f.settings,
            f.diary));
    expect(result!.ok, isTrue);
    await settle(tester);
    expectSelected(tester, DateTime(2026, 8, 2));
    expect(find.text('Una entrada restaurada de este día.'), findsOneWidget);
    expect(find.text('Una entrada restaurada de otro día.'), findsNothing);
    expect(find.text('Paseo junto al río.'), findsNothing);
    expect(find.text('Café con mi familia.'), findsNothing);
    expect(f.diary.length, 2);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  for (final scenario in [
    (name: 'light', width: 400.0, scale: 1.0, dark: false),
    (name: 'dark', width: 400.0, scale: 1.0, dark: true),
    (name: 'large-text', width: 320.0, scale: 2.0, dark: false),
  ]) {
    testWidgets('calendar picker and results are usable in ${scenario.name}',
        (tester) async {
      final f = await fixture(tester,
          width: scenario.width,
          scale: scenario.scale,
          dark: scenario.dark,
          background: true);
      await openCalendar(tester);
      expect(find.text('Cancelar').hitTestable(), findsOneWidget);
      expect(find.text('Ver día').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (scenario.scale > 1.3) {
        final input = find.descendant(
            of: find.byType(DatePickerDialog),
            matching: find.byType(TextField));
        expect(input, findsOneWidget,
            reason:
                'A narrow screen with large text starts in readable input mode.');
        expect(MediaQuery.textScalerOf(tester.element(input)).scale(16), 32);
        // Starting in input mode also opens the real phone's keyboard. Verify
        // the actions stay reachable on a short screen before taking full PNGs.
        tester.view.physicalSize = const Size(320, 640);
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        await settle(tester);
        expect(input.hitTestable(), findsOneWidget);
        expect(find.text('Cancelar').hitTestable(), findsOneWidget);
        expect(find.text('Ver día').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        tester.view.physicalSize = Size(scenario.width, 900);
        tester.view.resetViewInsets();
        await settle(tester);
      }
      await capture(tester, f.capture, 'picker-${scenario.name}');
      if (scenario.scale > 1.3) {
        await enterDay(tester, DateTime(2026, 8, 2));
        final calendarMode = find.descendant(
            of: find.byType(DatePickerDialog),
            matching: find.byIcon(Icons.calendar_today));
        await tester.tap(calendarMode);
        await settle(tester);
        expect(find.byType(CalendarDatePicker), findsOneWidget);
        expect(
            tester
                .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
                .initialDate,
            DateTime(2026, 8, 2),
            reason: 'Changing text scaling must preserve the chosen date.');
        expect(
            MediaQuery.textScalerOf(
                    tester.element(find.byType(CalendarDatePicker)))
                .scale(16),
            closeTo(16 * 1.4, .001));
        expect(find.text('Cancelar').hitTestable(), findsOneWidget);
        expect(find.text('Ver día').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, f.capture, 'picker-grid-${scenario.name}');
      }
      await enterDay(tester, DateTime(2026, 8, 2));
      if (scenario.scale > 1.3) {
        final input = find.descendant(
            of: find.byType(DatePickerDialog),
            matching: find.byType(TextField));
        expect(MediaQuery.textScalerOf(tester.element(input)).scale(16), 32,
            reason: 'Switching back to input restores the chosen text size.');
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Ver día'));
      await settle(tester);
      expectSelected(tester, DateTime(2026, 8, 2));
      final selected = find.byKey(const ValueKey('journal-date-filter'));
      if (scenario.scale > 1.3) {
        expect(MediaQuery.textScalerOf(tester.element(selected)).scale(16), 32,
            reason: 'The calendar adjustment never reduces Inventory text.');
      }
      await Scrollable.ensureVisible(tester.element(selected), alignment: .1);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await capture(tester, f.capture, 'result-${scenario.name}');
      final clear = find.byKey(const ValueKey('journal-date-clear'));
      await reveal(tester, clear);
      await tester.tap(clear);
      await settle(tester);
      expect(find.byKey(const ValueKey('journal-date-filter')), findsNothing);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  }
}
