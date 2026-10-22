import 'package:flutter/material.dart';

import 'message_status_icon.dart';

/// Tracing сохраняет счётчики эхо и отправок, но явно показывает shortfall.
class ChannelResendShortfallIndicator extends StatelessWidget {
  const ChannelResendShortfallIndicator({
    super.key,
    required this.shortfall,
    this.size = 12,
  });

  final ({int hops, int required})? shortfall;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (shortfall == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: MessageStatusIcon(
        isAcked: false,
        isChannel: true,
        hopShortfall: shortfall,
        size: size,
      ),
    );
  }
}
