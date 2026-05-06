import 'package:flutter/material.dart';
import '../helpers/chat_scroll_controller.dart';

class JumpToBottomButton extends StatelessWidget {
  final ChatScrollController scrollController;

  const JumpToBottomButton({super.key, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: scrollController.showJumpToBottom,
      builder: (context, show, _) {
        if (!show) return const SizedBox.shrink();
        return Positioned(
          right: 16,
          bottom: 16,
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
