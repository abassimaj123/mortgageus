import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary          = Color(0xFF1B3A6B); // navy blue
  static const Color primaryDark      = Color(0xFF2A5298); // gradient end
  static const Color secondary        = Color(0xFFD4A017); // gold
  static const Color accentGood       = Color(0xFF2E7D32); // dark green
  static const Color accentGoodLight  = Color(0xFF43A047); // lighter green (gradient)
  static const Color accentWarn       = Color(0xFFF57C00); // amber
  static const Color background       = Color(0xFFF8F9FA);
  // Tool icon colors
  static const Color toolRefi         = Color(0xFF9B59B6); // purple
  static const Color toolHistory      = Color(0xFF2ECC71); // emerald
  static const Color toolPmi          = Color(0xFFE74C3C); // red

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ).copyWith(
      primary:   primary,
      secondary: secondary,
      surface:   background,
    ),
    fontFamily: 'Inter',
    appBarTheme: const AppBarTheme(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    ).copyWith(secondary: secondary),
    fontFamily: 'Inter',
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.grey[900],
      foregroundColor: Colors.white,
      elevation: 0,
    ),
  );
}
