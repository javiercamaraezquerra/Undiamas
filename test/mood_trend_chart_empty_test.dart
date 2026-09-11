import 'dart:ui' show PointerDeviceKind;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:un_dia_mas/models/diary_entry.dart';
import 'package:un_dia_mas/widgets/mood_trend_chart.dart';

void main() {
  const emptyMessage = 'Todavía no hay entradas para mostrar tu ánimo.';
  Widget app(List<DiaryEntry> entries) => MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(
              child: MoodTrendChart(
                  entries: entries, now: () => DateTime(2026, 9, 10, 23)))));

  testWidgets('empty inventory shows a message without an invented chart point',
      (tester) async {
    await tester.pumpWidget(app([]));
    expect(find.text(emptyMessage), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
    expect(find.text('Ver entradas'), findsNothing);
  });

  testWidgets(
      'removing entries preserves last real dated point then shows empty',
      (tester) async {
    final earlier =
        DiaryEntry(createdAt: DateTime(2026, 8, 12), mood: 1, text: 'Primera');
    final remaining = DiaryEntry(
        createdAt: DateTime(2026, 9, 10, 12), mood: 4, text: 'Última');
    await tester.pumpWidget(app([earlier, remaining]));
    await tester.pumpWidget(app([remaining]));
    await tester.pumpAndSettle();
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final point = chart.data.lineBarsData.single.spots.single;
    expect(point.y, 4);
    expect(point.x, greaterThan(29));
    expect(point.x, lessThan(30));
    await tester.pumpWidget(app([]));
    await tester.pumpAndSettle();
    expect(find.text(emptyMessage), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stale chart callback cannot open a removed entry',
      (tester) async {
    final entry = DiaryEntry(
        createdAt: DateTime(2026, 9, 10), mood: 2, text: 'Eliminada');
    await tester.pumpWidget(app([entry]));
    final old = tester.widget<LineChart>(find.byType(LineChart)).data;
    final oldBar = old.lineBarsData.single;
    await tester.pumpWidget(app([]));
    old.lineTouchData.touchCallback!(
        FlTapUpEvent(TapUpDetails(kind: PointerDeviceKind.touch)),
        LineTouchResponse(
            [TouchLineBarSpot(oldBar, 0, oldBar.spots.single, 0)]));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mood-entry-sheet')), findsNothing);
    expect(find.text('Eliminada'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
