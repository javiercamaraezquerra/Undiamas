import 'package:flutter/material.dart';

class _NoFlashBuilder extends PageTransitionsBuilder {
  const _NoFlashBuilder();
  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child) {
    return FadeTransition(opacity: animation, child: child);
  }
}
