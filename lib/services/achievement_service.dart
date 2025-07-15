import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';

class AchievementService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  /* ─── canales ─── */
  static const _milestoneChannelId = 'achievements';
  static const _milestoneChannelName = 'Logros de sobriedad';
  static const _reflectionChannelId = 'daily_reflection';
  static const _reflectionChannelName = 'Reflexión diaria';

  /* ─── hitos ─── */
  static const Map<int, String> _milestones = {
    1: '¡Primer día limpio! 🌱',
    3: '3 días: cada paso cuenta 👣',
    7: '¡Primera semana limpia! 🎉',
    14: '2 semanas de constancia 🔑',
    30: '1 mes: ¡sigue así! 💪',
    60: '2 meses libres 🙌',
    90: '3 meses: confianza en ti 🤝',
    120: '4 meses sin consumir ✨',
    180: 'Medio año de progreso 💡',
    365: '¡1 año limpio! Orgullo total 🏆',
    730: '¡2 años libre! 🌟',
    1095: '3 años: inspiración constante 💖',
    1460: '4 años de fortaleza 💪',
    1825: '5 años: mitad de década 🎖️',
    2190: '6 años manteniéndote firme 🙏',
    2555: '7 años: ejemplo para otros 🕊️',
    2920: '8 años de constancia 🛡️',
    3285: '9 años y sumando 🚀',
    3650: '10 años limpio: leyenda 🏅',
  };

  static const int _reflectionBaseId = 10000;
  static Map<int, String> get milestones => Map.unmodifiable(_milestones);

  /* ─── init ─── */
  static Future<void> init() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(requestSoundPermission: true, requestAlertPermission: true),
    );
    await _plugin.initialize(settings);

    // 1️⃣ Solicitar permiso en Android 13+/iOS
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    // Zonas horarias
    try {
      tz.initializeTimeZones();
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
  }

  /* ─── LOGROS ─── */
  static Future<void> scheduleMilestones(DateTime startDate) async {
    await cancelMilestones();

    final now = tz.TZDateTime.now(tz.local);
    for (final entry in _milestones.entries) {
      final days = entry.key;
      final message = entry.value;

      final trigger = tz.TZDateTime(
            tz.local, startDate.year, startDate.month, startDate.day, 9)
          .add(Duration(days: days));

      if (trigger.isBefore(now)) continue;

      await _plugin.zonedSchedule(
        days,
        'Logro de recuperación',
        message,
        trigger,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _milestoneChannelId,
            _milestoneChannelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dateAndTime,
      );
    }
  }

  static Future<void> cancelMilestones() async {
    for (final id in _milestones.keys) {
      await _plugin.cancel(id);
    }
  }

  /* ─── REFLEXIÓN DIARIA ─── */
  static Future<void> scheduleDailyReflections(String reflectionsJson,
      {int daysAhead = 30}) async {
    await cancelDailyReflections(daysAhead: daysAhead);

    final List<dynamic> raw = jsonDecode(reflectionsJson);
    final titles = raw.map<String>((e) {
      if (e is Map && e['title'] != null) return e['title'] as String;
      final md = e.toString();
      final m = RegExp(r'^###\s+(.+)', multiLine: true).firstMatch(md);
      return m != null ? m.group(1)! : 'Reflexión del día';
    }).toList();

    final now = tz.TZDateTime.now(tz.local);
    var first = tz.TZDateTime(tz.local, now.year, now.month, now.day, 9);
    // ▶️ Si la programación ocurre antes de las 09:00, la primera es hoy.
    if (first.isBefore(now)) first = first.add(const Duration(days: 1));

    for (var i = 0; i < daysAhead; i++) {
      final date = first.add(Duration(days: i));
      final dayOfYear = int.parse(DateFormat('D').format(date)) - 1;
      final title = titles[dayOfYear % titles.length];

      await _plugin.zonedSchedule(
        _reflectionBaseId + i,
        'Reflexión diaria',
        title,
        date,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _reflectionChannelId,
            _reflectionChannelName,
            importance: Importance.defaultImportance,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dateAndTime,
      );
    }
  }

  static Future<void> cancelDailyReflections({int daysAhead = 30}) async {
    for (var i = 0; i < daysAhead; i++) {
      await _plugin.cancel(_reflectionBaseId + i);
    }
  }
}
