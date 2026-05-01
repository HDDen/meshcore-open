import 'package:flutter/material.dart';

/// MeshCore redesign palette — warm field-journal dark theme with
/// phosphor-green signal accents. Mirrors values from the redesign spec.
class MeshPalette {
  MeshPalette._();

  // Surfaces (warm near-black, olive undertone)
  static const bg = Color(0xFF0F1412);
  static const bg1 = Color(0xFF161C19);
  static const bg2 = Color(0xFF1D2521);
  static const bg3 = Color(0xFF28322D);
  static const bg4 = Color(0xFF34403A);

  // Lines
  static const line = Color(0xFF232C28);
  static const line2 = Color(0xFF34403A);
  static const line3 = Color(0xFF48564F);

  // Ink
  static const ink = Color(0xFFEFF3E8);
  static const ink2 = Color(0xFFBAC4B5);
  static const ink3 = Color(0xFF7C8B82);
  static const ink4 = Color(0xFF55635B);

  // Signal (phosphor)
  static const signal = Color(0xFF7BEFA8);
  static const signalDim = Color(0xFF4DC580);
  static const signalBg = Color(0x177BEFA8); // ~9% alpha
  static const signalLine = Color(0x427BEFA8); // ~26%
  static const signalGlow = Color(0x597BEFA8); // ~35%

  // Warn (ember)
  static const warn = Color(0xFFFFA552);
  static const warnDim = Color(0xFFC27E3C);
  static const warnBg = Color(0x1CFFA552);
  static const warnLine = Color(0x4DFFA552);

  // Alert (coral)
  static const alert = Color(0xFFFF6A5C);
  static const alertBg = Color(0x1CFF6A5C);
  static const alertLine = Color(0x52FF6A5C);

  // Blue (dusk sky)
  static const blue = Color(0xFF7FCBF5);
  static const blueBg = Color(0x1C7FCBF5);
  static const blueLine = Color(0x477FCBF5);

  // Magenta
  static const magenta = Color(0xFFDE7FDB);
  static const magentaBg = Color(0x1CDE7FDB);
  static const magentaLine = Color(0x47DE7FDB);

  // Me bubble (mossy)
  static const me = Color(0xFF1E3527);
  static const meBorder = Color(0xFF2D5039);
  static const meInk = Color(0xFFDEF0DC);

  // ── Light variant (used when user explicitly picks light theme)
  static const lightBg = Color(0xFFF5F3EC);
  static const lightBg1 = Color(0xFFECE9DF);
  static const lightBg2 = Color(0xFFE2DED2);
  static const lightLine = Color(0xFFCAC5B4);
  static const lightInk = Color(0xFF0F1410);
  static const lightInk2 = Color(0xFF3D463E);
  static const lightInk3 = Color(0xFF6A756D);
  static const lightSignal = Color(0xFF1A7A44);
}

/// Named font stacks — Flutter falls back to system fonts when the named
/// family isn't installed, keeping things working without bundled assets.
class MeshFonts {
  MeshFonts._();

  static const sans = 'Inter';
  static const mono = 'JetBrains Mono';
  static const display = 'Instrument Serif';

  static const List<String> sansFallback = [
    'system-ui',
    '-apple-system',
    'Roboto',
    'Noto Sans',
    'sans-serif',
  ];
  static const List<String> monoFallback = [
    'SF Mono',
    'Menlo',
    'Consolas',
    'Roboto Mono',
    'monospace',
  ];
  static const List<String> displayFallback = [
    'Cormorant Garamond',
    'Georgia',
    'Times New Roman',
    'serif',
  ];
}

/// Radii used consistently across the app.
class MeshRadii {
  MeshRadii._();
  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 18.0;
  static const xl = 24.0;
  static const pill = 999.0;
}

