import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:un_dia_mas/models/diary_entry.dart';
import 'package:un_dia_mas/utils/mood_timeline.dart';

DiaryEntry entry(DateTime date,
        {int mood = 2, String text = 'Texto original'}) =>
    DiaryEntry(createdAt: date, mood: mood, text: text);

// Real DateTime values are always valid. This models a conversion failure at
// an input boundary without manufacturing or modifying any persisted object.
class UnreadableDateTime implements DateTime {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unreadable date');
}

void main() {
  tzdata.initializeTimeZones();
  final utc = tz.UTC;
  final madrid = tz.getLocation('Europe/Madrid');
  tz.TZDateTime utcNow(int year, int month, int day, [int hour = 12]) =>
      tz.TZDateTime(utc, year, month, day, hour);

  test(
      'sorts a copy chronologically while preserving identity, text and source indices',
      () {
    final oldest = entry(DateTime.utc(2026, 9, 1, 9), text: '  Texto A\n');
    final middle =
        entry(DateTime.utc(2026, 9, 2, 15), mood: 4, text: 'Texto B');
    final newest = entry(DateTime.utc(2026, 9, 3, 8), mood: 0, text: 'Texto C');
    final source = [newest, oldest, middle];
    final timeline = MoodTimeline.build(source,
        period: MoodPeriod.all, now: utcNow(2026, 9, 10));
    expect(timeline.points.map((point) => point.entry).toList(),
        [oldest, middle, newest]);
    expect(
        timeline.points.map((point) => point.sourceIndex).toList(), [1, 2, 0]);
    expect(source, [newest, oldest, middle]);
    expect(identical(timeline.points.first.entry, oldest), isTrue);
    expect(oldest.text, '  Texto A\n');
    expect(oldest.createdAt, DateTime.utc(2026, 9, 1, 9));
    expect(oldest.mood, 2);
    expect(timeline.maxX, 3);
  });

  test(
      'equal timestamps and even repeated object references remain distinct points in stable order',
      () {
    final a = entry(DateTime.utc(2026, 9, 10, 12), text: 'Igual');
    final b = entry(DateTime.utc(2026, 9, 10, 12), text: 'Igual');
    final timeline = MoodTimeline.build([a, b, a],
        period: MoodPeriod.all, now: utcNow(2026, 9, 10));
    expect(timeline.points, hasLength(3));
    expect(
        timeline.points.map((point) => point.sourceIndex).toList(), [0, 1, 2]);
    expect(timeline.points.map((point) => point.x).toSet(), {0.5});
    expect(identical(timeline.points[0].entry, a), isTrue);
    expect(identical(timeline.points[1].entry, b), isTrue);
    expect(identical(timeline.points[2].entry, a), isTrue);
    expect(timeline.segments.single, hasLength(3));
  });

  test(
      'week includes its seven calendar dates including all of today, but not tomorrow',
      () {
    final source = [
      entry(DateTime.utc(2025, 12, 31, 23, 59)),
      entry(DateTime.utc(2026, 1, 1)),
      entry(DateTime.utc(2026, 1, 7, 23, 59, 59)),
      entry(DateTime.utc(2026, 1, 8)),
    ];
    final timeline = MoodTimeline.build(source,
        period: MoodPeriod.week, now: utcNow(2026, 1, 7, 8));
    expect(timeline.startDay, DateTime.utc(2026, 1, 1));
    expect(timeline.endDay, DateTime.utc(2026, 1, 7));
    expect(timeline.maxX, 7);
    expect(timeline.points.map((point) => point.entry).toList(),
        [source[1], source[2]]);
    expect(timeline.points.first.x, 0);
    expect(timeline.points.last.x, lessThan(7));
    expect(timeline.points.last.x, greaterThan(6.99));
  });

  test('month is thirty calendar dates, not this named month', () {
    final source = [
      entry(DateTime.utc(2026, 1, 1, 23, 59)),
      entry(DateTime.utc(2026, 1, 2)),
      entry(DateTime.utc(2026, 1, 31))
    ];
    final timeline = MoodTimeline.build(source,
        period: MoodPeriod.month, now: utcNow(2026, 1, 31));
    expect(timeline.startDay, DateTime.utc(2026, 1, 2));
    expect(timeline.endDay, DateTime.utc(2026, 1, 31));
    expect(timeline.maxX, 30);
    expect(timeline.points.map((point) => point.entry).toList(),
        source.skip(1).toList());
  });

  test('thirty-day boundary includes leap February without offset errors', () {
    final leap = MoodTimeline.build([],
        period: MoodPeriod.month, now: utcNow(2028, 3, 1));
    final ordinary = MoodTimeline.build([],
        period: MoodPeriod.month, now: utcNow(2027, 3, 1));
    expect(leap.startDay, DateTime.utc(2028, 2, 1));
    expect(ordinary.startDay, DateTime.utc(2027, 1, 31));
    expect(leap.maxX, 30);
    expect(ordinary.maxX, 30);
  });

  test('all includes future dates and spans only the stored dates', () {
    final past = entry(DateTime.utc(2025, 12, 31, 9));
    final future = entry(DateTime.utc(2026, 1, 14, 9));
    final all = MoodTimeline.build([future, past],
        period: MoodPeriod.all, now: utcNow(2026, 1, 7));
    final week = MoodTimeline.build([future, past],
        period: MoodPeriod.week, now: utcNow(2026, 1, 7));
    expect(all.points.map((point) => point.entry).toList(), [past, future]);
    expect(all.startDay, DateTime.utc(2025, 12, 31));
    expect(all.endDay, DateTime.utc(2026, 1, 14));
    expect(all.maxX, 15);
    expect(week.points, isEmpty);
  });

  test(
      'same-day points remain separate and are available together in day details',
      () {
    final source = [
      entry(DateTime.utc(2026, 9, 10, 8), mood: 0),
      entry(DateTime.utc(2026, 9, 10, 8, 30), mood: 4),
      entry(DateTime.utc(2026, 9, 11, 7), mood: 3)
    ];
    final timeline = MoodTimeline.build(source,
        period: MoodPeriod.all, now: utcNow(2026, 9, 11));
    final selectedDay = timeline.pointsOnDay(DateTime.utc(2026, 9, 10, 23));
    expect(selectedDay, hasLength(2));
    expect(selectedDay.map((point) => point.entry.mood).toList(), [0, 4]);
    expect(selectedDay.first.x, closeTo(8 / 24, 1e-12));
    expect(selectedDay.last.x - selectedDay.first.x, closeTo(0.5 / 24, 1e-12));
    expect(identical(selectedDay.first, timeline.points.first), isTrue);
    expect(timeline.pointsOnDay(DateTime.utc(2026, 9, 12)), isEmpty);
  });

  test('one missing calendar date cuts the segment with no invented point', () {
    final source = [
      entry(DateTime.utc(2026, 9, 1, 12)),
      entry(DateTime.utc(2026, 9, 2, 12)),
      entry(DateTime.utc(2026, 9, 4, 12)),
      entry(DateTime.utc(2026, 9, 7, 12))
    ];
    final timeline = MoodTimeline.build(source,
        period: MoodPeriod.all, now: utcNow(2026, 9, 10));
    expect(timeline.points, hasLength(4));
    expect(
        timeline.segments.map((segment) => segment.length).toList(), [2, 1, 1]);
    expect(
        timeline.points.map((point) => point.x).toList(), [0.5, 1.5, 3.5, 6.5]);
    expect(timeline.hasGaps, isTrue);
    expect(timeline.segments.expand((segment) => segment).toList(),
        timeline.points);
  });

  test('empty periods retain useful calendar bounds and no synthetic segment',
      () {
    for (final period in MoodPeriod.values) {
      final timeline =
          MoodTimeline.build([], period: period, now: utcNow(2026, 9, 10));
      expect(timeline.points, isEmpty);
      expect(timeline.segments, isEmpty);
      expect(timeline.hasGaps, isFalse);
      expect(timeline.skippedEntryCount, 0);
      expect(timeline.endDay, DateTime.utc(2026, 9, 10));
      expect(timeline.maxX,
          period == MoodPeriod.all ? 1 : (period == MoodPeriod.week ? 7 : 30));
    }
  });

  test(
      'one midnight entry has a non-degenerate axis without fake neighbouring data',
      () {
    final original = entry(DateTime.utc(2026, 9, 10));
    final timeline = MoodTimeline.build([original],
        period: MoodPeriod.all, now: utcNow(2026, 9, 10));
    expect(timeline.maxX, 1);
    expect(timeline.points.single.x, 0);
    expect(timeline.segments.single.single.entry, same(original));
    expect(timeline.hasGaps, isFalse);
  });

  test('a new current date changes filters without mutating the older snapshot',
      () {
    final original = entry(DateTime.utc(2026, 9, 4, 12));
    final first = MoodTimeline.build([original],
        period: MoodPeriod.week, now: utcNow(2026, 9, 10));
    final later = MoodTimeline.build([original],
        period: MoodPeriod.week, now: utcNow(2026, 9, 11));
    expect(first.points.single.entry, same(original));
    expect(later.points, isEmpty);
    expect(first.startDay, DateTime.utc(2026, 9, 4));
    expect(later.startDay, DateTime.utc(2026, 9, 5));
  });

  test('UTC timestamps are converted before local day filtering and details',
      () {
    final original = entry(DateTime.utc(2026, 9, 10, 22, 30));
    final timeline = MoodTimeline.build([original],
        period: MoodPeriod.week, now: tz.TZDateTime(madrid, 2026, 9, 11, 10));
    final point = timeline.points.single;
    expect(point.localDateTime.day, 11);
    expect(point.localDateTime.hour, 0);
    expect(point.localDateTime.minute, 30);
    expect(point.entry.createdAt, DateTime.utc(2026, 9, 10, 22, 30));
    expect(timeline.pointsOnDay(DateTime.utc(2026, 9, 10, 23)), [point]);
    expect(
        timeline.pointsOnDay(tz.TZDateTime(madrid, 2026, 9, 10, 12)), isEmpty);
  });

  test(
      'spring DST preserves calendar distances and a 23-hour day stays one day wide',
      () {
    final source = [
      entry(tz.TZDateTime(madrid, 2026, 3, 28, 12)),
      entry(tz.TZDateTime(madrid, 2026, 3, 29, 12)),
      entry(tz.TZDateTime(madrid, 2026, 3, 30, 12))
    ];
    final timeline = MoodTimeline.build(source,
        period: MoodPeriod.all, now: tz.TZDateTime(madrid, 2026, 3, 30, 13));
    expect(
        source.last.createdAt.difference(source.first.createdAt).inHours, 47);
    expect(timeline.maxX, 3);
    expect(timeline.points.first.x, 0.5);
    expect(timeline.points[1].x, closeTo(1 + 11 / 23, 1e-12));
    expect(timeline.points.last.x, 2.5);
    expect(timeline.segments, hasLength(1));
  });

  test(
      'repeated autumn clock hour keeps chronological order and distinct proportional X positions',
      () {
    final firstHalf =
        entry(DateTime.utc(2026, 10, 25, 0, 30), text: 'Primera 02:30');
    final secondHalf =
        entry(DateTime.utc(2026, 10, 25, 1, 30), text: 'Segunda 02:30');
    final timeline = MoodTimeline.build([secondHalf, firstHalf],
        period: MoodPeriod.all, now: tz.TZDateTime(madrid, 2026, 10, 25, 12));
    expect(timeline.points.map((point) => point.localDateTime.hour).toList(),
        [2, 2]);
    expect(timeline.points.map((point) => point.entry.text).toList(),
        ['Primera 02:30', 'Segunda 02:30']);
    expect(timeline.points[0].x, closeTo(2.5 / 25, 1e-12));
    expect(timeline.points[1].x, closeTo(3.5 / 25, 1e-12));
    expect(timeline.points[1].x, greaterThan(timeline.points[0].x));
    expect(timeline.maxX, 1);
  });

  test('a missing DST date still cuts a full calendar gap', () {
    final timeline = MoodTimeline.build([
      entry(tz.TZDateTime(madrid, 2026, 3, 28, 23)),
      entry(tz.TZDateTime(madrid, 2026, 3, 30, 1)),
    ], period: MoodPeriod.all, now: tz.TZDateTime(madrid, 2026, 3, 30, 12));
    expect(timeline.hasGaps, isTrue);
    expect(timeline.segments, hasLength(2));
    expect(timeline.maxX, 3);
  });

  test(
      'leap day exists on the calendar axis and adjacent dates remain connected',
      () {
    final timeline = MoodTimeline.build([
      entry(DateTime.utc(2028, 2, 28, 12)),
      entry(DateTime.utc(2028, 2, 29, 12)),
      entry(DateTime.utc(2028, 3, 1, 12)),
    ], period: MoodPeriod.all, now: utcNow(2028, 3, 1));
    expect(timeline.points.map((point) => point.x).toList(), [0.5, 1.5, 2.5]);
    expect(timeline.segments, hasLength(1));
    expect(timeline.maxX, 3);
  });

  test(
      'unrepresentable dates are counted without changing other data or hiding invalid moods',
      () {
    final unreadable =
        entry(UnreadableDateTime(), text: 'Fecha ilegible sin modificar');
    final extreme = entry(
        DateTime.fromMillisecondsSinceEpoch(8640000000000000, isUtc: true));
    final invalidMood = entry(DateTime.utc(2026, 9, 10),
        mood: 8, text: 'Ánimo original fuera de rango');
    final timeline = MoodTimeline.build([unreadable, extreme, invalidMood],
        period: MoodPeriod.all, now: utcNow(2026, 9, 10));
    expect(timeline.skippedEntryCount, 2);
    expect(timeline.points.single.entry, same(invalidMood));
    expect(timeline.points.single.entry.mood, 8);
    expect(timeline.points.single.sourceIndex, 2);
    expect(unreadable.text, 'Fecha ilegible sin modificar');
    expect(timeline.pointsOnDay(UnreadableDateTime()), isEmpty);
  });

  test('all public collection snapshots are immutable', () {
    final original = entry(DateTime.utc(2026, 9, 10));
    final timeline = MoodTimeline.build(List.unmodifiable([original]),
        period: MoodPeriod.all, now: utcNow(2026, 9, 10));
    expect(() => timeline.points.clear(), throwsUnsupportedError);
    expect(() => timeline.segments.clear(), throwsUnsupportedError);
    expect(() => timeline.segments.single.clear(), throwsUnsupportedError);
    expect(() => timeline.pointsOnDay(original.createdAt).clear(),
        throwsUnsupportedError);
  });

  test(
      'ten thousand unsorted records retain all identities and finite coordinates',
      () {
    final originals = List.generate(
        10000,
        (i) => entry(DateTime.utc(2024, 1, 1).add(Duration(minutes: i * 60)),
            mood: i % 5, text: 'Entrada $i'));
    final source = originals.reversed.toList();
    final timeline = MoodTimeline.build(source,
        period: MoodPeriod.all, now: utcNow(2026, 9, 10));
    expect(timeline.points, hasLength(originals.length));
    expect(timeline.segments, hasLength(1));
    for (var i = 0; i < originals.length; i++) {
      expect(timeline.points[i].entry, same(originals[i]));
      expect(timeline.points[i].sourceIndex, originals.length - 1 - i);
      expect(timeline.points[i].x.isFinite, isTrue);
      expect(timeline.points[i].x, inInclusiveRange(0, timeline.maxX));
    }
    expect(source.first, same(originals.last));
    expect(source.last, same(originals.first));
    expect(originals[321].text, 'Entrada 321');
  });
}
