import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0D47A1), // Deep Blue for medical feel
        secondary: const Color(0xFF00B0FF), // Light Blue accent
        surface: const Color(0xFFF5F5F5),
      ),
      textTheme: GoogleFonts.cairoTextTheme().copyWith(
        displayLarge: GoogleFonts.cairo(
          fontWeight: FontWeight.bold,
          color: const Color(0xFF0D47A1),
        ),
        displayMedium: GoogleFonts.cairo(
          fontWeight: FontWeight.bold,
          color: const Color(0xFF0D47A1),
        ),
        bodyLarge: GoogleFonts.cairo(color: const Color(0xFF0D47A1)),
        bodyMedium: GoogleFonts.cairo(
          color: const Color(0xFF0D47A1).withValues(alpha: 0.7),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        toolbarHeight: 48,
        iconTheme: const IconThemeData(size: 20),
        titleTextStyle: GoogleFonts.cairo(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0D47A1),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}
