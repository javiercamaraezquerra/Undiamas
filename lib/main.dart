import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'widgets/bottom_nav_bar.dart';
import 'theme/app_theme.dart';
import 'screens/onboarding_screen.dart';
import 'models/diary_entry.dart';
import 'models/post.dart';
import 'services/achievement_service.dart';
import 'services/encryption_service.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /* ──────────────── 1) Hive + cifrado ──────────────── */
  await Hive.initFlutter();
  Hive.registerAdapter(DiaryEntryAdapter());
  Hive.registerAdapter(PostAdapter());

  final cipher = await EncryptionService.getCipher();

  // Migración cajas a cifrado (idéntica a la versión anterior) ……………………………
  if (await Hive.boxExists('udm')) {
    final plain = await Hive.openBox('udm');
    final secure = await Hive.openBox('udm_secure', encryptionCipher: cipher);
    if (secure.isEmpty) await secure.putAll(plain.toMap());
    await plain.deleteFromDisk();
  }
  final settings = await Hive.openBox('udm_secure', encryptionCipher: cipher);

  if (await Hive.boxExists('diary')) {
    final plain = await Hive.openBox<DiaryEntry>('diary');
    final secure =
        await Hive.openBox<DiaryEntry>('diary_secure', encryptionCipher: cipher);
    if (secure.isEmpty) await secure.addAll(plain.values);
    await plain.deleteFromDisk();
  }

  /* ──────────────── 2) Ads ──────────────── */
  await MobileAds.instance.initialize();
  MobileAds.instance
      .updateRequestConfiguration(RequestConfiguration(testDeviceIds: ['TEST_DEVICE_ID']));

  /* ──────────────── 3) Notificaciones ──────────────── */
  await AchievementService.init();

  /* ──────────────── 4) Preferencias UI ──────────────── */
  final prefs = await SharedPreferences.getInstance();
  themeNotifier.value =
      (prefs.getBool('isDarkMode') ?? false) ? ThemeMode.dark : ThemeMode.light;

  /* ──────────────── 5) Arranque app (¡ya no hay awaits bloqueantes!) ──────────────── */
  final hasStartDate = settings.containsKey('startDate');
  runApp(UnDiaMasApp(showOnboarding: !hasStartDate));

  /* ──────────────── 6) Programación de notificaciones DESPUÉS del frame inicial ─── */
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      final milestonesOn = prefs.getBool('notifyMilestones') ?? true;
      final reflectionOn = prefs.getBool('notifyDailyReflection') ?? true;

      if (milestonesOn && hasStartDate) {
        final start = DateTime.parse(settings.get('startDate'));
        await AchievementService.scheduleMilestones(start);
      }

      if (reflectionOn) {
        final json = await rootBundle.loadString('assets/data/reflections.json');
        await AchievementService.scheduleDailyReflections(json);
      }
    } catch (e, s) {
      // Log en consola para depuración, sin romper la UI en producción
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
          title: 'Un Día Más',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          home: showOnboarding ? const OnboardingScreen() : BottomNavBar(),
        );
      },
    );
  }
}
