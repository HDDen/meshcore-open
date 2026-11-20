import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/mcoa_theme_style.dart';

/// Keeps the system bars aligned with the resolved application theme.
SystemUiOverlayStyle appSystemUiStyle(ThemeData theme) {
  final isDark = theme.brightness == Brightness.dark;
  final iconBrightness = isDark ? Brightness.light : Brightness.dark;
  final status = theme.extension<McoaThemeStyle>()?.options.colors['status_bar'];
  final statusBrightness = status == null ? theme.brightness
      : ThemeData.estimateBrightnessForColor(Color.alphaBlend(
          status, theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface,
        ));

  // Older Android uses this color; edge-to-edge uses the painted background.
  return SystemUiOverlayStyle(
    statusBarColor: status ?? Colors.transparent,
    statusBarIconBrightness: statusBrightness == Brightness.dark
        ? Brightness.light : Brightness.dark,
    statusBarBrightness: statusBrightness,
    systemNavigationBarColor: theme.colorScheme.surface,
    systemNavigationBarIconBrightness: iconBrightness,
    systemNavigationBarDividerColor: theme.colorScheme.surface,
    // Light-theme routes can paint dark maps below dark navigation buttons.
    systemNavigationBarContrastEnforced: !isDark,
  );
}

/// Paints the theme below transparent system bars without consuming insets.
class AppSystemUi extends StatelessWidget {
  const AppSystemUi({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = theme.extension<McoaThemeStyle>()?.options.colors['status_bar'];
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: SizedBox.expand(
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: appSystemUiStyle(theme),
          child: status == null ? child : Stack(
            fit: StackFit.expand,
            children: [
              child,
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: MediaQuery.viewPaddingOf(context).top,
                child: IgnorePointer(
                  child: AnnotatedRegion<SystemUiOverlayStyle>(
                    value: appSystemUiStyle(theme),
                    child: ColoredBox(
                      key: const ValueKey('mcoa-status-bar'),
                      color: status,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
