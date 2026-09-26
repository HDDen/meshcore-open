import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';

/// Swipe a message to the left to answer it. The channel transcript has its
/// own copy of this gesture, which came from upstream; this one serves the
/// direct and room chats, where upstream has no replies. The row slides with
/// a resistance curve over a hint, and letting go past [replySwipeThreshold]
/// calls [onReply].
class SwipeReplyBubble extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;

  /// Our own bubble lies over the side the hint is drawn on and slides away
  /// only as far as the icon, so the label would show as a cut tail.
  final bool iconOnlyHint;
  final double maxSwipeOffset;
  final double replySwipeThreshold;

  const SwipeReplyBubble({
    super.key,
    required this.child,
    required this.onReply,
    this.iconOnlyHint = false,
    this.maxSwipeOffset = 64,
    this.replySwipeThreshold = 64,
  });

  @override
  State<SwipeReplyBubble> createState() => _SwipeReplyBubbleState();
}

class _SwipeReplyBubbleState extends State<SwipeReplyBubble> {
  Offset? _swipeStartPosition;
  double _swipeOffset = 0;
  double _maxSwipeDistance = 0;
  int? _swipePointerId;
  bool _swipeLockedToHorizontal = false;

  void _handlePointerDown(PointerDownEvent event) {
    _swipePointerId = event.pointer;
    _swipeLockedToHorizontal = false;
    _swipeStartPosition = event.position;
    _maxSwipeDistance = 0;
    if (_swipeOffset != 0) {
      setState(() => _swipeOffset = 0);
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final start = _swipeStartPosition;
    if (_swipePointerId != event.pointer || start == null) return;

    final dx = event.position.dx - start.dx;
    const axisLockThreshold = 12.0;
    if (!_swipeLockedToHorizontal) {
      if (-dx < axisLockThreshold) return;
      _swipeLockedToHorizontal = true;
    }
    if (dx >= 0 || -dx < 6) return;

    if (-dx > _maxSwipeDistance) {
      _maxSwipeDistance = -dx;
    }
    final clamped = dx.clamp(-widget.maxSwipeOffset, 0.0).toDouble();
    final adjusted = _applySwipeResistance(clamped, widget.maxSwipeOffset);
    if (adjusted != _swipeOffset) {
      setState(() => _swipeOffset = adjusted);
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    final start = _swipeStartPosition;
    if (_swipeLockedToHorizontal && start != null) {
      final dx = event.position.dx - start.dx;
      final peak = math.max(
        _maxSwipeDistance,
        (-dx).clamp(0.0, double.infinity),
      );
      if (peak >= widget.replySwipeThreshold) {
        widget.onReply();
        HapticFeedback.selectionClick();
      }
    }
    _resetSwipe();
  }

  void _resetSwipe() {
    if (_swipeOffset != 0) {
      setState(() => _swipeOffset = 0);
    }
    _swipeStartPosition = null;
    _maxSwipeDistance = 0;
    _swipePointerId = null;
    _swipeLockedToHorizontal = false;
  }

  double _applySwipeResistance(double rawOffset, double maxOffset) {
    final abs = rawOffset.abs();
    if (abs <= 0) return 0;
    final norm = (abs / maxOffset).clamp(0.0, 1.0);
    const deadZone = 0.18;
    if (norm <= deadZone) {
      return rawOffset.sign * maxOffset * (norm * 0.08);
    }
    final t = ((norm - deadZone) / (1 - deadZone)).clamp(0.0, 1.0);
    final curved = t < 0.5
        ? 16 * math.pow(t, 5)
        : 1 - math.pow(-2 * t + 2, 5) / 2;
    const deadZoneEnd = 0.0144;
    return rawOffset.sign *
        maxOffset *
        (deadZoneEnd + curved * (1 - deadZoneEnd));
  }

  Widget _buildHint(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = Icon(Icons.reply, color: colorScheme.primary);
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: colorScheme.primary.withValues(alpha: 0.08),
      child: widget.iconOnlyHint
          ? icon
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.chat_reply,
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                icon,
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: (_) => _resetSwipe(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: _swipeOffset.abs() / widget.maxSwipeOffset,
              child: _buildHint(context),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            transform: Matrix4.translationValues(_swipeOffset, 0, 0),
            curve: Curves.easeOut,
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
