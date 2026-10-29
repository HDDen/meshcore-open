import 'package:flutter/material.dart';

/// Shared row inside settings cards, including About and the update checker.
/// MeshCard owns the padding and the full-card tap target.
class SettingsNavTileContent extends StatelessWidget {
  const SettingsNavTileContent({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.showChevron = true,
    this.titleColor,
    this.iconColor,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool showChevron;
  final Color? titleColor;
  final Color? iconColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final trailingWidget = trailing;
    final subtitleText = subtitle;
    final foreground = titleColor;
    return Row(
      children: [
        Icon(icon, size: 20, color: iconColor ?? scheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: titleColor,
                ),
              ),
              if (subtitleText != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitleText,
                  style: textTheme.bodySmall?.copyWith(
                    color: foreground != null
                        ? foreground.withValues(alpha: 0.7)
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailingWidget != null)
          trailingWidget
        else if (showChevron)
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant, size: 16),
      ],
    );
  }
}
