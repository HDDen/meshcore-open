import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../theme/mesh_theme.dart';
import '../widgets/mesh_ui.dart';

class ChromeRequiredScreen extends StatelessWidget {
  const ChromeRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon in tinted circle
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.tertiary.withValues(alpha: 0.10),
                    border: Border.all(
                      color: scheme.tertiary.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.browser_not_supported_rounded,
                    size: 42,
                    color: scheme.tertiary,
                  ),
                ),
                const SizedBox(height: 28),

                // Title
                Text(
                  l10n.scanner_chromeRequired,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 12),

                // Body text
                Text(
                  l10n.scanner_chromeRequiredMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.onSurfaceVariant,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 32),

                // Info chip
                MeshCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  color: scheme.secondaryContainer.withValues(alpha: 0.35),
                  borderColor: scheme.outline.withValues(alpha: 0.3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: scheme.secondary,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          l10n.chrome_bluetoothRequiresChromium,
                          style: MeshTheme.mono(
                            fontSize: 12,
                            color: scheme.onSecondaryContainer,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
