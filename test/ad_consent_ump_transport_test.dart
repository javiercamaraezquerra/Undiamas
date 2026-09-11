import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
// The plugin codec faithfully mocks native responses without making requests.
// ignore: implementation_imports
import 'package:google_mobile_ads/src/ad_instance_manager.dart';
import 'package:un_dia_mas/services/ad_consent_controller.dart';

class _ConsentInformation extends ConsentInformation {
  _ConsentInformation(this.calls);
  final List<String> calls;
  bool allowed = true;
  bool updateFails = false;
  ConsentRequestParameters? parameters;
  @override
  void requestConsentInfoUpdate(
      ConsentRequestParameters params,
      OnConsentInfoUpdateSuccessListener successListener,
      OnConsentInfoUpdateFailureListener failureListener) {
    parameters = params;
    calls.add('info');
    if (updateFails) {
      failureListener(FormError(errorCode: 2, message: 'Error ficticio'));
    } else {
      successListener();
    }
  }

  @override
  Future<bool> canRequestAds() async {
    calls.add('canRequestAds');
    return allowed;
  }

  @override
  Future<PrivacyOptionsRequirementStatus>
      getPrivacyOptionsRequirementStatus() async =>
          PrivacyOptionsRequirementStatus.required;
  @override
  Future<ConsentStatus> getConsentStatus() async => ConsentStatus.obtained;
  @override
  Future<bool> isConsentFormAvailable() async => true;
  @override
  Future<void> reset() async =>
      throw StateError('Production must never reset consent');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ump = MethodChannel('plugins.flutter.io/google_mobile_ads/ump');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ConsentInformation previousInfo;
  late AdInstanceManager previousManager;
  late _ConsentInformation information;
  late AdConsentController controller;
  late ValueNotifier<bool> signal;
  late List<String> calls;
  var formFails = false;
  Completer<void>? formReply;

  setUp(() {
    calls = [];
    formFails = false;
    formReply = null;
    previousInfo = ConsentInformation.instance;
    information = _ConsentInformation(calls);
    ConsentInformation.instance = information;
    previousManager = instanceManager;
    instanceManager = AdInstanceManager('plugins.flutter.io/google_mobile_ads');
    messenger.setMockMethodCallHandler(ump, (call) async {
      calls.add(call.method);
      if (formFails) {
        throw PlatformException(code: '3', message: 'Fallo ficticio');
      }
      if (formReply != null) await formReply!.future;
      return null;
    });
    messenger.setMockMethodCallHandler(instanceManager.channel, (call) async {
      calls.add(call.method);
      if (call.method == 'MobileAds#initialize') {
        return InitializationStatus({});
      }
      return null;
    });
    signal = ValueNotifier(true);
    controller = AdConsentController(
        canPresent: () => signal.value, presentationChanges: signal);
  });
  tearDown(() {
    controller.dispose();
    signal.dispose();
    messenger.setMockMethodCallHandler(ump, null);
    messenger.setMockMethodCallHandler(instanceManager.channel, null);
    ConsentInformation.instance = previousInfo;
    instanceManager = previousManager;
  });

  test('uses supported UMP APIs without debug geography or consent reset',
      () async {
    await controller.initialize();
    expect(calls, [
      'info',
      'UserMessagingPlatform#loadAndShowConsentFormIfRequired',
      'canRequestAds',
      '_init',
      'MobileAds#initialize'
    ]);
    expect(information.parameters!.consentDebugSettings, isNull);
    expect(controller.adsAllowed, isTrue);
    information.allowed = false;
    expect(await controller.showPrivacyOptions(), isTrue);
    expect(calls, contains('UserMessagingPlatform#showPrivacyOptionsForm'));
    expect(controller.adsAllowed, isFalse);
    expect(calls.where((call) => call == 'MobileAds#initialize').length, 1);
  });

  test('native form PlatformException is handled and does not initialize ads',
      () async {
    formFails = true;
    information.allowed = false;
    await controller.initialize();
    expect(controller.adsAllowed, isFalse);
    expect(controller.busy, isFalse);
    expect(controller.formVisible, isFalse);
    expect(calls, isNot(contains('MobileAds#initialize')));
  });

  test('native info failure reads current UMP permission and respects false',
      () async {
    information.updateFails = true;
    information.allowed = false;
    await controller.initialize();
    expect(calls, ['info', 'canRequestAds']);
    expect(controller.adsAllowed, isFalse);
    expect(controller.privacyOptionsRequired, isTrue);
  });

  test(
      'native info error still permits ads when UMP reports prior valid consent',
      () async {
    information.updateFails = true;
    await controller.initialize();
    expect(controller.adsAllowed, isTrue);
    expect(calls, contains('canRequestAds'));
    expect(calls, contains('MobileAds#initialize'));
    expect(
        calls,
        isNot(contains(
            'UserMessagingPlatform#loadAndShowConsentFormIfRequired')));
  });

  test('both form Futures hold presentation until native dismissal reply',
      () async {
    formReply = Completer<void>();
    final initial = controller.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(calls,
        contains('UserMessagingPlatform#loadAndShowConsentFormIfRequired'));
    expect(controller.formVisible, isTrue);
    expect(controller.busy, isTrue);
    expect(calls, isNot(contains('canRequestAds')));
    formReply!.complete();
    await initial;
    expect(controller.formVisible, isFalse);

    formReply = Completer<void>();
    final options = controller.showPrivacyOptions();
    await Future<void>.delayed(Duration.zero);
    expect(calls, contains('UserMessagingPlatform#showPrivacyOptionsForm'));
    expect(controller.formVisible, isTrue);
    expect(controller.adsAllowed, isFalse);
    formReply!.complete();
    expect(await options, isTrue);
    expect(controller.formVisible, isFalse);
  });
}
