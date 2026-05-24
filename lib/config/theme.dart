import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ---------------------------------------------------------------------------
  // 旧 token（保留，避免破坏现有引用）
  // ---------------------------------------------------------------------------
  static const Color background = Color(0xFFFAF4EA);
  static const Color backgroundWarm = Color(0xFFFCF6EC);
  static const Color card = Color(0xFFFFFFFF);
  static const Color cardWhite = Color(0xFFFFFFFF);
  static const Color primary = Color(0xFF3FAEA3);
  static const Color primaryDeep = Color(0xFF1F6F69);
  static const Color accent = Color(0xFFF4A261);
  static const Color accentSoft = Color(0xFFFCE6CB);
  static const Color text = Color(0xFF2F2620);
  static const Color textSoft = Color(0xFF6E6259);
  static const Color border = Color(0xFFECE3D2);
  static const Color successSoft = Color(0xFFEAF5F1);

  // ---------------------------------------------------------------------------
  // 新 token
  // ---------------------------------------------------------------------------
  static const Color surface0 = Color(0xFFFAF4EA);
  static const Color surface1 = Color(0xFFFFFFFF);
  static const Color surface2 = Color(0xFFEAF5F1);
  static const Color primarySoft = Color(0xFF52B5AA);
  static const Color borderHairline = Color(0xFFECE3D2);
  static const Color borderStrong = Color(0xFFD9C7AE);
  static const Color textCaption = Color(0xFFA09387);
  static const Color warningSoft = Color(0xFFFDEED7);
  static const Color dangerSoft = Color(0xFFFCE3DA);
  /// 桌面/Web 预览时手机外框周围的"环境"底色。
  /// 比 surface0 略深，让手机轮廓清晰可见；不要太深，避免画面被切割感太强。
  static const Color outerBg = Color(0xFFE7DEC7);

  // ---------------------------------------------------------------------------
  // 圆角 / 间距常量
  // ---------------------------------------------------------------------------
  static const double radiusLarge = 16; // 卡片 / 大容器
  static const double radiusMedium = 12; // 按钮 / 输入框 / 列表项
  static const double radiusBubble = 20; // 聊天气泡 / Pill
  static const double radiusPill = 999;

  // ---------------------------------------------------------------------------
  // 字体 / TextTheme（字重重排，恢复信息层级）
  // ---------------------------------------------------------------------------
  static const String _fontFamily = 'Microsoft YaHei';

  static const TextTheme _textTheme = TextTheme(
    headlineLarge: TextStyle(
      fontSize: 34,
      height: 1.2,
      fontWeight: FontWeight.w700,
      color: text,
    ),
    headlineMedium: TextStyle(
      fontSize: 30,
      height: 1.22,
      fontWeight: FontWeight.w700,
      color: text,
    ),
    titleLarge: TextStyle(
      fontSize: 24,
      height: 1.25,
      fontWeight: FontWeight.w700,
      color: text,
    ),
    titleMedium: TextStyle(
      fontSize: 22,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: text,
    ),
    titleSmall: TextStyle(
      fontSize: 20,
      height: 1.35,
      fontWeight: FontWeight.w600,
      color: text,
    ),
    bodyLarge: TextStyle(
      fontSize: 21,
      height: 1.5,
      fontWeight: FontWeight.w500,
      color: text,
    ),
    bodyMedium: TextStyle(
      fontSize: 19,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: textSoft,
    ),
    bodySmall: TextStyle(
      fontSize: 17,
      height: 1.4,
      fontWeight: FontWeight.w500,
      color: textCaption,
    ),
    labelLarge: TextStyle(
      fontSize: 20,
      height: 1.2,
      fontWeight: FontWeight.w600,
      color: text,
    ),
    labelMedium: TextStyle(
      fontSize: 18,
      height: 1.2,
      fontWeight: FontWeight.w500,
      color: text,
    ),
    labelSmall: TextStyle(
      fontSize: 16,
      height: 1.2,
      fontWeight: FontWeight.w500,
      color: textCaption,
    ),
  );

  // ---------------------------------------------------------------------------
  // ColorScheme
  // ---------------------------------------------------------------------------
  static final ColorScheme _colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: primary,
    onPrimary: Colors.white,
    primaryContainer: surface2,
    onPrimaryContainer: primaryDeep,
    secondary: primaryDeep,
    onSecondary: Colors.white,
    secondaryContainer: surface2,
    onSecondaryContainer: primaryDeep,
    tertiary: accent,
    onTertiary: Colors.white,
    tertiaryContainer: accentSoft,
    onTertiaryContainer: text,
    error: const Color(0xFFD8624A),
    onError: Colors.white,
    errorContainer: dangerSoft,
    onErrorContainer: const Color(0xFF7A2B1A),
    surface: surface1,
    onSurface: text,
    surfaceContainerHighest: surface2,
    surfaceContainerHigh: const Color(0xFFF6EFE2),
    surfaceContainer: const Color(0xFFFBF5EA),
    surfaceContainerLow: surface0,
    surfaceContainerLowest: Colors.white,
    onSurfaceVariant: textSoft,
    outline: borderStrong,
    outlineVariant: borderHairline,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: text,
    onInverseSurface: surface0,
    inversePrimary: primarySoft,
    surfaceTint: primary,
  );

  // ---------------------------------------------------------------------------
  // Component themes
  // ---------------------------------------------------------------------------
  static final CardThemeData _cardTheme = CardThemeData(
    color: surface1,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusLarge),
      side: const BorderSide(color: borderHairline, width: 1),
    ),
  );

  static final InputDecorationTheme _inputDecorationTheme = InputDecorationTheme(
    filled: true,
    fillColor: surface1,
    isDense: false,
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    labelStyle: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: textSoft,
    ),
    floatingLabelStyle: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: primaryDeep,
    ),
    hintStyle: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: textCaption,
    ),
    helperStyle: const TextStyle(
      fontSize: 13,
      color: textSoft,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
      borderSide: const BorderSide(color: borderHairline, width: 1),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
      borderSide: const BorderSide(color: borderHairline, width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
      borderSide: const BorderSide(color: primaryDeep, width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
      borderSide: const BorderSide(color: Color(0xFFD8624A), width: 1),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
      borderSide: const BorderSide(color: Color(0xFFD8624A), width: 1.6),
    ),
  );

  static final FilledButtonThemeData _filledButtonTheme = FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
    ),
  );

  static final OutlinedButtonThemeData _outlinedButtonTheme =
      OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: primaryDeep,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      side: const BorderSide(color: borderStrong, width: 1),
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
    ),
  );

  static final TextButtonThemeData _textButtonTheme = TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: primaryDeep,
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      textStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
    ),
  );

  static final IconButtonThemeData _iconButtonTheme = IconButtonThemeData(
    style: IconButton.styleFrom(
      foregroundColor: primaryDeep,
      minimumSize: const Size(40, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
    ),
  );

  static const AppBarTheme _appBarTheme = AppBarTheme(
    backgroundColor: surface0,
    foregroundColor: text,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: text,
    ),
    toolbarTextStyle: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 15,
      color: textSoft,
    ),
    iconTheme: IconThemeData(color: primaryDeep, size: 24),
  );

  static final NavigationBarThemeData _navigationBarTheme =
      NavigationBarThemeData(
    backgroundColor: surface1,
    surfaceTintColor: Colors.transparent,
    indicatorColor: surface2,
    indicatorShape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusPill),
    ),
    elevation: 0,
    height: 88,
    labelTextStyle: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return TextStyle(
        fontSize: 16,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? primaryDeep : textSoft,
      );
    }),
    iconTheme: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return IconThemeData(
        color: selected ? primaryDeep : textSoft,
        size: 30,
      );
    }),
  );

  static const DividerThemeData _dividerTheme = DividerThemeData(
    color: borderHairline,
    thickness: 1,
    space: 1,
  );

  static final ChipThemeData _chipTheme = ChipThemeData(
    backgroundColor: surface1,
    selectedColor: surface2,
    disabledColor: surface0,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    labelStyle: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: text,
    ),
    secondaryLabelStyle: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: primaryDeep,
    ),
    side: const BorderSide(color: borderHairline, width: 1),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusPill),
    ),
  );

  static final SegmentedButtonThemeData _segmentedButtonTheme =
      SegmentedButtonThemeData(
    style: SegmentedButton.styleFrom(
      foregroundColor: text,
      selectedForegroundColor: Colors.white,
      selectedBackgroundColor: primary,
      backgroundColor: surface1,
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      side: const BorderSide(color: borderHairline, width: 1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
    ),
  );

  static final SwitchThemeData _switchTheme = SwitchThemeData(
    trackOutlineColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return primary;
      return borderHairline;
    }),
    thumbColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return Colors.white;
      return Colors.white;
    }),
    trackColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return primary;
      return const Color(0xFFE6DDCB);
    }),
  );

  static final SliderThemeData _sliderTheme = SliderThemeData(
    activeTrackColor: primary,
    inactiveTrackColor: const Color(0xFFE6DDCB),
    thumbColor: primary,
    overlayColor: primary.withValues(alpha: 0.12),
  );

  static const ProgressIndicatorThemeData _progressTheme =
      ProgressIndicatorThemeData(
    color: primary,
    linearTrackColor: borderHairline,
    circularTrackColor: borderHairline,
  );

  static final SnackBarThemeData _snackBarTheme = SnackBarThemeData(
    backgroundColor: text,
    contentTextStyle: const TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w500,
    ),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
    ),
    elevation: 2,
  );

  static const ListTileThemeData _listTileTheme = ListTileThemeData(
    tileColor: surface1,
    iconColor: primaryDeep,
    textColor: text,
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    minVerticalPadding: 12,
    titleTextStyle: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: text,
    ),
    subtitleTextStyle: TextStyle(
      fontSize: 14,
      color: textSoft,
    ),
  );

  static final DialogThemeData _dialogTheme = DialogThemeData(
    backgroundColor: surface1,
    surfaceTintColor: Colors.transparent,
    elevation: 4,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusLarge),
    ),
    titleTextStyle: const TextStyle(
      fontFamily: _fontFamily,
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: text,
    ),
    contentTextStyle: const TextStyle(
      fontFamily: _fontFamily,
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: textSoft,
      height: 1.5,
    ),
  );

  // ---------------------------------------------------------------------------
  // ThemeData 总装
  // ---------------------------------------------------------------------------
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    fontFamily: _fontFamily,
    colorScheme: _colorScheme,
    scaffoldBackgroundColor: surface0,
    canvasColor: surface0,
    textTheme: _textTheme,
    cardTheme: _cardTheme,
    inputDecorationTheme: _inputDecorationTheme,
    filledButtonTheme: _filledButtonTheme,
    outlinedButtonTheme: _outlinedButtonTheme,
    textButtonTheme: _textButtonTheme,
    iconButtonTheme: _iconButtonTheme,
    appBarTheme: _appBarTheme,
    navigationBarTheme: _navigationBarTheme,
    dividerTheme: _dividerTheme,
    chipTheme: _chipTheme,
    segmentedButtonTheme: _segmentedButtonTheme,
    switchTheme: _switchTheme,
    sliderTheme: _sliderTheme,
    progressIndicatorTheme: _progressTheme,
    snackBarTheme: _snackBarTheme,
    listTileTheme: _listTileTheme,
    dialogTheme: _dialogTheme,
    splashFactory: InkSparkle.splashFactory,
  );
}
