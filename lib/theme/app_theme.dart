import 'package:flutter/material.dart';

/// Pequeño builder que evita el “flash” blanco entre pantallas
class _NoFlashBuilder extends PageTransitionsBuilder {
  const _NoFlashBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Desvanecemos la pantalla nueva sobre la anterior manteniendo el fondo
    return FadeTransition(opacity: animation, child: child);
  }
}

class AppTheme {
  /// Índigo original como color semilla
  static const _seed = Color(0xFF354DFF);

  /* ───────── Esquemas de Material 3 ───────── */
  static final _lightScheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: Brightness.light,
  );

  static final _darkScheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: Brightness.dark,
  );

  /* ───────── Tema claro ───────── */
  static final lightTheme = ThemeData(
    colorScheme: _lightScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: _lightScheme.surface,
    textTheme: const TextTheme(
      headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      bodyMedium: TextStyle(fontSize: 16),
    ).apply(bodyColor: Colors.black87, displayColor: Colors.black87),
    appBarTheme: const AppBarTheme(
      foregroundColor: Colors.white,
      backgroundColor: Colors.transparent,
      elevation: 0,
      titleTextStyle:
          TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withOpacity(.15),
      border: const OutlineInputBorder(),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _NoFlashBuilder(),
        TargetPlatform.iOS: _NoFlashBuilder(),
      },
    ),
  );

  /* ───────── Tema oscuro ───────── */
  static final darkTheme = ThemeData(
    colorScheme: _darkScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: _darkScheme.surface,
    textTheme: const TextTheme(
      headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      bodyMedium: TextStyle(fontSize: 16),
    ).apply(bodyColor: Colors.white, displayColor: Colors.white), // ← texto claro
    appBarTheme: const AppBarTheme(
      foregroundColor: Colors.white,
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withOpacity(.10),
      border: const OutlineInputBorder(),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _NoFlashBuilder(),
        TargetPlatform.iOS: _NoFlashBuilder(),
      },
    ),
  );
}