/// Shared helpers exposed via [MeshTheme.of].
class MeshTheme {
  MeshTheme._();

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: MeshPalette.signal,
      onPrimary: Color(0xFF0A1810),
      primaryContainer: MeshPalette.signalBg,
      onPrimaryContainer: MeshPalette.signal,
      secondary: MeshPalette.blue,
      onSecondary: Color(0xFF0A1520),
      tertiary: MeshPalette.magenta,
      onTertiary: Color(0xFF201020),
      error: MeshPalette.alert,
      onError: Color(0xFF1A0A08),
      errorContainer: MeshPalette.alertBg,
      onErrorContainer: MeshPalette.alert,
      surface: MeshPalette.bg,
      onSurface: MeshPalette.ink,
      surfaceContainerLowest: MeshPalette.bg,
      surfaceContainerLow: MeshPalette.bg1,
      surfaceContainer: MeshPalette.bg1,
      surfaceContainerHigh: MeshPalette.bg2,
      surfaceContainerHighest: MeshPalette.bg3,
      onSurfaceVariant: MeshPalette.ink2,
      outline: MeshPalette.line2,
      outlineVariant: MeshPalette.line,
      shadow: Colors.black,
      scrim: Colors.black54,
      inverseSurface: MeshPalette.ink,
      onInverseSurface: MeshPalette.bg,
      inversePrimary: MeshPalette.signalDim,
    );
    return _build(scheme, Brightness.dark);
  }

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: MeshPalette.lightSignal,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFD4E8D8),
      onPrimaryContainer: MeshPalette.lightSignal,
      secondary: Color(0xFF2F6EA8),
      onSecondary: Colors.white,
      tertiary: Color(0xFF8C4A8A),
      onTertiary: Colors.white,
      error: Color(0xFFB53D2F),
      onError: Colors.white,
      surface: MeshPalette.lightBg,
      onSurface: MeshPalette.lightInk,
      surfaceContainerLowest: MeshPalette.lightBg,
      surfaceContainerLow: MeshPalette.lightBg1,
      surfaceContainer: MeshPalette.lightBg1,
      surfaceContainerHigh: MeshPalette.lightBg2,
      surfaceContainerHighest: Color(0xFFD5D0C0),
      onSurfaceVariant: MeshPalette.lightInk2,
      outline: MeshPalette.lightLine,
      outlineVariant: Color(0xFFDBD6C6),
    );
    return _build(scheme, Brightness.light);
  }

  static ThemeData _build(ColorScheme scheme, Brightness brightness) {
    final baseText =
        Typography.material2021(
          platform: TargetPlatform.android,
          colorScheme: scheme,
        ).black.apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
          fontFamily: MeshFonts.sans,
          fontFamilyFallback: MeshFonts.sansFallback,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      fontFamily: MeshFonts.sans,
      fontFamilyFallback: MeshFonts.sansFallback,
      textTheme: baseText,
      dividerColor: scheme.outlineVariant,
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: MeshFonts.sans,
          fontFamilyFallback: MeshFonts.sansFallback,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: scheme.onSurface,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
        shape: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MeshRadii.md),
          side: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        tileColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MeshRadii.md),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MeshRadii.pill),
        ),
        extendedTextStyle: const TextStyle(
          fontFamily: MeshFonts.sans,
          fontFamilyFallback: MeshFonts.sansFallback,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MeshRadii.pill),
          ),
          textStyle: const TextStyle(
            fontFamily: MeshFonts.sans,
            fontFamilyFallback: MeshFonts.sansFallback,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MeshRadii.pill),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MeshRadii.pill),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MeshRadii.md),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MeshRadii.md),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MeshRadii.md),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: TextStyle(
          fontFamily: MeshFonts.sans,
          fontFamilyFallback: MeshFonts.sansFallback,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MeshRadii.pill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MeshRadii.md),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: MeshFonts.mono,
            fontFamilyFallback: MeshFonts.monoFallback,
            fontSize: 10,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.1,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            size: 22,
          );
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(MeshRadii.lg),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MeshRadii.lg),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        contentTextStyle: TextStyle(color: scheme.onSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MeshRadii.md),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MeshRadii.md),
        ),
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
      splashFactory: InkSparkle.splashFactory,
    );
  }

  /// Mono text style — sizes default to the body size Inter is using.
  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: MeshFonts.mono,
      fontFamilyFallback: MeshFonts.monoFallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing ?? 0.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  /// Serif display style.
  static TextStyle display({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: MeshFonts.display,
      fontFamilyFallback: MeshFonts.displayFallback,
      fontSize: fontSize,
      fontWeight: fontWeight ?? FontWeight.w400,
      color: color,
      letterSpacing: letterSpacing ?? -0.2,
    );
  }

  /// Small-caps mono label — used for section accents and chip labels.
  static TextStyle accentLabel({Color? color, double? fontSize}) {
    return TextStyle(
      fontFamily: MeshFonts.mono,
      fontFamilyFallback: MeshFonts.monoFallback,
      fontSize: fontSize ?? 9.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.8,
      color: color,
    );
  }

  /// Color-code an SNR value for consistency across the app.
  static Color snrColor(num? snr, {required bool blocked}) {
    if (blocked) return MeshPalette.alert;
    if (snr == null) return MeshPalette.ink3;
    if (snr > -5) return MeshPalette.signal;
    if (snr > -12) return MeshPalette.warn;
    return MeshPalette.alert;
  }
}
