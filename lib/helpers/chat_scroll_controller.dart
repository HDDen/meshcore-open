import 'package:flutter/material.dart';

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

  void scrollToBottomIfAtBottom() {
    // Only scroll if jump button is NOT showing (i.e., already at bottom)
    if (!showJumpToBottom.value && hasClients && position.maxScrollExtent > 0) {
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
