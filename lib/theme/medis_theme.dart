import 'package:flutter/material.dart';

/// Shared visual language for MeDis. Status colors always accompany text/icons.
abstract final class MeDisColors {
  static const primary = Color(0xFF2463A6);
  static const primaryDark = Color(0xFF184B82);
  static const primarySoft = Color(0xFFEAF2FA);
  static const background = Color(0xFFF5F7FA);
  static const surface = Colors.white;
  static const text = Color(0xFF182B42);
  static const muted = Color(0xFF5D6D80);
  static const subtle = Color(0xFF64748B);
  static const border = Color(0xFFDFE5EC);
  static const success = Color(0xFF217456);
  static const successSoft = Color(0xFFE8F4ED);
  static const warning = Color(0xFF926016);
  static const warningSoft = Color(0xFFFFF4DF);
  static const error = Color(0xFFBC3F42);
  static const errorSoft = Color(0xFFFCECED);
  static const prn = Color(0xFF7055A0);
  static const prnSoft = Color(0xFFF2EDF8);
}

abstract final class MeDisSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const page = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const pagePadding = EdgeInsets.all(page);
}

abstract final class MeDisRadius {
  static const input = 12.0;
  static const card = 16.0;
  static const sheet = 24.0;
}

abstract final class MeDisTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: MeDisColors.primary,
      primary: MeDisColors.primary,
      onPrimary: Colors.white,
      secondary: MeDisColors.success,
      surface: MeDisColors.surface,
      onSurface: MeDisColors.text,
      error: MeDisColors.error,
      outline: MeDisColors.border,
    );
    const text = TextTheme(
      headlineLarge:
          TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1.35),
      headlineMedium:
          TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.4),
      headlineSmall:
          TextStyle(fontSize: 23, fontWeight: FontWeight.w700, height: 1.4),
      titleLarge:
          TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.4),
      titleMedium:
          TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.5),
      titleSmall:
          TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.5),
      bodyLarge: TextStyle(fontSize: 16, height: 1.55),
      bodyMedium: TextStyle(fontSize: 16, height: 1.55),
      bodySmall: TextStyle(fontSize: 14, height: 1.5),
      labelLarge:
          TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
      labelMedium:
          TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.4),
      labelSmall: TextStyle(fontSize: 12, height: 1.4),
    );
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MeDisRadius.input));
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansThai',
      colorScheme: scheme,
      textTheme: text.apply(
          bodyColor: MeDisColors.text, displayColor: MeDisColors.text),
      scaffoldBackgroundColor: MeDisColors.background,
      canvasColor: MeDisColors.surface,
      disabledColor: MeDisColors.subtle,
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(
        backgroundColor: MeDisColors.background,
        foregroundColor: MeDisColors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
        titleTextStyle: TextStyle(
            fontFamily: 'NotoSansThai',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: MeDisColors.text),
      ),
      cardTheme: CardThemeData(
        color: MeDisColors.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MeDisRadius.card),
            side: const BorderSide(color: MeDisColors.border)),
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: shape,
        textStyle: const TextStyle(
            fontFamily: 'NotoSansThai',
            fontSize: 16,
            fontWeight: FontWeight.w600),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: const BorderSide(color: MeDisColors.border),
        shape: shape,
      )),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
      )),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MeDisColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: const TextStyle(color: MeDisColors.muted),
        hintStyle: const TextStyle(color: MeDisColors.subtle, fontSize: 14),
        prefixIconColor: MeDisColors.muted,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(MeDisRadius.input)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(MeDisRadius.input),
            borderSide: const BorderSide(color: MeDisColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(MeDisRadius.input),
            borderSide: const BorderSide(color: MeDisColors.primary, width: 2)),
        errorMaxLines: 3,
        helperMaxLines: 3,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        backgroundColor: MeDisColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: MeDisColors.primarySoft,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontFamily: 'NotoSansThai',
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: states.contains(WidgetState.selected)
                  ? MeDisColors.primary
                  : MeDisColors.muted,
            )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? MeDisColors.primary
                  : MeDisColors.muted,
            )),
      ),
      dividerTheme:
          const DividerThemeData(color: MeDisColors.border, thickness: 1),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: MeDisColors.muted,
        minVerticalPadding: 12,
        titleTextStyle: TextStyle(
            fontFamily: 'NotoSansThai',
            fontSize: 16,
            color: MeDisColors.text,
            fontWeight: FontWeight.w600,
            height: 1.5),
        subtitleTextStyle: TextStyle(
            fontFamily: 'NotoSansThai',
            fontSize: 14,
            color: MeDisColors.muted,
            height: 1.5),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: MeDisColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MeDisRadius.sheet)),
        titleTextStyle: const TextStyle(
            fontFamily: 'NotoSansThai',
            fontSize: 20,
            color: MeDisColors.text,
            fontWeight: FontWeight.w700,
            height: 1.4),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: MeDisColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(MeDisRadius.sheet))),
        clipBehavior: Clip.antiAlias,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: MeDisColors.text,
        shape: shape,
        contentTextStyle: const TextStyle(
            fontFamily: 'NotoSansThai',
            color: Colors.white,
            fontSize: 14,
            height: 1.5),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: MeDisColors.background,
        selectedColor: MeDisColors.primarySoft,
        side: const BorderSide(color: MeDisColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        labelStyle: const TextStyle(
            fontFamily: 'NotoSansThai', color: MeDisColors.text),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: MeDisColors.primary,
        foregroundColor: Colors.white,
        elevation: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: MeDisColors.primary,
          linearTrackColor: MeDisColors.border,
          circularTrackColor: MeDisColors.border),
    );
  }
}
