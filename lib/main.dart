import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'dart:io' show Platform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'widgets/bottom_nav_bar.dart';
import 'theme/app_theme.dart';
import 'screens/onboarding_screen.dart';
import 'models/diary_entry.dart';
import 'models/post.dart';
import 'services/achievement_service.dart';
import 'services/encryption_service.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
final GlobalKey<NavigatorState> _navKey = GlobalKey(debugLabel: 'root_nav');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /* ── 1) Hive + cifrado ── */
  await Hive.initFlutter();
  Hive.registerAdapter(DiaryEntryAdapter());
  Hive.registerAdapter(PostAdapter());

  final cipher = await EncryptionService.getCipher();

  if (await Hive.boxExists('udm')) {
    final plain  = await Hive.openBox('udm');
    final secure = await Hive.openBox('udm_secure', encryptionCipher: cipher);
    if (secure.isEmpty) await secure.putAll(plain.toMap());
    await plain.deleteFromDisk();
  }
  final settings = await Hive.openBox('udm_secure', encryptionCipher: cipher);

  if (await Hive.boxExists('diary')) {
    final plain  = await Hive.openBox<DiaryEntry>('diary');
    final secure = await Hive.openBox<DiaryEntry>('diary_secure',
        encryptionCipher: cipher);
    if (secure.isEmpty) await secure.addAll(plain.values);
    await plain.deleteFromDisk();
  }

  /* ── 2) Ads ── */
  await MobileAds.instance.initialize();
  MobileAds.instance.updateRequestConfiguration(
    RequestConfiguration(testDeviceIds: ['TEST_DEVICE_ID']),
  );

  /* ── 3) Notificaciones ── */
  await AchievementService.init();

  /* ── 4) Internacionalización ── */
  Intl.defaultLocale = 'es_ES';
  final prefs = await SharedPreferences.getInstance();
  themeNotifier.value =
      (prefs.getBool('isDarkMode') ?? false) ? ThemeMode.dark : ThemeMode.light;

  /* ── 5) Arranque UI ── */
  final hasStartDate = settings.containsKey('startDate');
  runApp(UnDiaMasApp(showOnboarding: !hasStartDate));

  /* ── 6) Programar notificaciones y gestionar permisos ── */
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final ctx = _navKey.currentContext;
    if (ctx == null) return;

    try {
      bool allowed = true;
      if (Platform.isAndroid) {
        final impl =
            FlutterLocalNotificationsPlugin().resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        allowed = await (impl as dynamic)?.areNotificationsEnabled() ?? true;
      }

      if (!allowed && ctx.mounted) {
        await showDialog(
          context: ctx,
          builder: (_) => AlertDialog(
            title: const Text('Permiso de notificaciones'),
            content: const Text(
                'Para avisarte de logros y reflexiones diarias necesitamos '
                'que actives las notificaciones.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Más tarde'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  // Intentamos abrir ajustes de la app (si el plugin lo soporta)
                  try {
                    final android = FlutterLocalNotificationsPlugin()
                        .resolvePlatformSpecificImplementation<
                            AndroidFlutterLocalNotificationsPlugin>();
                    await (android as dynamic)?.openNotificationSettings();
                  } catch (_) {
                    // Si la API no existe, simplemente no hacemos nada
                  }
                },
                child: const Text('Activar'),
              ),
            ],
          ),
        );
      }

      final milestonesOn = prefs.getBool('notifyMilestones') ?? true;
      final reflectionOn = prefs.getBool('notifyDailyReflection') ?? true;

      if (milestonesOn && hasStartDate) {
        final start = DateTime.parse(settings.get('startDate'));
        await AchievementService.scheduleMilestones(start);
      }
      if (reflectionOn) {
        final json =
            await rootBundle.loadString('assets/data/reflections.json');
        await AchievementService.scheduleDailyReflections(json);
      }
    } catch (e, s) {
      // ignore: avoid_print
      print('Error al programar notificaciones: $e\n$s');
    }
  });
}

class UnDiaMasApp extends StatelessWidget {
  final bool showOnboarding;
  const UnDiaMasApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, currentMode, __) {
        return MaterialApp(
          navigatorKey: _navKey,
          title: 'Un Día Más',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          locale: const Locale('es', 'ES'),
          supportedLocales: const [
            Locale('es', 'ES'),
            Locale('en', 'US'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          localeResolutionCallback: (_, __) => const Locale('es', 'ES'),
          home: showOnboarding ? const OnboardingScreen() : BottomNavBar(),
        );
      },
    );
  }
}
