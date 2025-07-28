import 'package:flutter/material.dart';

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
      foregroundColor: Colors.white,           // texto / iconos
      backgroundColor: Colors.transparent,     // lo oscurece el scrim
      elevation: 0,
      titleTextStyle:
          TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withOpacity(.15), // fondo semitransparente
      border: const OutlineInputBorder(),
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
    ),
    appBarTheme: const AppBarTheme(
      foregroundColor: Colors.white,
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
  );
}
