import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Brand Primary & Accents
  static const Color primary = Color(0xFF2563EB); // Royal Blue
  static const Color primaryHover = Color(0xFF1D4ED8);
  static const Color primaryLight = Color(0xFFDBEAFE);
  static const Color primaryDark = Color(0xFF1E40AF);
  static const Color accentSky = Color(0xFF0284C7);
  static const Color accentAmber = Color(0xFFD97706);
  static const Color accentEmerald = Color(0xFF059669);
  static const Color accentRed = Color(0xFFDC2626);

  // Dark Theme Palette (Midnight Dark)
  static const Color darkBg = Color(0xFF0B1120);
  static const Color darkCard = Color(0xFF131D31);
  static const Color darkCardSecondary = Color(0xFF1A263D);
  static const Color darkBorder = Color(0xFF22324E);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextMuted = Color(0xFF64748B);

  // Light Theme Palette (Warm Light)
  static const Color lightBg = Color(0xFFF1F5F9);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightCardSecondary = Color(0xFFF8FAFC);
  static const Color lightBorder = Color(0xFFCBD5E1);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextMuted = Color(0xFF64748B);

  // Gradient themes for courses
  static const List<List<Color>> cardGradients = [
    [Color(0xFF1D4ED8), Color(0xFF3730A3)], // Blue to Indigo
    [Color(0xFF334155), Color(0xFF0F172A)], // Slate dark
    [Color(0xFF0369A1), Color(0xFF1E3A8A)], // Sky to Deep Blue
    [Color(0xFF0F766E), Color(0xFF064E3B)], // Teal to Emerald
    [Color(0xFF4338CA), Color(0xFF1E293B)], // Indigo to Slate
    [Color(0xFF1E40AF), Color(0xFF1E293B)], // Blue to Slate
  ];
}

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.lightBg,
    primaryColor: AppColors.primary,
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      secondary: AppColors.accentSky,
      surface: AppColors.lightCard,
      onPrimary: Colors.white,
      onSurface: AppColors.lightTextPrimary,
      outline: AppColors.lightBorder,
    ),
    textTheme: GoogleFonts.interTextTheme(
      ThemeData.light().textTheme.apply(
        bodyColor: AppColors.lightTextPrimary,
        displayColor: AppColors.lightTextPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.lightCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.lightBorder, width: 1),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.lightCard.withValues(alpha: 0.95),
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: const IconThemeData(color: AppColors.lightTextPrimary),
      titleTextStyle: GoogleFonts.inter(
        color: AppColors.lightTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.lightBorder,
      thickness: 1,
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.darkBg,
    primaryColor: AppColors.primary,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      secondary: AppColors.accentSky,
      surface: AppColors.darkCard,
      onPrimary: Colors.white,
      onSurface: AppColors.darkTextPrimary,
      outline: AppColors.darkBorder,
    ),
    textTheme: GoogleFonts.interTextTheme(
      ThemeData.dark().textTheme.apply(
        bodyColor: AppColors.darkTextPrimary,
        displayColor: AppColors.darkTextPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.darkCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.darkBorder, width: 1),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.darkCard.withValues(alpha: 0.95),
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: const IconThemeData(color: AppColors.darkTextPrimary),
      titleTextStyle: GoogleFonts.inter(
        color: AppColors.darkTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.darkBorder,
      thickness: 1,
    ),
  );
}
