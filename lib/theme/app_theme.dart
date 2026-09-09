import 'package:flutter/material.dart';

abstract final class AppColors {
  static const canvas = Color(0xFF1C1C1C);
  static const sidebar = Color(0xFF171717);
  static const surface = Color(0xFF232323);
  static const surfaceRaised = Color(0xFF2A2A2A);
  static const surfaceHover = Color(0xFF303030);
  static const border = Color(0x14FFFFFF);
  static const borderStrong = Color(0x26FFFFFF);
  static const text = Color(0xFFE8E6E3);
  static const textMuted = Color(0xFF8F8D89);
  static const textFaint = Color(0xFF605E5B);
  static const danger = Color(0xFFD9776F);
  static const warm = Color(0xFFD1A46A);
  static const cool = Color(0xFF7FA7C9);
  static const success = Color(0xFF86B58C);
  static const badge = Color(0xFFE0574B);
}

const _radius = BorderRadius.all(Radius.circular(8));

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    surface: AppColors.canvas,
    onSurface: AppColors.text,
    surfaceContainer: AppColors.surface,
    surfaceContainerHigh: AppColors.surfaceRaised,
    primary: AppColors.text,
    onPrimary: AppColors.canvas,
    secondary: AppColors.textMuted,
    onSecondary: AppColors.canvas,
    error: AppColors.danger,
    onError: AppColors.canvas,
    outline: AppColors.border,
    outlineVariant: AppColors.border,
  );
  final base = ThemeData(
    brightness: Brightness.dark,
    colorScheme: scheme,
    useMaterial3: true,
  );
  final text = base.textTheme
      .apply(bodyColor: AppColors.text, displayColor: AppColors.text)
      .copyWith(
        headlineMedium: const TextStyle(
          color: AppColors.text,
          fontSize: 26,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.4,
          height: 1.3,
        ),
        headlineSmall: const TextStyle(
          color: AppColors.text,
          fontSize: 21,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.2,
          height: 1.4,
        ),
        titleMedium: const TextStyle(
          color: AppColors.text,
          fontSize: 16,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.1,
          height: 1.4,
        ),
        bodyMedium: const TextStyle(
          color: AppColors.text,
          fontSize: 14,
          height: 1.5,
        ),
        labelSmall: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: AppColors.textMuted,
        ),
      );
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.canvas,
    canvasColor: AppColors.canvas,
    dividerColor: AppColors.border,
    splashFactory: NoSplash.splashFactory,
    hoverColor: AppColors.surfaceHover,
    highlightColor: Colors.transparent,
    textTheme: text,
    iconTheme: const IconThemeData(color: AppColors.textMuted, size: 18),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surfaceRaised,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: AppColors.borderStrong),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppColors.surfaceRaised,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: _radius,
        side: BorderSide(color: AppColors.borderStrong),
      ),
      textStyle: TextStyle(fontSize: 14, color: AppColors.text),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      hintStyle: TextStyle(color: AppColors.textFaint),
      border: OutlineInputBorder(
        borderRadius: _radius,
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: _radius,
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: _radius,
        borderSide: BorderSide(color: AppColors.borderStrong),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.text,
        foregroundColor: AppColors.canvas,
        disabledBackgroundColor: AppColors.surfaceRaised,
        disabledForegroundColor: AppColors.textFaint,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: _radius),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textMuted,
        shape: const RoundedRectangleBorder(borderRadius: _radius),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: AppColors.surfaceRaised,
      side: BorderSide(color: AppColors.border),
      shape: StadiumBorder(),
      labelStyle: TextStyle(fontSize: 13, color: AppColors.text),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: AppColors.sidebar,
      shape: RoundedRectangleBorder(),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.textMuted,
    ),
  );
}
