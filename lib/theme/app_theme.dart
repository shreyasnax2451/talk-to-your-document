import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Claude-inspired warm dark palette
  static const Color background = Color(0xFF171715);
  static const Color surface = Color(0xFF232321);
  static const Color surfaceHover = Color(0xFF2C2C29);
  static const Color border = Color(0xFF353531);
  static const Color borderSubtle = Color(0xFF282825);
  
  // Accents
  static const Color accent = Color(0xFFCC785C); // Warm terracotta / rust
  static const Color accentLight = Color(0xFFDE9074);
  static const Color accentSubtle = Color(0xFF3D2A23);
  
  // Text
  static const Color textPrimary = Color(0xFFECECE8);
  static const Color textSecondary = Color(0xFFA2A299);
  static const Color textMuted = Color(0xFF73736C);
  
  // Status Colors
  static const Color readyText = Color(0xFF4ADE80);
  static const Color readyBg = Color(0xFF132F1D);
  static const Color readyBorder = Color(0xFF1D5A34);

  static const Color processingText = Color(0xFFFBBF24);
  static const Color processingBg = Color(0xFF332510);
  static const Color processingBorder = Color(0xFF6B4716);

  static const Color failedText = Color(0xFFF87171);
  static const Color failedBg = Color(0xFF381A1C);
  static const Color failedBorder = Color(0xFF6D2429);

  // User chat bubble
  static const Color userBubble = Color(0xFF2A2A27);

  static ThemeData get darkTheme {
    final textTheme = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: accent,
      canvasColor: surface,
      cardColor: surface,
      dividerColor: border,
      textTheme: textTheme.copyWith(
        headlineMedium: textTheme.headlineMedium?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: textTheme.bodyLarge?.copyWith(
          color: textPrimary,
          fontSize: 16,
          height: 1.5,
        ),
        bodyMedium: textTheme.bodyMedium?.copyWith(
          color: textSecondary,
          fontSize: 14,
          height: 1.4,
        ),
        labelLarge: textTheme.labelLarge?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accentLight,
        surface: surface,
        onSurface: textPrimary,
        error: failedText,
        outline: border,
      ),
    );
  }
}
