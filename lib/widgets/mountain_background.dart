import 'package:flutter/material.dart';

/// Fondo ilustrado con montañas, sol y figura.
/// La figura ahora NO se mueve entre pestañas; sólo cambia la imagen.
class MountainBackground extends StatelessWidget {
  final int pageIndex;                       // índice actual 0‑4
  final Duration duration;

  const MountainBackground({
    super.key,
    required this.pageIndex,
    this.duration = const Duration(milliseconds: 800),
  });

  /* ───────── posiciones ───────── */
  Alignment _sunPos(int i) {
    switch (i) {
      case 0: return const Alignment( 0.00, -0.90);
      case 1: return const Alignment(-0.55, -0.88);
      case 2: return const Alignment( 0.55, -0.86);
      case 3: return const Alignment(-0.25, -0.87);
      case 4: return const Alignment( 0.25, -0.89);
      default:return const Alignment(0, -0.88);
    }
  }

  // Figura fija, un poco más cerca del borde izquierdo
  static const Alignment _figureAlignment = Alignment(-0.65, 0.88);

  static const _figures = [
    'assets/images/figure_0.png',
    'assets/images/figure_1.png',
    'assets/images/figure_2.png',
    'assets/images/figure_3.png',
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, cs) {
      final size       = cs.biggest;
      final sunDia     = size.width * .35;
      final figureSize = size.width * .26;

      return Stack(
        children: [
          // 1 · Montañas
          Positioned.fill(
            child: Image.asset(
              'assets/images/bg_mountains.png',
              alignment: Alignment.topCenter,
              fit: BoxFit.cover,
            ),
          ),

          // 2 · Sol (sigue animando)
          AnimatedAlign(
            alignment: _sunPos(pageIndex),
            duration: duration,
            curve: Curves.easeInOut,
            child: ClipOval(
              child: Image.asset(
                'assets/images/sun.png',
                width: sunDia,
                height: sunDia,
                fit: BoxFit.contain,
              ),
            ),
          ),

          // 3 · Figura: misma posición siempre, sólo cambia PNG
          Align(
            alignment: _figureAlignment,
            child: Image.asset(
              _figures[pageIndex % _figures.length],
              width: figureSize,
              fit: BoxFit.contain,
              color: const Color(0xFF0D47A1),
              colorBlendMode: BlendMode.srcATop,
            ),
          ),
        ],
      );
    });
  }
}
