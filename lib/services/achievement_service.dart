import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'native_tz.dart'; // obtiene la zona local desde el canal nativo

/// Gestiona notificaciones de logros y reflexión diaria.
class AchievementService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  /* ─────── canales ─────── */
  static const _milestoneChannelId = 'achievements';
  static const _milestoneChannelName = 'Logros de sobriedad';
  static const _reflectionChannelId = 'daily_reflection';
  static const _reflectionChannelName = 'Reflexión diaria';

  /* ─────── hitos ─────── */
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

  /* ─── permisos cacheados ─── */
  static bool _exactAlarmGranted = true;

  /* ───────────────── init ───────────────── */
  static Future<void> init(
      {void Function(NotificationResponse)? onNotificationResponse}) async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestSoundPermission: true,
      ),
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: onNotificationResponse,
    );

    /* Permisos Android (POST_NOTIFICATIONS + EXACT_ALARM) */
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await (android as dynamic)?.requestPermission();
    _exactAlarmGranted =
        await (android as dynamic)?.hasExactAlarmPermission() ?? true;

    if (!_exactAlarmGranted) {
      _exactAlarmGranted =
          await (android as dynamic)?.requestExactAlarmsPermission() ?? false;
    }

    /* Time‑zones */
    tz.initializeTimeZones();
    final localName = await NativeTz.getLocalTz();
    tz.setLocalLocation(tz.getLocation(localName));
    dev.log('[TZ] Zona local: $localName');
  }

  /* ───────── helper para elegir modo ───────── */
  static AndroidScheduleMode _mode() => _exactAlarmGranted
      ? AndroidScheduleMode.exactAllowWhileIdle
      : AndroidScheduleMode.inexactAllowWhileIdle;

  /* ───────── LOGROS ───────── */
  static Future<void> scheduleMilestones(DateTime start) async {
    await cancelMilestones();
    final now = tz.TZDateTime.now(tz.local);

    for (final entry in _milestones.entries) {
      final trigger = tz.TZDateTime(
            tz.local, start.year, start.month, start.day, 9)
          .add(Duration(days: entry.key));

      if (trigger.isBefore(now)) continue;

      await _plugin.zonedSchedule(
        entry.key, // ID = nº días
        'Logro de recuperación',
        entry.value,
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
        androidScheduleMode: _mode(),
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

  /* ───────── REFLEXIÓN DIARIA ───────── */
  static Future<void> scheduleDailyReflections(
    String json, {
    int daysAhead = 60,
  }) async {
    await cancelDailyReflections(daysAhead: daysAhead);

    /* Extraemos títulos */
    final titles = (jsonDecode(json) as List<dynamic>).map<String>((e) {
      if (e is Map && e['title'] != null) return e['title'] as String;
      final m =
          RegExp(r'^###\s+(.+)', multiLine: true).firstMatch(e.toString());
      return m?.group(1) ?? 'Reflexión del día';
    }).toList();

    final now = tz.TZDateTime.now(tz.local);
    var first = tz.TZDateTime(tz.local, now.year, now.month, now.day, 9);
    if (first.isBefore(now)) first = first.add(const Duration(days: 1));

    for (var i = 0; i < daysAhead; i++) {
      final date = first.add(Duration(days: i));
      final doy = int.parse(DateFormat('D').format(date)) - 1;
      final title = titles[doy % titles.length];

      await _plugin.zonedSchedule(
        _reflectionBaseId + i,
        'Reflexión diaria',
        title,
        date,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _reflectionChannelId,
            _reflectionChannelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: '$doy',
        androidScheduleMode: _mode(),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dateAndTime,
      );
    }

    dev.log('[Notif] Programadas $daysAhead reflexiones '
        '(${_exactAlarmGranted ? 'exactas' : 'inexactas'})');
  }

  static Future<void> cancelDailyReflections({int daysAhead = 60}) async {
    for (var i = 0; i < daysAhead; i++) {
      await _plugin.cancel(_reflectionBaseId + i);
    }
  }
}
