import 'dart:async';
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
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:un_dia_mas/models/diary_entry.dart';
import 'package:un_dia_mas/screens/journal_screen.dart';
import 'package:un_dia_mas/services/journal_draft_store.dart';
import 'package:un_dia_mas/theme/app_theme.dart';
import 'package:un_dia_mas/widgets/mountain_background.dart';
import 'package:un_dia_mas/widgets/inventory_photo_attachment.dart';
import 'package:un_dia_mas/widgets/journal_feedback_card.dart';

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

  Future<({MemoryJournalAttachments gateway, GlobalKey capture})> mount(
      WidgetTester tester,
      {bool dark = false,
      double width = 400,
      double scale = 1,
      double keyboard = 0,
      int? initialMood = 3,
      String initialText = 'Hoy salí a caminar un rato.',
      bool withPhoto = true}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final directory = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('udm_photo_layout_')))!;
    addTearDown(() async {
      await Hive.close();
      final actual = await directory.resolveSymbolicLinks();
      final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
      if (!actual.toLowerCase().startsWith(
              '$temporaryRoot${Platform.pathSeparator}'.toLowerCase()) ||
          !directory.uri.pathSegments
              .where((p) => p.isNotEmpty)
              .last
              .startsWith('udm_photo_layout_')) {
        throw StateError('Unexpected layout fixture path');
      }
      await directory.delete(recursive: true);
    });
    final key = List.generate(32, (i) => i);
    FlutterSecureStorage.setMockInitialValues(
        {'hive_key': base64UrlEncode(key)});
    SharedPreferences.setMockInitialValues({'autoBackup': false});
    final gateway = MemoryJournalAttachments();
    // A generated landscape fixture, containing no user photos or metadata.
    final picture = img.Image(width: 640, height: 360);
    img.fill(picture, color: img.ColorRgb8(142, 194, 206));
    img.fillRect(picture,
        x1: 0, y1: 220, x2: 639, y2: 359, color: img.ColorRgb8(78, 123, 99));
    img.fillCircle(picture,
        x: 480, y: 80, radius: 30, color: img.ColorRgb8(247, 217, 153));
    final photoId =
        await gateway.importPhoto(Uint8List.fromList(img.encodePng(picture)));
    gateway.draft = JournalDraft(
        text: initialText,
        mood: initialMood,
        photoId: withPhoto ? photoId : null,
        entryKey: 'photo-draft-1234567890abcdef');
    await tester.runAsync(() async {
      Hive.init(directory.path);
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(DiaryEntryAdapter());
      }
      final box = await Hive.openBox<DiaryEntry>('diary_secure',
          encryptionCipher: HiveAesCipher(key));
      await box.put(
          1,
          DiaryEntry(
              createdAt: DateTime(2026, 9, 13, 18, 30),
              mood: 2,
              text: 'Un momento para parar.',
              photoId: photoId));
      await box.put(
          2,
          DiaryEntry(
              createdAt: DateTime(2026, 9, 12, 20),
              mood: 3,
              text: 'Una entrada anterior, sin fotografía.'));
      await box.flush();
    });
    final capture = GlobalKey();
    final appTheme = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
    await tester.pumpWidget(MaterialApp(
      theme: appTheme.copyWith(
          appBarTheme: appTheme.appBarTheme.copyWith(
              titleTextStyle: appTheme.appBarTheme.titleTextStyle
                  ?.copyWith(fontFamily: 'Roboto'),
              toolbarTextStyle: appTheme.appBarTheme.toolbarTextStyle
                  ?.copyWith(fontFamily: 'Roboto')),
          primaryTextTheme: appTheme.primaryTextTheme
              .apply(fontFamily: 'Roboto', fontFamilyFallback: const ['Emoji']),
          textTheme: appTheme.textTheme.apply(
              fontFamily: 'Roboto', fontFamilyFallback: const ['Emoji'])),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: RepaintBoundary(
          key: capture,
          child: Stack(children: [
            const MountainBackground(pageIndex: 1),
            JournalScreen(attachmentGateway: gateway),
          ])),
    ));
    // The sun animates continuously, so settle finite UI work with bounded pumps.
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    return (gateway: gateway, capture: capture);
  }

  Future<void> failPhotoSelection(
      WidgetTester tester, MemoryJournalAttachments gateway) async {
    gateway.pickOverride =
        (_) async => throw PlatformException(code: 'photo_access_denied');
    await tester.ensureVisible(find.text('Cambiar'));
    await tester.tap(find.text('Cambiar'));
    await settle(tester);
    await tester.tap(find.text('Elegir de la galería'));
    await settle(tester);
  }

  Future<void> captureFeedback(
      WidgetTester tester, GlobalKey key, String name) async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final raster = await boundary.toImage(pixelRatio: 1);
      final bytes = await raster.toByteData(format: ui.ImageByteFormat.png);
      raster.dispose();
      final output = Directory('build/validation');
      await output.create(recursive: true);
      await File('${output.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  for (final dark in [false, true]) {
    testWidgets(
        'photo preview and saved card render in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
      final fixture = await mount(tester, dark: dark);
      expect(find.text('Hoy salí a caminar un rato.'), findsOneWidget);
      expect(find.text('Cambiar'), findsOneWidget);
      expect(find.text('Quitar'), findsOneWidget);
      expect(find.byType(InventoryPhotoAttachment), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      final boundary = fixture.capture.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final raster = await boundary.toImage(pixelRatio: 1);
        final bytes = await raster.toByteData(format: ui.ImageByteFormat.png);
        raster.dispose();
        final output = Directory('build/validation');
        await output.create(recursive: true);
        await File(
                '${output.path}/journal-photo-${dark ? 'dark' : 'light'}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('small display, 200 percent text and keyboard remain scrollable',
      (tester) async {
    await mount(tester, width: 320, scale: 2, keyboard: 280);
    final save = find.widgetWithText(ElevatedButton, 'Guardar mi día');
    await tester.ensureVisible(save);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<ElevatedButton>(save).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Cambiar'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Quitar'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
      'gallery attachment saves, opens fully and can be removed without its message',
      (tester) async {
    final fixture = await mount(tester);
    final originalBytes = fixture.gateway.photos.values.first;
    await tester.tap(find.text('Quitar'));
    await settle(tester);
    fixture.gateway.selected = XFile.fromData(originalBytes);
    await tester.tap(find.byKey(const ValueKey('journal-add-photo')));
    await settle(tester);
    expect(find.text('Hacer foto'), findsOneWidget);
    expect(find.textContaining('también incluirán tus fotos'), findsOneWidget);
    await tester.tap(find.text('Elegir de la galería'));
    await settle(tester);
    expect(fixture.gateway.pickCalls, 1);
    expect(find.text('Cambiar'), findsOneWidget);
    expect(find.text('Hoy salí a caminar un rato.'), findsOneWidget);
    final save = find.widgetWithText(ElevatedButton, 'Guardar mi día');
    await tester.ensureVisible(save);
    await tester.runAsync(() => tester.tap(save));
    await settle(tester);
    final box = Hive.box<DiaryEntry>('diary_secure');
    expect(box.length, 3);
    final key = box.keys.singleWhere(
        (key) => box.get(key)!.text == 'Hoy salí a caminar un rato.');
    final savedPhoto = box.get(key)!.photoId;
    final savedDate = box.get(key)!.createdAt;
    expect(savedPhoto, isNotNull);
    expect(box.get(key)!.mood, 3);
    final photo = find.byType(InventoryPhotoAttachment).first;
    await tester.ensureVisible(photo);
    await tester.tap(photo);
    await settle(tester);
    expect(find.text('Fotografía'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    final menu = find.byKey(ValueKey('entry-menu-$key'));
    await tester.ensureVisible(menu);
    await tester.runAsync(() => tester.tap(menu));
    await settle(tester);
    await tester.runAsync(() => tester.tap(find.text('Quitar foto')));
    await settle(tester);
    expect(find.text('¿Quitar esta foto?'), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('Quitar foto')));
    await settle(tester);
    expect(box.length, 3);
    expect(box.get(key)!.photoId, isNull);
    expect(box.get(key)!.text, 'Hoy salí a caminar un rato.');
    expect(box.get(key)!.createdAt, savedDate);
    expect(box.get(key)!.mood, 3);
    expect(fixture.gateway.deleted, contains(savedPhoto));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
      'a photo-only entry offers deletion but cannot lose its sole attachment',
      (tester) async {
    final fixture = await mount(tester);
    await tester.enterText(find.byType(TextField), '');
    final save = find.widgetWithText(ElevatedButton, 'Guardar mi día');
    await tester.ensureVisible(save);
    await tester.runAsync(() => tester.tap(save));
    await settle(tester);
    final box = Hive.box<DiaryEntry>('diary_secure');
    final key = box.keys.singleWhere((key) => box.get(key)!.text.isEmpty);
    final photoId = box.get(key)!.photoId;
    expect(photoId, isNotNull);
    final menu = find.byKey(ValueKey('entry-menu-$key'));
    await tester.ensureVisible(menu);
    await tester.runAsync(() => tester.tap(menu));
    await settle(tester);
    expect(find.text('Quitar foto'), findsNothing);
    expect(find.text('Eliminar entrada'), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('Eliminar entrada')));
    await settle(tester);
    await tester.runAsync(() => tester.tap(find.text('Eliminar')));
    await settle(tester);
    expect(box.containsKey(key), isFalse);
    expect(box.length, 2);
    // The older entry still references the same photo, so keep its bytes.
    expect(fixture.gateway.photos.containsKey(photoId), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  for (final dark in [false, true]) {
    testWidgets(
        'photo failure stays readable with prior attachment in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
      final fixture = await mount(tester, dark: dark, initialMood: null);
      final previousPhoto = fixture.gateway.draft!.photoId;
      await failPhotoSelection(tester, fixture.gateway);
      expect(find.byKey(const ValueKey('journal-photo-issue')), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Elegir otra'), findsOneWidget);
      expect(find.byTooltip('Cerrar aviso'), findsOneWidget);
      expect(find.text('Elige cómo te sientes para guardar tu día.'),
          findsOneWidget);
      expect(fixture.gateway.draft!.photoId, previousPhoto);
      expect(fixture.gateway.draft!.text, 'Hoy salí a caminar un rato.');
      final panel = tester.widget<JournalFeedbackCard>(
          find.byKey(const ValueKey('journal-photo-issue')));
      expect(panel.message, isNotEmpty);
      expect(panel.isError, isTrue);
      Scrollable.of(
              tester.element(find.byKey(const ValueKey('journal-photo-issue'))))
          .position
          .jumpTo(0);
      await tester.pump(const Duration(milliseconds: 100));
      await captureFeedback(tester, fixture.capture,
          'journal-photo-error-${dark ? 'dark' : 'light'}-v25');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets(
      'error actions and missing mood remain reachable at 320 px with 200 percent text',
      (tester) async {
    final fixture = await mount(tester,
        width: 320, scale: 2, keyboard: 280, initialMood: null);
    await failPhotoSelection(tester, fixture.gateway);
    final retry = find.byKey(const ValueKey('journal-retry-photo'));
    final other = find.byKey(const ValueKey('journal-choose-other-photo'));
    await tester.ensureVisible(retry);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(other);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester
        .ensureVisible(find.byKey(const ValueKey('journal-photo-issue')));
    await tester.pump(const Duration(milliseconds: 100));
    await captureFeedback(
        tester, fixture.capture, 'journal-photo-error-large-text-v25');
    await tester.ensureVisible(find.byKey(const ValueKey('journal-mood-hint')));
    await tester.pump(const Duration(milliseconds: 100));
    await captureFeedback(
        tester, fixture.capture, 'journal-photo-mood-hint-large-text-v25');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
      'retry, choose another and dismiss preserve the prior photo and text',
      (tester) async {
    final fixture = await mount(tester);
    final previous = fixture.gateway.draft!.photoId;
    await failPhotoSelection(tester, fixture.gateway);
    final afterFailure = fixture.gateway.pickCalls;
    await tester
        .ensureVisible(find.byKey(const ValueKey('journal-retry-photo')));
    await tester.tap(find.byKey(const ValueKey('journal-retry-photo')));
    await settle(tester);
    expect(fixture.gateway.pickCalls, afterFailure + 1);
    ImageSource? requestedSource;
    fixture.gateway.pickOverride = (source) async {
      requestedSource = source;
      throw StateError('Simulated unavailable photo');
    };
    await tester.ensureVisible(
        find.byKey(const ValueKey('journal-choose-other-photo')));
    await tester.tap(find.byKey(const ValueKey('journal-choose-other-photo')));
    await settle(tester);
    expect(requestedSource, ImageSource.gallery);
    expect(fixture.gateway.draft!.photoId, previous);
    expect(fixture.gateway.draft!.text, 'Hoy salí a caminar un rato.');
    await tester.ensureVisible(find.byTooltip('Cerrar aviso'));
    await tester.tap(find.byTooltip('Cerrar aviso'));
    await settle(tester);
    expect(find.byKey(const ValueKey('journal-photo-issue')), findsNothing);
    expect(fixture.gateway.draft!.photoId, previous);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
      'missing mood explains disabled save and disappears after choosing mood',
      (tester) async {
    await mount(tester, initialMood: null, withPhoto: false);
    final save = find.widgetWithText(ElevatedButton, 'Guardar mi día');
    expect(tester.widget<ElevatedButton>(save).onPressed, isNull);
    expect(find.text('Elige cómo te sientes para guardar tu día.'),
        findsOneWidget);
    await tester.tap(find.text('🙂').first);
    await settle(tester);
    expect(find.byKey(const ValueKey('journal-mood-hint')), findsNothing);
    expect(tester.widget<ElevatedButton>(save).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
      'pending photo keeps a readable progress message and the previous attachment',
      (tester) async {
    final fixture = await mount(tester);
    final bytes = fixture.gateway.photos.values.first;
    final pending = Completer<Uint8List>();
    fixture.gateway.selected = XFile.fromData(bytes);
    fixture.gateway.prepareOverride = (_) => pending.future;
    await tester.tap(find.text('Cambiar'));
    await settle(tester);
    await tester.tap(find.text('Elegir de la galería'));
    await settle(tester);
    final feedback = find.byKey(const ValueKey('journal-progress'));
    expect(feedback, findsOneWidget);
    expect(find.text('Preparando foto…'), findsOneWidget);
    expect(tester.widget<JournalFeedbackCard>(feedback).isBusy, isTrue);
    expect(find.byType(InventoryPhotoAttachment), findsWidgets);
    pending.complete(bytes);
    await settle(tester);
    expect(feedback, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('draft errors use the readable panel without photo actions',
      (tester) async {
    final fixture = await mount(tester);
    fixture.gateway.failDraftWrite = true;
    await tester.enterText(
        find.byType(TextField), 'Este texto no debe perderse.');
    await settle(tester);
    final feedback = find.byKey(const ValueKey('journal-editor-issue'));
    expect(feedback, findsOneWidget);
    expect(tester.widget<JournalFeedbackCard>(feedback).actions, isEmpty);
    expect(find.byKey(const ValueKey('journal-photo-issue')), findsNothing);
    expect(find.text('Este texto no debe perderse.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
