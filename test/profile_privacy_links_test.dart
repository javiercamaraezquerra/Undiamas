import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:un_dia_mas/services/ad_consent_controller.dart';
import 'package:un_dia_mas/services/app_lock_controller.dart';
import 'package:un_dia_mas/widgets/profile_privacy_links.dart';

class _Consent extends AdConsentController {
  _Consent() : super(canPresent: () => true);
  bool requiredOptions = false;
  bool working = false;
  String? failure;
  Object? thrown;
  Completer<bool>? pending;
  int calls = 0;
  int starts = 0;

  @override
  bool get privacyOptionsRequired => requiredOptions;
  @override
  bool get busy => working;
  @override
  String? get message => failure;
  @override
  Future<void> initialize() async {
    starts++;
  }

  @override
  Future<bool> showPrivacyOptions() async {
    calls++;
    if (thrown != null) throw thrown!;
    return pending == null ? true : await pending!.future;
  }

  void change({bool? requiredOptions, bool? working}) {
    if (requiredOptions != null) this.requiredOptions = requiredOptions;
    if (working != null) this.working = working;
    notifyListeners();
  }
}

class _Preferences implements AppLockPreferences {
  bool? enabled;
  @override
  Future<bool?> readEnabled() async => enabled;
  @override
  Future<bool> writeEnabled(bool value) async {
    enabled = value;
    return true;
  }
}

class _Authentication implements AppLockAuthenticator {
  Completer<bool>? pending;
  @override
  Future<bool> isDeviceSupported() async => true;
  @override
  Future<bool> authenticate({required String reason}) async =>
      pending == null ? true : await pending!.future;
}

