import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color text = Color(0xFF24476B);
  static const Color textSoft = Color(0xFF7390AC);
  static const Color blue = Color(0xFF6AAEF1);
  static const Color blueDeep = Color(0xFF4B95E2);
  static const Color blueSoft = Color(0xFFDFEEFF);
  static const Color line = Color(0x29679CD4);

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    fontFamily: 'Microsoft YaHei',
    colorScheme: ColorScheme.fromSeed(
      seedColor: blue,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: const Color(0xFFEDF6FF),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontSize: 30,
        height: 1.2,
        fontWeight: FontWeight.w800,
        color: text,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: text,
      ),
      titleMedium: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      bodyLarge: TextStyle(
        fontSize: 19,
        height: 1.6,
        color: text,
      ),
      bodyMedium: TextStyle(
        fontSize: 15,
        height: 1.5,
        color: textSoft,
      ),
    ),
  );
}
