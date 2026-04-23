import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color _ink = Color(0xFF11233F);

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: const Color(0xFFF3F8FF),
    fontFamily: 'Segoe UI',
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        color: _ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: _ink,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: _ink,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: _ink,
      ),
      bodyLarge: TextStyle(
        fontSize: 18,
        color: Color(0xFF2C3E55),
      ),
      bodyMedium: TextStyle(
        fontSize: 15,
        color: Color(0xFF50657C),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: _ink,
      titleTextStyle: TextStyle(
        fontFamily: 'Segoe UI',
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: _ink,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withOpacity(0.92),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD6E4F5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD6E4F5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF1D4ED8), width: 1.4),
      ),
    ),
  );
}