void main() {
  final policy = Uri.parse('https://example.org/privacy-policy');
  late _Consent consent;
  late AppLockController lock;
  late _Authentication authentication;
  setUp(() async {
    consent = _Consent();
    authentication = _Authentication();
    lock = AppLockController(
        preferences: _Preferences(), authenticator: authentication);
    await lock.initialize();
  });
  tearDown(() {
    consent.dispose();
    lock.dispose();
  });

  Widget app(
          {Future<bool> Function(Uri)? launch,
          double scale = 1,
          bool dark = false}) =>
      MaterialApp(
          theme: ThemeData(
              useMaterial3: true,
              brightness: dark ? Brightness.dark : Brightness.light),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: ProfilePrivacyLinks(
                      foreground: dark ? Colors.white : Colors.black,
                      policyUri: policy,
                      consentController: consent,
                      appLock: lock,
                      openPolicy: launch ?? (_) async => true))));

  testWidgets(
      'policy always visible, advertising entry follows requirement without initializing UMP',
      (tester) async {
    await tester.pumpWidget(app());
    expect(find.text('Política de privacidad'), findsOneWidget);
    expect(find.text('Privacidad de anuncios'), findsNothing);
    consent.change(requiredOptions: true);
    await tester.pump();
    expect(find.text('Privacidad de anuncios'), findsOneWidget);
    consent.change(requiredOptions: false);
    await tester.pump();
    expect(find.text('Privacidad de anuncios'), findsNothing);
    expect(consent.starts, 0);
  });

  testWidgets(
      'policy opens exact supplied URL once and reports unsuccessful launch',
      (tester) async {
    final pending = Completer<bool>();
    final launches = <Uri>[];
    await tester.pumpWidget(app(launch: (uri) {
      launches.add(uri);
      return pending.future;
    }));
    await tester.tap(find.text('Política de privacidad'));
    await tester.tap(find.text('Política de privacidad'));
    await tester.pump();
    expect(launches, [policy]);
    expect(find.text('Abriendo…'), findsOneWidget);
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudo abrir la política'), findsOneWidget);
    expect(consent.calls, 0);
  });

  testWidgets('policy launch exception shows safe error and permits retry',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(app(launch: (_) async {
      calls++;
      throw StateError('internal detail');
    }));
    await tester.tap(find.text('Política de privacidad'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudo abrir la política'), findsOneWidget);
    expect(find.textContaining('internal detail'), findsNothing);
    await tester.tap(find.text('Política de privacidad'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets(
      'advertising form is single flight and false reports controller error',
      (tester) async {
    consent.requiredOptions = true;
    consent.pending = Completer<bool>();
    consent.failure =
        'No se pudo actualizar el consentimiento. Inténtalo de nuevo.';
    await tester.pumpWidget(app());
    await tester.tap(find.text('Privacidad de anuncios'));
    await tester.tap(find.text('Privacidad de anuncios'));
    await tester.pump();
    expect(consent.calls, 1);
    expect(
        tester
            .widget<ListTile>(
                find.byKey(const ValueKey('profile-privacy-policy')))
            .onTap,
        isNull);
    consent.pending!.complete(false);
    await tester.pumpAndSettle();
    expect(find.text(consent.failure!), findsOneWidget);
    expect(find.textContaining('actualizado correctamente'), findsNothing);
  });

  testWidgets(
      'controller exception is contained without exposing internal details',
      (tester) async {
    consent.requiredOptions = true;
    consent.thrown = StateError('internal UMP token');
    await tester.pumpWidget(app());
    await tester.tap(find.text('Privacidad de anuncios'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudieron abrir las opciones'),
        findsOneWidget);
    expect(find.textContaining('internal UMP token'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('busy or background or locked session cannot launch options',
      (tester) async {
    consent.requiredOptions = true;
    consent.working = true;
    await tester.pumpWidget(app());
    await tester.tap(find.text('Privacidad de anuncios'));
    expect(consent.calls, 0);
    consent.change(working: false);
    lock.handleLifecycle(AppLifecycleState.paused);
    await tester.pump();
    await tester.tap(find.text('Privacidad de anuncios'));
    expect(consent.calls, 0);
    lock.handleLifecycle(AppLifecycleState.resumed);
    await lock.setEnabled(true);
    lock.handleLifecycle(AppLifecycleState.paused);
    lock.handleLifecycle(AppLifecycleState.resumed);
    await tester.pump();
    await tester.tap(find.text('Privacidad de anuncios'));
    expect(consent.calls, 0);
    await lock.unlock();
    await tester.pump();
    await tester.tap(find.text('Privacidad de anuncios'));
    await tester.pumpAndSettle();
    expect(consent.calls, 1);
  });

  testWidgets('activating app lock cannot launch another privacy surface',
      (tester) async {
    consent.requiredOptions = true;
    authentication.pending = Completer<bool>();
    var policyCalls = 0;
    await tester.pumpWidget(app(launch: (_) async {
      policyCalls++;
      return true;
    }));
    final activation = lock.setEnabled(true);
    await tester.pump();
    expect(lock.changingSetting, isTrue);
    await tester.tap(find.text('Privacidad de anuncios'));
    await tester.tap(find.text('Política de privacidad'));
    expect(consent.calls, 0);
    expect(policyCalls, 0);
    authentication.pending!.complete(false);
    await activation;
    await tester.pumpAndSettle();
  });

  for (final advertising in [false, true]) {
    testWidgets(
        'completion after dispose is harmless for ${advertising ? 'consent' : 'policy'}',
        (tester) async {
      final pending = Completer<bool>();
      consent.requiredOptions = true;
      consent.pending = pending;
      await tester.pumpWidget(app(launch: (_) => pending.future));
      await tester.tap(find.text(
          advertising ? 'Privacidad de anuncios' : 'Política de privacidad'));
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final dark in [false, true]) {
    testWidgets(
        'privacy links fit 320px at 200 percent ${dark ? 'dark' : 'light'}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      consent.requiredOptions = true;
      await tester.pumpWidget(app(scale: 2, dark: dark));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Privacidad de anuncios'));
      await tester.pumpAndSettle();
      expect(consent.calls, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
