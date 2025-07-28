import 'package:flutter/material.dart';

/// Fondo ilustrado con montañas, sol y figura.
/// La figura no se anima entre pestañas; solo cambia la imagen mostrada.
class MountainBackground extends StatelessWidget {
  final int pageIndex;        // pestaña actual 0‑4
  final Duration duration;

  const MountainBackground({
    super.key,
    required this.pageIndex,
    this.duration = const Duration(milliseconds: 800),
  });

  /* ───────── posiciones del Sol ───────── */
  Alignment _sunPos(int i) {
    switch (i) {
      case 0: return const Alignment( 0.65, -0.94);
      case 1: return const Alignment(-0.55, -0.92);
      case 2: return const Alignment( 0.55, -0.90);
      case 3: return const Alignment(-0.25, -0.92);
      case 4: return const Alignment( 0.25, -0.93);
      default:return const Alignment(0,    -0.93);
    }
  }

  /* ───────── posición fija de la figura ───────── */
  static const Alignment _figureAlignment = Alignment(-0.85, 0.88);

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
      final sunDia     = size.width * .30; // ↓ más pequeño
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

          // 2 · Sol
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

          // 3 · Figura fija
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
