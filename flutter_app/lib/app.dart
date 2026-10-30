import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'l10n/app_localizations.dart';
import 'providers/providers.dart';
import 'screens/main_screen.dart';

class LinguaTraceApp extends ConsumerWidget {
  const LinguaTraceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(configProvider);
    return MaterialApp(
      title: 'LinguaTrace',
      theme: _getTheme(cfg.themeMode),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Russian is the default UI language; English is the fallback.
      locale: const Locale('ru'),
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }

  ThemeData _getTheme(String mode) {
    switch (mode) {
      case 'extra-light':
        return _extraLight();
      case 'light':
        return _latte();
      case 'medium':
        return _macchiato();
      default:
        return _mocha();
    }
  }

  // ── Catppuccin Mocha (dark) ───────────────────────────────────────────────
  ThemeData _mocha() => _build(
        brightness: Brightness.dark,
        base: const Color(0xFF1e1e2e),
        mantle: const Color(0xFF181825),
        surface0: const Color(0xFF313244),
        surface1: const Color(0xFF45475a),
        overlay0: const Color(0xFF6c7086),
        text: const Color(0xFFcdd6f4),
        blue: const Color(0xFF89b4fa),
        teal: const Color(0xFF94e2d5),
        red: const Color(0xFFf38ba8),
        mauve: const Color(0xFFcba6f7),
      );

  // ── Catppuccin Macchiato (medium) ─────────────────────────────────────────
  ThemeData _macchiato() => _build(
        brightness: Brightness.dark,
        base: const Color(0xFF24273a),
        mantle: const Color(0xFF1e2030),
        surface0: const Color(0xFF363a4f),
        surface1: const Color(0xFF494d64),
        overlay0: const Color(0xFF8087a2),
        text: const Color(0xFFcad3f5),
        blue: const Color(0xFF8aadf4),
        teal: const Color(0xFF8bd5ca),
        red: const Color(0xFFed8796),
        mauve: const Color(0xFFc6a0f6),
      );

  // ── Catppuccin Latte (light) ──────────────────────────────────────────────
  ThemeData _latte() => _build(
        brightness: Brightness.light,
        base: const Color(0xFFeff1f5),
        mantle: const Color(0xFFe6e9ef),
        surface0: const Color(0xFFccd0da),
        surface1: const Color(0xFFbcc0cc),
        overlay0: const Color(0xFF7c7f93),
        text: const Color(0xFF4c4f69),
        blue: const Color(0xFF1e66f5),
        teal: const Color(0xFF179299),
        red: const Color(0xFFd20f39),
        mauve: const Color(0xFF8839ef),
      );

  // ── Extra Light (very bright white) ─────────────────────────────────────
  ThemeData _extraLight() => _build(
        brightness: Brightness.light,
        base: Colors.white,
        mantle: const Color(0xFFF8F9FA),
        surface0: const Color(0xFFE9ECEF),
        surface1: const Color(0xFFDEE2E6),
        overlay0: const Color(0xFF6C757D),
        text: const Color(0xFF212529),
        blue: const Color(0xFF0D6EFD),
        teal: const Color(0xFF20C997),
        red: const Color(0xFFDC3545),
        mauve: const Color(0xFF6F42C1),
      );

  ThemeData _build({
    required Brightness brightness,
    required Color base,
    required Color mantle,
    required Color surface0,
    required Color surface1,
    required Color overlay0,
    required Color text,
    required Color blue,
    required Color teal,
    required Color red,
    required Color mauve,
  }) {
    final isDark = brightness == Brightness.dark;
    // outline is used all over the screens for SECONDARY TEXT — it must be
    // readable (overlay0, ~4.5:1), not surface0 (~1.4:1, invisible).
    // Surfaces/borders that want a subtle line use outlineVariant.
    final cs = isDark
        ? ColorScheme.dark(
            primary: blue, onPrimary: base, secondary: teal, tertiary: mauve,
            error: red, surface: mantle, onSurface: text,
            onSurfaceVariant: overlay0,
            surfaceContainerHighest: surface1, outline: overlay0, outlineVariant: surface0)
        : ColorScheme.light(
            primary: blue, onPrimary: Colors.white, secondary: teal, tertiary: mauve,
            error: red, surface: mantle, onSurface: text,
            onSurfaceVariant: overlay0,
            surfaceContainerHighest: surface1, outline: overlay0, outlineVariant: surface0);

    return ThemeData(
      useMaterial3: true, brightness: brightness, colorScheme: cs,
      scaffoldBackgroundColor: base,
      appBarTheme: AppBarTheme(
        backgroundColor: mantle, foregroundColor: text, elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.w600),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: mantle, height: 64,
        indicatorColor: blue.withOpacity(0.15),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? IconThemeData(color: blue, size: 22)
                : IconThemeData(color: overlay0, size: 22)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? TextStyle(color: blue, fontSize: 11, fontWeight: FontWeight.w600)
                : TextStyle(color: overlay0, fontSize: 11)),
      ),
      cardTheme: CardThemeData(
        color: mantle, elevation: 0, margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: surface0)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: isDark ? mantle : base,
        labelStyle: TextStyle(color: overlay0, fontSize: 13),
        border: OutlineInputBorder(borderSide: BorderSide(color: surface0), borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: surface0), borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: blue, width: 1.5), borderRadius: BorderRadius.circular(10)),
        hintStyle: TextStyle(color: overlay0),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: blue, foregroundColor: isDark ? base : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: blue)),
      listTileTheme: ListTileThemeData(tileColor: Colors.transparent, textColor: text, subtitleTextStyle: TextStyle(color: overlay0, fontSize: 12)),
      dividerTheme: DividerThemeData(color: surface0, thickness: 1),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? blue : text),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? blue.withOpacity(0.35) : surface0),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface1, contentTextStyle: TextStyle(color: text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), behavior: SnackBarBehavior.floating,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface0, labelStyle: TextStyle(color: text, fontSize: 12),
        side: BorderSide(color: surface0), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
