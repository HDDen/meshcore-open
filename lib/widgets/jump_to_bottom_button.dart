import 'package:flutter/material.dart';
import '../helpers/chat_scroll_controller.dart';

class JumpToBottomButton extends StatelessWidget {
  final ChatScrollController scrollController;
  final double bottom;

  const JumpToBottomButton({
    super.key,
    required this.scrollController,
    this.bottom = 16,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: scrollController.showJumpToBottom,
      builder: (context, show, _) {
        if (!show) return const SizedBox.shrink();
        return Positioned(
          right: 16,
          bottom: bottom,
          child: FloatingActionButton.small(
            heroTag: 'jump_to_bottom_button',
            onPressed: scrollController.jumpToBottom,
            child: const Icon(Icons.keyboard_arrow_down),
          ),
        );
      },
    );
  }
}
