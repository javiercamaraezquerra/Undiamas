import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/diary_entry.dart';
import 'models/post.dart';
import 'routes/fade_transparent_route.dart'; // ← NUEVO
import 'screens/onboarding_screen.dart';
import 'screens/reflection_screen.dart';
import 'services/achievement_service.dart';
import 'services/ad_consent_controller.dart';
import 'services/app_lock_controller.dart';
import 'services/encryption_service.dart';
import 'services/hive_restore_service.dart';
import 'services/inventory_storage.dart';
import 'services/inventory_backup_archive.dart';
import 'services/inventory_photo_store.dart';
import 'services/journal_draft_store.dart';
import 'services/notification_plan.dart';
import 'services/notification_refresh.dart';
import 'services/native_tz.dart';
import 'theme/app_theme.dart';
import 'widgets/bottom_nav_bar.dart';
import 'widgets/app_lock_gate.dart';
import 'widgets/inventory_recovery_app.dart';

final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);
final _navKey = GlobalKey<NavigatorState>(debugLabel: 'root_nav');
int? _pendingReflectionIndex;

void _handleNotification(NotificationResponse response) {
  final payload = response.payload;
  final index = payload == 'today'
      ? reflectionIndexForDate(DateTime.now())
      : int.tryParse(payload ?? '');
  if (index == null || index < 0 || index > 365) return;
  // Accept the old leap-year payload 365, but never index outside the collection.
  _pendingReflectionIndex = index.clamp(0, 364);
  _flushPendingReflection();
}

bool get _dataUnavailable =>
    HiveRestoreService.instance.busy ||
    HiveRestoreService.instance.recoveryRequired;

void _flushPendingReflection() {
  if (AppLockController.instance.covered ||
      _dataUnavailable ||
      _pendingReflectionIndex == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (AppLockController.instance.covered || _dataUnavailable) return;
    final navigator = _navKey.currentState;
    final index = _pendingReflectionIndex;
    if (navigator == null || index == null) return;
    _pendingReflectionIndex = null;
    navigator.push(FadeTransparentRoute(
        builder: (_) => ReflectionScreen(dayIndex: index)));
  });
}

void _afterFirstUnlock(Future<void> Function() action) {
  final lock = AppLockController.instance;
  void onChanged() {
    if (lock.covered || _dataUnavailable) return;
    lock.removeListener(onChanged);
    HiveRestoreService.instance.removeListener(onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // The user may have backgrounded the app before this frame.
      if (lock.covered || _dataUnavailable) {
        _afterFirstUnlock(action);
      } else {
        await action();
      }
    });
  }

  lock.addListener(onChanged);
  HiveRestoreService.instance.addListener(onChanged);
  onChanged();
}

/// Muestra la ayuda MIUI una sola vez
const bool _showMiuiHelp = true;

class _NotificationResumeObserver extends WidgetsBindingObserver {
  _NotificationResumeObserver(this.refresh);
  final ForegroundNotificationRefresh refresh;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh.requestRefresh();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HiveRestoreService.instance.beforeApplyRestore =
      JournalDraftStore.instance.clear;
  await AppLockController.instance.initialize();
  AppLockController.instance.addListener(_flushPendingReflection);
  HiveRestoreService.instance.addListener(_flushPendingReflection);

  /* ── Hive (cifrado) ─ */
  await Hive.initFlutter();
  Hive.registerAdapter(DiaryEntryAdapter());
  Hive.registerAdapter(PostAdapter());

  // Fail closed before mounting normal screens if opening, migration or a
  // previous restore cannot be completed without discarding existing data.
  late Box<dynamic> settings;
  Future<String?> recoverInventory() async {
    try {
      final cipher = await EncryptionService.getCipher();
      final opened = await InventoryStorage.open(cipher);
      settings = opened.settings;
      final result = await HiveRestoreService.instance
          .recoverInterrupted(settings, opened.diary);
      if (result.ok) {
        // Cleanup is optional. If the draft is unreadable, preserve every
        // attachment rather than risk deleting the only recoverable copy.
        try {
          await InventoryBackupArchive().cleanAbandonedWorkspaces();
          final draft = await JournalDraftStore.instance.load();
          await InventoryPhotoStore.instance.prune({
            for (final entry in opened.diary.values)
              if (entry.photoId != null) entry.photoId!,
            if (draft?.photoId != null) draft!.photoId!,
          });
        } catch (_) {
          // A storage cleanup failure never hides otherwise readable entries.
        }
      }
      return result.ok ? null : result.message;
    } catch (_) {
      return 'No se pudo abrir el Inventario de forma segura. '
          'Vuelve a intentarlo. Si el problema continúa, conserva la app '
          'instalada para poder revisar sus datos.';
    }
  }

