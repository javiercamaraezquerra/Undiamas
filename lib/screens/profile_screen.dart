import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../models/diary_entry.dart';
import '../services/achievement_service.dart';
import '../services/drive_backup_service.dart';
import '../services/encryption_service.dart';
import '../utils/mood_trend.dart';
import '../widgets/mood_trend_chart.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  /* ─── estado ─── */
  bool _isDark = false;
  bool _notifDaily = true;
  bool _notifMilestones = true;

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

  /* ───────────────── helpers preferencias ───────────────── */
  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _isDark = prefs.getBool('isDarkMode') ?? false;
    _notifDaily = prefs.getBool('notifyDailyReflection') ?? true;
    _notifMilestones = prefs.getBool('notifyMilestones') ?? true;

    /* fecha inicio sobriedad */
    final cipher = await EncryptionService.getCipher();
    final box = await Hive.openBox('udm_secure', encryptionCipher: cipher);
    if (box.containsKey('startDate')) {
      _startDate = DateTime.parse(box.get('startDate'));
      _daysClean = DateTime.now().difference(_startDate!).inDays;
    }
    if (mounted) setState(() {});
  }

  /* ───────────────── toggles UI ───────────────── */
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

  /* ───────────────── backup & restore ───────────────── */
  Future<bool> _confirmDriveConsent() async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Copia en Google Drive'),
            content: const Text(
                'Se abrirá una ventana de Google para que autorices el acceso '
                'a tu Drive (solo a la carpeta privada de la app). '
                'Si lo rechazas, la app seguirá funcionando, pero podrías '
                'perder los datos si cambias de móvil o reinstalas.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No gracias'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continuar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _backupToDrive() async {
    if (!await _confirmDriveConsent()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Copia no realizada. Puedes perder datos si cambias de dispositivo.')));
      }
      return;
    }

    final cipher = await EncryptionService.getCipher();
    final udm = await Hive.openBox('udm_secure', encryptionCipher: cipher);
    final diary =
        await Hive.openBox<DiaryEntry>('diary_secure', encryptionCipher: cipher);

    final ok =
        await DriveBackupService.uploadBackup(DriveBackupService.exportHive(udm, diary));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(ok ? 'Copia subida a Google Drive' : 'Error subiendo la copia.'),
    ));
  }

  Future<void> _restoreFromDrive() async {
    if (!await _confirmDriveConsent()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Restauración cancelada. Continúas con los datos locales.')));
      }
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Descargando copia…')));

    final data = await DriveBackupService.downloadBackup();
    if (data == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se encontró copia en Drive.')));
      }
      return;
    }

    final cipher = await EncryptionService.getCipher();
    final udm = await Hive.openBox('udm_secure', encryptionCipher: cipher);
    final diary =
        await Hive.openBox<DiaryEntry>('diary_secure', encryptionCipher: cipher);
    await DriveBackupService.importHive(data, udm, diary);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos restaurados con éxito.')));
      _loadPrefs();
    }
  }

  /* ───────────────── reset contador ───────────────── */
  Future<void> _resetSoberDate() async {
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Contador reiniciado!')));
    }
  }

  /* ───────────────── UI ───────────────── */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text('Modo oscuro'),
            trailing: Switch(value: _isDark, onChanged: _toggleTheme),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Notificación diaria de reflexión'),
            trailing: Switch(value: _notifDaily, onChanged: _toggleDailyNotif),
          ),
          ListTile(
            leading: const Icon(Icons.flag),
            title: const Text('Notificaciones de logros'),
            trailing:
                Switch(value: _notifMilestones, onChanged: _toggleMilestoneNotif),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.cloud_upload),
            title: const Text('Copia en Google Drive'),
            onTap: _backupToDrive,
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download),
            title: const Text('Restaurar desde Drive'),
            onTap: _restoreFromDrive,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Reiniciar contador'),
            subtitle: const Text('Establece hoy y ahora como inicio'),
            onTap: _resetSoberDate,
          ),
          const Divider(),
          if (_startDate != null) ..._buildProgressSection(),
          const Divider(),
          _buildMoodSection(),
        ],
      ),
    );
  }

  /* ─── componentes auxiliares ─── */
  List<Widget> _buildProgressSection() {
    final milestones = AchievementService.milestones.keys.toList()..sort();
    final next = milestones.firstWhere((d) => _daysClean < d, orElse: () => -1);

    return [
      ListTile(
        leading: const Icon(Icons.celebration),
        title: Text('Llevas $_daysClean días limpio'),
        subtitle: Text('Desde ${DateFormat.yMMMd().format(_startDate!)}'),
      ),
      if (next != -1)
        ListTile(
          leading: const Icon(Icons.flag_outlined),
          title: Text('Próximo hito: $next días'),
          subtitle: Text(AchievementService.milestones[next]!),
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
            final trend = moodTrendSign(entries);
            final avg = entries.isEmpty
                ? 2.0
                : entries.map((e) => e.mood).reduce((a, b) => a + b) /
                    entries.length;
            final icon = ['😢', '😕', '😐', '🙂', '😄'][avg.round()];

            late String phrase;
            if (entries.length < 2) {
              phrase = 'Añade más entradas para ver tu evolución 📈';
            } else if (trend == 1) {
              phrase = '¡Tu ánimo va mejorando $icon  Mantén el rumbo!';
            } else if (trend == -1) {
              phrase = 'Tu curva baja $icon  Refuerza tus estrategias 🙏';
            } else {
              phrase = 'Tu estado de ánimo se mantiene estable $icon';
            }

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
                    const SizedBox(height: 8),
                    Text(
                      phrase,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
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
