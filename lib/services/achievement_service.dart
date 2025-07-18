import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';

/// Gestiona notificaciones de logros y reflexión diaria.
class AchievementService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  /* ── canales ── */
  static const _milestoneChannelId   = 'achievements';
  static const _milestoneChannelName = 'Logros de sobriedad';
  static const _reflectionChannelId  = 'daily_reflection';
  static const _reflectionChannelName= 'Reflexión diaria';

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
  static Future<void> init({
    void Function(NotificationResponse)? onNotificationResponse,
  }) async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS:    DarwinInitializationSettings(
                requestSoundPermission: true,
                requestAlertPermission: true),
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: onNotificationResponse,
    );

    // 1️⃣ Comprobar si ya están activadas antes de volver a solicitar permiso
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    final enabled = await (androidImpl as dynamic)?.areNotificationsEnabled()
        ?? true;

    if (!enabled) {
      try {
        // Solo pedimos permiso si no estaba concedido
        await (androidImpl as dynamic)?.requestPermission();
      } catch (_) {/* versiones antiguas */}
    }

    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    // Zonas horarias (imprescindible para zonedSchedule)
    tz.initializeTimeZones();
  }

  /* ── LOGROS ── */
  static Future<void> scheduleMilestones(DateTime startDate) async {
    await cancelMilestones();

    final now = tz.TZDateTime.now(tz.local);
    for (final entry in _milestones.entries) {
      final days    = entry.key;
      final message = entry.value;

      final trigger = tz.TZDateTime(
        tz.local,
        startDate.year,
        startDate.month,
        startDate.day,
        9, // 09:00 hora local
      ).add(Duration(days: days));

      if (trigger.isBefore(now)) continue; // ya pasó

      await _plugin.zonedSchedule(
        days, // ID = número de días
        'Logro de recuperación',
        message,
        trigger,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _milestoneChannelId,
            _milestoneChannelName,
            importance: Importance.high,
            priority:  Priority.high,
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

  /* ── REFLEXIÓN DIARIA ── */
  static Future<void> scheduleDailyReflections(
    String reflectionsJson, {
    int daysAhead = 30,
  }) async {
    await cancelDailyReflections(daysAhead: daysAhead);

    // Parseamos los títulos a mostrar en la notificación
    final raw    = jsonDecode(reflectionsJson) as List<dynamic>;
    final titles = raw.map<String>((e) {
      if (e is Map && e['title'] != null) return e['title'] as String;
      final md = e.toString();
      final m  = RegExp(r'^###\s+(.+)', multiLine: true).firstMatch(md);
      return m != null ? m.group(1)! : 'Reflexión del día';
    }).toList();

    final now   = tz.TZDateTime.now(tz.local);
    var first   = tz.TZDateTime(tz.local, now.year, now.month, now.day, 9);
    if (first.isBefore(now)) first = first.add(const Duration(days: 1));

    for (var i = 0; i < daysAhead; i++) {
      final date   = first.add(Duration(days: i));
      final doy    = int.parse(DateFormat('D').format(date)) - 1;
      final title  = titles[doy % titles.length];

      await _plugin.zonedSchedule(
        _reflectionBaseId + i, // ID >= 10000
        'Reflexión diaria',
        title,
        date,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _reflectionChannelId,
            _reflectionChannelName,
            importance: Importance.high,
            priority:  Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: '$doy', // deep‑link al día concreto
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dateAndTime,
      );
    }

    // Control en logcat
    final pending = await _plugin.pendingNotificationRequests();
    dev.log('Programadas ${pending.length} notificaciones (hitos + diarias)');
  }

  static Future<void> cancelDailyReflections({int daysAhead = 30}) async {
    for (var i = 0; i < daysAhead; i++) {
      await _plugin.cancel(_reflectionBaseId + i);
    }
  }
}
