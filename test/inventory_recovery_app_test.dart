import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:un_dia_mas/widgets/inventory_recovery_app.dart';

void main() {
  const initialMessage =
      'La restauración no se ha completado. Inténtalo de nuevo.';

  testWidgets(
      'startup shows only the recovery screen and does not retry itself',
      (tester) async {
    var attempts = 0;
    var recovered = 0;
    await tester.pumpWidget(InventoryRecoveryApp(
      retry: () async {
        attempts++;
        return null;
      },
      onRecovered: () => recovered++,
      message: initialMessage,
    ));
    expect(find.text(initialMessage), findsOneWidget);
    expect(find.text('Recuperar el inventario'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    expect(attempts, 0);
    expect(recovered, 0);
  });

  testWidgets('returned failure stays covered and permits a later retry',
      (tester) async {
    var attempts = 0;
    var recovered = 0;
    await tester.pumpWidget(InventoryRecoveryApp(
      retry: () async {
        attempts++;
        return 'Todavía no se ha podido recuperar. Vuelve a intentarlo.';
      },
      onRecovered: () => recovered++,
      message: initialMessage,
    ));
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Todavía no se ha podido recuperar. Vuelve a intentarlo.'),
        findsOneWidget);
    expect(find.text('Recuperar el inventario'), findsOneWidget);
    expect(recovered, 0);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });

  testWidgets('double taps do not overlap and success is reported only once',
      (tester) async {
    final pending = Completer<String?>();
    var attempts = 0;
    var recovered = 0;
    await tester.pumpWidget(InventoryRecoveryApp(
      retry: () {
        attempts++;
        return pending.future;
      },
      onRecovered: () => recovered++,
      message: initialMessage,
    ));
    await tester.tap(find.text('Reintentar'));
    // No pump: the event handler itself must prevent a second request.
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(attempts, 1);
    expect(recovered, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    pending.complete(null);
    await tester.pump();
    await tester.pump();
    expect(recovered, 1);
    expect(find.text('Recuperar el inventario'), findsOneWidget);
    await tester.tap(find.text('Reintentando…'));
    await tester.pump(const Duration(seconds: 1));
    expect(attempts, 1);
    expect(recovered, 1);
    // The owner, not this screen, decides when to display the normal app.
    expect(find.byType(BottomNavigationBar), findsNothing);
  });

  testWidgets('retry exceptions show a safe error and allow another attempt',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(InventoryRecoveryApp(
      retry: () {
        attempts++;
        throw StateError('PRIVATE:path/key/content');
      },
      onRecovered: () => fail('A failed recovery must not open the app'),
      message: initialMessage,
    ));
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(
        find.text('No hemos podido recuperar el inventario. '
            'Puedes volver a intentarlo.'),
        findsOneWidget);
    expect(find.textContaining('PRIVATE'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });

  testWidgets(
      'an owner callback exception keeps the screen closed without repeats',
      (tester) async {
    var recovered = 0;
    await tester.pumpWidget(InventoryRecoveryApp(
      retry: () async => null,
      onRecovered: () {
        recovered++;
        throw StateError('PRIVATE:owner implementation');
      },
      message: initialMessage,
    ));
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(
        find.text('No hemos podido abrir la aplicación. '
            'Ciérrala y vuelve a abrirla.'),
        findsOneWidget);
    expect(find.textContaining('PRIVATE'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(recovered, 1);
  });

  testWidgets(
      'a pending retry can finish after disposal without invoking the owner',
      (tester) async {
    final pending = Completer<String?>();
    var recovered = 0;
    await tester.pumpWidget(InventoryRecoveryApp(
      retry: () => pending.future,
      onRecovered: () => recovered++,
      message: initialMessage,
    ));
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(null);
    await tester.pump();
    expect(recovered, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small display with large text keeps the retry button reachable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var attempts = 0;
    await tester.pumpWidget(InventoryRecoveryApp(
      retry: () async {
        attempts++;
        return initialMessage;
      },
      onRecovered: () {},
      message: initialMessage,
    ));
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(tester.takeException(), isNull);
  });
}
