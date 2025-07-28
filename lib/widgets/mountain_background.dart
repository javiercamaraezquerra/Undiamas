import 'package:flutter/material.dart';

class MountainBackground extends StatelessWidget {
  final int pageIndex;
  final Duration duration;

  const MountainBackground({
    super.key,
    required this.pageIndex,
    this.duration = const Duration(milliseconds: 800),
  });

  Alignment _sunPos(int i) {
    switch (i) {
      case 0: return const Alignment( 0.00, -0.82);
      case 1: return const Alignment(-0.55, -0.78);
      case 2: return const Alignment( 0.55, -0.76);
      case 3: return const Alignment(-0.25, -0.74);
      case 4: return const Alignment( 0.20, -0.80);
      default:return const Alignment(0, -0.78);
    }
  }

  Alignment _figPos(int i) {
    switch (i) {
      case 0: return const Alignment( 0.00,  0.86);
      case 1: return const Alignment(-0.40,  0.88);
      case 2: return const Alignment( 0.40,  0.86);
      case 3: return const Alignment( 0.10,  0.90);
      case 4: return const Alignment( 0.28,  0.86);
      default:return const Alignment(0, 0.88);
    }
  }

  static const _figures = [
    'assets/images/figure_0.png',
    'assets/images/figure_1.png',
    'assets/images/figure_2.png',
    'assets/images/figure_3.png',
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, cs) {
      final size      = cs.biggest;
      final sunDia    = size.width * .25;
      final figureDia = size.width * .26;

      return Stack(
        children: [
          Positioned.fill(
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                  Colors.white.withOpacity(0.15), BlendMode.srcATop),
              child: Image.asset(
                'assets/images/bg_mountains_vert.jpg',
                alignment: Alignment.topCenter,
                fit: BoxFit.cover,
              ),
            ),
          ),
          // —— Sol usando sun.png + ClipOval ——
          AnimatedAlign(
            alignment: _sunPos(pageIndex),
            duration: duration,
            curve: Curves.easeInOut,
            child: ClipOval(
              child: Image.asset(
                'assets/images/sun.png',
                width: sunDia,
                height: sunDia,
                fit: BoxFit.cover,
              ),
            ),
          ),
          // —— Figura ——
          AnimatedAlign(
            alignment: _figPos(pageIndex),
            duration: duration,
            curve: Curves.easeInOut,
            child: Image.asset(
              _figures[pageIndex % _figures.length],
              width: figureDia,
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
