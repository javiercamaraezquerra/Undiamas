import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'native_tz.dart';
import 'notification_plan.dart';

/// Gestiona notificaciones de logros y reflexión diaria.
class AchievementService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  /* ── canales ── */
  static const _milestoneChannelId = 'achievements';
  static const _milestoneChannelName = 'Logros de sobriedad';
  static const _reflectionChannelId = 'daily_reflection';
  static const _reflectionChannelName = 'Reflexión diaria';

  /* ── hitos ── */
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

  static Map<int, String> get milestones => Map.unmodifiable(_milestones);
  static const _settingsChannel = MethodChannel('undiamas/notifications');
  static Future<void> _tail = Future<void>.value();
  static bool _pluginInitialized = false;
  static bool _timeZonesLoaded = false;
  static void Function(NotificationResponse)? _onResponse;
  static tz.TZDateTime Function()? _testClock;

  // Public operations share one queue. Private helpers never enqueue again.
  // A failed request must not prevent a later request to turn notifications off.
  static Future<T> _enqueue<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  static Future<void> init(
      {void Function(NotificationResponse p)? onNotificationResponse}) {
    if (onNotificationResponse != null) _onResponse = onNotificationResponse;
    return _enqueue(() async {
      await _ensurePluginInitialized();
      await _refreshTimeZone();
    });
  }

  static Future<void> _ensurePluginInitialized() async {
    if (_pluginInitialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
          requestAlertPermission: true, requestSoundPermission: true),
    );
    final initialized = await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) =>
          _onResponse?.call(response),
    );
    if (initialized != true) {
      throw StateError('No se pudieron iniciar las notificaciones.');
    }
    _pluginInitialized = true;
  }

  static Future<void> _refreshTimeZone() async {
    if (!_timeZonesLoaded) {
      tz_data.initializeTimeZones();
      _timeZonesLoaded = true;
    }
    final name = await NativeTz.getLocalTz();
    try {
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      throw StateError('No se reconoce la zona horaria del dispositivo. '
          'Revisa la fecha y hora antes de activar los avisos.');
    }
  }

  static Future<bool> _readNotificationsEnabled() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final bool? enabled;
    if (android != null) {
      enabled = await android.areNotificationsEnabled();
    } else {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      enabled = (await ios?.checkPermissions())?.isEnabled;
    }
    if (enabled == null) {
      throw StateError('No se pudo comprobar el permiso de notificaciones.');
    }
    return enabled;
  }

  static Future<bool> notificationsEnabled() => _enqueue(() async {
        await _ensurePluginInitialized();
        return _readNotificationsEnabled();
      });

  static Future<bool> requestNotificationPermission() => _enqueue(() async {
        await _ensurePluginInitialized();
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final bool? granted;
        if (android != null) {
          granted = await android.requestNotificationsPermission();
        } else {
          final ios = _plugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
          granted = await ios?.requestPermissions(
              alert: true, badge: true, sound: true);
        }
        if (granted == null) {
          throw StateError(
              'No se pudo solicitar el permiso de notificaciones.');
        }
        return granted;
      });

  static Future<void> openNotificationSettings() => _enqueue(() async {
        await _settingsChannel.invokeMethod<void>('openSettings');
      });

  static Future<NotificationAppLaunchDetails?> getLaunchDetails() =>
      _enqueue(() async {
        await _ensurePluginInitialized();
        return _plugin.getNotificationAppLaunchDetails();
      });

  static Future<void> _prepareScheduling() async {
    await _ensurePluginInitialized();
    await _refreshTimeZone();
    if (!await _readNotificationsEnabled()) {
      throw StateError(
          'Las notificaciones están desactivadas en el dispositivo. '
          'Permítelas en sus ajustes antes de activar estos avisos.');
    }
  }

  static tz.TZDateTime _now() =>
      _testClock?.call() ?? tz.TZDateTime.now(tz.local);

  static Future<void> scheduleMilestones(DateTime start) => _enqueue(() async {
        await _prepareScheduling();
        final plan = NotificationPlan.milestones(start,
            now: _now(), milestones: _milestones);
        await _cancelIds(_milestones.keys);
        await _install(
            plan,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                  _milestoneChannelId, _milestoneChannelName,
                  importance: Importance.high, priority: Priority.high),
              iOS: DarwinNotificationDetails(),
            ));
      });

  static Future<void> cancelMilestones() => _enqueue(() async {
        await _ensurePluginInitialized();
        await _cancelIds(_milestones.keys);
      });

  /// The 60-day horizon is unchanged. Each date carries its corresponding text.
  static Future<void> scheduleDailyReflections(String json,
          {int daysAhead = 60}) =>
      _enqueue(() async {
        await _prepareScheduling();
        final plan = NotificationPlan.dailyReflections(json,
            now: _now(), daysAhead: daysAhead);
        // Only a completely valid plan is allowed to replace existing alarms.
        await _cancelDailyPending();
        await _install(
            plan,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                  _reflectionChannelId, _reflectionChannelName,
                  importance: Importance.high, priority: Priority.high),
              iOS: DarwinNotificationDetails(),
            ));
      });

  /// [daysAhead] is kept for source compatibility. Cancellation intentionally
  /// covers the entire reserved range, including copies with an older horizon.
  static Future<void> cancelDailyReflections({int daysAhead = 60}) =>
      _enqueue(() async {
        await _ensurePluginInitialized();
        await _cancelDailyPending();
      });

  static Future<void> _cancelDailyPending() async {
    final pending = await _plugin.pendingNotificationRequests();
    await _cancelIds(pending
        .where((p) =>
            p.id >= NotificationPlan.reflectionBaseId &&
            p.id <
                NotificationPlan.reflectionBaseId +
                    NotificationPlan.reflectionMaxDays)
        .map((p) => p.id)
        .toSet());
  }

  static Future<void> _cancelIds(Iterable<int> ids) async {
    var failed = false;
    for (final id in ids) {
      try {
        await _plugin.cancel(id);
      } catch (_) {
        failed = true;
      }
    }
    if (failed) {
      throw StateError('No se pudieron retirar todos los avisos pendientes. '
          'Vuelve a intentarlo antes de activarlos de nuevo.');
    }
  }

  static Future<void> _install(
      List<PlannedNotification> plan, NotificationDetails details) async {
    final attemptedIds = <int>[];
    try {
      for (final item in plan) {
        // Include the failing call: native code may install before responding.
        attemptedIds.add(item.id);
        await _plugin.zonedSchedule(
            item.id, item.title, item.body, item.scheduledAt, details,
            payload: item.payload,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime);
      }
    } catch (_) {
      try {
        await _cancelIds(attemptedIds);
      } catch (_) {
        throw StateError('No se pudieron programar todos los avisos ni retirar '
            'todos los del intento. Desactívalos y vuelve a intentarlo.');
      }
      throw StateError('No se pudieron programar todos los avisos. '
          'Se han retirado los nuevos avisos de este intento. Vuelve a intentarlo.');
    }
  }

  @visibleForTesting
  static Future<void> resetForTesting({tz.TZDateTime Function()? now}) async {
    await _tail;
    _pluginInitialized = false;
    _timeZonesLoaded = false;
    _onResponse = null;
    _testClock = now;
  }
}
