import 'package:flutter/material.dart';

import '../theme/mesh_theme.dart';

/// A thin rule with a small label in the middle, for a list that falls into
/// two parts: what the label names lies below it.
class LabeledDivider extends StatelessWidget {
  final String label;

  const LabeledDivider({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = scheme.outlineVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: line)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: MeshTheme.mono(
                fontSize: 10.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: line)),
        ],
      ),
    );
  }
}
