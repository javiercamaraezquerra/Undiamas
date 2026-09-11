import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:un_dia_mas/services/notification_plan.dart';

void main() {
  tzdata.initializeTimeZones();
  final madrid = tz.getLocation('Europe/Madrid');
  final catalog =
      jsonEncode(List.generate(365, (i) => '### Título $i\nTexto $i'));

  test('today before nine, tomorrow exactly at or after nine', () {
    for (final hour in [8, 9, 10]) {
      final now = tz.TZDateTime(madrid, 2026, 9, 10, hour);
      final plan = NotificationPlan.dailyReflections(catalog, now: now);
      expect(plan, hasLength(60));
      expect(plan.first.scheduledAt.day, hour < 9 ? 10 : 11);
      expect(plan.every((item) => item.scheduledAt.isAfter(now)), isTrue);
      expect(plan.every((item) => item.scheduledAt.hour == 9), isTrue);
      expect(plan.map((item) => item.id).toSet(), hasLength(60));
      expect(plan.first.id, 10000);
      expect(plan.last.id, 10059);
    }
  });

  for (final fixture in [
    (month: 3, day: 28, hours: 23),
    (month: 10, day: 24, hours: 25),
  ]) {
    test('Madrid DST month ${fixture.month} preserves nine for all sixty dates',
        () {
      final now = tz.TZDateTime(madrid, 2026, fixture.month, fixture.day, 8);
      final plan = NotificationPlan.dailyReflections(catalog, now: now);
      expect(plan[1].scheduledAt.difference(plan[0].scheduledAt).inHours,
          fixture.hours);
      final calendarDates = <String>{};
      for (final item in plan) {
        final date = item.scheduledAt;
        expect(date.hour, 9);
        expect(date.minute, 0);
        calendarDates.add('${date.year}-${date.month}-${date.day}');
        expect(item.payload, '${reflectionIndexForDate(date)}');
        expect(item.body, 'Título ${item.payload}');
      }
      expect(calendarDates, hasLength(60));
    });
  }

  test('passing nine before the DST jump starts tomorrow at nine, not ten', () {
    final plan = NotificationPlan.dailyReflections(catalog,
        now: tz.TZDateTime(madrid, 2026, 3, 28, 10), daysAhead: 2);
    expect(plan.first.scheduledAt, tz.TZDateTime(madrid, 2026, 3, 29, 9));
    expect(plan.last.scheduledAt, tz.TZDateTime(madrid, 2026, 3, 30, 9));
  });

  test('calendar construction also holds across southern hemisphere DST', () {
    final sydney = tz.getLocation('Australia/Sydney');
    final plan = NotificationPlan.dailyReflections(catalog,
        now: tz.TZDateTime(sydney, 2026, 4, 3, 10));
    expect(plan.every((item) => item.scheduledAt.hour == 9), isTrue);
    expect(plan.every((item) => item.scheduledAt.location == sydney), isTrue);
  });

  test('leap February shares the 28th and March text retains its calendar date',
      () {
    final plan = NotificationPlan.dailyReflections(catalog,
        now: tz.TZDateTime(madrid, 2028, 2, 28, 8), daysAhead: 4);
    expect(plan.map((item) => item.payload).toList(), ['58', '58', '59', '60']);
    expect(plan.map((item) => item.body).toList(),
        ['Título 58', 'Título 58', 'Título 59', 'Título 60']);
    expect(reflectionIndexForDate(DateTime(2027, 3, 1)), 59);
    expect(reflectionIndexForDate(DateTime(2028, 3, 1)), 59);
  });

  test(
      'December 31 leap year and January 1 use matching notification title and payload',
      () {
    final plan = NotificationPlan.dailyReflections(catalog,
        now: tz.TZDateTime(madrid, 2028, 12, 31, 8), daysAhead: 2);
    expect(plan.first.payload, '364');
    expect(plan.first.body, 'Título 364');
    expect(plan.last.payload, '0');
    expect(plan.last.body, 'Título 0');
    expect(plan.last.scheduledAt, tz.TZDateTime(madrid, 2029, 1, 1, 9));
  });

  test('real 365-asset keeps its exact headings at February/March and year end',
      () {
    final raw = File('assets/data/reflections.json').readAsStringSync();
    final parsed = jsonDecode(raw) as List;
    expect(parsed, hasLength(365));
    for (final date in [
      tz.TZDateTime(madrid, 2028, 2, 29, 8),
      tz.TZDateTime(madrid, 2028, 3, 1, 8),
      tz.TZDateTime(madrid, 2028, 12, 31, 8),
    ]) {
      final item =
          NotificationPlan.dailyReflections(raw, now: date, daysAhead: 1)
              .single;
      final index = reflectionIndexForDate(date);
      final header = (parsed[index] as String)
          .split('\n')
          .first
          .replaceFirst('### ', '')
          .trim();
      expect(item.body, header);
      expect(item.payload, '$index');
    }
  });

  test('malformed catalog is rejected entirely, including its last entry', () {
    for (final raw in [
      'not JSON',
      '{}',
      '[]',
      jsonEncode(List.generate(364, (i) => '### Título $i')),
      jsonEncode([...List.generate(364, (i) => '### Título $i'), null]),
      jsonEncode([
        ...List.generate(364, (i) => '### Título $i'),
        {'title': 4}
      ]),
      jsonEncode([...List.generate(364, (i) => '### Título $i'), '   ']),
    ]) {
      expect(
          () => NotificationPlan.dailyReflections(raw,
              now: tz.TZDateTime(madrid, 2026, 9, 10)),
          throwsFormatException);
    }
  });

  test('duration range cannot schedule outside reserved daily IDs', () {
    final now = tz.TZDateTime(madrid, 2026, 9, 10);
    expect(NotificationPlan.dailyReflections(catalog, now: now, daysAhead: 0),
        isEmpty);
    expect(
        NotificationPlan.dailyReflections(catalog,
                now: now, daysAhead: NotificationPlan.reflectionMaxDays)
            .last
            .id,
        10999);
    for (final days in [-1, 1001]) {
      expect(
          () => NotificationPlan.dailyReflections(catalog,
              now: now, daysAhead: days),
          throwsArgumentError);
    }
  });

  test('milestones keep elapsed 24-hour days through DST and stable legacy IDs',
      () {
    final start = tz.TZDateTime(madrid, 2026, 3, 28, 9);
    final plan = NotificationPlan.milestones(start,
        now: tz.TZDateTime(madrid, 2026, 3, 28, 10),
        milestones: {1: 'Día 1', 3: 'Día 3', 3650: 'Diez años'});
    expect(plan.map((item) => item.id).toList(), [1, 3, 3650]);
    expect(plan.first.scheduledAt.difference(start), const Duration(days: 1));
    expect(plan.first.scheduledAt.hour, 10,
        reason:
            'The existing sobriety counter counts elapsed days, not calendar anniversaries.');
    expect(plan.every((item) => item.payload == null), isTrue);
    expect(plan.every((item) => item.id < NotificationPlan.reflectionBaseId),
        isTrue);
  });

  test('past milestones and an exact-now milestone are excluded', () {
    final start = tz.TZDateTime(madrid, 2026, 9, 1, 12);
    final plan = NotificationPlan.milestones(start,
        now: tz.TZDateTime(madrid, 2026, 9, 4, 12),
        milestones: {1: 'Día1', 3: 'Día3', 7: 'Día7'});
    expect(plan.map((item) => item.id).toList(), [7]);
    expect(plan.single.body, 'Día7');
  });
}
