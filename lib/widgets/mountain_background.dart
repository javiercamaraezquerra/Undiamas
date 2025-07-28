import 'package:flutter/material.dart';

/// Escena de fondo animada (montañas + sol + figura).
///
/// De momento usamos place‑holders vectoriales para el sol y la figura.
/// Más adelante podrás sustituirlos por PNG independientes:
///   child: Image.asset('assets/images/sun.png', width: 180),
///   child: Image.asset('assets/images/figure.png', width: 220),
class MountainBackground extends StatelessWidget {
  final int pageIndex;
  final Duration duration; // Animación lenta (1,2 s por defecto)

  const MountainBackground({
    super.key,
    required this.pageIndex,
    this.duration = const Duration(milliseconds: 1200),
  });

  //──────────────────────── Posiciones predefinidas ──────────────────────────
  Alignment _sunPos(int i) {
    switch (i) {
      case 0: return const Alignment( 0.00,  0.15); // Home
      case 1: return const Alignment(-0.55, -0.10); // Diario
      case 2: return const Alignment( 0.55, -0.20); // Reflexión
      case 3: return const Alignment(-0.25,  0.30); // Recursos
      case 4: return const Alignment( 0.00, -0.25); // Perfil
      default:return Alignment.center;
    }
  }

  Alignment _figurePos(int i) {
    switch (i) {
      case 0: return const Alignment( 0.00,  0.83);
      case 1: return const Alignment(-0.45,  0.85);
      case 2: return const Alignment( 0.45,  0.82);
      case 3: return const Alignment( 0.10,  0.88);
      case 4: return const Alignment( 0.35,  0.83);
      default:return Alignment.bottomCenter;
    }
  }

  //───────────────────────── Widgets place‑holder ────────────────────────────
  Widget _sun() => Container(
        width: 180,
        height: 180,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [Color(0xFFFFE59D), Color(0xFFFFC56E)],
            center: Alignment(-0.15, -0.25),
            radius: 0.9,
          ),
        ),
      );

  Widget _figure() => const Icon(
        Icons.self_improvement,
        size: 220,
        color: Color(0xFF0D47A1), // azul oscuro
      );

  //──────────────────────────────── Build ────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          // 1) Imagen de fondo
          Image.asset(
            'assets/images/bg_mountains.jpg',
            fit: BoxFit.cover,
          ),

          // 2) Sol animado
          Hero(
            tag: 'hero_sun',
            child: AnimatedAlign(
              alignment: _sunPos(pageIndex),
              duration: duration,
              curve: Curves.easeInOut,
              child: _sun(),
            ),
          ),

          // 3) Figura animada
          Hero(
            tag: 'hero_figure',
            child: AnimatedAlign(
              alignment: _figurePos(pageIndex),
              duration: duration,
              curve: Curves.easeInOut,
              child: _figure(),
            ),
          ),
        ],
      ),
    );
  }
}
