import 'package:flutter/material.dart';

/// Escena de fondo animada (montañas + sol + figura).
///
/// Si más adelante sustituyes los place‑holders por PNG independientes,
/// basta con reemplazar los widgets `_sun()` y `_figure()` por sendos
/// `Image.asset('assets/images/sun.png')` y `Image.asset('assets/images/figure.png')`.
class MountainBackground extends StatelessWidget {
  final int pageIndex;
  /// Animación lenta (1,2 s). Ajusta si lo ves necesario.
  final Duration duration;

  const MountainBackground({
    super.key,
    required this.pageIndex,
    this.duration = const Duration(milliseconds: 1200),
  });

  //─────────────────────────────────────────────────────────────────────────────
  // Posiciones predefinidas por pestaña
  //─────────────────────────────────────────────────────────────────────────────
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

  //─────────────────────────────────────────────────────────────────────────────
  // Widgets auxiliares (place‑holders)
  //─────────────────────────────────────────────────────────────────────────────
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
        color: Color(0xFF0D47A1), // azul oscuro aprox. silueta
      );

  //─────────────────────────────────────────────────────────────────────────────
  // Build
  //─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          // Fondo estático
          Image.asset(
            'assets/images/bg_mountains.jpg',
            fit: BoxFit.cover,
          ),

          // Sol animado
          Hero(
            tag: 'hero_sun',
            child: AnimatedAlign(
              alignment: _sunPos(pageIndex),
              duration: duration,
              curve: Curves.easeInOut,
              child: _sun(),
            ),
          ),

          // Figura animada
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
