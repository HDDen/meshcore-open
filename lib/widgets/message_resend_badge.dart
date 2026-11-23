import 'package:flutter/material.dart';

import '../theme/mesh_theme.dart';
import 'tx_power_boost_badge.dart';

/// The same attempt counter and power evidence for text and AEIC messages.
class MessageResendBadge extends StatelessWidget {
  const MessageResendBadge({
    super.key,
    required this.resends,
    required this.pending,
    required this.color,
    this.textScale = 1,
    this.showAttempts = true,
    this.boosted = false,
    this.withLna = false,
  });

  final int resends;
  final bool pending;
  final Color color;
  final double textScale;
  final bool showAttempts;
  final bool boosted;
  final bool withLna;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (showAttempts) ...[
        const SizedBox(width: 6),
        if (pending) ...[
          SizedBox(
            width: 9 * textScale,
            height: 9 * textScale,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
          ),
          const SizedBox(width: 4),
        ] else ...[
          Icon(Icons.replay, size: 11 * textScale, color: color),
          const SizedBox(width: 2),
        ],
        Text(
          '${resends + 1}',
          style: MeshTheme.mono(fontSize: 10 * textScale, color: color),
        ),
      ],
      if (boosted) ...[
        const SizedBox(width: 4),
        TxPowerBoostBadge(withLna: withLna, size: 12 * textScale, color: color),
      ],
    ],
  );
}
