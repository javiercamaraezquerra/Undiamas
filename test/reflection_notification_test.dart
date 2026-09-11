import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:un_dia_mas/screens/reflection_screen.dart';
import 'package:un_dia_mas/services/notification_plan.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final raw = jsonEncode(List.generate(365,
      (index) => '### Reflexión $index\nTexto ficticio para la fecha $index.'));
  ByteData bytes() =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(raw)));

  setUp(() {
    rootBundle.clear();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  tearDown(() {
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    rootBundle.clear();
  });

  testWidgets(
      'notification payload opens the same indexed reflection as its title',
      (tester) async {
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (_) async => bytes());
    const index = 364;
    await tester
        .pumpWidget(const MaterialApp(home: ReflectionScreen(dayIndex: index)));
    await tester.pumpAndSettle();
    expect(find.text('Reflexión $index'), findsOneWidget);
    expect(find.textContaining('Texto ficticio para la fecha $index.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'resume before the first asset response does not read an uninitialized day',
      (tester) async {
    final pending = Completer<ByteData?>();
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (_) => pending.future);
    await tester.pumpWidget(const MaterialApp(home: ReflectionScreen()));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.takeException(), isNull);
    pending.complete(bytes());
    await tester.pumpAndSettle();
    expect(find.text('Reflexión ${reflectionIndexForDate(DateTime.now())}'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'closing during asset loading does not create a new midnight timer',
      (tester) async {
    final pending = Completer<ByteData?>();
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (_) => pending.future);
    await tester.pumpWidget(const MaterialApp(home: ReflectionScreen()));
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(bytes());
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    // Flutter's test teardown additionally rejects any still-pending Timer.
  });
}
