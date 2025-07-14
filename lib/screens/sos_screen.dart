import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});
  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  static const _helpline = 'tel:+34900845040';
  static const _emergency = 'tel:112';

  late final AudioPlayer _player;
  late final StreamSubscription<PlayerState> _playerSub;
  bool _isPlaying = false;
  String? _quote;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _playerSub = _player.playerStateStream.listen(
      (s) => setState(() => _isPlaying = s.playing),
    );
    _preloadAudio();
    _loadQuote();
  }

  Future<void> _preloadAudio() async {
    try {
      await _player.setAsset('assets/audio/relax60s.mp3');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se encontró el audio de meditación')));
      }
    }
  }

  Future<void> _loadQuote() async {
    final jsonStr = await rootBundle.loadString('assets/data/quotes.json');
    final List<dynamic> all = jsonDecode(jsonStr);
    setState(() => _quote = (all..shuffle(Random())).first as String);
  }

  Future<void> _toggleAudio() async {
    if (_player.audioSource == null) {
      await _preloadAudio();
    }
    try {
      _isPlaying ? await _player.pause() : await _player.play();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Error al reproducir el audio de meditación')));
      }
    }
  }

  Future<void> _callNumber(String number) async {
    final uri = Uri.parse(number);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  void dispose() {
    _playerSub.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Necesito ayuda')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Tengo ganas de consumir',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),

            // ── CALMA INMEDIATA ──────────────────────────────────────────
            _sectionTitle('Calma inmediata'),
            _actionButton(
              icon: Icons.self_improvement,
              label: 'Respirar 60 s',
              onTap: _showBreathingDialog,
            ),
            _actionButton(
              icon: Icons.fitness_center,
              label: 'Relajación muscular',
              onTap: _showMuscleDialog,
            ),
            _actionButton(
              icon: Icons.landscape,
              label: 'Visualización guiada',
              onTap: _showVisualizationDialog,
            ),
            _actionButton(
              icon: Icons.spa,
              label: 'Grounding 5‑4‑3‑2‑1',
              onTap: _showGroundingDialog,
            ),

            // ── DISTRÁETE ───────────────────────────────────────────────
            const SizedBox(height: 16),
            _sectionTitle('Distráete'),
            if (_quote != null)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_quote!, textAlign: TextAlign.center),
                ),
              ),
            _actionButton(
              icon: Icons.refresh,
              label: 'Otra cita',
              onTap: _loadQuote,
            ),
            _actionButton(
              icon: _isPlaying ? Icons.pause : Icons.headset,
              label: _isPlaying ? 'Pausar audio' : 'Audio de meditación',
              onTap: _toggleAudio,
            ),

            // ── PIDE AYUDA ──────────────────────────────────────────────
            const SizedBox(height: 16),
            _sectionTitle('Pide ayuda'),
            _actionButton(
              icon: Icons.support_agent,
              label: 'Línea ayuda',
              onTap: () => _callNumber(_helpline),
            ),
            _actionButton(
              icon: Icons.warning,
              label: 'Emergencias 112',
              onTap: () => _callNumber(_emergency),
            ),
          ],
        ),
      ),
    );
  }

  // ── Utilidades UI ─────────────────────────────────────────────────────
  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _actionButton(
          {required IconData icon,
          required String label,
          required VoidCallback onTap}) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: ElevatedButton.icon(
          icon: Icon(icon),
          label: Text(label),
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: const StadiumBorder(),
          ),
        ),
      );

  // ── Diálogos guiados ──────────────────────────────────────────────────
  void _showBreathingDialog() => showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _BreathingDialog(),
      );

  void _showMuscleDialog() => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Relajación muscular progresiva'),
          content: const Text(
              '1) Tensa pies y pantorrillas 5 s y suelta.\n'
              '2) Repite subiendo: muslos, abdomen, hombros, rostro.\n'
              '3) Inhala al tensar, exhala al soltar.\n'
              'Tarda ~2 min y reduce la activación simpática.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar')),
          ],
        ),
      );

  void _showVisualizationDialog() => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Visualización guiada'),
          content: const Text(
              'Imagina un lugar seguro (playa, bosque…).\n'
              'Observa colores, sonidos y temperatura.\n'
              'Respira lento y mantén la imagen 60 s.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar')),
          ],
        ),
      );

  void _showGroundingDialog() => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Grounding 5‑4‑3‑2‑1'),
          content: const Text(
              'Ancla tu atención al presente:\n\n'
              '✔ 5 cosas que puedas VER\n'
              '✔ 4 que puedas TOCAR\n'
              '✔ 3 que puedas OÍR\n'
              '✔ 2 que puedas OLER\n'
              '✔ 1 que puedas SABOREAR\n\n'
              'Lleva ~2 min.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Iniciar')),
          ],
        ),
      );
}

// ── Widget de respiración (círculo animado + temporizador) ─────────────
class _BreathingDialog extends StatefulWidget {
  const _BreathingDialog();

  @override
  State<_BreathingDialog> createState() => _BreathingDialogState();
}

class _BreathingDialogState extends State<_BreathingDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _seconds = 60;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _seconds--);
      if (_seconds == 0) {
        t.cancel();
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Respira conmigo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, child) => Transform.scale(
              scale: 0.5 + _ctrl.value * 0.5,
              child: child,
            ),
            child: const Icon(Icons.circle, size: 100, color: Colors.blue),
          ),
          const SizedBox(height: 12),
          Text('Tiempo restante: $_seconds s'),
        ],
      ),
    );
  }
}
