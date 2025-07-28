import 'dart:async';
import 'package:flutter/material.dart';

/// Fondo con montañas, sol desplazable y figura animada.
class MountainBackground extends StatelessWidget {
  final int pageIndex;
  final Duration duration;

  const MountainBackground({
    super.key,
    required this.pageIndex,
    this.duration = const Duration(milliseconds: 1000),
  });

  /* ── posiciones relativas (‑1..1) ── */
  Alignment _sunPos(int i) {
    switch (i) {
      case 0: return const Alignment( 0.00, -0.70);
      case 1: return const Alignment(-0.55, -0.60);
      case 2: return const Alignment( 0.55, -0.55);
      case 3: return const Alignment(-0.25, -0.50);
      case 4: return const Alignment( 0.15, -0.65);
      default:return const Alignment(0, -0.6);
    }
  }

  Alignment _figPos(int i) {
    switch (i) {
      case 0: return const Alignment( 0.00,  0.80);
      case 1: return const Alignment(-0.40,  0.82);
      case 2: return const Alignment( 0.40,  0.80);
      case 3: return const Alignment( 0.10,  0.85);
      case 4: return const Alignment( 0.30,  0.80);
      default:return const Alignment(0, 0.8);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, cs) {
      final size = cs.biggest;
      final sunDia   = size.width * .30; // 30 % (no tapa UI)
      final figureSz = size.width * .28; // 28 %

      return Stack(
        children: [
          // Imagen vertical (rellena arriba, recorta laterales si hace falta)
          Positioned.fill(
            child: Image.asset(
              'assets/images/bg_mountains.png',
              alignment: Alignment.topCenter,
              fit: BoxFit.cover,
            ),
          ),

          // Degradado de relleno (por si falta imagen abajo)
          Positioned.fill(
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(0, 0.6),
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),
          ),

          // Sol
          AnimatedAlign(
            alignment: _sunPos(pageIndex),
            duration: duration,
            curve: Curves.easeInOut,
            child: Image.asset(
              'assets/images/sun.png',
              width: sunDia,
              height: sunDia,
              fit: BoxFit.contain,
            ),
          ),

          // Colina frontal para “apoyar” la figura
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: figureSz * 0.7,
            child: CustomPaint(
              painter: _HillPainter(color: const Color(0xFF051933)),
            ),
          ),

          // Figura animada (4 frames, cambio cada 2 s)
          AnimatedAlign(
            alignment: _figPos(pageIndex),
            duration: duration,
            curve: Curves.easeInOut,
            child: _AnimatedFigure(size: figureSz),
          ),
        ],
      );
    });
  }
}

/* ── Figura con animación de fotogramas ── */
class _AnimatedFigure extends StatefulWidget {
  final double size;
  const _AnimatedFigure({required this.size});

  @override
  State<_AnimatedFigure> createState() => _AnimatedFigureState();
}

class _AnimatedFigureState extends State<_AnimatedFigure> {
  static const _frames = [
    'assets/images/figure_0.png',
    'assets/images/figure_1.png',
    'assets/images/figure_2.png',
    'assets/images/figure_3.png',
  ];
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      setState(() => _index = (_index + 1) % _frames.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: Image.asset(
        _frames[_index],
        key: ValueKey(_index),
        width: widget.size,
        fit: BoxFit.contain,
        color: const Color(0xFF0D47A1),
        colorBlendMode: BlendMode.srcATop,
      ),
    );
  }
}

/* ── Dibuja una colina oscura ── */
class _HillPainter extends CustomPainter {
  final Color color;
  const _HillPainter({required this.color});

  @override
  void paint(Canvas c, Size s) {
    final p = Path()
      ..moveTo(0, s.height * 0.4)
      ..quadraticBezierTo(
          s.width * 0.3, s.height * 0.10, s.width * 0.6, s.height * 0.25)
      ..quadraticBezierTo(
          s.width * 0.9, s.height * 0.40, s.width, s.height * 0.20)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();

    c.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
