import 'package:flutter/material.dart';

/// Fondo ilustrado con montañas y sol animado.
/// · `precacheImage` + `gaplessPlayback`  → sin flashes.  
/// · `Hero(tag:'sun')`                    → movimiento continuo entre pantallas.
class MountainBackground extends StatelessWidget {
  final int pageIndex;                 // determina la posición del sol
  final Duration duration;

  const MountainBackground({
    super.key,
    required this.pageIndex,
    this.duration = const Duration(milliseconds: 800),
  });

  /* posiciones del sol para hasta 5 páginas */
  Alignment get _sunPos => const [
        Alignment( 1.10, -0.75),
        Alignment( 0.90, -0.85),
        Alignment( 0.70, -0.95),
        Alignment( 0.50, -1.05),
        Alignment( 0.30, -1.15),
      ][pageIndex % 5];

  @override
  Widget build(BuildContext context) {
    /* precarga imágenes (solo la 1.ª vez) */
    precacheImage(const AssetImage('assets/images/sun.png'), context);
    precacheImage(const AssetImage('assets/images/bg_mountains.png'), context);

    return LayoutBuilder(builder: (_, cs) {
      final d = cs.maxWidth * .35; // diámetro del sol

      return Stack(children: [
        /* montañas */
        Positioned.fill(
          child: Image.asset(
            'assets/images/bg_mountains.png',
            alignment: Alignment.topCenter,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        ),

        /* scrim para contraste */
        const Positioned(
          top: 0, left: 0, right: 0, height: 120,
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

        /* sol animado */
        AnimatedAlign(
          alignment: _sunPos,
          duration: duration,
          curve: Curves.easeInOut,
          child: Hero(
            tag: 'sun',
            flightShuttleBuilder: (_, __, ___, ____, _____) => _sun(d),
            child: _sun(d),
          ),
        ),
      ]);
    });
  }

  Widget _sun(double dia) => ClipOval(
        child: Image.asset(
          'assets/images/sun.png',
          width: dia,
          height: dia,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      );
}
