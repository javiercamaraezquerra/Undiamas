import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
    final sdkRoot = Platform.environment['FLUTTER_ROOT'];
    // CI provides FLUTTER_ROOT; the local runtime lives beside this checkout.
    // Geometry assertions need the same real fonts locally and in CI.
    final root = Platform.environment['UDM_QA_FONT_ROOT'] ??
        (sdkRoot != null && sdkRoot.isNotEmpty
            ? '$sdkRoot/bin/cache/artifacts/material_fonts'
            : '../undiamas-runtime/flutter-3.32.8/bin/cache/artifacts/material_fonts');
    for (final font in {
      'Roboto': '$root/Roboto-Regular.ttf',
      'MaterialIcons': '$root/MaterialIcons-Regular.otf',
      'Emoji': 'C:/Windows/Fonts/seguiemj.ttf',
    }.entries) {
      final file = File(font.value);
      if (font.key != 'Emoji' && !await file.exists()) {
        throw StateError('Required layout-test font is missing: ${file.path}. '
            'Set FLUTTER_ROOT or UDM_QA_FONT_ROOT to the Flutter SDK fonts.');
      }
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
          bool background = false,
          double keyboard = 0}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final directory = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('udm_search_test_')))!;
    addTearDown(() async {
      await Hive.close();
      final actual = await directory.resolveSymbolicLinks();
      final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
      final name = directory.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (!actual.toLowerCase().startsWith(
              '$temporaryRoot${Platform.pathSeparator}'.toLowerCase()) ||
          !name.startsWith('udm_search_test_')) {
        throw StateError('Unexpected search fixture path');
      }
      await directory.delete(recursive: true);
    });
    final cipherKey = List<int>.generate(32, (i) => i);
    FlutterSecureStorage.setMockInitialValues(
        {'hive_key': base64UrlEncode(cipherKey)});
    SharedPreferences.setMockInitialValues({'autoBackup': false});
    final gateway = MemoryJournalAttachments();
    final photoA = await gateway.importPhoto(Uint8List.fromList(img.encodePng(
        img.Image(width: 20, height: 20)..setPixelRgb(0, 0, 250, 0, 0))));
    final photoB = await gateway.importPhoto(Uint8List.fromList(img.encodePng(
        img.Image(width: 20, height: 20)..setPixelRgb(0, 0, 0, 250, 0))));
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
            createdAt: DateTime(2026, 8, 1),
            mood: 3,
            text: 'Café con calma.',
            photoId: photoA),
        19: DiaryEntry(
            createdAt: DateTime(2026, 8, 2),
            mood: 4,
            text: 'Un paseo por el río.',
            photoId: photoB),
        'saved-stable-key': DiaryEntry(
            createdAt: DateTime(2026, 8, 3),
            mood: 2,
            text: 'CAFÉ con mi familia.'),
      });
      await diary.flush();
    });
    final capture = GlobalKey();
    final theme = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
    await tester.pumpWidget(MaterialApp(
      theme: theme.copyWith(
          appBarTheme: theme.appBarTheme.copyWith(
              titleTextStyle: theme.appBarTheme.titleTextStyle
                  ?.copyWith(fontFamily: 'Roboto'),
              toolbarTextStyle: theme.appBarTheme.toolbarTextStyle
                  ?.copyWith(fontFamily: 'Roboto')),
          textTheme: theme.textTheme.apply(
              fontFamily: 'Roboto', fontFamilyFallback: const ['Emoji'])),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: RepaintBoundary(
          key: capture,
          child: Stack(children: [
            if (background) const MountainBackground(pageIndex: 1),
            JournalScreen(attachmentGateway: gateway),
          ])),
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
    if (finder.evaluate().isEmpty) {
      // Slivers outside the viewport/cache may not exist yet, particularly
      // with the wider fallback font, enlarged text and the keyboard together.
      final inventoryScroll = find
          .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(finder, 180,
          scrollable: inventoryScroll, maxScrolls: 30);
      await settle(tester);
    }
    await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
    await settle(tester);
    expect(finder.hitTestable(), findsOneWidget);
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

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  }

  testWidgets('search filters saved text and photos while preserving the draft',
      (tester) async {
    final f = await fixture(tester);
    await tester.enterText(find.byType(TextField), 'Mi borrador pendiente');
    await tester.tap(find.text('🙂').first);
    await settle(tester);
    await search(tester, 'CAFE calma');
    expect(find.text('1 entrada encontrada'), findsOneWidget);
    expect(find.text('Café con calma.'), findsOneWidget);
    expect(find.text('Un paseo por el río.'), findsNothing);
    expect(find.text('CAFÉ con mi familia.'), findsNothing);
    final photo = tester.widget<InventoryPhotoAttachment>(
        find.byType(InventoryPhotoAttachment));
    expect(photo.photoId, f.diary.get(4)!.photoId);
    expect(f.gateway.draft!.text, 'Mi borrador pendiente');
    expect(f.gateway.draft!.mood, 3);
    expect(f.diary.length, 3);

    await search(tester, 'rio');
    expect(find.text('Un paseo por el río.'), findsOneWidget);
    expect(
        tester
            .widget<InventoryPhotoAttachment>(
                find.byType(InventoryPhotoAttachment))
            .photoId,
        f.diary.get(19)!.photoId);
    await search(tester, 'imposible');
    expect(find.text('0 entradas encontradas'), findsOneWidget);
    expect(find.textContaining('No hay entradas con esas palabras'),
        findsOneWidget);
    final clear = find.byTooltip('Limpiar búsqueda');
    await reveal(tester, clear);
    await tester.tap(clear);
    await settle(tester);
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('journal-search-field')))
            .controller!
            .text,
        '');
    final close = find.byTooltip('Cerrar búsqueda');
    await reveal(tester, close);
    await tester.tap(close);
    await settle(tester);
    expect(find.byKey(const ValueKey('journal-search-field')), findsNothing);
    expect(f.gateway.draft!.text, 'Mi borrador pendiente');
    expect(f.diary.length, 3);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('deleting a filtered result uses its stable Hive key only',
      (tester) async {
    final f = await fixture(tester);
    final saved = f.diary.get('saved-stable-key')!;
    final other = f.diary.get(19)!;
    final deletedPhoto = f.diary.get(4)!.photoId;
    await tester.enterText(find.byType(TextField), 'Conservar borrador');
    await search(tester, 'cafe');
    expect(find.text('2 entradas encontradas'), findsOneWidget);
    final menu = find.byKey(const ValueKey('entry-menu-4'));
    await reveal(tester, menu);
    await tester.runAsync(() => tester.tap(menu));
    await settle(tester);
    await tester.runAsync(() => tester.tap(find.text('Eliminar entrada')));
    await settle(tester);
    await tester.runAsync(() => tester.tap(find.text('Eliminar')));
    await settle(tester);
    expect(f.diary.containsKey(4), isFalse);
    expect(f.diary.keys.toList(), [19, 'saved-stable-key']);
    expect(identical(f.diary.get(19), other), isTrue);
    expect(identical(f.diary.get('saved-stable-key'), saved), isTrue);
    expect(f.gateway.deleted, contains(deletedPhoto));
    expect(f.gateway.photos.containsKey(other.photoId), isTrue);
    expect(find.text('1 entrada encontrada'), findsOneWidget);
    expect(find.text('CAFÉ con mi familia.'), findsOneWidget);
    expect(f.gateway.draft!.text, 'Conservar borrador');
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets(
      'saving with a search open refreshes results without changing query',
      (tester) async {
    final f = await fixture(tester);
    await tester.enterText(find.byType(TextField), 'Otro café con calma.');
    await tester.tap(find.text('🙂').first);
    await search(tester, 'cafe');
    final save = find.widgetWithText(ElevatedButton, 'Guardar mi día');
    await reveal(tester, save);
    await tester.runAsync(() => tester.tap(save));
    await settle(tester);
    expect(f.diary.length, 4);
    expect(f.diary.values.where((e) => e.text == 'Otro café con calma.'),
        hasLength(1));
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('journal-search-field')))
            .controller!
            .text,
        'cafe');
    expect(find.text('3 entradas encontradas'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('search updates after a real restore and rejects stale deletion',
      (tester) async {
    final f = await fixture(tester);
    await search(tester, 'rio');
    final menu = find.byKey(const ValueKey('entry-menu-19'));
    await reveal(tester, menu);
    await tester.runAsync(() => tester.tap(menu));
    await settle(tester);
    await tester.runAsync(() => tester.tap(find.text('Eliminar entrada')));
    await settle(tester);
    final prepared = HiveRestoreService.prepare({
      'udm': {'startDate': '2025-01-02T10:00:00.000'},
      'diary': [
        {
          'createdAt': '2026-09-02T10:00:00.000',
          'mood': 3,
          'text': 'El RÍO al volver a casa.'
        },
        {
          'createdAt': '2026-09-03T10:00:00.000',
          'mood': 2,
          'text': 'Una entrada restaurada sin coincidencia.'
        },
      ],
    });
    final result = await tester.runAsync(() =>
        HiveRestoreService.instance.restore(prepared, f.settings, f.diary));
    expect(result!.ok, isTrue);
    await tester.runAsync(() => tester.tap(find.text('Eliminar')));
    await settle(tester);
    expect(f.diary.length, 2);
    expect(f.diary.get(0)!.text, 'El RÍO al volver a casa.');
    expect(find.textContaining('No se pudo completar la eliminación'),
        findsOneWidget);
    expect(find.text('1 entrada encontrada'), findsOneWidget);
    expect(find.text('El RÍO al volver a casa.'), findsOneWidget);
    expect(find.text('Un paseo por el río.'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  for (final scenario in [
    (name: 'light', width: 400.0, scale: 1.0, dark: false, keyboard: 0.0),
    (name: 'dark', width: 400.0, scale: 1.0, dark: true, keyboard: 0.0),
    (
      name: 'large-text',
      width: 320.0,
      scale: 2.0,
      dark: false,
      keyboard: 280.0
    ),
  ]) {
    testWidgets('search remains usable with ${scenario.name} layout',
        (tester) async {
      final f = await fixture(tester,
          width: scenario.width,
          scale: scenario.scale,
          dark: scenario.dark,
          keyboard: scenario.keyboard,
          background: true);
      await search(tester, 'cafe');
      final field = find.byKey(const ValueKey('journal-search-field'));
      await Scrollable.ensureVisible(tester.element(field), alignment: .1);
      await settle(tester);
      expect(find.text('2 entradas encontradas'), findsOneWidget);
      if (scenario.scale > 1.3) {
        // Readable lines occupy the card, instead of a thin column squeezed
        // between mood and menu. The date can wrap before the time, not midway.
        expect(tester.getSize(find.text('CAFÉ con mi familia.')).width,
            greaterThan(220));
        expect(tester.getSize(find.text('3/8/2026')).height, lessThan(60));
      }
      expect(tester.takeException(), isNull);
      final boundary = f.capture.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final raster = await boundary.toImage(pixelRatio: 1);
        final bytes = await raster.toByteData(format: ui.ImageByteFormat.png);
        raster.dispose();
        final output = Directory('build/validation');
        await output.create(recursive: true);
        await File('${output.path}/journal-search-${scenario.name}-v29.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      });
      await reveal(tester, find.byTooltip('Limpiar búsqueda'));
      await tester.tap(find.byTooltip('Limpiar búsqueda'));
      await settle(tester);
      await reveal(tester, find.byTooltip('Cerrar búsqueda'));
      await tester.tap(find.byTooltip('Cerrar búsqueda'));
      await settle(tester);
      expect(find.byKey(const ValueKey('journal-search-field')), findsNothing);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  }
}
