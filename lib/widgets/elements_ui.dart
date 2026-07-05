import 'package:flutter/material.dart';

class FeatureToggleRow extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool value;
  final bool hasRefreshing;
  final bool isRefreshing;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onRefresh;
  final String? refreshTooltip;

  const FeatureToggleRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    this.hasRefreshing = false,
    this.isRefreshing = false,
    this.onChanged,
    this.onRefresh,
    this.refreshTooltip,
  });

  @override
  State<FeatureToggleRow> createState() => _FeatureToggleRow();
}

class _FeatureToggleRow extends State<FeatureToggleRow> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.subtitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(value: widget.value, onChanged: widget.onChanged),
              if (widget.hasRefreshing) ...[
                const SizedBox(width: 4),
                widget.isRefreshing
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: scheme.primary,
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.refresh, size: 18),
                        onPressed: widget.onRefresh,
                        tooltip: widget.refreshTooltip,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
