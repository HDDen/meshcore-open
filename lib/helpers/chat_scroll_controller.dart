import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

class ChatScrollController extends ScrollController {
  final ValueNotifier<bool> showJumpToBottom = ValueNotifier(false);
  VoidCallback? onScrollNearTop;

  static const _bottomThreshold = 100.0;
  static const _topThreshold = 50.0;

  ChatScrollController() {
    addListener(_handleScroll);
  }

  void _handleScroll() {
    if (!hasClients) return;
    final pos = position;

    // With reverse: true, position 0 is bottom, maxScrollExtent is top
    // Show jump button when scrolled away from bottom (position > threshold)
    final isAtBottom = pos.pixels <= _bottomThreshold;
    if (showJumpToBottom.value == isAtBottom) {
      showJumpToBottom.value = !isAtBottom;
    }

    // Pagination trigger when scrolled near top (maxScrollExtent)
    if (pos.pixels >= pos.maxScrollExtent - _topThreshold) {
      onScrollNearTop?.call();
    }
  }

  void jumpToBottom() {
    if (hasClients && position.maxScrollExtent > 0) {
      animateTo(
        0, // With reverse: true, position 0 is bottom
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void handleKeyboardOpen() {
    // Simple: just scroll to bottom when keyboard opens
    if (hasClients) {
      animateTo(
        0, // With reverse: true, position 0 is bottom
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  bool scrollBy(double delta) {
    if (!hasClients) return false;
    final pos = position;
    final target = (pos.pixels + delta)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent)
        .toDouble();
    if (target == pos.pixels) return true;
    animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
    return true;
  }

  /// Jumps toward an off-screen message so that lazy ListView.builder builds
  /// items near it. Only visible + cacheExtent items have real heights, so we
  /// use proportion of maxScrollExtent (itself an estimate from built items'
  /// avg height). Call [onJumped] on the next frame to ensureVisible/scroll
  /// to the exact target.
  void jumpToEstimatedOffset({
    required int unreadCount,
    required int totalMessages,
    required VoidCallback onJumped,
  }) {
    if (!hasClients || totalMessages == 0) return;
    final maxExtent = position.maxScrollExtent;
    final jumpOffset = maxExtent * (unreadCount / totalMessages);
    if (jumpOffset > 100) {
      jumpTo(jumpOffset);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => onJumped());
  }

  /// The newest row the list showed when [followNewMessage] last ran, so a
  /// rebuild for anything else (a relay heard, a reading, a reaction, in a
  /// direct chat any notification of the connector) leaves the list alone.
  Object? _newestMessageShown;

  /// Follows a new message at the bottom of the chat when the reader is
  /// there. [newestMessage] identifies the last row, its message id: a
  /// rebuild that shows the same one snaps nothing, and the id is kept
  /// whether or not a snap happened, so a reader who was away or scrolling
  /// when the message came is not pulled down by the next rebuild either.
  void followNewMessage(Object? newestMessage) {
    if (newestMessage == _newestMessageShown) return;
    _newestMessageShown = newestMessage;
    scrollToBottomIfAtBottom();
  }

  /// Whether the reader is dragging the list or has flung it. A drag or a
  /// wheel tick sets the direction and a fling keeps it; an animation of
  /// this controller's own never sets it, so it does not block itself.
  bool get _readerIsScrolling =>
      hasClients && position.userScrollDirection != ScrollDirection.idle;

  void scrollToBottomIfAtBottom() {
    // Only scroll if jump button is NOT showing (i.e., already at bottom).
    // Never while the reader is scrolling: animateTo begins a new scroll
    // activity, which ends the drag under their finger or their fling, and
    // at the bottom exactly Flutter turns it into a jumpTo, which does the
    // same.
    if (!showJumpToBottom.value &&
        hasClients &&
        position.maxScrollExtent > 0 &&
        !_readerIsScrolling) {
      animateTo(
        0, // With reverse: true, position 0 is bottom
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    showJumpToBottom.dispose();
    super.dispose();
  }
}

/// Prevents list rebuilds triggered by one asynchronous operation from
/// snapping a chat to its newest message.
class ChatBottomSnapGuard {
  int _generation = 0;
  bool _isSuppressed = false;

  bool get isSuppressed => _isSuppressed;

  Future<void> run(Future<void> Function() operation) async {
    final generation = ++_generation;
    _isSuppressed = true;
    try {
      await operation();
    } finally {
      // Connector notifications can rebuild the list more than once. Keep the
      // guard through the frame that applies the final message-height changes.
      await WidgetsBinding.instance.endOfFrame;
      if (generation == _generation) {
        _isSuppressed = false;
      }
    }
  }
}
