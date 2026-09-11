import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:un_dia_mas/models/diary_entry.dart';
import 'package:un_dia_mas/widgets/mood_trend_chart.dart';

final _today = DateTime(2026, 9, 10, 23, 50);
DiaryEntry _entry(int day, int mood, String text,
        {int month = 9, int hour = 12}) =>
    DiaryEntry(
        createdAt: DateTime(2026, month, day, hour), mood: mood, text: text);

Widget _app(List<DiaryEntry> entries,
        {double scale = 1,
        bool dark = false,
        Listenable? invalidation,
        bool available = true,
        DateTime Function()? now,
        GlobalKey<NavigatorState>? navigatorKey}) =>
    MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData(
            useMaterial3: true,
            brightness: dark ? Brightness.dark : Brightness.light),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Scaffold(
            body: SingleChildScrollView(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: MoodTrendChart(
                        entries: entries,
                        now: now ?? () => _today,
                        invalidationSignal: invalidation,
                        entriesAvailable: available)))));

List<FlSpot> _spots(WidgetTester tester) => tester
    .widget<LineChart>(find.byType(LineChart))
    .data
    .lineBarsData
    .expand((bar) => bar.spots)
    .toList();

Future<void> _list(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('mood-view-entries')));
  await tester.tap(find.byKey(const ValueKey('mood-view-entries')));
  await tester.pumpAndSettle();
}

