import 'package:flutter/material.dart';

/// The Listit visual language, lifted straight from the website so the app
/// feels like the same product. Primary is the site's Bootstrap blue
/// (#007bff); muted slate (#506066) is the site's secondary text colour.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF007BFF);
  static const Color primaryDark = Color(0xFF0056D6);
  static const Color slate = Color(0xFF506066);
  static const Color ink = Color(0xFF1B2430);
  static const Color muted = Color(0xFF8792A0);
  static const Color line = Color(0xFFE6E8EB);
  static const Color surface = Color(0xFFF6F8FA);
  static const Color success = Color(0xFF16A34A);
  static const Color danger = Color(0xFFEF4444);
  static const Color save = Color(0xFFF59E0B);
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
      ),
      scaffoldBackgroundColor: Colors.white,
      fontFamily: 'Roboto',
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      dividerColor: AppColors.line,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