  final recoveryMessage = await recoverInventory();
  if (recoveryMessage != null) {
    final recovered = Completer<void>();
    runApp(InventoryRecoveryApp(
      message: recoveryMessage,
      retry: recoverInventory,
      onRecovered: () {
        if (!recovered.isCompleted) recovered.complete();
      },
    ));
    await recovered.future;
  }

  /* ── Notificaciones (init + deep‑link) ─ */
  try {
    await AchievementService.init(onNotificationResponse: _handleNotification);
    final launch = await AchievementService.getLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse != null) {
      _handleNotification(launch!.notificationResponse!);
    }
  } catch (e, s) {
    debugPrint('Init notifications error: $e\n$s');
  }

  /* ── Preferencias / tema ─ */
  Intl.defaultLocale = 'es_ES';
  final prefs = await SharedPreferences.getInstance();
  themeNotifier.value =
      (prefs.getBool('isDarkMode') ?? false) ? ThemeMode.dark : ThemeMode.light;

  final hasStartDate = settings.containsKey('startDate');
  var notificationStartupReady = false;
  final notificationRefresh = ForegroundNotificationRefresh(
    canRun: () =>
        notificationStartupReady &&
        settings.isOpen &&
        !AppLockController.instance.covered &&
        !_dataUnavailable,
    configurationKey: () async {
      await prefs.reload();
      final timezone = await NativeTz.getLocalTz();
      final allowed = await AchievementService.notificationsEnabled();
      final now = DateTime.now();
      return '$timezone/${now.year}-${now.month}-${now.day}/$allowed/'
          '${prefs.getBool('notifyDailyReflection') ?? true}/'
          '${prefs.getBool('notifyMilestones') ?? true}/${settings.get('startDate')}';
    },
    refresh: () => HiveRestoreService.instance.runExclusive(() async {
      await prefs.reload();
      // Read the current flags inside the same data lock used by Profile.
      // A denied system permission is a user choice, not a recurring error.
      if (!await AchievementService.notificationsEnabled()) {
        await AchievementService.cancelMilestones();
        await AchievementService.cancelDailyReflections();
        return;
      }
      if ((prefs.getBool('notifyMilestones') ?? true) &&
          settings.containsKey('startDate')) {
        await AchievementService.scheduleMilestones(
            DateTime.parse(settings.get('startDate')));
      } else {
        await AchievementService.cancelMilestones();
      }
      if (prefs.getBool('notifyDailyReflection') ?? true) {
        final json =
            await rootBundle.loadString('assets/data/reflections.json');
        await AchievementService.scheduleDailyReflections(json);
      } else {
        await AchievementService.cancelDailyReflections();
      }
    }),
    onError: (_, __) {
      final context = _navKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text('No se pudieron actualizar los recordatorios. '
              'Puedes volver a intentarlo desde Perfil.'),
        ));
      }
    },
  );
  WidgetsBinding.instance
      .addObserver(_NotificationResumeObserver(notificationRefresh));
  AppLockController.instance.addListener(notificationRefresh.onStateChanged);
  HiveRestoreService.instance.addListener(notificationRefresh.onStateChanged);
  runApp(UnDiaMasApp(showOnboarding: !hasStartDate));
  _flushPendingReflection();

  /* ── Permisos + MIUI + programación ─ */
  _afterFirstUnlock(() async {
    final ctx = _navKey.currentContext;
    if (ctx == null) return;

    /* 1 · POST_NOTIFICATIONS (Android 13+) */
    try {
      final wantsNotifications =
          (prefs.getBool('notifyDailyReflection') ?? true) ||
              (prefs.getBool('notifyMilestones') ?? true);
      if (wantsNotifications &&
          !await AchievementService.notificationsEnabled() &&
          !(prefs.getBool('notificationPermissionAsked') ?? false)) {
        await prefs.setBool('notificationPermissionAsked', true);
        final granted =
            await AchievementService.requestNotificationPermission();
        if (!granted && ctx.mounted) {
          ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(const SnackBar(
            content:
                Text('Las notificaciones no están permitidas en este móvil. '
                    'Puedes activarlas desde Perfil cuando quieras.'),
          ));
        }
      }
    } catch (_) {
      if (ctx.mounted) {
        ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(const SnackBar(
          content: Text('No se pudo comprobar el permiso de notificaciones. '
              'Puedes volver a intentarlo desde Perfil.'),
        ));
      }
    }

    /* 2 · Ayuda MIUI (inicio automático) */
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

    /* 3 · Programar y renovar al volver otro día o cambiar zona/permisos */
    notificationStartupReady = true;
    notificationRefresh.requestRefresh();
    // Defer UMP until startup permission dialogs have finished. The controller
    // waits for an uncovered foreground before presenting any native form.
    unawaited(AdConsentController.instance.initialize());
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
        builder: (_, child) => AppLockGate(
          nativeModalChanges: AdConsentController.instance,
          nativeModalVisible: () => AdConsentController.instance.formVisible,
          child: child ?? const SizedBox.shrink(),
        ),
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
