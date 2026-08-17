import 'package:flutter/cupertino.dart';
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

/// Corner rounding, in one place.
///
/// Established marketplaces round their corners just enough to look finished
/// and no further; heavy rounding is what makes an interface read as a brand
/// new app rather than one that has been running for years. Anything that
/// needs a radius picks it from here so the whole app stays consistent.
class AppRadius {
  AppRadius._();

  /// Photos, thumbnails, small badges.
  static const double image = 6;

  /// Buttons, inputs, chips, dropdowns - the things you tap.
  static const double control = 8;

  /// Cards and panels.
  static const double card = 10;

  /// Reserved for elements that genuinely are circular or pill-shaped:
  /// avatars, the "+" in the toolbar, photo counters over an image.
  static const double pill = 999;
}

/// Text sizes, in one place, so headings stay in proportion across screens.
/// Deliberately restrained - a marketplace earns attention with listings, not
/// with large type.
class AppText {
  AppText._();

  /// Screen-level heading (an ad title on its own page).
  static const double title = 22;

  /// Section heading within a page ("Description", "Featured Dealer").
  static const double section = 17;

  /// A listing title in a list.
  static const double listing = 15;

  /// Ordinary supporting copy.
  static const double body = 14;

  /// Metadata: counts, timestamps, spec chips.
  static const double meta = 13;

  /// The smallest label used - badges and photo counters.
  static const double micro = 11.5;
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
      fontFamily: 'Inter',
    );

    return base.copyWith(
      // Pages slide in from the right and slide back on pop (with edge-swipe
      // back), like DoneDeal / native iOS, rather than the default fade-up.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      dividerColor: AppColors.line,
      dividerTheme: const DividerThemeData(
        color: AppColors.line,
        thickness: 1,
        space: 1,
      ),
      // Panels get a hairline border rather than a shadow. Shadows on every
      // surface are the single biggest thing that made the app read as a
      // concept mock-up instead of a working marketplace.
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.line),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      // Every text field: white, hairline border, small radius. Focus is shown
      // by the border turning blue rather than by the field growing a shadow.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(color: AppColors.muted, fontSize: 15),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: const BorderSide(color: AppColors.line),
        ),
        backgroundColor: Colors.white,
        labelStyle: const TextStyle(fontSize: AppText.body),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
      ),
    );
  }
}
