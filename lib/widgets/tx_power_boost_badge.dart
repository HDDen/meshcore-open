import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

class TxPowerBoostBadge extends StatelessWidget {
  const TxPowerBoostBadge({
    super.key,
    required this.size,
    required this.color,
    required this.withLna,
  });

  final double size;
  final Color color;
  final bool withLna;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: withLna
        ? context.l10n.messageSentWithTxPowerBoostAndLna
        : context.l10n.messageSentWithTxPowerBoost,
    child: Icon(Icons.bolt, size: size, color: withLna ? Colors.red : color),
  );
}
