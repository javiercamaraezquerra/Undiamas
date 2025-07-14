import 'package:flutter/material.dart';

class AppTheme {
  /// Índigo original como color semilla
  static const _seed = Color(0xFF354DFF);

  /// Esquema claro
  static final _lightScheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: Brightness.light,
  );

  /// Esquema oscuro
  static final _darkScheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: Brightness.dark,
  );

  /// Tema claro Material 3
  static final lightTheme = ThemeData(
    colorScheme: _lightScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: _lightScheme.surface,
    textTheme: const TextTheme(
      headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      bodyMedium: TextStyle(fontSize: 16),
    ),
  );

  /// Tema oscuro Material 3
  static final darkTheme = ThemeData(
    colorScheme: _darkScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: _darkScheme.surface,
    textTheme: const TextTheme(
      headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      bodyMedium: TextStyle(fontSize: 16),
    ),
  );
}
