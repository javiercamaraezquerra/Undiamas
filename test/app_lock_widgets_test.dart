import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:un_dia_mas/services/app_lock_controller.dart';
import 'package:un_dia_mas/widgets/app_lock_gate.dart';
import 'package:un_dia_mas/widgets/app_lock_tile.dart';

class MemoryPrivacy implements AppLockPreferences {
  MemoryPrivacy(this.enabled);
  bool? enabled;
  bool readFails = false;
  final writes = <bool>[];
  @override
  Future<bool?> readEnabled() async {
    if (readFails) throw StateError('Read failed');
    return enabled;
  }

  @override
  Future<bool> writeEnabled(bool value) async {
    writes.add(value);
    enabled = value;
    return true;
  }
}

class DeviceChallenge implements AppLockAuthenticator {
  int attempts = 0;
  bool supported = true;
  Completer<bool>? pending;
  @override
  Future<bool> isDeviceSupported() async => supported;
  @override
  Future<bool> authenticate({required String reason}) {
    attempts++;
    pending = Completer<bool>();
    return pending!.future;
  }

  void answer(bool success) => pending!.complete(success);
}

class DraftScreen extends StatefulWidget {
  const DraftScreen({super.key});
  @override
  State<DraftScreen> createState() => _DraftScreenState();
}

