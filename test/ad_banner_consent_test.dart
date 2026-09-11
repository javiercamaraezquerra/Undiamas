import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
// The plugin's own codec is needed to mock its native transport, never Google.
// ignore: implementation_imports
import 'package:google_mobile_ads/src/ad_instance_manager.dart';
import 'package:un_dia_mas/services/ad_consent_controller.dart';
import 'package:un_dia_mas/widgets/ad_banner.dart';

import 'ad_consent_controller_test.dart' show FakeAdConsentGateway;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('two banners wait for UMP, dispose on change, ignore late load',
      (tester) async {
    final previous = instanceManager;
    instanceManager = AdInstanceManager('plugins.flutter.io/google_mobile_ads');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(instanceManager.channel, (call) async {
      calls.add(call);
      return null;
    });
    final gateway = FakeAdConsentGateway()..sdkPending = Completer<void>();
    final signal = ValueNotifier(true);
    final controller = AdConsentController(
        gateway: gateway,
        canPresent: () => signal.value,
        presentationChanges: signal);
    await tester.pumpWidget(MaterialApp(
        home: Column(children: [
      AdBanner(adUnitId: 'fake-unit-one', consentController: controller),
      AdBanner(adUnitId: 'fake-unit-two', consentController: controller),
    ])));
    final initialize = controller.initialize();
    await tester.pump();
    expect(calls.where((c) => c.method == 'loadBannerAd'), isEmpty);
    gateway.sdkPending!.complete();
    await initialize;
    await tester.pump();
    final requests = calls.where((c) => c.method == 'loadBannerAd').toList();
    expect(requests.length, 2);
    expect(requests.map((c) => c.arguments['adUnitId']),
        ['fake-unit-one', 'fake-unit-two']);
    expect(gateway.calls.where((c) => c == 'sdk').length, 1);
    final oldBanner =
        instanceManager.adFor(requests.first.arguments['adId']) as BannerAd;

    // Opening/clicking a native ad temporarily pauses the Flutter activity.
    // Keep its Ad objects, do not dispose or submit replacement requests.
    controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await tester.pump();
    expect(controller.adsAllowed, isTrue);
    expect(controller.canLoadAds, isFalse);
    expect(calls.where((c) => c.method == 'disposeAd'), isEmpty);
    controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
    controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls.where((c) => c.method == 'loadBannerAd').length, 2);
    expect(calls.where((c) => c.method == 'disposeAd'), isEmpty);

    gateway.allowed = false;
    gateway.optionsPending = Completer<void>();
    final change = controller.showPrivacyOptions();
    await tester.pump();
    expect(calls.where((c) => c.method == 'disposeAd').length, 2);
    // Simulate a native completion delivered after revocation/disposal.
    oldBanner.listener.onAdLoaded!(oldBanner);
    await tester.pump();
    expect(find.byType(AdWidget), findsNothing);
    gateway.optionsPending!.complete();
    await change;
    await tester.pump();
    expect(calls.where((c) => c.method == 'loadBannerAd').length, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    signal.dispose();
    messenger.setMockMethodCallHandler(instanceManager.channel, null);
    instanceManager = previous;
  });
}
