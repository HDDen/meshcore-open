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
        final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
        if (!show && !keyboardVisible) return const SizedBox.shrink();
        return Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (show)
                FloatingActionButton.small(
                  heroTag: 'jump_to_bottom_button',
                  onPressed: scrollController.jumpToBottom,
                  child: const Icon(Icons.keyboard_arrow_down),
                ),
              if (show && keyboardVisible) const SizedBox(height: 8),
              if (keyboardVisible)
                FloatingActionButton.small(
                  heroTag: 'hide_keyboard_button',
                  onPressed: () => FocusScope.of(context).unfocus(),
                  child: const Icon(Icons.keyboard_hide),
                ),
            ],
          ),
        );
      },
    );
  }
}
