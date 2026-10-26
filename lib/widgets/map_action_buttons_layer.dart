import 'package:flutter/material.dart';

/// Keeps map controls in the body stack so the selected card can cover them.
class MapActionButtonsLayer extends StatelessWidget {
  const MapActionButtonsLayer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final endPadding = Directionality.of(context) == TextDirection.ltr
        ? padding.right
        : padding.left;
    return PositionedDirectional(
      end: kFloatingActionButtonMargin + endPadding,
      // The map body already ends above the safe bottom navigation bar.
      bottom: kFloatingActionButtonMargin,
      child: child,
    );
  }
}
