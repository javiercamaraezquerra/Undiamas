import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/diary_entry.dart';
import 'models/post.dart';
import 'screens/onboarding_screen.dart';
import 'screens/reflection_screen.dart';
import 'services/achievement_service.dart';
import 'services/encryption_service.dart';
import 'theme/app_theme.dart';
import 'widgets/bottom_nav_bar.dart';

final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);
final _navKey       = GlobalKey<NavigatorState>(debugLabel: 'root_nav');

/// Muestra la ayuda MIUI una sola vez
const bool _showMiuiHelp = true;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /* ── Hive (cifrado) ───────────────────────────────────────────── */
  await Hive.initFlutter();
  Hive.registerAdapter(DiaryEntryAdapter());
  Hive.registerAdapter(PostAdapter());

  final cipher = await EncryptionService.getCipher();

  // Migraciones (cajas sin cifrar → cifradas)
  if (await Hive.boxExists('udm')) {
    final p = await Hive.openBox('udm');
    final s = await Hive.openBox('udm_secure', encryptionCipher: cipher);
    if (s.isEmpty) await s.putAll(p.toMap());
    await p.deleteFromDisk();
  }
  final settings = await Hive.openBox('udm_secure', encryptionCipher: cipher);

  if (await Hive.boxExists('diary')) {
    final p = await Hive.openBox<DiaryEntry>('diary');
    final s = await Hive.openBox<DiaryEntry>('diary_secure',
        encryptionCipher: cipher);
    if (s.isEmpty) await s.addAll(p.values);
    await p.deleteFromDisk();
  }

  /* ── Ads ──────────────────────────────────────────────────────── */
  await MobileAds.instance.initialize();
  await MobileAds.instance.updateRequestConfiguration(
    RequestConfiguration(testDeviceIds: ['TEST_DEVICE_ID']),
  );

  /* ── Notificaciones (init + deep‑link) ───────────────────────── */
  try {
    await AchievementService.init(onNotificationResponse: (resp) {
      final idx = int.tryParse(resp.payload ?? '');
      if (idx != null) {
        _navKey.currentState?.push(
          MaterialPageRoute(builder: (_) => ReflectionScreen(dayIndex: idx)),
        );
      }
    });
  } catch (e, s) {
    debugPrint('Init notifications error: $e\n$s');
  }

  /* ── Preferencias / tema ─────────────────────────────────────── */
  Intl.defaultLocale = 'es_ES';
  final prefs = await SharedPreferences.getInstance();
  themeNotifier.value =
      (prefs.getBool('isDarkMode') ?? false) ? ThemeMode.dark : ThemeMode.light;

  final hasStartDate = settings.containsKey('startDate');
  runApp(UnDiaMasApp(showOnboarding: !hasStartDate));

  /* ── Diálogos de permisos + MIUI + programación ──────────────── */
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final ctx = _navKey.currentContext;
    if (ctx == null) return;

    final androidImpl = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    /* 1 · POST_NOTIFICATIONS (Android 13+) ─ runtime permission */
    bool notifAllowed = true;
    try {
      notifAllowed =
          await (androidImpl as dynamic)?.areNotificationsEnabled() ?? true;
    } catch (_) {}

    if (!notifAllowed && ctx.mounted) {
      final granted = await (androidImpl as dynamic)?.requestPermission() ?? false;

      if (!granted && ctx.mounted) {
        await showDialog(
          context: ctx,
          builder: (_) => AlertDialog(
            title: const Text('Permiso de notificaciones'),
            content: const Text(
              'Sin este permiso la app no podrá enviarte avisos. '
              'Ábrelo en Ajustes > Notificaciones y actívalo manualmente.',
              textAlign: TextAlign.justify,
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cerrar')),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  (androidImpl as dynamic)?.openNotificationSettings();
                },
                child: const Text('Abrir ajustes'),
              ),
            ],
          ),
        );
      }
    }

    /* 2 · SCHEDULE_EXACT_ALARM (Android 12+) */
    bool exactAllowed = true;
    try {
      exactAllowed =
          await (androidImpl as dynamic)?.hasExactAlarmPermission() ?? true;
    } catch (_) {}

    if (!exactAllowed && ctx.mounted) {
      final grant = await (androidImpl as dynamic)
              ?.requestExactAlarmsPermission() ??
          false;
      if (!grant && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
            content: Text('No se pudo otorgar “Alarmas exactas”.')));
      }
    }

    /* 3 · Ayuda MIUI (inicio automático) */
    if (_showMiuiHelp &&
        Platform.isAndroid &&
        (await _isMiui()) &&
        !(prefs.getBool('miuiHelpShown') ?? false) &&
        ctx.mounted) {
      await showDialog(
        context: ctx,
        builder: (_) => AlertDialog(
          title: const Text('Permiso de inicio automático'),
          content: const Text(
            'Para que las notificaciones se muestren con la pantalla apagada '
            'MIUI debe permitir que la app se inicie automáticamente en segundo plano.',
            textAlign: TextAlign.justify,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Omitir'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await openMiuiAutoStartSettings();
              },
              child: const Text('Abrir ajustes'),
            ),
          ],
        ),
      );
      await prefs.setBool('miuiHelpShown', true);
    }

    /* 4 · Programar notificaciones si procede */
    final milestonesOn = prefs.getBool('notifyMilestones') ?? true;
    final reflectionOn = prefs.getBool('notifyDailyReflection') ?? true;

    try {
      if (milestonesOn && hasStartDate) {
        final start = DateTime.parse(settings.get('startDate'));
        await AchievementService.scheduleMilestones(start);
      }
      if (reflectionOn) {
        final json =
            await rootBundle.loadString('assets/data/reflections.json');
        await AchievementService.scheduleDailyReflections(json);
      }
    } catch (e) {
      debugPrint('Schedule notifications error: $e');
    }
  });
}

/* ───────────────── helpers MIUI ───────────────── */

Future<bool> _isMiui() async {
  try {
    final props = await const MethodChannel('undiamas/props')
        .invokeMethod<Map>('getProps');
    final v = (props?['ro.miui.ui.version.name'] ?? '') as String;
    return v.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Abre «Inicio automático» en MIUI (si existe)
Future<void> openMiuiAutoStartSettings() async {
  const ch = MethodChannel('undiamas/intent');
  try {
    await ch.invokeMethod('openAutoStart');
  } catch (_) {}
}

/* ───────────────── APP ───────────────── */

class UnDiaMasApp extends StatelessWidget {
  final bool showOnboarding;
  const UnDiaMasApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) => MaterialApp(
        navigatorKey: _navKey,
        title: 'Un Día Más',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: mode,
        locale: const Locale('es', 'ES'),
        supportedLocales: const [Locale('es', 'ES'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        localeResolutionCallback: (_, __) => const Locale('es', 'ES'),
        home: showOnboarding ? const OnboardingScreen() : BottomNavBar(),
      ),
    );
  }
}
