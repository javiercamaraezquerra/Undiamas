import 'package:flutter/material.dart';

/// Fondo ilustrado con montañas y sol animado.
/// * Scrim superior para contraste (negro → transparente).  
/// * El **sol** se desplaza suavemente entre páginas (`pageIndex`).  
/// * Se ha eliminado la figura/frente: solo fondo + sol.
class MountainBackground extends StatelessWidget {
  final int pageIndex;                       // mueve únicamente el sol
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

  /* ───── BUILD ───── */
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, cs) {
      final width  = cs.biggest.width;
      final sunDia = width * .35;

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
        ],
      );
    });
  }
}
