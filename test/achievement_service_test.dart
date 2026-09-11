import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:un_dia_mas/services/achievement_service.dart';
import 'package:un_dia_mas/services/notification_plan.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const pluginChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  const zoneChannel = MethodChannel('undiamas/tz');
  const settingsChannel = MethodChannel('undiamas/notifications');
  final json =
      jsonEncode(List.generate(365, (i) => '### Reflexión $i\nTexto $i'));
  final calls = <MethodCall>[];
  final events = <String>[];
  final pending = <int, Map<String, dynamic>>{};
  final cancelFailures = <int>{};
  bool? initResult;
  bool? enabled;
  bool? requested;
  String? zone;
  int? scheduleFailure;
  Completer<void>? scheduleWait;
  Completer<void>? scheduleStarted;
  Map<String, dynamic>? launch;
  var failPendingLookup = false;
  final futureYear = DateTime.now().year + 5;

  List<MethodCall> named(String name) =>
      calls.where((c) => c.method == name).toList();
  List<Map<String, dynamic>> scheduled() => named('zonedSchedule')
      .map((c) => Map<String, dynamic>.from(c.arguments as Map))
      .toList();
  Map<String, dynamic> oldNotification(int id) =>
      {'id': id, 'title': 'Anterior', 'body': 'Anterior', 'payload': ''};

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await AchievementService.resetForTesting(
        now: () => tz.TZDateTime(tz.local, futureYear, 3, 1, 8));
    calls.clear();
    events.clear();
    pending.clear();
    cancelFailures.clear();
    initResult = true;
    enabled = true;
    requested = true;
    zone = 'Europe/Madrid';
    scheduleFailure = null;
    scheduleWait = null;
    scheduleStarted = null;
    launch = null;
    failPendingLookup = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(zoneChannel,
        (call) async {
      expect(call.method, 'getLocalTz');
      events.add('timezone');
      return zone;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(settingsChannel,
        (call) async {
      calls.add(call);
      expect(call.method, 'openSettings');
      return null;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(pluginChannel,
        (call) async {
      calls.add(call);
      events.add(call.method);
      switch (call.method) {
        case 'initialize':
          return initResult;
        case 'areNotificationsEnabled':
          return enabled;
        case 'requestNotificationsPermission':
          return requested;
        case 'getNotificationAppLaunchDetails':
          return launch;
        case 'pendingNotificationRequests':
          if (failPendingLookup) {
            throw PlatformException(code: 'fixture_pending_error');
          }
          return pending.values.toList();
        case 'cancel':
          final id = (call.arguments as Map)['id'] as int;
          if (cancelFailures.contains(id)) {
            throw PlatformException(code: 'fixture_cancel_error');
          }
          pending.remove(id);
          return null;
        case 'zonedSchedule':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final id = args['id'] as int;
          // Also model the ambiguous native case: installed before failure reply.
          pending[id] = {
            'id': id,
            'title': args['title'],
            'body': args['body'],
            'payload': args['payload']
          };
          if (scheduleStarted != null && !scheduleStarted!.isCompleted) {
            scheduleStarted!.complete();
          }
          await scheduleWait?.future;
          if (id == scheduleFailure) {
            throw PlatformException(code: 'fixture_schedule_error');
          }
          return null;
        default:
          fail('Unexpected native notification method: ${call.method}');
      }
    });
  });

  tearDown(() async {
    await AchievementService.resetForTesting();
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(pluginChannel, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(zoneChannel, null);
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(settingsChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
      'lazy initialization uses local timezone and matching title/payload at 09:00',
      () async {
    await AchievementService.scheduleDailyReflections(json, daysAhead: 2);
    expect(events.indexOf('initialize'), lessThan(events.indexOf('timezone')));
    expect(
        events.indexOf('timezone'), lessThan(events.indexOf('zonedSchedule')));
    expect(named('initialize'), hasLength(1));
    final notices = scheduled();
    expect(notices.map((n) => n['id']), [10000, 10001]);
    for (var i = 0; i < notices.length; i++) {
      final item = notices[i];
      final index = reflectionIndexForDate(DateTime(futureYear, 3, 1 + i));
      expect(item['title'], 'Reflexión diaria');
      expect(item['body'], 'Reflexión $index');
      expect(item['payload'], '$index');
      expect(item['timeZoneName'], 'Europe/Madrid');
      expect(item['scheduledDateTime'], endsWith('T09:00:00'));
      expect(
          (item['platformSpecifics'] as Map)['channelId'], 'daily_reflection');
      expect((item['platformSpecifics'] as Map)['scheduleMode'],
          'inexactAllowWhileIdle');
      expect(item.containsKey('matchDateTimeComponents'), isFalse);
    }
    expect(calls.any((c) => c.method.toLowerCase().contains('exactalarm')),
        isFalse);
  });

  test(
      'permission APIs use typed Android methods and open native notification settings',
      () async {
    enabled = false;
    requested = false;
    expect(await AchievementService.notificationsEnabled(), isFalse);
    expect(await AchievementService.requestNotificationPermission(), isFalse);
    enabled = true;
    requested = true;
    expect(await AchievementService.notificationsEnabled(), isTrue);
    expect(await AchievementService.requestNotificationPermission(), isTrue);
    await AchievementService.openNotificationSettings();
    expect(named('initialize'), hasLength(1));
    expect(named('areNotificationsEnabled'), hasLength(2));
    expect(named('requestNotificationsPermission'), hasLength(2));
    expect(named('openSettings'), hasLength(1));
    expect(named('requestPermission'), isEmpty);
  });

  test('unknown permission result never reports permission granted', () async {
    enabled = null;
    requested = null;
    await expectLater(
        AchievementService.notificationsEnabled(), throwsStateError);
    await expectLater(
        AchievementService.requestNotificationPermission(), throwsStateError);
  });

  test(
      'denied permission does not cancel old schedules or claim new scheduling succeeded',
      () async {
    pending[10000] = oldNotification(10000);
    enabled = false;
    await expectLater(
        AchievementService.scheduleDailyReflections(json), throwsStateError);
    expect(pending.keys, [10000]);
    expect(named('cancel'), isEmpty);
    expect(scheduled(), isEmpty);
    // The user can still turn the old schedules off while permission is denied.
    await AchievementService.cancelDailyReflections();
    expect(pending, isEmpty);
  });

  test(
      'missing or unrecognised timezone leaves previous alarms intact and can be retried',
      () async {
    pending[10000] = oldNotification(10000);
    zone = null;
    await expectLater(
        AchievementService.scheduleDailyReflections(json), throwsStateError);
    zone = 'Not/A_Real_Zone';
    await expectLater(
        AchievementService.scheduleDailyReflections(json), throwsStateError);
    expect(named('cancel'), isEmpty);
    expect(scheduled(), isEmpty);
    zone = 'Europe/Madrid';
    await AchievementService.scheduleDailyReflections(json, daysAhead: 1);
    expect(scheduled(), hasLength(1));
    zone = 'Atlantic/Canary';
    await AchievementService.scheduleDailyReflections(json, daysAhead: 1);
    expect(scheduled().last['timeZoneName'], 'Atlantic/Canary');
    expect(scheduled().last['scheduledDateTime'], endsWith('T09:00:00'));
  });

  test(
      'failed plugin initialization is propagated and retried before scheduling',
      () async {
    initResult = false;
    await expectLater(AchievementService.init(), throwsStateError);
    expect(scheduled(), isEmpty);
    initResult = true;
    await AchievementService.scheduleDailyReflections(json, daysAhead: 1);
    expect(named('initialize'), hasLength(2));
    expect(scheduled(), hasLength(1));
  });

  test(
      'invalid payload or out-of-range horizon is rejected before cancellation',
      () async {
    pending[10007] = oldNotification(10007);
    await expectLater(AchievementService.scheduleDailyReflections('[]'),
        throwsFormatException);
    await expectLater(
        AchievementService.scheduleDailyReflections(json, daysAhead: 1001),
        throwsArgumentError);
    expect(named('cancel'), isEmpty);
    expect(scheduled(), isEmpty);
    expect(pending.keys, [10007]);
  });

  test(
      'turning daily off removes every pending reserved ID from older horizons only',
      () async {
    for (final id in [7, 9999, 10000, 10060, 10999, 11000]) {
      pending[id] = oldNotification(id);
    }
    await AchievementService.cancelDailyReflections(daysAhead: 1);
    expect(named('cancel').map((c) => (c.arguments as Map)['id']),
        [10000, 10060, 10999]);
    expect(pending.keys, [7, 9999, 11000]);
  });

  test(
      'partial native schedule failure cancels attempted alarms including ambiguous failure',
      () async {
    scheduleFailure = 10001;
    await expectLater(
        AchievementService.scheduleDailyReflections(json, daysAhead: 3),
        throwsStateError);
    expect(scheduled().map((n) => n['id']), [10000, 10001]);
    expect(
        named('cancel').map((c) => (c.arguments as Map)['id']), [10000, 10001]);
    expect(pending, isEmpty);
    scheduleFailure = null;
    await AchievementService.scheduleDailyReflections(json, daysAhead: 1);
    expect(pending.keys, [10000]);
  });

  test(
      'compensation failure is reported, and a later explicit off can finish cleanup',
      () async {
    scheduleFailure = 10001;
    cancelFailures.add(10000);
    await expectLater(
        AchievementService.scheduleDailyReflections(json, daysAhead: 2),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('ni retirar'))));
    expect(pending.keys, [10000]);
    cancelFailures.clear();
    await AchievementService.cancelDailyReflections();
    expect(pending, isEmpty);
  });

  test(
      'schedule followed by off waits for scheduling and leaves no daily alarms',
      () async {
    scheduleWait = Completer<void>();
    scheduleStarted = Completer<void>();
    final scheduling =
        AchievementService.scheduleDailyReflections(json, daysAhead: 2);
    await scheduleStarted!.future;
    final turningOff = AchievementService.cancelDailyReflections();
    final milestonesOff = AchievementService.cancelMilestones();
    await Future<void>.delayed(Duration.zero);
    expect(named('pendingNotificationRequests'), hasLength(1));
    expect(named('cancel'), isEmpty);
    scheduleWait!.complete();
    await Future.wait([scheduling, turningOff, milestonesOff]);
    expect(pending, isEmpty);
    final lastSchedule = events.lastIndexOf('zonedSchedule');
    expect(events.lastIndexOf('pendingNotificationRequests'),
        greaterThan(lastSchedule));
  });

  test(
      'pending lookup and cancellation errors propagate without beginning replacement',
      () async {
    pending[10000] = oldNotification(10000);
    pending[10001] = oldNotification(10001);
    failPendingLookup = true;
    await expectLater(AchievementService.cancelDailyReflections(),
        throwsA(isA<PlatformException>()));
    failPendingLookup = false;
    cancelFailures.add(10000);
    await expectLater(
        AchievementService.scheduleDailyReflections(json, daysAhead: 1),
        throwsStateError);
    expect(scheduled(), isEmpty);
    expect(pending.keys, [10000]);
  });

  test('milestones retain their IDs and channel and use inexact scheduling',
      () async {
    await AchievementService.init();
    final start = tz.TZDateTime(tz.local, futureYear, 3, 1, 7);
    await AchievementService.scheduleMilestones(start);
    final notices = scheduled();
    expect(notices.map((n) => n['id']), AchievementService.milestones.keys);
    for (final n in notices) {
      expect(n['title'], 'Logro de recuperación');
      expect(n['body'], AchievementService.milestones[n['id']]);
      expect(n['payload'], '');
      expect((n['platformSpecifics'] as Map)['channelId'], 'achievements');
      expect((n['platformSpecifics'] as Map)['scheduleMode'],
          'inexactAllowWhileIdle');
    }
  });

  test(
      'cold launch details and a callback registered after lazy init remain available',
      () async {
    launch = {
      'notificationLaunchedApp': true,
      'notificationResponse': {
        'notificationId': 10004,
        'notificationResponseType': 0,
        'payload': '65'
      },
    };
    final details = await AchievementService.getLaunchDetails();
    expect(details?.didNotificationLaunchApp, isTrue);
    expect(details?.notificationResponse?.payload, '65');
    String? received;
    await AchievementService.init(
        onNotificationResponse: (r) => received = r.payload);
    final answered = Completer<void>();
    ServicesBinding.instance.channelBuffers.push(
        pluginChannel.name,
        const StandardMethodCodec().encodeMethodCall(const MethodCall(
          'didReceiveNotificationResponse',
          {
            'notificationId': 10004,
            'notificationResponseType': 0,
            'payload': '65'
          },
        )),
        (_) => answered.complete());
    await answered.future;
    expect(received, '65');
    expect(named('initialize'), hasLength(1));
  });
}