class _DraftScreenState extends State<DraftScreen> {
  final editor = TextEditingController();
  @override
  void dispose() {
    editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          const Text('Contenido privado'),
          TextField(controller: editor),
          TextButton(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                        body: Center(child: Text('Ruta privada'))))),
            child: const Text('Abrir ruta'),
          ),
        ]),
      );
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final nativeCalls = <MethodCall>[];
  void moveLifecycle(AppLifecycleState target) {
    const states = [
      AppLifecycleState.resumed,
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused
    ];
    var current =
        states.indexOf(binding.lifecycleState ?? AppLifecycleState.resumed);
    final end = states.indexOf(target);
    if (current < 0) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      current = 0;
    }
    while (current != end) {
      current += current < end ? 1 : -1;
      binding.handleAppLifecycleStateChanged(states[current]);
    }
  }

  setUp(() async {
    nativeCalls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('undiamas/privacy'),
      (call) async {
        nativeCalls.add(call);
        return null;
      },
    );
    moveLifecycle(AppLifecycleState.resumed);
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('undiamas/privacy'), null);
  });

  Future<void> mountGate(WidgetTester tester, AppLockController lock) async {
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => AppLockGate(controller: lock, child: child!),
      home: const DraftScreen(),
    ));
    await tester.pump();
  }

  testWidgets('disabled opens normally and never requests authentication',
      (tester) async {
    final auth = DeviceChallenge();
    final lock = AppLockController(
        preferences: MemoryPrivacy(false), authenticator: auth);
    await lock.initialize();
    await mountGate(tester, lock);
    expect(find.text('Contenido privado'), findsOneWidget);
    moveLifecycle(AppLifecycleState.paused);
    await tester.pump();
    moveLifecycle(AppLifecycleState.resumed);
    await tester.pump();
    expect(auth.attempts, 0);
    expect(find.text('Contenido privado'), findsOneWidget);
    expect(nativeCalls.every((call) => call.method == 'setLocked'), isTrue);
  });

  testWidgets(
      'cold start hides every route until native success; cancel does not loop',
      (tester) async {
    final auth = DeviceChallenge();
    final lock = AppLockController(
        preferences: MemoryPrivacy(true), authenticator: auth);
    await lock.initialize();
    await mountGate(tester, lock);
    expect(auth.attempts, 1);
    expect(find.byType(DraftScreen, skipOffstage: false), findsNothing);
    auth.answer(false);
    await tester.pumpAndSettle();
    expect(find.text('Contenido privado'), findsNothing);
    expect(find.text('Desbloquear'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(auth.attempts, 1);
    await tester.tap(find.text('Desbloquear'));
    await tester.pump();
    expect(auth.attempts, 2);
    auth.answer(true);
    await tester.pumpAndSettle();
    expect(find.text('Contenido privado'), findsOneWidget);
    expect(nativeCalls.last.method, 'setLocked');
    expect(nativeCalls.last.arguments, false);
  });

  testWidgets('reopening relocks and preserves an unsaved form',
      (tester) async {
    final auth = DeviceChallenge();
    final lock = AppLockController(
        preferences: MemoryPrivacy(true), authenticator: auth);
    await lock.initialize();
    await mountGate(tester, lock);
    auth.answer(true);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Mi borrador de prueba');
    final editorBefore =
        tester.widget<TextField>(find.byType(TextField)).controller;
    moveLifecycle(AppLifecycleState.inactive);
    moveLifecycle(AppLifecycleState.hidden);
    moveLifecycle(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('Mi borrador de prueba'), findsOneWidget,
        reason:
            'The last authenticated screen stays available for normal Recents.');
    expect(lock.locked, isTrue);
    await tester.tap(find.text('Abrir ruta'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Ruta privada'), findsNothing,
        reason: 'Visible background content must not accept input.');
    moveLifecycle(AppLifecycleState.resumed);
    await tester.pump();
    expect(auth.attempts, 2);
    expect(find.text('Contenido privado'), findsNothing);
    auth.answer(true);
    await tester.pumpAndSettle();
    final editorAfter =
        tester.widget<TextField>(find.byType(TextField)).controller;
    expect(identical(editorBefore, editorAfter), isTrue);
    expect(editorAfter!.text, 'Mi borrador de prueba');
  });

  testWidgets(
      'covers secondary routes; native PIN activity does not cause a second prompt',
      (tester) async {
    final auth = DeviceChallenge();
    final lock = AppLockController(
        preferences: MemoryPrivacy(true), authenticator: auth);
    await lock.initialize();
    await mountGate(tester, lock);
    moveLifecycle(AppLifecycleState.inactive);
    moveLifecycle(AppLifecycleState.paused);
    auth.answer(true);
    await tester.pump();
    expect(find.text('Contenido privado'), findsNothing);
    moveLifecycle(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(auth.attempts, 1);
    await tester.tap(find.text('Abrir ruta'));
    await tester.pumpAndSettle();
    expect(find.text('Ruta privada'), findsOneWidget);
    moveLifecycle(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('Ruta privada'), findsOneWidget);
    moveLifecycle(AppLifecycleState.resumed);
    await tester.pump();
    auth.answer(true);
    await tester.pumpAndSettle();
    expect(find.text('Ruta privada'), findsOneWidget);
  });

  testWidgets(
      'temporary inactive keeps the normal snapshot without restarting the session',
      (tester) async {
    final auth = DeviceChallenge();
    final lock = AppLockController(
        preferences: MemoryPrivacy(true), authenticator: auth);
    await lock.initialize();
    await mountGate(tester, lock);
    auth.answer(true);
    await tester.pumpAndSettle();
    moveLifecycle(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Contenido privado'), findsOneWidget);
    moveLifecycle(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Contenido privado'), findsOneWidget);
    expect(auth.attempts, 1);
  });

  testWidgets(
      'cancelled external PIN returns to the lock without an automatic retry',
      (tester) async {
    final auth = DeviceChallenge();
    final lock = AppLockController(
        preferences: MemoryPrivacy(true), authenticator: auth);
    await lock.initialize();
    await mountGate(tester, lock);
    moveLifecycle(AppLifecycleState.paused);
    auth.answer(false);
    await tester.pump();
    moveLifecycle(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(auth.attempts, 1);
    expect(find.text('Contenido privado'), findsNothing);
    expect(find.text('Desbloquear'), findsOneWidget);
  });

  testWidgets('startup waits until the app is actually resumed',
      (tester) async {
    final auth = DeviceChallenge();
    final lock = AppLockController(
        preferences: MemoryPrivacy(true), authenticator: auth);
    await lock.initialize();
    moveLifecycle(AppLifecycleState.inactive);
    await mountGate(tester, lock);
    expect(auth.attempts, 0);
    expect(find.text('Contenido privado'), findsNothing);
    moveLifecycle(AppLifecycleState.resumed);
    await tester.pump();
    expect(auth.attempts, 1);
    auth.answer(true);
    await tester.pumpAndSettle();
    expect(find.text('Contenido privado'), findsOneWidget);
  });

  testWidgets(
      'leaving a rejected lock never uncovers an old authenticated screen',
      (tester) async {
    final auth = DeviceChallenge();
    final lock = AppLockController(
        preferences: MemoryPrivacy(true), authenticator: auth);
    await lock.initialize();
    await mountGate(tester, lock);
    auth.answer(true);
    await tester.pumpAndSettle();
    moveLifecycle(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('Contenido privado'), findsOneWidget);
    moveLifecycle(AppLifecycleState.resumed);
    await tester.pump();
    auth.answer(false);
    await tester.pumpAndSettle();
    expect(find.text('Contenido privado'), findsNothing);
    moveLifecycle(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('Contenido privado'), findsNothing);
    expect(find.text('Desbloquear'), findsOneWidget);
    expect(nativeCalls.every((call) => call.method == 'setLocked'), isTrue);
  });

  testWidgets('unreadable preference stays covered and offers retry',
      (tester) async {
    final prefs = MemoryPrivacy(true)..readFails = true;
    final auth = DeviceChallenge();
    final lock = AppLockController(preferences: prefs, authenticator: auth);
    await lock.initialize();
    await mountGate(tester, lock);
    expect(find.text('Contenido privado'), findsNothing);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(auth.attempts, 0);
    prefs.readFails = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    auth.answer(true);
    await tester.pumpAndSettle();
    expect(find.text('Contenido privado'), findsOneWidget);
  });

  testWidgets(
      'profile explains before enabling; cancel keeps preference unchanged',
      (tester) async {
    final prefs = MemoryPrivacy(false);
    final auth = DeviceChallenge();
    final lock = AppLockController(preferences: prefs, authenticator: auth);
    await lock.initialize();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: AppLockTile(foreground: Colors.black, controller: lock),
    )));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.textContaining('no tendrás que crear otro código'),
        findsOneWidget);
    expect(find.textContaining('capturas'), findsNothing);
    expect(find.textContaining('aplicaciones recientes'), findsNothing);
    expect(auth.attempts, 0);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(prefs.writes, isEmpty);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets(
      'switch updates only after native success; turning off requests verification',
      (tester) async {
    final prefs = MemoryPrivacy(false);
    final auth = DeviceChallenge();
    final lock = AppLockController(preferences: prefs, authenticator: auth);
    await lock.initialize();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: AppLockTile(foreground: Colors.black, controller: lock),
    )));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(prefs.writes, isEmpty);
    auth.answer(true);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(auth.attempts, 2);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    auth.answer(true);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(prefs.writes, [true, false]);
  });

  testWidgets('explanation remains usable on small screens with large text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final lock = AppLockController(
        preferences: MemoryPrivacy(false), authenticator: DeviceChallenge());
    await lock.initialize();
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.7)),
          child: child!),
      home: Scaffold(
          body: AppLockTile(foreground: Colors.black, controller: lock)),
    ));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Continuar'), findsOneWidget);
  });
}
