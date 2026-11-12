import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

class TxPowerBoostBadge extends StatelessWidget {
  const TxPowerBoostBadge({
    super.key,
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: context.l10n.messageSentWithTxPowerBoost,
    child: Icon(Icons.bolt, size: size, color: color),
  );
}
