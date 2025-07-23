import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdb;
import 'package:timezone/timezone.dart' as tz;

/// visible en todos los builds (ajusta a false antes de publicar)
const bool _showTestTools = true;

/// Muestra la reflexión del día o la indicada por [dayIndex] (0‑364).
class ReflectionScreen extends StatefulWidget {
  final int? dayIndex;
  const ReflectionScreen({super.key, this.dayIndex});

  @override
  State<ReflectionScreen> createState() => _ReflectionScreenState();
}

class _ReflectionScreenState extends State<ReflectionScreen>
    with WidgetsBindingObserver {
  String? _header;
  String? _body;
  String? _loadError;
  late int _currentDoY; // 1‑365
  Timer? _midnightTimer;

  static const _soloPorHoyUrl = 'https://fzla.org/principio-diario/';
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /* ───────────────────────────── lifecycle ───────────────────────────── */
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadReflection();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.dayIndex == null) {
      final today = _dayOfYear(DateTime.now());
      if (today != _currentDoY) _loadReflection();
    }
  }

  /* ─────────────────────── carga de la reflexión ─────────────────────── */
  Future<void> _loadReflection() async {
    try {
      String raw = await rootBundle.loadString('assets/data/reflections.json');
      raw = raw.replaceAll(
          RegExp(r'/\*[^*]*\*+(?:[^/*][^*]*\*+)*/', dotAll: true), '');
      raw = raw
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      final data = jsonDecode(raw) as List<dynamic>;
      if (data.length < 365) throw const FormatException('Faltan reflexiones');

      _currentDoY = widget.dayIndex != null
          ? widget.dayIndex! + 1
          : _dayOfYear(DateTime.now());
      final idx = (_currentDoY - 1).clamp(0, 364);

      final md = data[idx] as String;
      final lines = LineSplitter.split(md).toList();
      if (lines.isEmpty) throw const FormatException('Sin contenido');

      _header = lines.first.replaceFirst(RegExp(r'^###\s*'), '').trim();
      _body = lines.skip(1).join('\n').trim();
      _loadError = null;
    } catch (e, st) {
      dev.log('Reflections load error', error: e, stackTrace: st);
      _loadError = 'No se pudo cargar la reflexión solicitada.';
    }
    if (mounted) setState(() {});
    if (widget.dayIndex == null) _scheduleMidnightReload();
  }

  void _scheduleMidnightReload() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final ms = nextMidnight.difference(now).inMilliseconds;
    _midnightTimer = Timer(Duration(milliseconds: ms + 1000), () {
      if (mounted) _loadReflection();
    });
  }

  int _dayOfYear(DateTime dt) => int.parse(DateFormat('D').format(dt));

  /* ─────────────────── helpers notificaciones test ─────────────────── */

  Future<void> _ensurePluginReady() async {
    // 1) zona horaria local
    try {
      tzdb.initializeTimeZones();
    } catch (_) {}
    // 2) inicialización rápida si fuera necesaria
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 6)),
    );
  }

  /// Programa una notificación que saltará en 10 s (canal “test”).
  Future<void> _scheduleTestNotification() async {
    try {
      await _ensurePluginReady();

      // ── Comprobar / solicitar EXACT_ALARM si la API lo soporta ──
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      bool exactGranted = false;
      if (android != null) {
        try {
          exactGranted =
              await (android as dynamic).hasExactAlarmPermission() ?? false;
          if (!exactGranted) {
            exactGranted =
                await (android as dynamic).requestExactAlarmsPermission() ??
                    false;
          }
        } catch (_) {
          // Método no disponible en esta versión del plugin → usamos modo inexacto
        }
      }

      final trigger =
          tz.TZDateTime.now(tz.local).add(const Duration(seconds: 10));

      await _plugin.zonedSchedule(
        99999,
        'TEST',
        'Esto es una prueba programada',
        trigger,
        const NotificationDetails(
          android: AndroidNotificationDetails(
              'test', 'Pruebas',
              importance: Importance.high, priority: Priority.high),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: exactGranted
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(exactGranted
              ? '⏰ Notificación exacta programada (10 s).'
              : '⏰ Programada en modo inexacto (puede retrasarse unos segundos).')));
    } catch (e) {
      _showError('Error al programar: $e');
    }
  }

  /// Envía una notificación inmediata (permite comprobar POST_NOTIFICATIONS).
  Future<void> _sendImmediateNotification() async {
    try {
      await _ensurePluginReady();
      await _plugin.show(
        88888,
        'Prueba inmediata',
        'Si lees esto, el permiso de notificaciones está OK',
        const NotificationDetails(
          android: AndroidNotificationDetails('test', 'Pruebas',
              importance: Importance.high, priority: Priority.high),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      _showError('Error al enviar: $e');
    }
  }

  /// Muestra todas las notificaciones pendientes.
  Future<void> _showPendingNotifications() async {
    try {
      await _ensurePluginReady();
      final list = await _plugin.pendingNotificationRequests();
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Notificaciones en cola'),
          content: SizedBox(
            width: double.maxFinite,
            child: list.isEmpty
                ? const Text('No hay notificaciones pendientes.')
                : ListView(
                    children: list
                        .map((n) => ListTile(
                              title: Text('${n.id} – ${n.title ?? ''}'),
                              subtitle: Text(n.body ?? ''),
                            ))
                        .toList(),
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar')),
          ],
        ),
      );
    } catch (e) {
      _showError('Error al obtener lista: $e');
    }
  }

  /* ────────────────────────────── UI ────────────────────────────── */
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reflexión diaria')),
        body: Center(child: Text(_loadError!, textAlign: TextAlign.center)),
      );
    }

    if (_header == null || _body == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Reflexión diaria')),
      body: Container(
        color: theme.scaffoldBackgroundColor,
        width: double.infinity,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_header!,
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                elevation: 1,
                color: theme.colorScheme.surface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: MarkdownBody(
                    data: _body!,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurface),
                      blockquotePadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      blockquoteDecoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        border: Border(
                          left: BorderSide(
                              color: theme.colorScheme.primary, width: 4),
                        ),
                      ),
                      blockquote: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurface,
                      ),
                      blockSpacing: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              /* ───────── enlace adicional ───────── */
              TextButton.icon(
                icon: const Icon(Icons.open_in_new),
                style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary),
                onPressed: () async {
                  final uri = Uri.parse(_soloPorHoyUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                  } else {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'No se pudo abrir el enlace, inténtalo más tarde.')));
                  }
                },
                label: const Text(
                  'Si también quieres ver la reflexión diaria de “Sólo por hoy”, '
                  'haz clic aquí para verla gratuitamente.',
                  textAlign: TextAlign.start,
                ),
              ),
              /* ───────── utilidades TEST (borrar antes de publicar) ───────── */
              if (_showTestTools) ...[
                const Divider(height: 32),
                Text('Herramientas de prueba',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _scheduleTestNotification,
                  child: const Text('Probar notificación (10 s)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _sendImmediateNotification,
                  child: const Text('Enviar ahora'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _showPendingNotifications,
                  child: const Text('Ver notificaciones pendientes'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
