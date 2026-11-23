import 'package:flutter/material.dart';

/// Monochrome cinema palette inspired by Apple TV / Infuse.
///
/// `#E50914` (`accent`) is reserved strictly for thin progress bars and tiny
/// active/live indicators. Primary actions use crisp white (`#FFFFFF`) on
/// near-black (`#0B0B0D`) surfaces.
abstract final class AppColors {
  static const Color background = Color(0xFF0B0B0D);
  static const Color surface = Color(0xFF141417);
  static const Color surfaceElevated = Color(0xFF1C1C21);
  static const Color border = Color(0xFF26262C);

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFA1A1AA);
  static const Color textMuted = Color(0xFF6B6B76);

  static const Color primaryAction = Color(0xFFFFFFFF);
  static const Color onPrimaryAction = Color(0xFF0B0B0D);

  /// Reserved strictly for thin progress bars and tiny active/live dots.
  static const Color accent = Color(0xFFE50914);
  static const Color online = Color(0xFF34C759);
}

abstract final class AppTheme {
  static ThemeData get darkTheme {
    const colorScheme = ColorScheme.dark(
      primary: AppColors.primaryAction,
      onPrimary: AppColors.onPrimaryAction,
      secondary: AppColors.textSecondary,
      onSecondary: AppColors.onPrimaryAction,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerLowest: AppColors.background,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.surfaceElevated,
      surfaceContainerHighest: Color(0xFF24242B),
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.border,
      outlineVariant: AppColors.border,
      error: Color(0xFFFF453A),
      onError: AppColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      dividerColor: AppColors.border,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceElevated,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryAction,
          foregroundColor: AppColors.onPrimaryAction,
          disabledBackgroundColor: AppColors.surfaceElevated,
          disabledForegroundColor: AppColors.textMuted,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.border),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.textSecondary),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primaryAction,
        secondarySelectedColor: AppColors.primaryAction,
        disabledColor: AppColors.surface,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        labelStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: const TextStyle(
          color: AppColors.onPrimaryAction,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        showCheckmark: false,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primaryAction;
            }
            return AppColors.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.onPrimaryAction;
            }
            return AppColors.textSecondary;
          }),
          side: WidgetStateProperty.all(
            const BorderSide(color: AppColors.border),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.surfaceElevated,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.textPrimary, size: 22);
          }
          return const IconThemeData(color: AppColors.textMuted, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            );
          }
          return const TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          );
        }),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.surfaceElevated,
        selectedIconTheme: IconThemeData(color: AppColors.textPrimary, size: 22),
        unselectedIconTheme: IconThemeData(color: AppColors.textMuted, size: 22),
        selectedLabelTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.textPrimary,
      ),
    );
  }
}
