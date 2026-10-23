import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps the system bars aligned with the resolved application theme.
SystemUiOverlayStyle appSystemUiStyle(ThemeData theme) {
  final isDark = theme.brightness == Brightness.dark;
  final iconBrightness = isDark ? Brightness.light : Brightness.dark;

  // Older Android uses this color; edge-to-edge uses the painted background.
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: iconBrightness,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
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
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: SizedBox.expand(
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: appSystemUiStyle(theme),
          child: child,
        ),
      ),
    );
  }
}
