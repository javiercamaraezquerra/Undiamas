import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:un_dia_mas/models/diary_entry.dart';
import 'package:un_dia_mas/services/app_lock_controller.dart';
import 'package:un_dia_mas/widgets/app_lock_gate.dart';
import 'package:un_dia_mas/widgets/mood_trend_chart.dart';

import 'app_lock_widgets_test.dart' show DeviceChallenge, MemoryPrivacy;

void main() {
  testWidgets(
      'chart detail respects privacy and cannot resurrect entries replaced while locked',
      (tester) async {
    final binding = tester.binding;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final semantics = tester.ensureSemantics();
    var semanticsDisposed = false;
    void disposeSemantics() {
      if (semanticsDisposed) return;
      semanticsDisposed = true;
      semantics.dispose();
    }

    addTearDown(disposeSemantics);
    final nativeCalls = <MethodCall>[];
    const privacyChannel = MethodChannel('undiamas/privacy');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(privacyChannel,
        (call) async {
      nativeCalls.add(call);
      return null;
    });
    addTearDown(() => binding.defaultBinaryMessenger
        .setMockMethodCallHandler(privacyChannel, null));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    final preferences = MemoryPrivacy(true);
    final authentication = DeviceChallenge();
    final lock = AppLockController(
        preferences: preferences, authenticator: authentication);
    addTearDown(lock.dispose);
    await lock.initialize();
    final now = DateTime(2026, 9, 10, 12);
    const removedText = 'Entrada ficticia eliminada: paseo por el parque.';
    const currentText = 'Entrada ficticia vigente: conversación de apoyo.';
    final original = DiaryEntry(
        createdAt: DateTime(2026, 9, 10, 10), mood: 3, text: removedText);
    final current = DiaryEntry(
        createdAt: original.createdAt, mood: original.mood, text: currentText);
    final entries = ValueNotifier<List<DiaryEntry>>([original]);
    addTearDown(entries.dispose);

    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => AppLockGate(controller: lock, child: child!),
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ValueListenableBuilder<List<DiaryEntry>>(
              valueListenable: entries,
              builder: (_, value, __) =>
                  MoodTrendChart(entries: value, now: () => now),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(authentication.attempts, 1);
    authentication.answer(true);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mood-view-entries')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mood-entry-0')));
    await tester.pumpAndSettle();
    expect(find.text(removedText), findsOneWidget);
    final closePosition = tester.getCenter(find.byTooltip('Cerrar'));

    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    expect(lock.covered, isTrue);
    expect(find.text(removedText), findsOneWidget,
        reason: 'The accepted Recents behavior keeps the last unlocked image.');
    expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(removedText))), findsNothing,
        reason:
            'The visible background snapshot must expose no private semantics.');
    await tester.tapAt(closePosition);
    await tester.pump();
    expect(find.text(removedText), findsOneWidget,
        reason:
            'Blocked background input must not close or operate the detail.');

    for (final state in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    expect(authentication.attempts, 2);
    expect(find.text(removedText), findsNothing);
    expect(find.byTooltip('Cerrar'), findsNothing);
    expect(find.bySemanticsLabel(RegExp(RegExp.escape(removedText))),
        findsNothing);
    authentication.answer(false);
    await tester.pumpAndSettle();
    expect(lock.covered, isTrue);
    expect(find.text('Desbloquear'), findsOneWidget);

    // A replacement can preserve the plotted date and mood while changing the
    // private text. Its old modal must not survive simply because the dot does.
    entries.value = [current];
    await tester.pumpAndSettle();
    expect(find.text(removedText), findsNothing);
    expect(find.text(currentText), findsNothing);
    expect(find.bySemanticsLabel(RegExp(RegExp.escape(currentText))),
        findsNothing);
    expect(authentication.attempts, 2,
        reason: 'Updating inventory must not trigger an authentication loop.');
    await tester.tap(find.text('Desbloquear'));
    await tester.pump();
    expect(authentication.attempts, 3);
    expect(find.text(currentText), findsNothing);
    authentication.answer(true);
    await tester.pumpAndSettle();
    expect(lock.covered, isFalse);
    expect(find.text(removedText, skipOffstage: false), findsNothing);
    await tester.tap(find.byKey(const Key('mood-view-entries')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mood-entry-0')));
    await tester.pumpAndSettle();
    expect(find.text(currentText), findsOneWidget);
    expect(find.text(removedText, skipOffstage: false), findsNothing);
    expect(entries.value.single, same(current));
    expect(current.text, currentText);
    expect(current.createdAt, original.createdAt);
    expect(current.mood, original.mood);
    expect(preferences.enabled, isTrue);
    expect(preferences.writes, isEmpty);
    if (nativeCalls.isNotEmpty) {
      expect(nativeCalls.last.method, 'setLocked');
      expect(nativeCalls.last.arguments, isFalse);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    disposeSemantics();
  });
}
