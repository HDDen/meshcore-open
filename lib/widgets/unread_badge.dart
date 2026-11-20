import 'package:flutter/material.dart';

import '../theme/mesh_theme.dart';

class UnreadBadge extends StatelessWidget {
  final int count;
  final Color? backgroundColor;
  final Color? textColor;

  const UnreadBadge({super.key, required this.count, this.backgroundColor, this.textColor});

  @override
  Widget build(BuildContext context) {
    final display = count > 9999 ? '9999+' : count.toString();
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor ?? MeshPalette.alert,
        borderRadius: BorderRadius.circular(MeshRadii.pill),
      ),
      child: Text(
        display,
        style: MeshTheme.mono(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: textColor ?? Colors.white,
        ),
      ),
    );
  }
}
