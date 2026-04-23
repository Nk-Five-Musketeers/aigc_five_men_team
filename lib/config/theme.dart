import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF1E88E5),
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: const Color(0xFFF5F7FA),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
      titleLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 20),
      bodyMedium: TextStyle(fontSize: 18),
    ),
  );
}
