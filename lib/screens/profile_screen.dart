import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator, rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../models/diary_entry.dart';
import '../services/achievement_service.dart';
import '../services/drive_backup_service.dart';
import '../services/encryption_service.dart';
import '../services/hive_restore_service.dart';
import '../services/inventory_photo_store.dart';
import '../services/journal_draft_store.dart';
import '../services/picker_photo_cache_cleaner.dart';
import '../services/notification_preferences_controller.dart';
import '../services/notification_preference_storage.dart';
import '../widgets/mood_trend_chart.dart';
import '../widgets/restore_backup_dialog.dart';
import '../widgets/app_lock_tile.dart';
import '../widgets/profile_privacy_links.dart';
import '../routes/fade_transparent_route.dart';
import 'tutorial_screen.dart';

const _kDisclaimer =
    'La información y los recordatorios de esta aplicación son de carácter '
    'educativo y de apoyo. No sustituyen la valoración ni el tratamiento de '
    'profesionales de la salud.';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.notificationsController});
  final NotificationsController? notificationsController;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  /* ───────── estado ───────── */
  bool _isDark = false;
  bool _notifDaily = true;
  bool _notifMilestones = true;
  bool _autoBackup = false;
  bool _restoreInProgress = false;
  bool _backupInProgress = false;
  bool _resetInProgress = false;
  bool _notificationToggleInProgress = false;
  bool _openingNotificationSettings = false;
  bool _prefsLoaded = false;
  late final NotificationsController _notifications;

  bool get _notificationControlsBusy =>
      !_prefsLoaded ||
      _notificationToggleInProgress ||
      _notifications.busy ||
      _restoreInProgress ||
      _backupInProgress ||
      _resetInProgress;

  DateTime? _startDate;
  int _daysClean = 0;

  late Future<Box<DiaryEntry>> _diaryBoxFuture;

  @override
  void initState() {
    super.initState();
    _notifications =
        widget.notificationsController ?? NotificationsController();
    _notifications.addListener(_notificationStatusChanged);
    WidgetsBinding.instance.addObserver(this);
    _diaryBoxFuture = EncryptionService.getCipher().then(
      (c) => Hive.openBox<DiaryEntry>('diary_secure', encryptionCipher: c),
    );
    _refreshStoredPrefs();
    _notifications.refresh();
  }

  void _notificationStatusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _notifications.refresh();
      if (!_prefsLoaded) _refreshStoredPrefs();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifications.removeListener(_notificationStatusChanged);
    if (widget.notificationsController == null) _notifications.dispose();
    super.dispose();
  }

  /* ───────── carga inicial ───────── */
  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final cipher = await EncryptionService.getCipher();
    final box = await Hive.openBox('udm_secure', encryptionCipher: cipher);
    if (!mounted) return;
    final storedDate = box.get('startDate');
    final startDate =
        storedDate is String ? DateTime.tryParse(storedDate) : null;
    setState(() {
      _isDark = prefs.getBool('isDarkMode') ?? false;
      _notifDaily = prefs.getBool('notifyDailyReflection') ?? true;
      _notifMilestones = prefs.getBool('notifyMilestones') ?? true;
      _autoBackup = prefs.getBool('autoBackup') ?? false;
      _prefsLoaded = true;
      _startDate = startDate;
      _daysClean =
          startDate == null ? 0 : DateTime.now().difference(startDate).inDays;
    });
  }

  Future<bool> _refreshStoredPrefs() async {
    try {
      await _loadPrefs();
      return true;
    } catch (_) {
      if (mounted) {
        setState(() => _prefsLoaded = false);
        _showSnack('No se pudieron comprobar los ajustes guardados. '
            'Vuelve a abrir Perfil para intentarlo de nuevo.');
      }
      return false;
    }
  }

  /* ───────── toggles ───────── */
  Future<void> _toggleTheme(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', v);
    themeNotifier.value = v ? ThemeMode.dark : ThemeMode.light;
    setState(() => _isDark = v);
  }

  Future<void> _toggleDailyNotif(bool value) =>
      _toggleNotification(daily: true, value: value);

  Future<void> _toggleMilestoneNotif(bool value) =>
      _toggleNotification(daily: false, value: value);

  Future<void> _toggleNotification(
      {required bool daily, required bool value}) async {
    if (_notificationControlsBusy) return;
    final storage = HiveRestoreService.instance;
    final generation = storage.generation;
    setState(() => _notificationToggleInProgress = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final result = await _notifications.change(
        enable: value,
        isCurrent: () => mounted && generation == storage.generation,
        schedule: () async {
          if (daily) {
            final json =
                await rootBundle.loadString('assets/data/reflections.json');
            await AchievementService.scheduleDailyReflections(json);
          } else {
            final stored = Hive.box<dynamic>('udm_secure').get('startDate');
            final start = stored is String ? DateTime.tryParse(stored) : null;
            if (start == null) throw StateError('No valid start date');
            await AchievementService.scheduleMilestones(start);
          }
        },
        cancel: daily
            ? AchievementService.cancelDailyReflections
            : AchievementService.cancelMilestones,
        persist: (enabled) => persistNotificationPreference(prefs,
            daily ? 'notifyDailyReflection' : 'notifyMilestones', enabled),
        runExclusive: (action) =>
            storage.runExclusive(action, expectedGeneration: generation),
      );
      if (!mounted) return;
      switch (result) {
        case NotificationPreferenceResult.applied:
          setState(() {
            if (daily) {
              _notifDaily = value;
            } else {
              _notifMilestones = value;
            }
          });
        case NotificationPreferenceResult.denied:
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Android no permite las notificaciones. '
                'No se ha activado este aviso.'),
            action: SnackBarAction(
              label: 'Abrir ajustes',
              onPressed: _openNotificationSettings,
            ),
          ));
        case NotificationPreferenceResult.failed:
          if (await _refreshStoredPrefs() && mounted) {
            _showSnack('No se pudo completar el cambio del aviso. '
                'Se muestran los ajustes guardados; puedes volver a intentarlo.');
          }
        case NotificationPreferenceResult.cancelled:
          _showSnack('Los datos han cambiado. Revisa el perfil antes de '
              'volver a cambiar este aviso.');
        case NotificationPreferenceResult.busy:
          break;
      }
    } catch (_) {
      if (mounted) {
        _showSnack('No se pudo cambiar este aviso. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _notificationToggleInProgress = false);
    }
  }

  Future<void> _openNotificationSettings() async {
    if (!mounted || _openingNotificationSettings) return;
    _openingNotificationSettings = true;
    try {
      await _notifications.openSettings();
      if (mounted) await _notifications.refresh();
    } catch (_) {
      if (mounted) {
        _showSnack('No se pudieron abrir los ajustes de notificaciones.');
      }
    } finally {
      _openingNotificationSettings = false;
    }
  }

  String? get _notificationPermissionMessage =>
      _notifications.systemEnabled == false
          ? 'Bloqueadas por Android. Toca para abrir ajustes.'
          : null;

  Future<void> _toggleAutoBackup(bool v) async {
    if (_backupInProgress ||
        _restoreInProgress ||
        _resetInProgress ||
        _notificationToggleInProgress ||
        _notifications.busy) {
      return;
    }
    final service = HiveRestoreService.instance;
    final generation = service.generation;
    final uploadInitialCopy = v && !_autoBackup;
    setState(() => _backupInProgress = true);
    ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? waiting;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      if (uploadInitialCopy) {
        final consent = await _confirmDriveConsent();
        if (!mounted || !consent) return;
      }
      String? uploadError;
      await service.runExclusive(() async {
        if (uploadInitialCopy) {
          waiting = _showSnack('Subiendo copia inicial…', persistent: true);
          final cipher = await EncryptionService.getCipher();
          final udm =
              await Hive.openBox('udm_secure', encryptionCipher: cipher);
          final diary = await Hive.openBox<DiaryEntry>('diary_secure',
              encryptionCipher: cipher);
          // Export and upload share the lock: an old export cannot replace the
          // Drive copy after a later restoration has changed local data.
          final result = await DriveBackupService.uploadBackup(
              DriveBackupService.exportHive(udm, diary));
          if (!result.ok) {
            uploadError = result.message ?? 'Error al subir la copia.';
            return;
          }
        }
        await prefs.setBool('autoBackup', v);
      }, expectedGeneration: generation);
      if (!mounted) return;
      if (uploadError != null) {
        _showSnack(uploadError!);
      } else {
        setState(() => _autoBackup = v);
      }
    } catch (_) {
      if (mounted) {
        _showSnack('No se pudo cambiar la copia automática. '
            'Espera a que termine cualquier otra operación y vuelve a intentarlo.');
      }
    } finally {
      waiting?.close();
      if (mounted) setState(() => _backupInProgress = false);
    }
  }

  /* ───────── drive helpers ───────── */
  Future<bool> _confirmDriveConsent({bool forRestore = false}) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Google Drive'),
            content: Text(
              forRestore
                  ? 'La app accederá a su carpeta privada de Drive para '
                      'descargar tu copia. Antes de cambiar datos, podrás '
                      'revisar su contenido y decidir si quieres restaurarla.'
                  : 'Se guardarán tus entradas, incluidas sus fotos, y los datos '
                      'de inicio en la carpeta privada de la app en Google Drive. '
                      'La copia te permite recuperarlos en otro móvil. '
                      'La conexión está protegida; el archivo no tiene cifrado '
                      'propio de extremo a extremo.',
              textAlign: TextAlign.justify,
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Permitir')),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _restoreFromDrive() async {
    if (_restoreInProgress ||
        _backupInProgress ||
        _resetInProgress ||
        _notificationToggleInProgress ||
        _notifications.busy) {
      return;
    }
    setState(() => _restoreInProgress = true);
    ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? waiting;
    try {
      final consent = await _confirmDriveConsent(forRestore: true);
      if (!mounted || !consent) return;
      waiting = _showSnack('Descargando copia…', persistent: true);
      final download = await DriveBackupService.downloadBackup();
      waiting.close();
      waiting = null;
      if (!mounted) return;
      if (!download.ok || download.data == null) {
        _showSnack(download.message ?? 'No se encontró una copia válida.');
        return;
      }

      // Preparation validates the entire payload before asking to replace it.
      // It must never clear or write either of the user's boxes.
      final prepared = HiveRestoreService.prepare(download.data!);
      final cipher = await EncryptionService.getCipher();
      if (!mounted) return;
      final udm = await Hive.openBox('udm_secure', encryptionCipher: cipher);
      if (!mounted) return;
      final diary = await Hive.openBox<DiaryEntry>('diary_secure',
          encryptionCipher: cipher);
      if (!mounted) return;
      final consentToReplace = await showDialog<bool>(
        context: context,
        builder: (_) => RestoreBackupConfirmation(
          currentEntryCount: diary.length,
          backup: prepared,
        ),
      );
      if (!mounted || consentToReplace != true) return;

      final oldValue = udm.get('startDate');
      final oldDate = oldValue is String ? DateTime.tryParse(oldValue) : null;
      final service = HiveRestoreService.instance;
      final result = await showDialog<HiveRestoreResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => RestoreBackupOperation(
          restore: () => service.restore(prepared, udm, diary),
          recover: () => service.recoverInterrupted(udm, diary),
        ),
      );
      if (!mounted || result == null) return;
      final restoredGeneration = service.generation;

      // The dialog stays open for recoveryRequired. Notification failures below
      // must never be reported as failure of the already completed data write.
      setState(() => _diaryBoxFuture = Future.value(diary));
      final outcome = result.recovered
          ? 'Se han recuperado tus datos anteriores. La copia no se ha aplicado.'
          : (result.ok ? 'Datos restaurados.' : result.message);
      try {
        await _loadPrefs();
      } catch (_) {
        if (mounted) {
          _showSnack('$outcome No se pudo actualizar la vista del perfil.');
        }
        return;
      }
      if (!mounted) return;
      if (_notifMilestones &&
          _startDate != null &&
          oldDate?.millisecondsSinceEpoch !=
              _startDate!.millisecondsSinceEpoch) {
        try {
          await service.runExclusive(() async {
            // Read the desired preference under the same lock as scheduling:
            // returning to this screen must not re-enable a later opt-out.
            final prefs = await SharedPreferences.getInstance();
            final storedStartDate = udm.get('startDate');
            final currentStartDate = storedStartDate is String
                ? DateTime.tryParse(storedStartDate)
                : null;
            if ((prefs.getBool('notifyMilestones') ?? true) &&
                currentStartDate != null) {
              await AchievementService.scheduleMilestones(currentStartDate);
            }
          }, expectedGeneration: restoredGeneration);
        } catch (_) {
          if (mounted) {
            _showSnack(
                '$outcome No se pudieron reprogramar los avisos de logros. '
                'Puedes desactivarlos y volver a activarlos en Perfil.');
          }
          return;
        }
      }
      if (mounted) _showSnack(outcome);
    } on FormatException {
      if (mounted) {
        _showSnack('La copia tiene datos incompletos o no válidos. '
            'No se ha cambiado tu inventario.');
      }
    } catch (_) {
      if (mounted) {
        _showSnack('No se pudo preparar la restauración. Inténtalo de nuevo.');
      }
    } finally {
      waiting?.close();
      if (mounted) setState(() => _restoreInProgress = false);
    }
  }

  /* ───────── reiniciar contador ───────── */
  Future<void> _resetSoberDate() async {
    if (_restoreInProgress ||
        _backupInProgress ||
        _resetInProgress ||
        _notificationToggleInProgress ||
        _notifications.busy) {
      return;
    }
    final service = HiveRestoreService.instance;
    final generation = service.generation;
    setState(() => _resetInProgress = true);
    DateTime? appliedDate;
    try {
      final bool confirm = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Reiniciar contador'),
              content: const Text(
                'Se establecerá la fecha y hora actuales como nuevo inicio '
                'de tu periodo de no consumir y se volverán a programar los hitos. '
                '¿Deseas continuar?',
                textAlign: TextAlign.justify,
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Reiniciar')),
              ],
            ),
          ) ??
          false;
      if (!mounted || !confirm) return;
      await service.runExclusive(() async {
        final now = DateTime.now();
        final cipher = await EncryptionService.getCipher();
        final box = await Hive.openBox('udm_secure', encryptionCipher: cipher);
        await box.put('startDate', now.toIso8601String());
        appliedDate = now;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('start_date');
        if (prefs.getBool('notifyMilestones') ?? true) {
          await AchievementService.scheduleMilestones(now);
        }
      }, expectedGeneration: generation);
      if (mounted) _showSnack('¡Contador reiniciado!');
    } catch (_) {
      if (mounted) {
        _showSnack(appliedDate == null
            ? 'No se pudo reiniciar el contador. Inténtalo de nuevo.'
            : 'La fecha se ha actualizado, pero no se han podido completar '
                'los ajustes y avisos.');
      }
    } finally {
      if (mounted) {
        setState(() {
          if (appliedDate != null) {
            _startDate = appliedDate;
            _daysClean = 0;
          }
          _resetInProgress = false;
        });
      }
    }
  }

  /* ───────── eliminación total ───────── */
  Future<void> _deleteAccountAndData() async {
    if (_restoreInProgress ||
        _backupInProgress ||
        _resetInProgress ||
        _notificationToggleInProgress ||
        _notifications.busy) {
      return;
    }
    final service = HiveRestoreService.instance;
    final generation = service.generation;
    final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Eliminar cuenta y datos'),
            content: const Text(
              'Se borrarán todos los datos locales (diario, logros, ajustes) y se '
              'revocará el acceso a tu Google Drive. Esta acción es irreversible.',
              textAlign: TextAlign.justify,
            ),
            actions: [
              TextButton(
                child: const Text('Cancelar'),
                onPressed: () => Navigator.pop(context, false),
              ),
              ElevatedButton(
                child: const Text('Eliminar'),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted || !confirm || _restoreInProgress) return;

    try {
      if (generation != service.generation) {
        _showSnack(
            'Los datos han cambiado. Revisa el perfil antes de eliminarlos.');
        return;
      }
      await service.runDeletion(() async {
        await AchievementService.cancelDailyReflections();
        await AchievementService.cancelMilestones();

        if (await DriveBackupService.isSignedIn()) {
          await DriveBackupService.deleteBackup();
          await DriveBackupService.disconnect();
        }

        final cipher = await EncryptionService.getCipher();
        // Remove the undo data first so deletion cannot later resurrect it.
        // A failure here must stop before destroying the encryption key.
        final boxes = [
          await Hive.openBox(HiveRestoreService.recoveryBoxName,
              encryptionCipher: cipher),
          await Hive.openBox('udm_secure', encryptionCipher: cipher),
          await Hive.openBox<DiaryEntry>('diary_secure',
              encryptionCipher: cipher),
        ];
        for (final box in boxes) {
          await box.clear();
          await box.deleteFromDisk();
        }

        // Private attachments and drafts share the local key. Remove them
        // before destroying it so a partial failure can still be retried.
        await PickerPhotoCacheCleaner.instance.clear();
        await JournalDraftStore.instance.clear();
        await InventoryPhotoStore.instance.clear();

        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        await EncryptionService.wipeKey();
        await const FlutterSecureStorage().deleteAll();
      });
    } catch (_) {
      if (mounted) {
        _showSnack('No se pudo completar la eliminación. Inténtalo de nuevo.');
      }
      return;
    }

    if (mounted) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Completado'),
          content: const Text(
              'Tus datos han sido eliminados. La aplicación se reiniciará.'),
          actions: [
            ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Aceptar')),
          ],
        ),
      );
      await SystemNavigator.pop();
    }
  }

  /* ───────── snacks ───────── */
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> _showSnack(
      String msg,
      {bool persistent = false}) {
    final sb = SnackBar(
      content: Text(msg),
      duration:
          persistent ? const Duration(days: 1) : const Duration(seconds: 4),
    );
    return ScaffoldMessenger.of(context).showSnackBar(sb);
  }

  /* ───────── UI ───────── */
  @override
  Widget build(BuildContext context) {
    final bool darkMode = Theme.of(context).brightness == Brightness.dark;
    final Color scrimColor = darkMode
        ? Colors.black.withValues(alpha: .55)
        : Colors.black.withValues(alpha: .25);

    /* ── color de texto/íconos sobre el scrim ── */
    final Color fg = Colors.white;

    ListTile _tile({
      required IconData icon,
      required String title,
      String? subtitle,
      Widget? trailing,
      VoidCallback? onTap,
    }) {
      return ListTile(
        leading: Icon(icon, color: fg),
        title: Text(title, style: TextStyle(color: fg)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle, style: TextStyle(color: fg)),
        trailing: trailing,
        iconColor: fg,
        textColor: fg,
        onTap: onTap,
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Perfil'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Positioned.fill(child: Container(color: scrimColor)),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              children: [
                _tile(
                  icon: Icons.brightness_6,
                  title: 'Modo oscuro',
                  trailing: Switch(
                      value: _isDark,
                      onChanged: _toggleTheme,
                      activeColor: Theme.of(context).colorScheme.primary),
                ),
                _tile(
                  icon: Icons.notifications_active_outlined,
                  title: 'Notificación diaria de reflexión',
                  subtitle: _notificationPermissionMessage,
                  onTap: _notificationPermissionMessage != null &&
                          !_notificationControlsBusy
                      ? _openNotificationSettings
                      : null,
                  trailing: Switch(
                      value: _notifDaily,
                      onChanged:
                          _notificationControlsBusy ? null : _toggleDailyNotif,
                      activeColor: Theme.of(context).colorScheme.primary),
                ),
                _tile(
                  icon: Icons.flag,
                  title: 'Notificaciones de logros',
                  subtitle: _notificationPermissionMessage,
                  onTap: _notificationPermissionMessage != null &&
                          !_notificationControlsBusy
                      ? _openNotificationSettings
                      : null,
                  trailing: Switch(
                      value: _notifMilestones,
                      onChanged: _notificationControlsBusy
                          ? null
                          : _toggleMilestoneNotif,
                      activeColor: Theme.of(context).colorScheme.primary),
                ),

                // (ANTES estaba aquí "Ver tutorial rápido") — MOVIDO más abajo

                _tile(
                  icon: Icons.cloud_sync,
                  title: 'Copias automáticas en Drive',
                  trailing: Switch(
                      value: _autoBackup,
                      onChanged: _restoreInProgress ||
                              _backupInProgress ||
                              _resetInProgress
                          ? null
                          : _toggleAutoBackup,
                      activeColor: Theme.of(context).colorScheme.primary),
                ),
                AppLockTile(foreground: fg),
                ProfilePrivacyLinks(
                  foreground: fg,
                  policyUri: Uri.parse(
                      'https://sites.google.com/view/undiamas-privacy'),
                ),
                const Divider(),
                _tile(
                  icon: Icons.cloud_download,
                  title: 'Restaurar desde Drive',
                  subtitle:
                      _restoreInProgress ? 'Restauración en curso…' : null,
                  onTap: _restoreInProgress ? null : _restoreFromDrive,
                ),
                // const Divider(),  // ← QUITADO: sin línea antes de "Reiniciar contador"

                _tile(
                  // ← se mantiene aquí pero sin divisores arriba/abajo
                  icon: Icons.refresh,
                  title: 'Reiniciar contador',
                  subtitle: 'Establece hoy y ahora como inicio',
                  onTap: _resetSoberDate,
                ),
                // const Divider(),  // ← QUITADO

                if (_startDate != null) ..._buildProgressSection(fg),
                const Divider(),
                _buildMoodSection(),

                const Divider(), // separación del bloque final

                // NUEVA UBICACIÓN: justo encima de "Eliminar", sin Divider entre ambos
                _tile(
                  icon: Icons.slideshow,
                  title: 'Ver tutorial rápido',
                  onTap: () => Navigator.push(
                    context,
                    FadeTransparentRoute(
                        builder: (_) => const TutorialScreen()),
                  ),
                ),

                // botón rojo, sin Divider por encima
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Eliminar cuenta y datos',
                      style: TextStyle(color: Colors.red)),
                  onTap: _deleteAccountAndData,
                ),

                const SizedBox(height: 18),
                Text(
                  _kDisclaimer,
                  style:
                      TextStyle(color: fg.withValues(alpha: .9), fontSize: 14),
                  textAlign: TextAlign.justify,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /* ───────── helpers UI ───────── */
  List<Widget> _buildProgressSection(Color fg) {
    final milestones = AchievementService.milestones.keys.toList()..sort();
    final next = milestones.firstWhere((d) => _daysClean < d, orElse: () => -1);

    return [
      ListTile(
        leading: Icon(Icons.celebration, color: fg),
        title:
            Text('Llevas $_daysClean días limpio', style: TextStyle(color: fg)),
        subtitle: Text('Desde ${DateFormat.yMMMd().format(_startDate!)}',
            style: TextStyle(color: fg)),
        iconColor: fg,
        textColor: fg,
      ),
      if (next != -1)
        ListTile(
          leading: Icon(Icons.flag_outlined, color: fg),
          title: Text('Próximo hito: $next días', style: TextStyle(color: fg)),
          subtitle: Text(AchievementService.milestones[next]!,
              style: TextStyle(color: fg)),
          iconColor: fg,
          textColor: fg,
        ),
    ];
  }

  Widget _buildMoodSection() {
    return FutureBuilder<Box<DiaryEntry>>(
      future: _diaryBoxFuture,
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final box = snap.data!;
        if (!box.isOpen) return const SizedBox.shrink();
        final storage = HiveRestoreService.instance;
        final changes = Listenable.merge([box.listenable(), storage]);
        return AnimatedBuilder(
          animation: changes,
          builder: (_, __) {
            final available =
                box.isOpen && !storage.busy && !storage.recoveryRequired;
            final entries = available ? box.values.toList() : <DiaryEntry>[];
            return Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    const ListTile(
                      dense: true,
                      leading: Icon(Icons.show_chart),
                      title: Text('Tendencia de ánimo'),
                    ),
                    MoodTrendChart(
                      entries: entries,
                      entriesAvailable: available,
                      invalidationSignal: changes,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
