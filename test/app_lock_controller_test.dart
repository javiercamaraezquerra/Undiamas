import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:un_dia_mas/services/app_lock_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Preferences preferences;
  late _Authenticator authenticator;
  late AppLockController controller;

  setUp(() {
    preferences = _Preferences();
    authenticator = _Authenticator();
    controller = AppLockController(
        preferences: preferences, authenticator: authenticator);
  });
  tearDown(() => controller.dispose());

  Future<void> protectedSession({bool unlock = false}) async {
    preferences.value = true;
    await controller.initialize();
    if (unlock) await controller.unlock();
  }

  test('first use remains covered until the missing preference is read',
      () async {
    expect(controller.covered, true);
    await controller.initialize();
    expect(controller.initialized, true);
    expect(controller.enabled, false);
    expect(controller.covered, false);
    expect(preferences.writes, isEmpty);
    expect(authenticator.calls, 0);
  });

  test(
      'a persisted enabled preference starts locked without launching a prompt',
      () async {
    await protectedSession();
    expect(controller.locked, true);
    expect(controller.covered, true);
    expect(authenticator.calls, 0);
    expect(preferences.writes, isEmpty);
  });

  test(
      'concurrent initialization reads once and respects the current lifecycle',
      () async {
    final read = Completer<bool?>();
    preferences.read = () => read.future;
    final first = controller.initialize();
    final second = controller.initialize();
    controller.handleLifecycle(AppLifecycleState.paused);
    read.complete(true);
    await Future.wait([first, second]);
    expect(preferences.reads, 1);
    expect(controller.covered, true);
    expect(controller.obscured, true);
    expect(controller.locked, true);
  });

  test('read failure stays covered and an explicit retry can recover',
      () async {
    preferences.read = () async => throw StateError('fixture read failure');
    await controller.initialize();
    expect(controller.initialized, false);
    expect(controller.covered, true);
    expect(controller.message, contains('leer'));
    expect(await controller.setEnabled(false), false);
    await controller.unlock();
    expect(authenticator.calls, 0);
    preferences.read = () async => true;
    await controller.initialize();
    expect(controller.initialized, true);
    expect(controller.enabled, true);
    expect(controller.covered, true);
    expect(preferences.writes, isEmpty);
  });

  test('a device without a supported lock cannot activate protection',
      () async {
    await controller.initialize();
    authenticator.supported = false;
    expect(await controller.setEnabled(true), false);
    expect(controller.enabled, false);
    expect(controller.message, contains('PIN'));
    expect(authenticator.calls, 0);
    expect(preferences.writes, isEmpty);
  });

  test('canceling activation leaves the preference unchanged', () async {
    await controller.initialize();
    authenticator.challenge = () async => false;
    expect(await controller.setEnabled(true), false);
    expect(controller.enabled, false);
    expect(controller.changingSetting, false);
    expect(controller.authenticating, false);
    expect(preferences.writes, isEmpty);
  });

  test('activation cannot persist before authentication succeeds', () async {
    await controller.initialize();
    final entered = Completer<void>();
    final challenge = Completer<bool>();
    authenticator.challenge = () {
      entered.complete();
      return challenge.future;
    };
    final activating = controller.setEnabled(true);
    await entered.future;
    expect(controller.changingSetting, true);
    expect(controller.authenticating, true);
    expect(controller.enabled, false);
    expect(preferences.writes, isEmpty);
    expect(await controller.setEnabled(true), false);
    challenge.complete(true);
    expect(await activating, true);
    expect(preferences.writes, [true]);
    expect(controller.enabled, true);
    expect(controller.covered, false);
  });

  test(
      'disabling also needs authentication and cancellation leaves it protected',
      () async {
    await protectedSession(unlock: true);
    authenticator.challenge = () async => false;
    expect(await controller.setEnabled(false), false);
    expect(authenticator.calls, 2);
    expect(controller.enabled, true);
    expect(controller.covered, true);
    expect(preferences.writes, isEmpty);
  });

  test('authenticated disabling persists only the disabled preference',
      () async {
    await protectedSession();
    expect(await controller.setEnabled(false), true);
    expect(authenticator.calls, 1);
    expect(authenticator.reasons.single, contains('desactivar'));
    expect(preferences.writes, [false]);
    expect(controller.enabled, false);
    expect(controller.covered, false);
  });

  for (final errorCode in [
    'PasscodeNotSet',
    'NotEnrolled',
    'LockedOut',
    'PermanentlyLockedOut',
    'NotAvailable',
    'fixture_unknown_error',
  ]) {
    test('$errorCode keeps protected content closed and permits a manual retry',
        () async {
      await protectedSession();
      authenticator.challenge = () async => throw PlatformException(
          code: errorCode, message: 'Sensitive native fixture text');
      await controller.unlock();
      expect(controller.covered, true);
      expect(controller.authenticating, false);
      expect(controller.message, isNotEmpty);
      expect(controller.message, isNot(contains('Sensitive')));
      expect(preferences.writes, isEmpty);
      authenticator.challenge = () async => true;
      await controller.unlock();
      expect(controller.covered, false);
    });
  }

  test(
      'duplicate unlock and preference requests share no overlapping challenge',
      () async {
    await protectedSession();
    final entered = Completer<void>();
    final challenge = Completer<bool>();
    authenticator.challenge = () {
      entered.complete();
      return challenge.future;
    };
    final unlocking = controller.unlock();
    await entered.future;
    await controller.unlock();
    expect(await controller.setEnabled(false), false);
    expect(authenticator.calls, 1);
    expect(controller.covered, true);
    challenge.complete(true);
    await unlocking;
    expect(controller.covered, false);
  });

  test('inactive covers briefly without relocking an authenticated session',
      () async {
    await protectedSession(unlock: true);
    controller.handleLifecycle(AppLifecycleState.inactive);
    expect(controller.covered, true);
    expect(controller.obscured, true);
    expect(controller.locked, false);
    controller.handleLifecycle(AppLifecycleState.resumed);
    expect(controller.covered, false);
    expect(authenticator.calls, 1);
  });

  for (final state in [AppLifecycleState.hidden, AppLifecycleState.paused]) {
    test('$state relocks but lifecycle events never launch a prompt', () async {
      await protectedSession(unlock: true);
      controller.handleLifecycle(state);
      controller.handleLifecycle(AppLifecycleState.resumed);
      controller.handleLifecycle(state);
      controller.handleLifecycle(AppLifecycleState.resumed);
      expect(controller.covered, true);
      expect(controller.locked, true);
      expect(authenticator.calls, 1);
    });
  }

  test(
      'external PIN lifecycle preserves the sticky attempt without a second one',
      () async {
    await protectedSession();
    final entered = Completer<void>();
    final challenge = Completer<bool>();
    authenticator.challenge = () {
      entered.complete();
      return challenge.future;
    };
    final unlocking = controller.unlock();
    await entered.future;
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.resumed,
    ]) {
      controller.handleLifecycle(state);
      await controller.unlock();
      expect(controller.authenticating, true);
      expect(controller.covered, true);
    }
    expect(authenticator.calls, 1);
    challenge.complete(true);
    await unlocking;
    expect(controller.covered, false);
    expect(authenticator.calls, 1);
  });

  for (final success in [true, false]) {
    test('native PIN result $success survives the complete return lifecycle',
        () async {
      await protectedSession();
      final entered = Completer<void>();
      final challenge = Completer<bool>();
      authenticator.challenge = () {
        entered.complete();
        return challenge.future;
      };
      final unlocking = controller.unlock();
      await entered.future;
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        controller.handleLifecycle(state);
      }
      challenge.complete(success);
      await unlocking;
      expect(controller.covered, true);
      expect(controller.authenticating, false);
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
      ]) {
        controller.handleLifecycle(state);
        expect(controller.covered, true);
        expect(controller.locked, !success,
            reason: 'Returning through hidden must preserve the PIN result.');
        expect(authenticator.calls, 1);
      }
      controller.handleLifecycle(AppLifecycleState.resumed);
      expect(controller.covered, !success);
      expect(authenticator.calls, 1);
    });
  }

  test('leaving after authentication while persistence is pending relocks',
      () async {
    await controller.initialize();
    final writing = Completer<void>();
    final commit = Completer<bool>();
    preferences.write = (_) {
      writing.complete();
      return commit.future;
    };
    final activating = controller.setEnabled(true);
    await writing.future;
    expect(controller.authenticating, false);
    expect(controller.changingSetting, true);
    controller.handleLifecycle(AppLifecycleState.paused);
    commit.complete(true);
    expect(await activating, true);
    controller.handleLifecycle(AppLifecycleState.resumed);
    expect(controller.enabled, true);
    expect(controller.covered, true);
  });

  for (final initialEnabled in [true, false]) {
    test('failed persistence preserves the previous setting $initialEnabled',
        () async {
      preferences.value = initialEnabled;
      await controller.initialize();
      preferences.write = (_) async => preferences.writes.length > 1;
      expect(await controller.setEnabled(!initialEnabled), false);
      expect(preferences.writes, [!initialEnabled, initialEnabled]);
      expect(preferences.value, initialEnabled);
      expect(controller.enabled, initialEnabled);
      expect(controller.covered, initialEnabled);
      expect(controller.message, contains('guardar'));
      expect(controller.changingSetting, false);
    });
  }

  test('failing both commit and rollback does not open a protected session',
      () async {
    await protectedSession(unlock: true);
    preferences.write = (_) async => throw StateError('fixture disk failure');
    expect(await controller.setEnabled(false), false);
    expect(controller.enabled, true);
    expect(controller.covered, true);
    expect(controller.message, contains('sigue activado'));
  });

  test('default preferences use only the new privacy key', () async {
    SharedPreferences.setMockInitialValues({
      'notifyDailyReflection': true,
      'autoBackup': true,
      'fav_resources': ['fixture-resource'],
    });
    final local = AppLockController(authenticator: authenticator);
    addTearDown(local.dispose);
    await local.initialize();
    expect(await local.setEnabled(true), true);
    final stored = await SharedPreferences.getInstance();
    expect(stored.getKeys(), {
      'notifyDailyReflection',
      'autoBackup',
      'fav_resources',
      AppLockController.preferenceKey,
    });
    expect(stored.getStringList('fav_resources'), ['fixture-resource']);
    expect(stored.getBool(AppLockController.preferenceKey), true);
    expect(await local.setEnabled(false), true);
    expect(stored.getBool(AppLockController.preferenceKey), false);
    expect(stored.getBool('autoBackup'), true);
  });

  test('malformed stored preference cannot silently disable protection',
      () async {
    SharedPreferences.setMockInitialValues({
      AppLockController.preferenceKey: 'invalid fixture type',
    });
    final local = AppLockController(authenticator: authenticator);
    addTearDown(local.dispose);
    await local.initialize();
    expect(local.initialized, false);
    expect(local.covered, true);
    expect(authenticator.calls, 0);
  });
}

class _Preferences implements AppLockPreferences {
  bool? value;
  int reads = 0;
  final writes = <bool>[];
  Future<bool?> Function()? read;
  Future<bool> Function(bool)? write;
  @override
  Future<bool?> readEnabled() async {
    reads++;
    return read == null ? value : await read!();
  }

  @override
  Future<bool> writeEnabled(bool enabled) async {
    writes.add(enabled);
    value = enabled; // Model SharedPreferences updating its in-memory cache.
    return write == null ? true : await write!(enabled);
  }
}

class _Authenticator implements AppLockAuthenticator {
  bool supported = true;
  int calls = 0;
  final reasons = <String>[];
  Future<bool> Function()? challenge;
  @override
  Future<bool> isDeviceSupported() async => supported;
  @override
  Future<bool> authenticate({required String reason}) async {
    calls++;
    reasons.add(reason);
    return challenge == null ? true : await challenge!();
  }
}
