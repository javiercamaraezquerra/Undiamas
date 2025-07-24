import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'native_tz.dart';

/// Gestiona notificaciones de logros y reflexión diaria.
class AchievementService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  /* ── canales ── */
  static const _milestoneChannelId   = 'achievements';
  static const _milestoneChannelName = 'Logros de sobriedad';
  static const _reflectionChannelId  = 'daily_reflection';
  static const _reflectionChannelName = 'Reflexión diaria';

  /* ── hitos ── */
  static const Map<int, String> _milestones = {
    1:    '¡Primer día limpio! 🌱',
    3:    '3 días: cada paso cuenta 👣',
    7:    '¡Primera semana limpia! 🎉',
    14:   '2 semanas de constancia 🔑',
    30:   '1 mes: ¡sigue así! 💪',
    60:   '2 meses libres 🙌',
    90:   '3 meses: confianza en ti 🤝',
    120:  '4 meses sin consumir ✨',
    180:  'Medio año de progreso 💡',
    365:  '¡1 año limpio! Orgullo total 🏆',
    730:  '¡2 años libre! 🌟',
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

  /* ── init ── */
  static Future<void> init(
      {void Function(NotificationResponse p)? onNotificationResponse}) async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS:     DarwinInitializationSettings(
                 requestAlertPermission: true,
                 requestSoundPermission: true),
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: onNotificationResponse,
    );

    /* Zonas horarias */
    tz.initializeTimeZones();
    final localName = await NativeTz.getLocalTz();
    tz.setLocalLocation(tz.getLocation(localName));
    dev.log('[TZ] Zona local: $localName');
  }

  /* ── LOGROS ─ */
  static Future<void> scheduleMilestones(DateTime start) async {
    await cancelMilestones();
    final now = tz.TZDateTime.now(tz.local);

    // ★ El instante exacto del hito es: fecha‑hora de inicio + N días.
    final base = tz.TZDateTime.from(start, tz.local);

    for (final e in _milestones.entries) {
      final trigger = base.add(Duration(days: e.key));             // ★

      if (trigger.isBefore(now)) continue;

      await _plugin.zonedSchedule(
        e.key,
        'Logro de recuperación',
        e.value,
        trigger,
        const NotificationDetails(
          android: AndroidNotificationDetails(
              _milestoneChannelId, _milestoneChannelName,
              importance: Importance.high, priority: Priority.high),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  static Future<void> cancelMilestones() async {
    for (final id in _milestones.keys) {
      await _plugin.cancel(id);
    }
  }

  /* ── REFLEXIÓN DIARIA (sin cambios) ─ */
  static Future<void> scheduleDailyReflections(String json,
      {int daysAhead = 60}) async {
    await cancelDailyReflections(daysAhead: daysAhead);

    final items = (jsonDecode(json) as List<dynamic>).map((e) {
      if (e is Map && e['title'] != null) return e['title'] as String;
      final m = RegExp(r'^###\s+(.+)', multiLine: true).firstMatch(e.toString());
      return m?.group(1) ?? 'Reflexión del día';
    }).toList();

    final now   = tz.TZDateTime.now(tz.local);
    var first   = tz.TZDateTime(tz.local, now.year, now.month, now.day, 9);
    if (first.isBefore(now)) first = first.add(const Duration(days: 1));

    for (var i = 0; i < daysAhead; i++) {
      final date  = first.add(Duration(days: i));
      final doy   = int.parse(DateFormat('D').format(date)) - 1;
      final title = items[doy % items.length];

      await _plugin.zonedSchedule(
        _reflectionBaseId + i,
        'Reflexión diaria',
        title,
        date,
        const NotificationDetails(
          android: AndroidNotificationDetails(
              _reflectionChannelId, _reflectionChannelName,
              importance: Importance.high, priority: Priority.high),
          iOS: DarwinNotificationDetails(),
        ),
        payload: '$doy',
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }

    dev.log('[Notif] programadas $daysAhead reflexiones (modo inexacto)');
  }

  static Future<void> cancelDailyReflections({int daysAhead = 60}) async {
    for (var i = 0; i < daysAhead; i++) {
      await _plugin.cancel(_reflectionBaseId + i);
    }
  }
}
