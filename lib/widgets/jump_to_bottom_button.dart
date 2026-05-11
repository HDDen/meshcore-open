import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../helpers/chat_scroll_controller.dart';
import '../services/app_settings_service.dart';

class JumpToBottomButton extends StatefulWidget {
  final ChatScrollController scrollController;

  const JumpToBottomButton({super.key, required this.scrollController});

  @override
  State<JumpToBottomButton> createState() => _JumpToBottomButtonState();
}

class _JumpToBottomButtonState extends State<JumpToBottomButton>
    with WidgetsBindingObserver {
  bool _keyboardVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncKeyboardVisibility();
    });
  }

  @override
  void didChangeMetrics() {
    _syncKeyboardVisibility();
  }

  void _syncKeyboardVisibility() {
    final keyboardVisible = WidgetsBinding.instance.platformDispatcher.views
        .any((view) => view.viewInsets.bottom > 0);
    if (keyboardVisible == _keyboardVisible || !mounted) return;
    setState(() => _keyboardVisible = keyboardVisible);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showKeyboardHidingButton = context.select<AppSettingsService, bool>(
      (settingsService) => settingsService.settings.showKeyboardHidingButton,
    );

    return ValueListenableBuilder<bool>(
      valueListenable: widget.scrollController.showJumpToBottom,
      builder: (context, show, _) {
        final showHideKeyboardButton =
            showKeyboardHidingButton && _keyboardVisible;
        if (!show && !showHideKeyboardButton) return const SizedBox.shrink();
        return Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (show)
                FloatingActionButton.small(
                  heroTag: 'jump_to_bottom_button',
                  onPressed: widget.scrollController.jumpToBottom,
                  child: const Icon(Icons.keyboard_arrow_down),
                ),
              if (show && showHideKeyboardButton) const SizedBox(height: 8),
              if (showHideKeyboardButton)
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
