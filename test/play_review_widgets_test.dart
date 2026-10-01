import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:un_dia_mas/services/play_review_service.dart';
import 'package:un_dia_mas/theme/app_theme.dart';
import 'package:un_dia_mas/widgets/play_review_prompt.dart';
import 'package:un_dia_mas/widgets/profile_review_tile.dart';

import 'play_review_service_test.dart' show MemoryReviewPreferences;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late PlayReviewService service;
  late MemoryReviewPreferences storage;
  late ReviewNavigationObserver navigation;
  late ValueNotifier<bool> available;
  late ValueNotifier<int> tab;
  late GlobalKey<NavigatorState> navigatorKey;
  late DateTime now;
  late List<Uri> links;
  late bool launchResult;
  late GlobalKey capture;

  setUpAll(() async {
    final root = Platform.environment['UDM_QA_FONT_ROOT'] ??
        '../undiamas-runtime/flutter-3.32.8/bin/cache/artifacts/material_fonts';
    for (final font in {
      'Roboto': '$root/roboto-regular.ttf',
      'MaterialIcons': '$root/materialicons-regular.otf',
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

  setUp(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    storage = MemoryReviewPreferences();
    navigation = ReviewNavigationObserver();
    available = ValueNotifier(true);
    tab = ValueNotifier(0);
    navigatorKey = GlobalKey<NavigatorState>();
    capture = GlobalKey();
    now = DateTime(2026, 10, 3, 12);
    links = [];
    launchResult = true;
  });

  // Construct the queue in the widget test's FakeAsync zone. Creating it in
  // setUp mixes real/fake microtask queues and can strand a future in the test.
  void prepareService() {
    service = PlayReviewService(
        preferences: storage,
        now: () => now,
        launch: (uri) async {
          links.add(uri);
          return launchResult;
        });
    service.finishStartup();
  }

  tearDown(() {
    service.dispose();
    navigation.revision.dispose();
    available.dispose();
    tab.dispose();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  Future<void> eligible() async {
    for (final day in [1, 2, 3]) {
      now = DateTime(2026, 10, day, 12);
      await service.recordUsageDay();
    }
  }

  Widget app({double scale = 1, bool dark = false}) => RepaintBoundary(
      key: capture,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [navigation],
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: ValueListenableBuilder<int>(
          valueListenable: tab,
          builder: (context, index, _) => PlayReviewPromptHost(
            tabIndex: index,
            service: service,
            canPresent: () => available.value,
            environmentChanges: available,
            navigationObserver: navigation,
            child: Scaffold(
                bottomNavigationBar: BottomNavigationBar(
                  type: BottomNavigationBarType.fixed,
                  currentIndex: index,
                  onTap: (value) => tab.value = value,
                  items: const [
                    BottomNavigationBarItem(
                        icon: Icon(Icons.home), label: 'Inicio'),
                    BottomNavigationBarItem(
                        icon: Icon(Icons.edit), label: 'Inventario'),
                    BottomNavigationBarItem(
                        icon: Icon(Icons.auto_stories), label: 'Reflexión'),
                    BottomNavigationBarItem(
                        icon: Icon(Icons.lightbulb_outline), label: 'Recursos'),
                    BottomNavigationBarItem(
                        icon: Icon(Icons.person), label: 'Perfil'),
                  ],
                ),
                body: ListView(children: [
                  TextButton(
                      onPressed: () {}, child: const Text('Interacción')),
                  const TextField(
                      key: ValueKey('test-review-search'),
                      decoration:
                          InputDecoration(labelText: 'Buscar en Recursos')),
                  ProfileReviewTile(
                      foreground: dark ? Colors.white : Colors.black,
                      service: service,
                      canLaunch: () => available.value),
                ])),
          ),
        ),
      ));

  Future<void> changeTab(WidgetTester tester, int index) async {
    tab.value = index;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();
  }

  testWidgets('no startup prompt; deliberate neutral tab change invites once',
      (tester) async {
    prepareService();
    await eligible();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Tu opinión nos ayuda'), findsNothing);
    await changeTab(tester, 3);
    expect(find.text('Tu opinión nos ayuda'), findsOneWidget);
    expect(find.textContaining('Gracias por dedicarnos'), findsOneWidget);
    await tester.tap(find.text('Ahora no'));
    await tester.pumpAndSettle();
    await changeTab(tester, 4);
    await changeTab(tester, 0);
    expect(find.text('Tu opinión nos ayuda'), findsNothing);
    expect(links, isEmpty);
  });

  testWidgets(
      'journal/reflection are protected and preference tile stays voluntary',
      (tester) async {
    prepareService();
    await eligible();
    await tester.pumpWidget(app());
    await changeTab(tester, 1);
    await changeTab(tester, 2);
    expect(find.text('Tu opinión nos ayuda'), findsNothing);
    await tester.tap(find.text('Valorar en Google Play'));
    await tester.pumpAndSettle();
    expect(links, [PlayReviewService.marketUri]);
    await changeTab(tester, 4);
    expect(find.text('Tu opinión nos ayuda'), findsNothing);
  });

  testWidgets('pending invitation is cancelled by a later tab or another route',
      (tester) async {
    prepareService();
    await eligible();
    await tester.pumpWidget(app());
    tab.value = 3;
    await tester.pump();
    tab.value = 1;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Tu opinión nos ayuda'), findsNothing);
    tab.value = 4;
    await tester.pump();
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Ayuda SOS'))));
    await tester.pumpAndSettle();
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Tu opinión nos ayuda'), findsNothing);
  });

  testWidgets('background cancels pending request and resume does not prompt',
      (tester) async {
    prepareService();
    await eligible();
    await tester.pumpWidget(app());
    tab.value = 3;
    await tester.pump();
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused
    ]) {
      binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump(const Duration(seconds: 1));
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed
    ]) {
      binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(find.text('Tu opinión nos ayuda'), findsNothing);
    await changeTab(tester, 4);
    expect(find.text('Tu opinión nos ayuda'), findsOneWidget);
  });

  testWidgets(
      'lock/auth/consent/write blocker prevents and removes our modal safely',
      (tester) async {
    prepareService();
    await eligible();
    available.value = false;
    await tester.pumpWidget(app());
    await changeTab(tester, 4);
    expect(find.text('Tu opinión nos ayuda'), findsNothing);
    available.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Tu opinión nos ayuda'), findsNothing);
    await changeTab(tester, 3);
    expect(find.text('Tu opinión nos ayuda'), findsOneWidget);
    available.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Tu opinión nos ayuda'), findsNothing);
    expect(find.text('Interacción'), findsOneWidget);
  });

  testWidgets('a new route removes only invitation, never the new route',
      (tester) async {
    prepareService();
    await eligible();
    await tester.pumpWidget(app());
    await changeTab(tester, 3);
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Otra pantalla'))));
    await tester.pumpAndSettle();
    expect(find.text('Otra pantalla'), findsOneWidget);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Tu opinión nos ayuda'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('startup consent preparation cannot count or invite',
      (tester) async {
    prepareService();
    service.dispose();
    service = PlayReviewService(preferences: storage);
    await tester.pumpWidget(app());
    await tester.tap(find.text('Interacción'));
    await tester.pumpAndSettle();
    expect(storage.value, isNull);
    service.finishStartup();
    await tester.tap(find.text('Interacción'));
    await tester.pumpAndSettle();
    expect(storage.value, isNotNull);
  });

  testWidgets('keyboard avoids prompting while typing', (tester) async {
    prepareService();
    await eligible();
    await tester.pumpWidget(app());
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await changeTab(tester, 3);
    expect(find.text('Tu opinión nos ayuda'), findsNothing);
  });

  testWidgets('semantic tab activation counts usage without a pointer',
      (tester) async {
    prepareService();
    await tester.runAsync(() async {});
    await tester.pumpWidget(app());
    for (final day in [1, 2, 3]) {
      now = DateTime(2026, 10, day, 12);
      await changeTab(tester, day.isOdd ? 3 : 4);
    }
    expect(find.text('Tu opinión nos ayuda'), findsOneWidget);
  });

  testWidgets('actual navigation-bar taps invite on the third used date',
      (tester) async {
    prepareService();
    await tester.runAsync(() async {});
    await tester.pumpWidget(app());
    for (final day in [1, 2, 3]) {
      now = DateTime(2026, 10, day, 12);
      await tester.tap(find.text(day == 1
          ? 'Recursos'
          : day == 2
              ? 'Perfil'
              : 'Inicio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();
      expect(find.text('Tu opinión nos ayuda'),
          day < 3 ? findsNothing : findsOneWidget);
    }
    await tester.tap(find.text('Ahora no'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recursos'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Tu opinión nos ayuda'), findsNothing);
  });

  testWidgets('invitation button opens listing and closes only itself',
      (tester) async {
    prepareService();
    await eligible();
    await tester.pumpWidget(app());
    await changeTab(tester, 3);
    await tester
        .tap(find.widgetWithText(FilledButton, 'Valorar en Google Play'));
    await tester.pumpAndSettle();
    expect(links, [PlayReviewService.marketUri]);
    expect(find.text('Tu opinión nos ayuda'), findsNothing);
    expect(find.text('Interacción'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invitation failure stays readable and dismissible',
      (tester) async {
    prepareService();
    launchResult = false;
    await eligible();
    await tester.pumpWidget(app());
    await changeTab(tester, 3);
    await tester
        .tap(find.widgetWithText(FilledButton, 'Valorar en Google Play'));
    await tester.pumpAndSettle();
    expect(links, [PlayReviewService.marketUri, PlayReviewService.webUri]);
    expect(find.textContaining('Puedes volver a intentarlo'), findsOneWidget);
    await tester.tap(find.text('Ahora no'));
    await tester.pumpAndSettle();
    expect(find.text('Tu opinión nos ayuda'), findsNothing);
  });

  testWidgets('new task after navigation cancels delayed invitation',
      (tester) async {
    prepareService();
    await eligible();
    await tester.pumpWidget(app());
    tab.value = 3;
    await tester.pump();
    await tester.tap(find.text('Interacción'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Tu opinión nos ayuda'), findsNothing);
  });

  testWidgets('editable focus with no software keyboard suppresses invitation',
      (tester) async {
    prepareService();
    await eligible();
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const ValueKey('test-review-search')));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding();
    addTearDown(tester.view.resetViewInsets);
    await changeTab(tester, 3);
    expect(find.text('Tu opinión nos ayuda'), findsNothing);
  });

  testWidgets('manual failed launch shows plain error, remains retryable',
      (tester) async {
    prepareService();
    service.dispose();
    service = PlayReviewService(
        preferences: storage,
        launch: (_) async => throw StateError('secret native detail'));
    service.finishStartup();
    await tester.pumpWidget(app());
    await tester.tap(find.text('Valorar en Google Play'));
    await tester.pumpAndSettle();
    expect(find.text('No se pudo abrir Google Play. Vuelve a intentarlo.'),
        findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('profile-play-review')))
            .onTap,
        isNotNull);
  });

  testWidgets('manual navigation during platform await prevents fallback',
      (tester) async {
    prepareService();
    final pending = Completer<bool>();
    service.dispose();
    service = PlayReviewService(
        preferences: storage,
        launch: (uri) {
          links.add(uri);
          return pending.future;
        });
    await tester.pumpWidget(app());
    await tester.tap(find.text('Valorar en Google Play'));
    await tester.pump();
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Nueva pantalla'))));
    await tester.pumpAndSettle();
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(links, [PlayReviewService.marketUri]);
    expect(find.text('Nueva pantalla'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in [
    (name: 'light', dark: false, width: 400.0, scale: 1.0),
    (name: 'dark', dark: true, width: 400.0, scale: 1.0),
    (name: 'large-text', dark: false, width: 320.0, scale: 2.0),
  ]) {
    testWidgets('invitation and Profile fit ${scenario.name}', (tester) async {
      prepareService();
      tester.view.physicalSize = Size(scenario.width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await eligible();
      await tester.pumpWidget(app(scale: scenario.scale, dark: scenario.dark));
      await changeTab(tester, 3);
      expect(find.text('Tu opinión nos ayuda'), findsOneWidget);
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final raster = await boundary.toImage(pixelRatio: 1);
        final bytes = await raster.toByteData(format: ui.ImageByteFormat.png);
        raster.dispose();
        final output = Directory('build/validation');
        await output.create(recursive: true);
        await File('${output.path}/review-prompt-${scenario.name}-v29.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      });
      await tester.ensureVisible(find.text('Ahora no'));
      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
