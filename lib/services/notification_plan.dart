import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

/// The shipped collection has one text for each date of a non-leap year.
/// February 29 shares February 28; March 1 always opens the March 1 text.
int reflectionIndexForDate(DateTime date) {
  final day = date.month == 2 && date.day == 29 ? 28 : date.day;
  return DateTime.utc(2001, date.month, day)
      .difference(DateTime.utc(2001, 1, 1))
      .inDays;
}

class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.scheduledAt,
    required this.title,
    required this.body,
    this.payload,
  });

  final int id;
  final tz.TZDateTime scheduledAt;
  final String title;
  final String body;
  final String? payload;
}

/// Pure planning: validate and calculate everything before cancelling any of
/// the notifications already installed on the device.
class NotificationPlan {
  static const reflectionBaseId = 10000;
  static const reflectionMaxDays = 1000; // Reserved IDs 10000..10999.

  static List<PlannedNotification> dailyReflections(String json,
      {required tz.TZDateTime now, int daysAhead = 60}) {
    if (daysAhead < 0 || daysAhead > reflectionMaxDays) {
      throw ArgumentError.value(
          daysAhead, 'daysAhead', 'Outside the reserved notification ID range');
    }
    final raw = jsonDecode(json);
    if (raw is! List || raw.length != 365) {
      throw const FormatException(
          'La colección debe contener 365 reflexiones.');
    }
    final titles = <String>[];
    for (final item in raw) {
      final String title;
      if (item is Map && item['title'] is String) {
        title = (item['title'] as String).trim();
      } else if (item is String) {
        final match = RegExp(r'^###\s+(.+)', multiLine: true).firstMatch(item);
        title = match?.group(1)?.trim() ?? 'Reflexión del día';
        if (item.trim().isEmpty) {
          throw const FormatException('Una reflexión está vacía.');
        }
      } else {
        throw const FormatException(
            'Una reflexión tiene un formato no válido.');
      }
      if (title.isEmpty) {
        throw const FormatException('Una reflexión no tiene título.');
      }
      titles.add(title);
    }

    final todayAtNine =
        tz.TZDateTime(now.location, now.year, now.month, now.day, 9);
    final firstDayOffset = todayAtNine.isAfter(now) ? 0 : 1;
    return [
      for (var i = 0; i < daysAhead; i++)
        _reflection(now, firstDayOffset + i, i, titles),
    ];
  }

  static PlannedNotification _reflection(
      tz.TZDateTime now, int dayOffset, int sequence, List<String> titles) {
    // Calendar construction preserves 09:00 when a day has 23 or 25 hours.
    final date = tz.TZDateTime(
        now.location, now.year, now.month, now.day + dayOffset, 9);
    final index = reflectionIndexForDate(date);
    return PlannedNotification(
      id: reflectionBaseId + sequence,
      scheduledAt: date,
      title: 'Reflexión diaria',
      body: titles[index],
      payload: '$index',
    );
  }

  static List<PlannedNotification> milestones(DateTime start,
      {required tz.TZDateTime now, required Map<int, String> milestones}) {
    final base = tz.TZDateTime.from(start, now.location);
    return [
      for (final item in milestones.entries)
        if (base.add(Duration(days: item.key)).isAfter(now))
          PlannedNotification(
            id: item.key,
            scheduledAt: base.add(Duration(days: item.key)),
            title: 'Logro de recuperación',
            body: item.value,
          ),
    ];
  }
}
