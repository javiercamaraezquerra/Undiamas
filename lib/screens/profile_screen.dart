import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../models/diary_entry.dart';
import '../services/achievement_service.dart';
import '../services/drive_backup_service.dart';
import '../services/encryption_service.dart';
import '../widgets/mood_trend_chart.dart';

const _kDisclaimer =
    'La información y los recordatorios de esta aplicación son de carácter '
    'educativo y de apoyo. No sustituyen la valoración ni el tratamiento de '
    'profesionales de la salud.';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  /* ───────── estado ───────── */
  bool _isDark = false;
  bool _notifDaily = true;
  bool _notifMilestones = true;
  bool _autoBackup = false;

  DateTime? _startDate;
  int _daysClean = 0;

  late Future<Box<DiaryEntry>> _diaryBoxFuture;

  @override
  void initState() {
    super.initState();
    _diaryBoxFuture = EncryptionService.getCipher().then(
      (c) => Hive.openBox<DiaryEntry>('diary_secure', encryptionCipher: c),
    );
    _loadPrefs();
  }

  /* ───────── carga inicial ───────── */
  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _isDark = prefs.getBool('isDarkMode') ?? false;
    _notifDaily = prefs.getBool('notifyDailyReflection') ?? true;
    _notifMilestones = prefs.getBool('notifyMilestones') ?? true;
    _autoBackup = prefs.getBool('autoBackup') ?? false;

    final cipher = await EncryptionService.getCipher();
    final box = await Hive.openBox('udm_secure', encryptionCipher: cipher);
    if (box.containsKey('startDate')) {
      _startDate = DateTime.parse(box.get('startDate'));
      _daysClean = DateTime.now().difference(_startDate!).inDays;
    }
    if (mounted) setState(() {});
  }

  /* ───────── toggles ───────── */
  Future<void> _toggleTheme(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', v);
    themeNotifier.value = v ? ThemeMode.dark : ThemeMode.light;
    setState(() => _isDark = v);
  }

  Future<void> _toggleDailyNotif(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifyDailyReflection', v);
    setState(() => _notifDaily = v);

    if (v) {
      final json = await DefaultAssetBundle.of(context)
          .loadString('assets/data/reflections.json');
      await AchievementService.scheduleDailyReflections(json);
    } else {
      await AchievementService.cancelDailyReflections();
    }
  }

  Future<void> _toggleMilestoneNotif(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifyMilestones', v);
    setState(() => _notifMilestones = v);

    if (v && _startDate != null) {
      await AchievementService.scheduleMilestones(_startDate!);
    } else {
      await AchievementService.cancelMilestones();
    }
  }

  Future<void> _toggleAutoBackup(bool v) async {
    final prefs = await SharedPreferences.getInstance();

    if (v && !_autoBackup) {
      if (!await _confirmDriveConsent()) return;

      final wait = _showSnack('Subiendo copia inicial…', persistent: true);
      final cipher = await EncryptionService.getCipher();
      final udm = await Hive.openBox('udm_secure', encryptionCipher: cipher);
      final diary =
          await Hive.openBox<DiaryEntry>('diary_secure', encryptionCipher: cipher);

      final res =
          await DriveBackupService.uploadBackup(DriveBackupService.exportHive(udm, diary));

      wait.close();
      if (!res.ok) {
        _showSnack(res.message ?? 'Error al subir la copia.');
        return;
      }
    }

    await prefs.setBool('autoBackup', v);
    setState(() => _autoBackup = v);
  }

  /* ───────── drive helpers ───────── */
  Future<bool> _confirmDriveConsent() async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Google Drive'),
            content: const Text(
              'La app necesitará acceder a tu carpeta privada de Drive para '
              'almacenar copias de seguridad. Si lo rechazas, podrías perder '
              'los datos al cambiar de dispositivo.',
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
    if (!await _confirmDriveConsent()) {
      _showSnack('Restauración cancelada.');
      return;
    }

    final wait = _showSnack('Descargando copia…', persistent: true);
    final result = await DriveBackupService.downloadBackup();
    wait.close();

    if (!result.ok || result.data == null) {
      _showSnack(result.message ?? 'No se encontró copia válida.');
      return;
    }

    final cipher = await EncryptionService.getCipher();
    final udm = await Hive.openBox('udm_secure', encryptionCipher: cipher);
    final diary =
        await Hive.openBox<DiaryEntry>('diary_secure', encryptionCipher: cipher);

    final imported =
        await DriveBackupService.importHive(result.data!, udm, diary);

    _showSnack(imported
        ? 'Datos restaurados.'
        : 'La copia estaba vacía o dañada.');

    if (imported) {
      setState(() {
        _diaryBoxFuture = EncryptionService.getCipher().then(
          (c) => Hive.openBox<DiaryEntry>('diary_secure', encryptionCipher: c),
        );
      });
      _loadPrefs();
    }
  }

  /* ───────── reiniciar contador ───────── */
  Future<void> _resetSoberDate() async {
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
    if (!confirm) return;

    final now = DateTime.now();
    final cipher = await EncryptionService.getCipher();
    final box = await Hive.openBox('udm_secure', encryptionCipher: cipher);
    await box.put('startDate', now.toIso8601String());

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('start_date');
    if (_notifMilestones) await AchievementService.scheduleMilestones(now);

    setState(() {
      _startDate = now;
      _daysClean = 0;
    });
    _showSnack('¡Contador reiniciado!');
  }

  /* ───────── eliminación total ───────── */
  Future<void> _deleteAccountAndData() async {
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
    if (!confirm) return;

    await AchievementService.cancelDailyReflections();
    await AchievementService.cancelMilestones();

    if (await DriveBackupService.isSignedIn()) {
      await DriveBackupService.deleteBackup();
      await DriveBackupService.disconnect();
    }

    final cipher = await EncryptionService.getCipher();
    final boxes = [
      await Hive.openBox('udm_secure', encryptionCipher: cipher),
      await Hive.openBox<DiaryEntry>('diary_secure', encryptionCipher: cipher),
    ];
    for (final b in boxes) {
      await b.clear();
      await b.deleteFromDisk();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    await EncryptionService.wipeKey();
    await const FlutterSecureStorage().deleteAll();

    if (mounted) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Completado'),
          content:
              const Text('Tus datos han sido eliminados. La aplicación se reiniciará.'),
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
    final Color scrimColor =
        darkMode ? Colors.black.withOpacity(.55) : Colors.black.withOpacity(.25);

    /* ── color de texto/íconos sobre el scrim ── */
    final Color fg = darkMode ? Colors.white : Colors.white;

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
        subtitle:
            subtitle == null ? null : Text(subtitle, style: TextStyle(color: fg)),
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
                  trailing: Switch(
                      value: _notifDaily,
                      onChanged: _toggleDailyNotif,
                      activeColor: Theme.of(context).colorScheme.primary),
                ),
                _tile(
                  icon: Icons.flag,
                  title: 'Notificaciones de logros',
                  trailing: Switch(
                      value: _notifMilestones,
                      onChanged: _toggleMilestoneNotif,
                      activeColor: Theme.of(context).colorScheme.primary),
                ),
                _tile(
                  icon: Icons.cloud_sync,
                  title: 'Copias automáticas en Drive',
                  trailing: Switch(
                      value: _autoBackup,
                      onChanged: _toggleAutoBackup,
                      activeColor: Theme.of(context).colorScheme.primary),
                ),
                const Divider(),
                _tile(
                  icon: Icons.cloud_download,
                  title: 'Restaurar desde Drive',
                  onTap: _restoreFromDrive,
                ),
                const Divider(),
                _tile(
                  icon: Icons.refresh,
                  title: 'Reiniciar contador',
                  subtitle: 'Establece hoy y ahora como inicio',
                  onTap: _resetSoberDate,
                ),
                const Divider(),
                if (_startDate != null) ..._buildProgressSection(fg),
                const Divider(),
                _buildMoodSection(),
                const Divider(),
                // botón rojo mantiene su estilo
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Eliminar cuenta y datos',
                      style: TextStyle(color: Colors.red)),
                  onTap: _deleteAccountAndData,
                ),
                const SizedBox(height: 18),
                Text(
                  _kDisclaimer,
                  style: TextStyle(color: fg.withOpacity(.9), fontSize: 14),
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
        title: Text('Llevas $_daysClean días limpio', style: TextStyle(color: fg)),
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
        return ValueListenableBuilder(
          valueListenable: box.listenable(),
          builder: (_, __, ___) {
            final entries = box.values.toList();
            return Card(
              elevation: 1,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    const ListTile(
                      dense: true,
                      leading: Icon(Icons.show_chart),
                      title: Text('Tendencia de ánimo'),
                    ),
                    AspectRatio(
                      aspectRatio: 1.6,
                      child: MoodTrendChart(entries: entries),
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
