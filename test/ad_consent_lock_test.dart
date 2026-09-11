import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:un_dia_mas/services/ad_consent_controller.dart';
import 'package:un_dia_mas/services/app_lock_controller.dart';
import 'package:un_dia_mas/widgets/app_lock_gate.dart';

import 'ad_consent_controller_test.dart' show FakeAdConsentGateway;
import 'app_lock_widgets_test.dart' show DeviceChallenge, MemoryPrivacy;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'UMP close after resume defers PIN and never unlocks private data',
      (tester) async {
    final auth = DeviceChallenge();
    final lock = AppLockController(
        preferences: MemoryPrivacy(true), authenticator: auth);
    await lock.initialize();
    final gateway = FakeAdConsentGateway()..formPending = Completer<void>();
    final consent = AdConsentController(
      gateway: gateway,
      canPresent: () =>
          !lock.covered && !lock.authenticating && !lock.changingSetting,
      presentationChanges: lock,
    );
    var privateTaps = 0;
    await tester.pumpWidget(MaterialApp(
      home: AppLockGate(
        controller: lock,
        nativeModalChanges: consent,
        nativeModalVisible: () => consent.formVisible,
        child: TextButton(
            onPressed: () => privateTaps++,
            child: const Text('Entrada privada ficticia')),
      ),
    ));
    await tester.pump();
    expect(auth.attempts, 1);
    auth.answer(true);
    await tester.pump();
    expect(find.text('Entrada privada ficticia'), findsOneWidget);
    final initialization = consent.initialize();
    await tester.pump();
    expect(consent.formVisible, isTrue);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed
    ]) {
      binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    expect(auth.attempts, 1,
        reason: 'Native UMP form must finish before a new PIN');
    expect(lock.covered, isTrue);
    expect(find.text('Entrada privada ficticia'), findsNothing);
    expect(find.text('Desbloquear'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.ancestor(
      of: find.text('Desbloquear'),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    ));
    expect(button.onPressed, isNull);
    expect(privateTaps, 0);

    // Cancelling/failing the native form releases only the presentation slot.
    gateway.allowed = false;
    gateway.formPending!.completeError(StateError('Cancelación ficticia'));
    await initialization;
    await tester.pump();
    await tester.pump();
    expect(consent.formVisible, isFalse);
    expect(auth.attempts, 2);
    expect(lock.covered, isTrue);
    expect(consent.adsAllowed, isFalse);
    auth.answer(false);
    await tester.pump();
    expect(find.text('Entrada privada ficticia'), findsNothing);
    expect(lock.covered, isTrue);
    expect(privateTaps, 0);
    await tester.tap(find.text('Desbloquear'));
    await tester.pump();
    auth.answer(true);
    await tester.pump();
    expect(find.text('Entrada privada ficticia'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    consent.dispose();
    lock.dispose();
    expect(tester.takeException(), isNull);
  });
}
