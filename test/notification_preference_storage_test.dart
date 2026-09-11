import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:un_dia_mas/services/notification_preference_storage.dart';
import 'package:un_dia_mas/services/notification_preferences_controller.dart';
import 'package:un_dia_mas/services/notification_refresh.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  const key = 'notifyDailyReflection';
  late Map<String, Object> disk;
  late SharedPreferences preferences;
  var throwOnWrite = false;
  var failReads = false;
  var commitDespiteFailedResponse = false;

  setUp(() async {
    SharedPreferences.resetStatic();
    disk = {'flutter.$key': false, 'flutter.privacyAppLockEnabled': true};
    throwOnWrite = false;
    failReads = false;
    commitDespiteFailedResponse = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'getAll') {
        if (failReads) throw PlatformException(code: 'read_failed');
        return Map<String, Object>.from(disk);
      }
      if (call.method == 'setBool') {
        final arguments = Map<String, dynamic>.from(call.arguments as Map);
        final value = arguments['value'] as bool;
        expect(preferences.getBool(key), value,
            reason:
                'The real SharedPreferences cache has already changed before platform acknowledgement.');
        if (commitDespiteFailedResponse) {
          disk[arguments['key'] as String] = value;
        }
        if (throwOnWrite) throw PlatformException(code: 'write_failed');
        return false;
      }
      throw StateError('Unexpected preference platform call: ${call.method}');
    });
    preferences = await SharedPreferences.getInstance();
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    SharedPreferences.resetStatic();
  });

  for (final original in [false, true]) {
    for (final throws in [false, true]) {
      test(
          'failed write ${throws ? 'throws' : 'returns false'} from $original reloads disk before reporting failure',
          () async {
        disk['flutter.$key'] = original;
        await preferences.reload();
        throwOnWrite = throws;
        var schedules = 0;
        var cancellations = 0;
        final controller =
            NotificationsController(readPermission: () async => true);
        addTearDown(controller.dispose);
        final result = await controller.change(
          enable: !original,
          isCurrent: () => true,
          schedule: () async {
            schedules++;
          },
          cancel: () async {
            cancellations++;
          },
          persist: (value) =>
              persistNotificationPreference(preferences, key, value),
          runExclusive: (action) => action(),
        );
        expect(result, NotificationPreferenceResult.failed);
        expect(preferences.getBool(key), original);
        expect(disk['flutter.$key'], original);
        expect(preferences.getBool('privacyAppLockEnabled'), isTrue);
        expect(schedules, original ? 0 : 1);
        expect(cancellations, 1);
      });
    }
  }

  test(
      'ambiguous failed response re-reads the actual persisted value rather than inventing rollback',
      () async {
    commitDespiteFailedResponse = true;
    expect(
        await persistNotificationPreference(preferences, key, true), isFalse);
    expect(disk['flutter.$key'], isTrue);
    expect(preferences.getBool(key), isTrue,
        reason:
            'Profile can display the verified value even when the operation reports an error.');
  });

  test(
      'failed reload is propagated and foreground never schedules from the optimistic cache',
      () async {
    failReads = true;
    await expectLater(persistNotificationPreference(preferences, key, true),
        throwsA(isA<PlatformException>()));
    expect(preferences.getBool(key), isTrue,
        reason: 'This is the unverified plugin cache, not a persisted choice.');
    expect(disk['flutter.$key'], isFalse);
    var refreshes = 0;
    final errors = <Object>[];
    final coordinator = ForegroundNotificationRefresh(
      canRun: () => true,
      configurationKey: () async {
        await preferences.reload(); // The production main integration guard.
        return '${preferences.getBool(key)}';
      },
      refresh: () async {
        await preferences.reload(); // Rechecked inside the data operation too.
        if (preferences.getBool(key) == true) refreshes++;
      },
      onError: (error, _) => errors.add(error),
    );
    addTearDown(coordinator.dispose);
    coordinator.requestRefresh();
    await Future<void>.delayed(Duration.zero);
    expect(refreshes, 0);
    expect(errors, hasLength(1));
    failReads = false;
    coordinator.requestRefresh();
    await Future<void>.delayed(Duration.zero);
    expect(preferences.getBool(key), isFalse);
    expect(refreshes, 0);
  });

  test('second reload failure aborts refresh before any scheduling side effect',
      () async {
    var refreshes = 0;
    final errors = <Object>[];
    final coordinator = ForegroundNotificationRefresh(
      canRun: () => true,
      configurationKey: () async {
        await preferences.reload();
        failReads = true;
        return 'verified-before-lock';
      },
      refresh: () async {
        await preferences.reload();
        refreshes++;
      },
      onError: (error, _) => errors.add(error),
    );
    addTearDown(coordinator.dispose);
    coordinator.requestRefresh();
    await Future<void>.delayed(Duration.zero);
    expect(refreshes, 0);
    expect(errors, hasLength(1));
  });
}
