import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
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

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
final GlobalKey<NavigatorState> _navKey = GlobalKey(debugLabel: 'root_nav');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /* Hive inicial */
  await Hive.initFlutter();
  Hive.registerAdapter(DiaryEntryAdapter());
  Hive.registerAdapter(PostAdapter());

  final cipher = await EncryptionService.getCipher();
  if (await Hive.boxExists('udm')) {
    final p = await Hive.openBox('udm');
    final s = await Hive.openBox('udm_secure', encryptionCipher: cipher);
    if (s.isEmpty) await s.putAll(p.toMap());
    await p.deleteFromDisk();
  }
  final settings = await Hive.openBox('udm_secure', encryptionCipher: cipher);

  if (await Hive.boxExists('diary')) {
    final p = await Hive.openBox<DiaryEntry>('diary');
    final s =
        await Hive.openBox<DiaryEntry>('diary_secure', encryptionCipher: cipher);
    if (s.isEmpty) await s.addAll(p.values);
    await p.deleteFromDisk();
  }

  /* Ads */
  await MobileAds.instance.initialize();
  await MobileAds.instance.updateRequestConfiguration(
    RequestConfiguration(testDeviceIds: ['TEST_DEVICE_ID']),
  );

  /* Notificaciones */
  await AchievementService.init(onNotificationResponse: (resp) {
    final idx = int.tryParse(resp.payload ?? '');
    if (idx != null) {
      _navKey.currentState?.push(
        MaterialPageRoute(builder: (_) => ReflectionScreen(dayIndex: idx)),
      );
    }
  });

  /* Preferencias */
  Intl.defaultLocale = 'es_ES';
  final prefs = await SharedPreferences.getInstance();
  themeNotifier.value =
      (prefs.getBool('isDarkMode') ?? false) ? ThemeMode.dark : ThemeMode.light;

  final hasStartDate = settings.containsKey('startDate');
  runApp(UnDiaMasApp(showOnboarding: !hasStartDate));

  /* Permiso racionalizado + programación de notifs */
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final ctx = _navKey.currentContext;
    if (ctx == null) return;

    bool allowed = true;
    if (Platform.isAndroid) {
      final impl = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      allowed = await (impl as dynamic)?.areNotificationsEnabled() ?? true;
    }

    final shown = prefs.getBool('notifDialogShown') ?? false;
    if (!allowed) {
      if (!shown && ctx.mounted) {
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
                  child: const Text('Más tarde')),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final android = FlutterLocalNotificationsPlugin()
                      .resolvePlatformSpecificImplementation<
                          AndroidFlutterLocalNotificationsPlugin>();
                  await (android as dynamic)?.openNotificationSettings();
                },
                child: const Text('Activar'),
              ),
            ],
          ),
        );
        await prefs.setBool('notifDialogShown', true);
      } else if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: const Text(
                'Notificaciones desactivadas. Actívalas para recibir avisos.'),
            action: SnackBarAction(
              label: 'Ajustes',
              onPressed: () async {
                final android = FlutterLocalNotificationsPlugin()
                    .resolvePlatformSpecificImplementation<
                        AndroidFlutterLocalNotificationsPlugin>();
                await (android as dynamic)?.openNotificationSettings();
              },
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }

    /* Programar notificaciones */
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
  });
}

class UnDiaMasApp extends StatelessWidget {
  final bool showOnboarding;
  const UnDiaMasApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp(
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
        );
      },
    );
  }
}
