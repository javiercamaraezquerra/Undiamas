import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:async';                      // ⬅️ Timer
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';         // ⬅️ Día del año

/// Muestra la reflexión correspondiente al día del año.
/// • Recarga automáticamente si el usuario atraviesa la medianoche
///   estando dentro de la app o al volver del segundo plano.
class ReflectionScreen extends StatefulWidget {
  const ReflectionScreen({super.key});

  @override
  State<ReflectionScreen> createState() => _ReflectionScreenState();
}

class _ReflectionScreenState extends State<ReflectionScreen>
    with WidgetsBindingObserver {
  String? _header;        // Ej.: Día 197 – 15 Julio
  String? _body;          // Markdown
  String? _loadError;
  late int _currentDoY;   // Día del año que estamos mostrando
  Timer? _midnightTimer;  // Dispara justo a las 00:00

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadToday();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  /* ──────────────── Recarga al volver a primer plano ──────────────── */
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final today = _dayOfYear(DateTime.now());
      if (today != _currentDoY) _loadToday();        // nuevo día
    }
  }

  /* ──────────────── Carga reflexión de hoy ──────────────── */
  Future<void> _loadToday() async {
    try {
      /* 1) Leer JSON y quitar comentarios ........................... */
      String raw =
          await rootBundle.loadString('assets/data/reflections.json');
      raw = raw.replaceAll(
          RegExp(r'/\*[^*]*\*+(?:[^/*][^*]*\*+)*/', dotAll: true), '');
      raw = raw
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      final data = jsonDecode(raw) as List<dynamic>;
      if (data.length < 365) throw const FormatException('Faltan reflexiones');

      /* 2) Calcular índice (día del año local, 0‑364) ............... */
      final now = DateTime.now();
      _currentDoY = _dayOfYear(now);
      final idx = (_currentDoY - 1).clamp(0, 364);

      final md = data[idx] as String;

      /* 3) Separar cabecera y cuerpo Markdown ....................... */
      final lines = LineSplitter.split(md).toList();
      if (lines.isEmpty) throw const FormatException('Sin contenido');

      _header = lines.first.replaceFirst(RegExp(r'^###\s*'), '').trim();
      _body = lines.skip(1).join('\n').trim();
      _loadError = null;
    } catch (e, st) {
      dev.log('Reflections load error', error: e, stackTrace: st);
      _loadError = 'No se pudo cargar la reflexión de hoy.';
    }
    if (mounted) setState(() {});
    _scheduleMidnightReload();
  }

  /* ──────────────── Programa recarga automática a las 00:00 ───────── */
  void _scheduleMidnightReload() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final msUntilMidnight = nextMidnight.difference(now).inMilliseconds;
    _midnightTimer = Timer(Duration(milliseconds: msUntilMidnight + 1000), () {
      if (mounted) _loadToday();
    });
  }

  /* ──────────────── Util ──────────────── */
  int _dayOfYear(DateTime dt) => int.parse(DateFormat('D').format(dt));

  /* ──────────────── UI ──────────────── */
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
              /* Encabezado */
              Text(
                _header!,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              /* Cuerpo Markdown */
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
            ],
          ),
        ),
      ),
    );
  }
}
