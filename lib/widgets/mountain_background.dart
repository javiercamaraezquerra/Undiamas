import 'package:flutter/material.dart';

/// Fondo ilustrado con montañas, sol y figura.
///   · Scrim superior para contraste (negro → transparente).  
///   · Figura estática (no se anima al cambiar de pestaña) y ligeramente
///     desplazada a la izquierda.
///   · Imagen de figura se muestra con sus colores originales (sin tinte).
class MountainBackground extends StatelessWidget {
  final int pageIndex;              // sigue moviendo sólo el sol
  final Duration duration;

  const MountainBackground({
    super.key,
    required this.pageIndex,
    this.duration = const Duration(milliseconds: 800),
  });

  Alignment get _sunAlignment => [
        const Alignment(0.65, -0.90),
        const Alignment(0.75, -0.95),
        const Alignment(0.55, -0.95),
        const Alignment(-0.25, -0.87),
        const Alignment(0.25, -0.90),
      ][pageIndex % 5];

  // figura fija
  static const Alignment _figureAlignment = Alignment(-0.65, 0.86);

  static const _figures = [
    'assets/images/figure_0.png',
    'assets/images/figure_1.png',
    'assets/images/figure_2.png',
    'assets/images/figure_3.png',
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, cs) {
      final w = cs.biggest.width;
      final sunDia = w * .35;
      final figDia = w * .26;

      return Stack(
        children: [
          /* 1 · Montañas */
          Positioned.fill(
            child: Image.asset(
              'assets/images/bg_mountains.png',
              alignment: Alignment.topCenter,
              fit: BoxFit.cover,
            ),
          ),

          /* 2 · Scrim superior */
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 120,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black45, Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

          /* 3 · Sol (animado) */
          AnimatedAlign(
            alignment: _sunAlignment,
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

          /* 4 · Figura (estática, sin tinte) */
          Align(
            alignment: _figureAlignment,
            child: Image.asset(
              _figures[pageIndex % _figures.length],
              width: figDia,
              fit: BoxFit.contain,
            ),
          ),
        ],
      );
    });
  }
}
