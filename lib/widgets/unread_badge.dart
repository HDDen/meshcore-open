import 'package:flutter/material.dart';

import '../theme/mesh_theme.dart';

class UnreadBadge extends StatelessWidget {
  final int count;
  final Color color;

  const UnreadBadge({
    super.key,
    required this.count,
    this.color = MeshPalette.alert,
  });

  @override
  Widget build(BuildContext context) {
    final display = count > 9999 ? '9999+' : count.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(MeshRadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        display,
        style: MeshTheme.mono(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
