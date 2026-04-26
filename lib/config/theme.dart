import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color background = Color(0xFFFDF6EC);
  static const Color backgroundWarm = Color(0xFFFFF8EF);
  static const Color card = Color(0xFFFFFDF8);
  static const Color cardWhite = Color(0xFFFFFFFF);
  static const Color primary = Color(0xFF3FAEA3);
  static const Color primaryDeep = Color(0xFF247A74);
  static const Color accent = Color(0xFFF4A261);
  static const Color accentSoft = Color(0xFFFFE8C7);
  static const Color text = Color(0xFF3A2A22);
  static const Color textSoft = Color(0xFF7B6F66);
  static const Color border = Color(0xFFF0DDC8);
  static const Color successSoft = Color(0xFFE8F6F2);

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    fontFamily: 'Microsoft YaHei',
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: background,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 34,
        height: 1.18,
        fontWeight: FontWeight.w800,
        color: text,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        height: 1.22,
        fontWeight: FontWeight.w800,
        color: text,
      ),
      titleLarge: TextStyle(
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w800,
        color: text,
      ),
      titleMedium: TextStyle(
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      bodyLarge: TextStyle(
        fontSize: 19,
        height: 1.55,
        color: text,
      ),
      bodyMedium: TextStyle(
        fontSize: 16,
        height: 1.5,
        color: textSoft,
      ),
    ),
  );
}
