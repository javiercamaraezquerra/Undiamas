import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:un_dia_mas/services/notification_refresh.dart';

Future<void> drain() => Future<void>.delayed(Duration.zero);

void main() {
  test(
      'a blocked request waits for privacy/data and plain state events never create work',
      () async {
    var allowed = false;
    var keyReads = 0;
    var refreshed = 0;
    final coordinator = ForegroundNotificationRefresh(
      canRun: () => allowed,
      configurationKey: () async {
        keyReads++;
        return 'day1/Madrid';
      },
      refresh: () async {
        refreshed++;
      },
    );
    coordinator.onStateChanged();
    coordinator.requestRefresh();
    coordinator.requestRefresh();
    await drain();
    expect(keyReads, 0);
    expect(refreshed, 0);
    allowed = true;
    coordinator.onStateChanged();
    await drain();
    expect(keyReads, 1);
    expect(refreshed, 1);
    coordinator.onStateChanged();
    await drain();
    expect(keyReads, 1);
    coordinator.dispose();
  });

  test('rechecks availability after awaiting the configuration key', () async {
    var allowed = true;
    var reads = 0;
    var refreshed = 0;
    final key = Completer<String>();
    final coordinator = ForegroundNotificationRefresh(
      canRun: () => allowed,
      configurationKey: () {
        reads++;
        return reads == 1 ? key.future : Future.value('key');
      },
      refresh: () async {
        refreshed++;
      },
    );
    coordinator.requestRefresh();
    allowed = false;
    key.complete('key');
    await drain();
    expect(refreshed, 0);
    expect(reads, 1);
    allowed = true;
    coordinator.onStateChanged();
    await drain();
    expect(refreshed, 1);
    expect(reads, 2);
    coordinator.dispose();
  });

  test(
      'coalesces requests during refresh and never runs two refreshes together',
      () async {
    var reads = 0;
    var refreshed = 0;
    var concurrent = 0;
    var maximum = 0;
    final done = Completer<void>();
    final coordinator = ForegroundNotificationRefresh(
      canRun: () => true,
      configurationKey: () async {
        reads++;
        return 'same';
      },
      refresh: () async {
        refreshed++;
        concurrent++;
        if (concurrent > maximum) maximum = concurrent;
        await done.future;
        concurrent--;
      },
    );
    coordinator.requestRefresh();
    await drain();
    for (var i = 0; i < 20; i++) {
      coordinator.requestRefresh();
      coordinator.onStateChanged();
    }
    expect(refreshed, 1);
    done.complete();
    await drain();
    expect(reads, 2);
    expect(refreshed, 1);
    expect(maximum, 1);
    coordinator.dispose();
  });

  test('same day/key is cached; date, timezone and settings changes refresh',
      () async {
    var key = '2026-09-10/Madrid/on';
    var count = 0;
    final coordinator = ForegroundNotificationRefresh(
      canRun: () => true,
      configurationKey: () async => key,
      refresh: () async {
        count++;
      },
    );
    coordinator.requestRefresh();
    await drain();
    coordinator.requestRefresh();
    await drain();
    expect(count, 1);
    for (final next in [
      '2026-09-11/Madrid/on',
      '2026-09-11/London/on',
      '2026-09-11/London/off'
    ]) {
      key = next;
      coordinator.requestRefresh();
      await drain();
    }
    expect(count, 4);
    coordinator.dispose();
  });

  test('a newer key requested during refresh is applied once after it finishes',
      () async {
    var key = 'old';
    var calls = 0;
    final first = Completer<void>();
    final coordinator = ForegroundNotificationRefresh(
      canRun: () => true,
      configurationKey: () async => key,
      refresh: () async {
        calls++;
        if (calls == 1) await first.future;
      },
    );
    coordinator.requestRefresh();
    await drain();
    key = 'new';
    coordinator.requestRefresh();
    coordinator.requestRefresh();
    first.complete();
    await drain();
    expect(calls, 2);
    coordinator.dispose();
  });

  for (final failingPart in ['key', 'refresh']) {
    test('$failingPart failure is not cached and retries only on a new request',
        () async {
      var fail = true;
      var reads = 0;
      var refreshes = 0;
      final errors = <Object>[];
      final coordinator = ForegroundNotificationRefresh(
        canRun: () => true,
        configurationKey: () async {
          reads++;
          if (fail && failingPart == 'key') throw StateError('key failed');
          return 'same';
        },
        refresh: () async {
          refreshes++;
          if (fail && failingPart == 'refresh') {
            throw StateError('refresh failed');
          }
        },
        onError: (error, _) => errors.add(error),
      );
      coordinator.requestRefresh();
      await drain();
      coordinator.onStateChanged();
      coordinator.onStateChanged();
      await drain();
      expect(errors, hasLength(1));
      expect(reads, 1);
      fail = false;
      coordinator.requestRefresh();
      await drain();
      expect(reads, 2);
      expect(refreshes, failingPart == 'key' ? 1 : 2);
      coordinator.requestRefresh();
      await drain();
      expect(refreshes, failingPart == 'key' ? 1 : 2);
      coordinator.dispose();
    });
  }

  test('a failed replacement invalidates the previously successful key too',
      () async {
    var key = 'A';
    final attempted = <String>[];
    final coordinator = ForegroundNotificationRefresh(
      canRun: () => true,
      configurationKey: () async => key,
      refresh: () async {
        attempted.add(key);
        if (key == 'B') throw StateError('Old alarms cancelled before failure');
      },
    );
    coordinator.requestRefresh();
    await drain();
    key = 'B';
    coordinator.requestRefresh();
    await drain();
    key = 'A';
    coordinator.requestRefresh();
    await drain();
    expect(attempted, ['A', 'B', 'A']);
    coordinator.dispose();
  });

  test('dispose during configuration suppresses refresh and later requests',
      () async {
    final key = Completer<String>();
    var refreshes = 0;
    final coordinator = ForegroundNotificationRefresh(
      canRun: () => true,
      configurationKey: () => key.future,
      refresh: () async {
        refreshes++;
      },
    );
    coordinator.requestRefresh();
    coordinator.dispose();
    key.complete('key');
    await drain();
    coordinator.requestRefresh();
    coordinator.onStateChanged();
    await drain();
    expect(refreshes, 0);
  });

  test('dispose during refresh suppresses queued work and error callback',
      () async {
    final refresh = Completer<void>();
    var reads = 0;
    final errors = <Object>[];
    final coordinator = ForegroundNotificationRefresh(
      canRun: () => true,
      configurationKey: () async {
        reads++;
        return 'key';
      },
      refresh: () => refresh.future,
      onError: (error, _) => errors.add(error),
    );
    coordinator.requestRefresh();
    await drain();
    coordinator.requestRefresh();
    coordinator.dispose();
    refresh.completeError(StateError('platform failed after disposal'));
    await drain();
    expect(errors, isEmpty);
    expect(reads, 1);
  });
}
