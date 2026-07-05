import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../l10n/l10n.dart';
import '../theme/mesh_theme.dart';

class MessageStatusIcon extends StatefulWidget {
  final bool isAcked;
  final bool isFailed;
  final bool isPending;
  final bool isRepeated;
  final double size;

  /// Base tint for the sent/sending state. On a colored (outgoing) bubble a
  /// plain grey tick is nearly invisible, so callers can pass the bubble's own
  /// meta/text color for contrast. Falls back to [ColorScheme.onSurfaceVariant].
  final Color? onColor;

  const MessageStatusIcon({
    super.key,
    required this.isAcked,
    this.isFailed = false,
    this.isPending = false,
    this.isRepeated = false,
    this.size = 14,
    this.onColor,
  });

  @override
  State<MessageStatusIcon> createState() => _MessageStatusIconState();
}

class _MessageStatusIconState extends State<MessageStatusIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isPending) _controller.repeat();
  }

  @override
  void didUpdateWidget(MessageStatusIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPending && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPending && _controller.isAnimating) {
      _controller
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final double size = widget.size;
    final Color baseColor = widget.onColor ?? colorScheme.onSurfaceVariant;

    if (widget.isFailed) {
      return Semantics(
        label: l10n.messageStatus_failed,
        child: Icon(Icons.cancel, size: size, color: colorScheme.error),
      );
    }

    if (widget.isPending) {
      return Semantics(
        label: l10n.messageStatus_pending,
        child: _SendingDots(
          controller: _controller,
          color: baseColor,
          size: size,
        ),
      );
    }

    final bool delivered = widget.isAcked || widget.isRepeated;
    final String label = widget.isRepeated
        ? l10n.messageStatus_repeated
        : widget.isAcked
        ? l10n.messageStatus_delivered
        : l10n.messageStatus_sent;
    // Use palette colors: tertiary (warn/amber) for acked/repeated, base for sent.
    final Color color = delivered
        ? MeshPalette.signal.withValues(alpha: 0.9)
        : baseColor;

    return Semantics(
      label: label,
      child: delivered
          ? SvgPicture.asset(
              'assets/icons/done_all.svg',
              width: size,
              height: size,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            )
          : Icon(Icons.done, size: size, color: color),
    );
  }
}

/// Three dots that pulse left-to-right while a message is in flight.
class _SendingDots extends StatelessWidget {
  final AnimationController controller;
  final Color color;
  final double size;

  const _SendingDots({
    required this.controller,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final double dot = (size * 0.24).clamp(2.0, 4.0);
    return SizedBox(
      height: size,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(3, (i) {
              final double phase = (controller.value - i * 0.18) % 1.0;
              final double t = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
              final double opacity = 0.25 + 0.75 * t.clamp(0.0, 1.0);
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: dot * 0.28),
                child: Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: opacity),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
