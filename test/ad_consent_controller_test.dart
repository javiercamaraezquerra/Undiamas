import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:un_dia_mas/services/ad_consent_controller.dart';

class FakeAdConsentGateway implements AdConsentGateway {
  final calls = <String>[];
  bool allowed = true;
  bool required = true;
  String? failAt;
  Completer<void>? updatePending;
  Completer<void>? formPending;
  Completer<void>? optionsPending;
  Completer<void>? sdkPending;

  Future<void> _call(String name, [Completer<void>? pending]) async {
    calls.add(name);
    if (failAt == name) throw StateError('Fallo ficticio');
    if (pending != null) await pending.future;
  }

  @override
  Future<void> updateConsentInfo() => _call('update', updatePending);
  @override
  Future<void> showRequiredForm() => _call('form', formPending);
  @override
  Future<void> showPrivacyOptions() => _call('options', optionsPending);
  @override
  Future<void> initializeAds() => _call('sdk', sdkPending);
  @override
  Future<bool> canRequestAds() async {
    await _call('allowed');
    return allowed;
  }

  @override
  Future<bool> privacyOptionsRequired() async {
    await _call('required');
    return required;
  }
}

Future<void> flushConsent() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.value();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeAdConsentGateway gateway;
  late ValueNotifier<bool> unlocked;
  late AdConsentController controller;

  setUp(() {
    gateway = FakeAdConsentGateway();
    unlocked = ValueNotifier(true);
    controller = AdConsentController(
      gateway: gateway,
      canPresent: () => unlocked.value,
      presentationChanges: unlocked,
    );
  });
  tearDown(() {
    controller.dispose();
    unlocked.dispose();
  });

  test('coalesces startup and initializes SDK only after UMP approval',
      () async {
    gateway.updatePending = Completer<void>();
    final first = controller.initialize();
    final second = controller.initialize();
    expect(identical(first, second), isTrue);
    await flushConsent();
    expect(gateway.calls, ['update']);
    expect(controller.adsAllowed, isFalse);
    gateway.updatePending!.complete();
    await first;
    expect(gateway.calls,
        ['update', 'required', 'form', 'required', 'allowed', 'sdk']);
    expect(controller.adsAllowed, isTrue);
    expect(controller.busy, isFalse);
    await controller.initialize();
    expect(gateway.calls.where((v) => v == 'update').length, 1);
  });

  test('waits while locked, then checks lock again after info update',
      () async {
    unlocked.value = false;
    gateway.updatePending = Completer<void>();
    final done = controller.initialize();
    await flushConsent();
    expect(gateway.calls, isEmpty);
    unlocked.value = true;
    await flushConsent();
    expect(gateway.calls, ['update']);
    unlocked.value = false;
    gateway.updatePending!.complete();
    await flushConsent();
    expect(gateway.calls, ['update', 'required']);
    expect(controller.formVisible, isFalse);
    unlocked.value = true;
    await done;
    expect(controller.adsAllowed, isTrue);
  });

  test('UMP not allowed does not initialize advertising SDK', () async {
    gateway.allowed = false;
    await controller.initialize();
    expect(controller.adsAllowed, isFalse);
    expect(gateway.calls, isNot(contains('sdk')));
    expect(controller.privacyOptionsRequired, isTrue);
  });

  for (final failure in ['allowed', 'sdk']) {
    test('$failure error completes without enabling ads or blocking app',
        () async {
      gateway.failAt = failure;
      await controller.initialize();
      expect(controller.adsAllowed, isFalse);
      expect(controller.busy, isFalse);
      expect(controller.formVisible, isFalse);
      expect(controller.message, contains('sin anuncios'));
    });
  }

  for (final failure in ['update', 'form']) {
    for (final previousAllowed in [false, true]) {
      test('$failure error obeys native canRequestAds=$previousAllowed',
          () async {
        gateway.failAt = failure;
        gateway.allowed = previousAllowed;
        await controller.initialize();
        expect(controller.adsAllowed, previousAllowed);
        expect(controller.busy, isFalse);
        expect(controller.formVisible, isFalse);
        expect(gateway.calls, contains('allowed'));
        expect(gateway.calls.contains('sdk'), previousAllowed);
        if (failure == 'update') {
          expect(gateway.calls, isNot(contains('form')));
        }
      });
    }
  }

  test(
      'privacy change revokes eligibility before native form and coalesces SDK',
      () async {
    await controller.initialize();
    gateway.optionsPending = Completer<void>();
    final change = controller.showPrivacyOptions();
    expect(controller.adsAllowed, isFalse);
    expect(controller.busy, isTrue);
    expect(await controller.showPrivacyOptions(), isFalse);
    await flushConsent();
    expect(controller.formVisible, isTrue);
    gateway.allowed = false;
    gateway.optionsPending!.complete();
    expect(await change, isTrue);
    expect(controller.adsAllowed, isFalse);
    expect(gateway.calls.where((v) => v == 'options').length, 1);
    gateway.optionsPending = null;
    gateway.allowed = true;
    expect(await controller.showPrivacyOptions(), isTrue);
    expect(controller.adsAllowed, isTrue);
    expect(gateway.calls.where((v) => v == 'sdk').length, 1);
  });

  test('privacy form error leaves no old ads and offers retry', () async {
    await controller.initialize();
    gateway.failAt = 'options';
    gateway.allowed = false;
    expect(await controller.showPrivacyOptions(), isFalse);
    expect(controller.adsAllowed, isFalse);
    expect(controller.privacyOptionsRequired, isTrue);
    expect(controller.formVisible, isFalse);
    gateway.failAt = null;
    gateway.allowed = true;
    expect(await controller.showPrivacyOptions(), isTrue);
    expect(controller.adsAllowed, isTrue);
  });

  test('does not open privacy options while locked or if not required',
      () async {
    gateway.required = false;
    await controller.initialize();
    expect(await controller.showPrivacyOptions(), isFalse);
    expect(gateway.calls, isNot(contains('options')));
    unlocked.value = false;
    expect(controller.adsAllowed, isTrue);
    expect(controller.canLoadAds, isFalse);
    expect(await controller.showPrivacyOptions(), isFalse);
  });

  test('background hides ads and prevents opening a native form', () async {
    controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
    controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    final done = controller.initialize();
    await flushConsent();
    expect(gateway.calls, isEmpty);
    controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
    controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(gateway.calls, isEmpty);
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await done;
    expect(controller.adsAllowed, isTrue);
    controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(controller.adsAllowed, isTrue);
    expect(controller.canLoadAds, isFalse);
  });

  test('a failed SDK Future is cleared so explicit options can retry',
      () async {
    gateway.failAt = 'sdk';
    await controller.initialize();
    expect(controller.adsAllowed, isFalse);
    expect(gateway.calls.where((c) => c == 'sdk').length, 1);
    gateway.failAt = null;
    expect(await controller.showPrivacyOptions(), isTrue);
    expect(controller.adsAllowed, isTrue);
    expect(gateway.calls.where((c) => c == 'sdk').length, 2);
    await controller.showPrivacyOptions();
    expect(gateway.calls.where((c) => c == 'sdk').length, 2);
  });

  Future<void> backgroundAndResume() async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed
    ]) {
      controller.didChangeAppLifecycleState(state);
    }
    await flushConsent();
  }

  test('one silent resume retry recovers missing entry point without a popup',
      () async {
    gateway.required = false;
    gateway.allowed = false;
    gateway.failAt = 'update';
    await controller.initialize();
    expect(controller.adsAllowed, isFalse);
    gateway.failAt = null;
    gateway.allowed = true;
    unlocked.value = false;
    await backgroundAndResume();
    expect(gateway.calls.where((c) => c == 'update').length, 1);
    unlocked.value = true;
    await flushConsent();
    expect(controller.adsAllowed, isTrue);
    expect(gateway.calls.where((c) => c == 'update').length, 2);
    expect(gateway.calls, isNot(contains('form')));
    await backgroundAndResume();
    expect(gateway.calls.where((c) => c == 'update').length, 2);
  });

  test('failed silent retry does not loop and a normal denial is never retried',
      () async {
    gateway.required = false;
    gateway.allowed = false;
    gateway.failAt = 'update';
    await controller.initialize();
    await backgroundAndResume();
    await backgroundAndResume();
    expect(gateway.calls.where((c) => c == 'update').length, 2);
    expect(gateway.calls, isNot(contains('form')));
    expect(controller.adsAllowed, isFalse);

    final otherGateway = FakeAdConsentGateway()
      ..allowed = false
      ..required = false;
    final other = AdConsentController(
        gateway: otherGateway,
        canPresent: () => unlocked.value,
        presentationChanges: unlocked);
    await other.initialize();
    other.didChangeAppLifecycleState(AppLifecycleState.hidden);
    other.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await flushConsent();
    expect(otherGateway.calls.where((c) => c == 'update').length, 1);
    other.dispose();
  });

  test('disposed waiter completes without presenting anything', () async {
    final state = ValueNotifier(false);
    final other = AdConsentController(
        gateway: gateway,
        canPresent: () => state.value,
        presentationChanges: state);
    final done = other.initialize();
    other.dispose();
    await done;
    expect(gateway.calls, isEmpty);
    state.dispose();
  });

  test('late SDK result cannot revive a disposed controller', () async {
    final state = ValueNotifier(true);
    final other = AdConsentController(
        gateway: gateway,
        canPresent: () => state.value,
        presentationChanges: state);
    gateway.sdkPending = Completer<void>();
    final done = other.initialize();
    await flushConsent();
    expect(gateway.calls, contains('sdk'));
    other.dispose();
    gateway.sdkPending!.complete();
    await done;
    expect(other.adsAllowed, isFalse);
    state.dispose();
  });
}
