import 'package:flutter/material.dart';

/// Fondo ilustrado con montañas, sol y figura.
/// * Scrim superior para contraste (negro → transparente).  
/// * El **sol** sigue animándose entre pantallas.  
/// * La **figura** se muestra al 75 % de su tamaño original y
///   puede cambiar de posición en cada página.
class MountainBackground extends StatelessWidget {
  final int pageIndex;                       // mueve sol + figura
  final Duration duration;

  const MountainBackground({
    super.key,
    required this.pageIndex,
    this.duration = const Duration(milliseconds: 800),
  });

  /* ───── Posiciones del sol (por página) ───── */
  Alignment get _sunAlignment => const [
        Alignment( 1.10, -0.75),
        Alignment( 0.90, -0.85),
        Alignment( 0.70, -0.95),
        Alignment( 0.50, -1.05),
        Alignment( 0.30, -1.15),
      ][pageIndex % 5];

  /* ───── Posiciones de la figura (por página) ───── */
  static const _figureAlignments = [
    Alignment(-0.85, 0.56),
    Alignment(-0.70, 0.58),
    Alignment(-0.60, 0.60),
    Alignment(-0.50, 0.58),
    Alignment(-0.40, 0.56),
  ];

  Alignment get _figureAlignment =>
      _figureAlignments[pageIndex % _figureAlignments.length];

  /* ───── Rutas de las figuras ─────
     Sustituye estas imágenes por las nuevas; el código ya las escalará */
  static const _figures = [
    'assets/images/figure_0.png',
    'assets/images/figure_1.png',
    'assets/images/figure_2.png',
    'assets/images/figure_3.png',
  ];

  /* ───── BUILD ───── */
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, cs) {
      final width = cs.biggest.width;

      /* Tamaños relativos */
      final sunDia   = width * .35;          // igual que antes
      final figDia   = width * .20 ;    // reducir tamaño imagen

      return Stack(
        children: [
          /* 1 ▸ Montañas */
          Positioned.fill(
            child: Image.asset(
              'assets/images/bg_mountains.png',
              alignment: Alignment.topCenter,
              fit: BoxFit.cover,
            ),
          ),

          /* 2 ▸ Scrim superior */
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

          /* 3 ▸ Sol (animado) */
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

          /* 4 ▸ Figura (posicionable y escalada) */
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
