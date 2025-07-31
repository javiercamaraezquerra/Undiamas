import 'package:flutter/material.dart';

/// Ruta con fundido opaco‑false: la pantalla anterior sigue visible
/// durante la transición, evitando el “pantallazo” blanco.
class FadeTransparentRoute<T> extends PageRouteBuilder<T> {
  FadeTransparentRoute({required WidgetBuilder builder})
      : super(
          opaque: false,
          barrierColor: Colors.transparent,
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, __, ___) => builder(_),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        );
}