Future<void> _read(WidgetTester tester, int index) async {
  await tester.tap(find.byKey(ValueKey('mood-entry-$index')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'defaults to 30 days, filters 7/all, preserves gaps and all points',
      (tester) async {
    final entries = [
      _entry(1, 0, 'Antigua', month: 1),
      _entry(20, 1, 'Mes', month: 8),
      _entry(9, 2, 'Semana'),
      _entry(10, 4, 'Hoy')
    ];
    await tester.pumpWidget(_app(entries));
    expect(_spots(tester).length, 3);
    final monthChart = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(monthChart.lineBarsData.length, 2);
    expect(
        monthChart.lineBarsData
            .every((bar) => !bar.isCurved && !bar.belowBarData.show),
        isTrue);
    await tester.tap(find.text('7 días'));
    await tester.pumpAndSettle();
    expect(_spots(tester).length, 2);
    await tester.tap(find.text('Todo'));
    await tester.pumpAndSettle();
    expect(_spots(tester).length, 4);
    expect(entries.first.text, 'Antigua');
  });

  testWidgets(
      'tapAt a real plotted point near last-day corner opens its exact text',
      (tester) async {
    final entries = [
      _entry(10, 1, 'Mañana', hour: 8),
      _entry(10, 4, 'Última del día', hour: 23)
    ];
    await tester.pumpWidget(_app(entries));
    await tester.pumpAndSettle();
    final chart = tester.widget<LineChart>(find.byType(LineChart)).data;
    final rect = tester.getRect(find.byType(LineChart));
    final point = _spots(tester).last;
    final left = chart.titlesData.leftTitles.sideTitles.reservedSize;
    final coordinate = Offset(
        rect.left + left + (rect.width - left) * point.x / chart.maxX,
        rect.bottom -
            rect.height * (point.y - chart.minY) / (chart.maxY - chart.minY));
    await tester.tapAt(coordinate);
    await tester.pumpAndSettle();
    expect(find.text('Última del día'), findsOneWidget);
    expect(find.text('10 sept 2026 · 23:00'), findsOneWidget);
    expect(find.byKey(const ValueKey('mood-select-0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mood-select-0')));
    await tester.pumpAndSettle();
    expect(find.text('Mañana'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'same timestamp and mood remain separately selectable with exact untrimmed text',
      (tester) async {
    final entries = [
      _entry(10, 2, '  Primera\nLínea dos  '),
      _entry(10, 2, 'Segunda')
    ];
    await tester.pumpWidget(_app(entries));
    expect(_spots(tester)[0], _spots(tester)[1]);
    await _list(tester);
    await _read(tester, 1);
    expect(find.text('Segunda'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mood-select-0')));
    await tester.pumpAndSettle();
    final body = tester
        .widget<SelectableText>(find.byKey(const ValueKey('mood-entry-text')));
    expect(body.data, entries[0].text);
  });

  testWidgets(
      'all entries can be selected in a long same-day list without averaging',
      (tester) async {
    final entries = List.generate(30, (i) => _entry(10, i % 5, 'Texto $i'));
    await tester.pumpWidget(_app(entries));
    expect(_spots(tester).length, 30);
    await _list(tester);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('mood-entry-29')), 300,
        scrollable: find.descendant(
            of: find.byKey(const ValueKey('mood-entry-list')),
            matching: find.byType(Scrollable)));
    await _read(tester, 29);
    expect(find.text('Texto 29'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('Elegir otra entrada (30)'), findsOneWidget);
  });

  testWidgets('data replacement closes detail even with equal date and mood',
      (tester) async {
    await tester.pumpWidget(_app([_entry(10, 2, 'Antes')]));
    await _list(tester);
    await _read(tester, 0);
    await tester.pumpWidget(_app([_entry(10, 2, 'Después')]));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mood-entry-sheet')), findsNothing);
    expect(find.text('Antes'), findsNothing);
    await _list(tester);
    await _read(tester, 0);
    expect(find.text('Después'), findsOneWidget);
  });

  testWidgets('invalidation removes its own sheet and keeps a dialog above it',
      (tester) async {
    final signal = ChangeNotifier();
    final navigator = GlobalKey<NavigatorState>();
    addTearDown(signal.dispose);
    await tester.pumpWidget(_app([_entry(10, 2, 'Viejo')],
        invalidation: signal, navigatorKey: navigator));
    await _list(tester);
    await _read(tester, 0);
    showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) =>
            const AlertDialog(title: Text('Restauración en curso')));
    await tester.pumpAndSettle();
    signal.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Restauración en curso'), findsOneWidget);
    expect(find.text('Viejo', skipOffstage: false), findsNothing);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mood-entry-sheet')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing chart with detail open safely removes the sheet',
      (tester) async {
    final data = ValueNotifier(true);
    addTearDown(data.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ValueListenableBuilder<bool>(
                valueListenable: data,
                builder: (_, enabled, __) => SingleChildScrollView(
                    child: enabled
                        ? MoodTrendChart(
                            entries: [_entry(10, 2, 'Texto privado')],
                            now: () => _today)
                        : const Text('Otra pantalla'))))));
    await _list(tester);
    await _read(tester, 0);
    data.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Otra pantalla'), findsOneWidget);
    expect(find.byKey(const ValueKey('mood-entry-sheet')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'invalid mood remains readable without invented chart value or bridge',
      (tester) async {
    await tester.pumpWidget(_app([
      _entry(8, 1, 'Antes'),
      _entry(9, 8, 'Ánimo importado'),
      _entry(10, 3, 'Después')
    ]));
    final chart = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(chart.lineBarsData.length, 2);
    expect(_spots(tester).map((p) => p.y), [1, 3]);
    await _list(tester);
    await _read(tester, 1);
    expect(find.text('Ánimo importado'), findsOneWidget);
    expect(find.text('Ánimo no disponible'), findsOneWidget);
  });

  testWidgets('resuming refreshes the period when the local day changes',
      (tester) async {
    var now = _today;
    await tester.pumpWidget(
        _app([_entry(12, 2, 'Último día incluido', month: 8)], now: () => now));
    expect(_spots(tester).length, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = DateTime(2026, 9, 11, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('No hay entradas en estos 30 días.'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets(
        '320px and 200% text keeps filters and long detail usable ${dark ? 'dark' : 'light'}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(
          [_entry(10, 3, List.filled(20, 'Texto largo de prueba.').join(' '))],
          scale: 2, dark: dark));
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNWidgets(3));
      await tester.tap(find.text('7 días'));
      await tester.pumpAndSettle();
      await _list(tester);
      await _read(tester, 0);
      expect(find.byKey(const ValueKey('mood-entry-text')), findsOneWidget);
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unavailable inventory cannot expose chart or open entries',
      (tester) async {
    await tester.pumpWidget(_app([_entry(10, 3, 'Privado')], available: false));
    expect(find.byType(LineChart), findsNothing);
    expect(find.text('Ver entradas'), findsNothing);
    expect(find.text('Privado'), findsNothing);
  });
}
