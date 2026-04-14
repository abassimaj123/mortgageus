import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary    = Color(0xFF1B3A6B); // navy blue
  static const Color secondary  = Color(0xFFD4A017); // gold
  static const Color accentGood = Color(0xFF2E7D32); // green
  static const Color accentWarn = Color(0xFFF57C00); // amber
  static const Color background = Color(0xFFF8F9FA);

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
