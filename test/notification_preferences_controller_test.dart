import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:un_dia_mas/services/notification_preferences_controller.dart';

void main() {
  Future<NotificationPreferenceResult> change(
    NotificationsController controller,
    List<String> events, {
    bool enable = true,
    bool Function()? isCurrent,
    Future<void> Function()? schedule,
    Future<void> Function()? cancel,
    Future<bool> Function(bool)? persist,
  }) =>
      controller.change(
        enable: enable,
        isCurrent: isCurrent ?? () => true,
        schedule: schedule ?? () async => events.add('schedule'),
        cancel: cancel ?? () async => events.add('cancel'),
        persist: persist ??
            (value) async {
              events.add('persist:$value');
              return true;
            },
        runExclusive: (action) async {
          events.add('lock');
          await action();
        },
      );

  test('denial never schedules or changes preference, settings remain explicit',
      () async {
    final events = <String>[];
    final controller = NotificationsController(
      readPermission: () async => false,
      requestPermission: () async {
        events.add('request');
        return false;
      },
      openSettings: () async => events.add('settings'),
    );
    addTearDown(controller.dispose);
    expect(
        await change(controller, events), NotificationPreferenceResult.denied);
    expect(events, ['request']);
    expect(controller.systemEnabled, isFalse);
    expect(controller.busy, isFalse);
    await controller.openSettings();
    expect(events, ['request', 'settings']);
  });

  test('permission grant schedules before persisting enabled', () async {
    final events = <String>[];
    var allowed = false;
    final controller = NotificationsController(
      readPermission: () async => allowed,
      requestPermission: () async {
        events.add('request');
        allowed = true;
        return true;
      },
      openSettings: () async {},
    );
    addTearDown(controller.dispose);
    expect(
        await change(controller, events), NotificationPreferenceResult.applied);
    expect(events, ['request', 'lock', 'schedule', 'persist:true']);
    expect(controller.systemEnabled, isTrue);
  });

  test('permission read error is not treated as permission granted', () async {
    final events = <String>[];
    final controller = NotificationsController(
      readPermission: () async => throw StateError('Unavailable'),
      requestPermission: () async {
        events.add('request');
        return true;
      },
      openSettings: () async {},
    );
    addTearDown(controller.dispose);
    expect(
        await change(controller, events), NotificationPreferenceResult.failed);
    expect(events, isEmpty);
  });

  test('partial schedule failure cancels leftovers and never persists true',
      () async {
    final events = <String>[];
    final controller = NotificationsController(
      readPermission: () async => true,
      requestPermission: () async => true,
      openSettings: () async {},
    );
    addTearDown(controller.dispose);
    expect(
      await change(controller, events, schedule: () async {
        events.add('partial schedule');
        throw StateError('One alarm failed');
      }),
      NotificationPreferenceResult.failed,
    );
    expect(events, ['lock', 'partial schedule', 'cancel']);
  });

  test('turning off needs no permission and persists false only after cancel',
      () async {
    final events = <String>[];
    final controller = NotificationsController(
      readPermission: () async => throw StateError('Must not check'),
      requestPermission: () async => throw StateError('Must not request'),
      openSettings: () async {},
    );
    addTearDown(controller.dispose);
    expect(await change(controller, events, enable: false),
        NotificationPreferenceResult.applied);
    expect(events, ['lock', 'cancel', 'persist:false']);
    events.clear();
    expect(
        await change(controller, events,
            enable: false,
            cancel: () async => throw StateError('Cancel failed')),
        NotificationPreferenceResult.failed);
    expect(events, ['lock']);
  });

  test('preference persistence failure reports failure and cancels new alarms',
      () async {
    final events = <String>[];
    final controller = NotificationsController(
      readPermission: () async => true,
      requestPermission: () async => true,
      openSettings: () async {},
    );
    addTearDown(controller.dispose);
    expect(await change(controller, events, persist: (_) async => false),
        NotificationPreferenceResult.failed);
    expect(events, ['lock', 'schedule', 'cancel']);
  });

  test('second tap does not start a second permission or scheduling operation',
      () async {
    final permission = Completer<bool>();
    final events = <String>[];
    final controller = NotificationsController(
      readPermission: () => permission.future,
      requestPermission: () async => true,
      openSettings: () async {},
    );
    addTearDown(controller.dispose);
    final first = change(controller, events);
    expect(controller.busy, isTrue);
    expect(await change(controller, events), NotificationPreferenceResult.busy);
    permission.complete(true);
    expect(await first, NotificationPreferenceResult.applied);
    expect(events, ['lock', 'schedule', 'persist:true']);
  });

  test('old generation or removed screen cancels before scheduling', () async {
    final permission = Completer<bool>();
    final events = <String>[];
    var current = true;
    final controller = NotificationsController(
      readPermission: () => permission.future,
      requestPermission: () async => true,
      openSettings: () async {},
    );
    addTearDown(controller.dispose);
    final pending = change(controller, events, isCurrent: () => current);
    current = false;
    permission.complete(true);
    expect(await pending, NotificationPreferenceResult.cancelled);
    expect(events, isEmpty);
  });

  test('settings return refreshes real permission without altering any choice',
      () async {
    var allowed = false;
    var requests = 0;
    final controller = NotificationsController(
      readPermission: () async => allowed,
      requestPermission: () async {
        requests++;
        return allowed;
      },
      openSettings: () async {},
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.systemEnabled, isFalse);
    allowed = true;
    await controller.refresh();
    expect(controller.systemEnabled, isTrue);
    expect(requests, 0);
  });

  test('older status read cannot overwrite a newer permission refresh',
      () async {
    final oldRead = Completer<bool>();
    var calls = 0;
    final controller = NotificationsController(
      readPermission: () => ++calls == 1 ? oldRead.future : Future.value(true),
      requestPermission: () async => true,
      openSettings: () async {},
    );
    addTearDown(controller.dispose);
    final pending = controller.refresh();
    await controller.refresh();
    oldRead.complete(false);
    await pending;
    expect(controller.systemEnabled, isTrue);
  });
}
