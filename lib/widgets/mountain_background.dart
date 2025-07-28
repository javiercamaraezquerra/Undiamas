import 'package:flutter/material.dart';

/// Escena de fondo persistente con:
///   1) Imagen de montañas (`bg_mountains.png`)
///   2) Sol (círculo con degradado)
///   3) Figura (icono de persona meditando)
///
/// Las posiciones de sol y figura cambian suavemente al cambiar de pestaña.
/// `Hero` permite que la animación continúe si navegas a otras pantallas
/// que reutilicen esas etiquetas.
class MountainBackground extends StatelessWidget {
  final int pageIndex;
  final Duration duration;  // animación lenta (1,2 s)

  const MountainBackground({
    super.key,
    required this.pageIndex,
    this.duration = const Duration(milliseconds: 1200),
  });

  //─────────────────── Posiciones predefinidas ───────────────────
  Alignment _sunPos(int i) {
    switch (i) {
      case 0: return const Alignment( 0.00,  0.15);
      case 1: return const Alignment(-0.55, -0.10);
      case 2: return const Alignment( 0.55, -0.20);
      case 3: return const Alignment(-0.25,  0.30);
      case 4: return const Alignment( 0.00, -0.25);
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

  //──────────────────── Widgets auxiliares ───────────────────────
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
        color: Color(0xFF0D47A1),
      );

  //────────────────────────── Build ───────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          // Fondo ilustrado
          Image.asset(
            'assets/images/bg_mountains.png',
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
