import 'package:timezone/timezone.dart' as tz;

import '../models/diary_entry.dart';

enum MoodPeriod { week, month, all }

/// One original entry. No averaging, deduplication or mutation of Hive objects.
class MoodTimelinePoint {
  const MoodTimelinePoint._({
    required this.entry,
    required this.localDateTime,
    required this.x,
    required this.sourceIndex,
  });

  final DiaryEntry entry;
  final DateTime localDateTime;
  final double x;
  final int sourceIndex;
}

/// An immutable view of the supplied entries on a local calendar axis.
///
/// Week/month include all of today and its preceding 6/29 calendar dates.
/// Future dates are retained in [MoodPeriod.all], but excluded from those
/// current periods. A future time later today still belongs to today's date.
/// The all period spans the stored dates, including future ones, and uses
/// today only when no entry has a representable local date.
class MoodTimeline {
  MoodTimeline._({
    required List<MoodTimelinePoint> points,
    required List<List<MoodTimelinePoint>> segments,
    required this.startDay,
    required this.endDay,
    required this.maxX,
    required this.skippedEntryCount,
    required _Calendar calendar,
  })  : points = List.unmodifiable(points),
        segments = List.unmodifiable(segments
            .map((segment) => List<MoodTimelinePoint>.unmodifiable(segment))),
        _calendar = calendar;

  factory MoodTimeline.build(List<DiaryEntry> entries,
      {required MoodPeriod period, required DateTime now}) {
    final calendar = _Calendar(now);
    final today = calendar.day(calendar.local(now));
    final todayOrdinal = _ordinal(today);
    final records = <_EntryTime>[];
    var skipped = 0;
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      try {
        final local = calendar.local(entry.createdAt);
        final day = calendar.day(local);
        final nextDay = calendar.day(local, offset: 1);
        final length = nextDay.difference(day).inMicroseconds;
        final elapsed = local.difference(day).inMicroseconds;
        if (length <= 0 || elapsed < 0 || elapsed >= length) {
          skipped++;
          continue;
        }
        records.add(
            _EntryTime(entry, local, _ordinal(day), elapsed / length, index));
      } catch (_) {
        // DateTime itself cannot hold a malformed date. This covers conversion
        // failures or extreme dates whose local day boundary is unrepresentable.
        // Keep the original entry untouched; the UI can disclose this count.
        skipped++;
      }
    }
    records.sort((a, b) {
      final byTime = a.local.compareTo(b.local);
      return byTime != 0 ? byTime : a.sourceIndex.compareTo(b.sourceIndex);
    });

    final DateTime start;
    final DateTime end;
    if (period == MoodPeriod.all && records.isNotEmpty) {
      start = calendar.day(records.first.local);
      end = calendar.day(records.last.local);
    } else {
      final precedingDays = switch (period) {
        MoodPeriod.week => 6,
        MoodPeriod.month => 29,
        MoodPeriod.all => 0,
      };
      start = calendar.day(today, offset: -precedingDays);
      end = today;
    }
    final startOrdinal = _ordinal(start);
    final endOrdinal = period == MoodPeriod.all ? _ordinal(end) : todayOrdinal;
    final points = <MoodTimelinePoint>[];
    final segments = <List<MoodTimelinePoint>>[];
    int? previousDay;
    for (final record in records) {
      if (record.day < startOrdinal || record.day > endOrdinal) continue;
      final point = MoodTimelinePoint._(
        entry: record.entry,
        localDateTime: record.local,
        x: record.day - startOrdinal + record.fraction,
        sourceIndex: record.sourceIndex,
      );
      points.add(point);
      if (previousDay == null || record.day - previousDay > 1) {
        segments.add(<MoodTimelinePoint>[]);
      }
      segments.last.add(point);
      previousDay = record.day;
    }
    return MoodTimeline._(
      points: points,
      segments: segments,
      startDay: start,
      endDay: end,
      maxX:
          (endOrdinal - startOrdinal + 1).clamp(1, double.maxFinite).toDouble(),
      skippedEntryCount: skipped,
      calendar: calendar,
    );
  }

  final List<MoodTimelinePoint> points;
  final List<List<MoodTimelinePoint>> segments;
  final DateTime startDay;
  final DateTime endDay;

  /// Calendar-day units, ending at the boundary AFTER inclusive [endDay].
  /// A one-day range therefore has maxX=1, never a degenerate zero-width axis.
  final double maxX;

  /// Interior missing dates split the line. Empty edges do not add segments.
  bool get hasGaps => segments.length > 1;

  /// Only unrepresentable dates are skipped. Unexpected mood values are kept;
  /// consumers must label them unavailable instead of clamping their emotion.
  final int skippedEntryCount;
  final _Calendar _calendar;

  List<MoodTimelinePoint> pointsOnDay(DateTime date) {
    final int ordinal;
    try {
      ordinal = _ordinal(_calendar.local(date));
    } catch (_) {
      return const [];
    }
    return List.unmodifiable(
        points.where((point) => _ordinal(point.localDateTime) == ordinal));
  }
}

class _EntryTime {
  const _EntryTime(
      this.entry, this.local, this.day, this.fraction, this.sourceIndex);
  final DiaryEntry entry;
  final DateTime local;
  final int day;
  final double fraction;
  final int sourceIndex;
}

class _Calendar {
  _Calendar(DateTime now)
      : location = now is tz.TZDateTime ? now.location : null;
  final tz.Location? location;

  DateTime local(DateTime value) =>
      location == null ? value.toLocal() : tz.TZDateTime.from(value, location!);

  DateTime day(DateTime value, {int offset = 0}) => location == null
      ? DateTime(value.year, value.month, value.day + offset)
      : tz.TZDateTime(location!, value.year, value.month, value.day + offset);
}

// UTC midnight is only an ordinal for a LOCAL calendar date. It is never the
// plotted instant; using it prevents 23/25-hour days changing date distances.
int _ordinal(DateTime date) => DateTime.utc(date.year, date.month, date.day)
    .difference(DateTime.utc(1970))
    .inDays;
