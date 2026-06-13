import 'package:flutter/material.dart';
import '../theme/mesh_theme.dart';

class SignalUi {
  final IconData icon;
  final Color color;

  const SignalUi({required this.icon, required this.color});
}

SignalUi signalUiForStrengthTier(int tier) {
  switch (tier) {
    case 0:
      return const SignalUi(
        icon: Icons.signal_cellular_4_bar,
        color: MeshPalette.signal,
      );
    case 1:
      return const SignalUi(
        icon: Icons.signal_cellular_alt,
        color: MeshPalette.signalDim,
      );
    case 2:
      return const SignalUi(
        icon: Icons.signal_cellular_alt_2_bar,
        color: MeshPalette.warn,
      );
    case 3:
      return const SignalUi(
        icon: Icons.signal_cellular_alt_1_bar,
        color: MeshPalette.warnDim,
      );
    default:
      return const SignalUi(
        icon: Icons.signal_cellular_alt_1_bar,
        color: MeshPalette.alert,
      );
  }
}
