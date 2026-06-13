import 'package:flutter/material.dart';

import '../theme/mesh_theme.dart';

class UnreadBadge extends StatelessWidget {
  final int count;

  const UnreadBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final display = count > 9999 ? '9999+' : count.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: MeshPalette.blue.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(MeshRadii.pill),
        border: Border.all(color: MeshPalette.blue.withValues(alpha: 0.45)),
      ),
      child: Text(
        display,
        style: MeshTheme.mono(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: MeshPalette.blue,
        ),
      ),
    );
  }
}
