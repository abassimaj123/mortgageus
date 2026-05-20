import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';

class AppTheme {
  AppTheme._();

  static const Color primary = Color(0xFF1B3A6B); // navy blue
  static const Color accent = Color(0xFFF59E0B); // amber
  // Aliases and extra palette
  static const Color secondary = accent; // compat alias used in main.dart
  static const Color primaryDark = Color(0xFF2A5298); // gradient end
  static const Color accentGood = Color(0xFF2E7D32); // dark green
  static const Color accentGoodLight = Color(0xFF43A047); // lighter green
  static const Color accentWarn = Color(0xFFF57C00); // amber-warn
  static const Color background = Color(0xFFF8F9FA);
  static const Color labelGray = Color(0xFF64748B); // slate-500
  static const Color surfaceTint = Color(0xFFEFF3FA); // light navy tint
  // Info box semantic colors
  static const Color infoSurface = Color(0xFFEFF6FF);
  static const Color infoBorder = Color(0xFFBFDBFE);
  static const Color infoIcon = Color(0xFF1D4ED8);
  static const Color infoText = Color(0xFF1E3A8A);
  // Tool icon colors
  static const Color toolRefi = Color(0xFF9B59B6); // purple
  static const Color toolHistory = Color(0xFF2ECC71); // emerald
  static const Color toolPmi = Color(0xFFE74C3C); // red
  static const Color toolInvestment = Color(0xFF0D9488); // teal-600
  static const Color toolFha = Color(0xFF1E3A8A); // FHA navy
  static const Color toolVa = Color(0xFFB91C1C); // VA red
  static const Color toolUsda = Color(0xFF15803D); // USDA green
  static const Color toolPmiDetail = Color(0xFF7C3AED); // purple-600
  static const Color toolPoints = Color(0xFFEA580C); // orange-600
  // Chart geometry tokens — delegated to CalcwiseChartTokens
  static const double chartCenterR = CalcwiseChartTokens.donutCenterR;
  static const double chartSectionR = CalcwiseChartTokens.donutSectionR;
  // Typography scale tokens
  static const double tableBodySize = CalcwiseChartTokens.tableBodySize;
  static const double tableHeaderSize = CalcwiseChartTokens.tableHeaderSize;

  static ThemeData get light =>
      CalcwiseThemeFactory.buildLight(primary: primary, accent: accent);
  static ThemeData get dark =>
      CalcwiseThemeFactory.buildDark(primary: primary, accent: accent);
}
