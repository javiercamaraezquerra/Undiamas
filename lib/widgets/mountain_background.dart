import 'package:flutter/material.dart';

/// Fondo ilustrado con montañas, sol y figura.
/// Incluye un *scrim* (degradado negro → transparente) en la parte superior
/// para garantizar contraste de los títulos independientemente del fondo.
class MountainBackground extends StatelessWidget {
  final int pageIndex;              // pestaña actual (0‑4)
  final Duration duration;

  const MountainBackground({
    super.key,
    required this.pageIndex,
    this.duration = const Duration(milliseconds: 800),
  });

  /* ───────── Posiciones ───────── */
  Alignment _sunPos(int i) => [
        const Alignment(0.00, -0.90),
        const Alignment(-0.55, -0.88),
        const Alignment(0.55, -0.86),
        const Alignment(-0.25, -0.87),
        const Alignment(0.25, -0.90),
      ][i % 5];

  Alignment _figPos(int i) => [
        const Alignment(0.00, 0.86),
        const Alignment(-0.40, 0.88),
        const Alignment(0.40, 0.86),
        const Alignment(0.10, 0.90),
        const Alignment(0.28, 0.86),
      ][i % 5];

  static const _figures = [
    'assets/images/figure_0.png',
    'assets/images/figure_1.png',
    'assets/images/figure_2.png',
    'assets/images/figure_3.png',
  ];

  /* ───────── Build ───────── */
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, cs) {
      final width   = cs.biggest.width;
      final sunDia  = width * .35;
      final figDia  = width * .26;

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

          /* 2 · Scrim superior para contraste */
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

          /* 3 · Sol */
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

          /* 4 · Figura */
          AnimatedAlign(
            alignment: _figPos(pageIndex),
            duration: duration,
            curve: Curves.easeInOut,
            child: Image.asset(
              _figures[pageIndex % _figures.length],
              width: figDia,
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
