import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:un_dia_mas/screens/reflection_screen.dart';
import 'package:un_dia_mas/services/notification_plan.dart';
import 'package:un_dia_mas/theme/app_theme.dart';

const _assetPath = 'assets/data/reflections.json';
const _months = [
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];

List<String> _readCatalog() =>
    (jsonDecode(File(_assetPath).readAsStringSync()) as List).cast<String>();

// RichText inspects what Markdown actually renders, including quoted titles.
Finder _renderedText(String text) => find.byWidgetPredicate(
      (widget) => widget is RichText && widget.text.toPlainText() == text,
      description: 'rendered text "$text"',
    );

void _expectInsideViewport(WidgetTester tester, Finder text) {
  final viewport = tester.getRect(find.byType(SingleChildScrollView));
  final bounds = tester.getRect(text);
  expect(bounds.left, greaterThanOrEqualTo(viewport.left - 0.5));
  expect(bounds.right, lessThanOrEqualTo(viewport.right + 0.5));
  expect(bounds.top, greaterThanOrEqualTo(viewport.top - 0.5));
  expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
}

Future<void> _expectReadableByScrolling(
    WidgetTester tester, Finder text) async {
  await tester.ensureVisible(text);
  await tester.pumpAndSettle();
  final viewport = tester.getRect(find.byType(SingleChildScrollView));
  final start = tester.getRect(text);
  expect(start.left, greaterThanOrEqualTo(viewport.left - 0.5));
  expect(start.right, lessThanOrEqualTo(viewport.right + 0.5));
  expect(start.top, greaterThanOrEqualTo(viewport.top - 0.5));
  expect(start.top, lessThan(viewport.bottom));
  if (start.height <= viewport.height) {
    _expectInsideViewport(tester, text);
  }

  // A large-font paragraph may need more than one screen. Its beginning and
  // end must both be reachable; it need not fit the viewport all at once.
  await Scrollable.ensureVisible(tester.element(text), alignment: 1);
  await tester.pumpAndSettle();
  final end = tester.getRect(text);
  expect(end.bottom, greaterThan(viewport.top));
  expect(end.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(rootBundle.clear);
  tearDown(rootBundle.clear);

  test('real asset has 365 complete reflections in calendar order', () {
    final catalog = _readCatalog();
    expect(catalog, hasLength(365));

    for (var index = 0; index < catalog.length; index++) {
      final date = DateTime.utc(2027, 1, 1).add(Duration(days: index));
      final lines = const LineSplitter().convert(catalog[index]);
      expect(
        lines.first,
        '### Día ${index + 1} – ${date.day} ${_months[date.month - 1]}',
        reason: 'The array position must retain its actual calendar date.',
      );
      expect(lines.where((line) => line.startsWith('> ')), hasLength(1));
      expect(lines.where((line) => line.startsWith('Pregunta para hoy: ')),
          hasLength(1));
      expect(lines.last.trim(), matches(RegExp(r'^Pregunta para hoy: ¿.+\?$')));
      final paragraphs = catalog[index].trim().split(RegExp(r'\r?\n\s*\r?\n'));
      expect(paragraphs.length, greaterThanOrEqualTo(4),
          reason: 'The date, title, reflection and question must all exist.');
    }
  });

  test('every ordinary and leap-year date selects the matching real text', () {
    final catalog = _readCatalog();
    final textByDate = <String, String>{};
    for (var index = 0; index < 365; index++) {
      final date = DateTime.utc(2027, 1, 1).add(Duration(days: index));
      textByDate['${date.month}/${date.day}'] = catalog[index];
    }

    for (final year in [2027, 2028]) {
      for (var date = DateTime.utc(year, 1, 1);
          date.year == year;
          date = date.add(const Duration(days: 1))) {
        final calendarKey = date.month == 2 && date.day == 29
            ? '2/28'
            : '${date.month}/${date.day}';
        final index = reflectionIndexForDate(date);
        expect(index, inInclusiveRange(0, 364));
        expect(catalog[index], textByDate[calendarKey],
            reason: 'Wrong reflection for ${date.toIso8601String()}.');
      }
    }
  });

  // Two approved calendar entries and the longest entry by characters.
  for (final index in [115, 175, 305]) {
    for (final variant in [
      (scale: 1.0, dark: false),
      (scale: 2.0, dark: false),
      (scale: 2.0, dark: true),
    ]) {
      testWidgets(
          'real day ${index + 1} is readable at 320x640, '
          '${variant.scale}x, ${variant.dark ? 'dark' : 'light'}',
          (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Flutter decodes large assets in a real isolate. Let that work finish
        // outside the fake widget clock, retaining the real bundle's cache.
        final bundled =
            await tester.runAsync(() => rootBundle.loadString(_assetPath));
        expect(bundled, File(_assetPath).readAsStringSync(),
            reason: 'The bundled collection must match the source asset.');
        final lines = const LineSplitter().convert(_readCatalog()[index]);
        final header = lines.first.replaceFirst('### ', '').trim();
        final title = lines
            .singleWhere((line) => line.startsWith('> '))
            .substring(2)
            .trim();
        final question = lines.last.trim();

        try {
          // ReflectionScreen loads the real bundled asset; no channel or
          // AssetBundle mock can conceal packaging or Markdown failures.
          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: variant.dark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(variant.scale)),
              child: child!,
            ),
            home: ReflectionScreen(dayIndex: index),
          ));
          // Deliver listeners of the real Future cached above before asking
          // the fake clock to settle the screen's loading animation.
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.text('No se pudo cargar la reflexión solicitada.'),
              findsNothing);

          final headerText = _renderedText(header);
          expect(headerText, findsOneWidget);
          _expectInsideViewport(tester, headerText);

          for (final text in [title, question]) {
            final rendered = _renderedText(text);
            expect(rendered, findsOneWidget);
            await _expectReadableByScrolling(tester, rendered);
          }
          final scrollable = tester.state<ScrollableState>(
            find.descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Scrollable),
            ),
          );
          expect(scrollable.position.pixels, greaterThan(0),
              reason: 'The final question must be reachable by scrolling.');
        } finally {
          // Explicit indices do not start midnight timers; unmounting also
          // removes ReflectionScreen's lifecycle observer after any failure.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      });
    }
  }
}
