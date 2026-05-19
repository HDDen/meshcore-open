import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../helpers/chat_scroll_controller.dart';
import '../services/app_settings_service.dart';

typedef ChatMessageListBuilder =
    Widget Function(
      BuildContext context,
      EdgeInsets padding,
      double bottomReservedExtent,
    );

class JumpToBottomButton extends StatefulWidget {
  final ChatScrollController scrollController;

  static const double buttonRightInset = 16;
  static const double buttonBottomInset = 16;
  static const double buttonSpacing = 8;
  static const double smallButtonExtent = 40;
  static const double messageListGap = 8;

  const JumpToBottomButton({super.key, required this.scrollController});

  static double reservedMessageListPadding({
    required bool showJumpToBottomButton,
    required bool showHideKeyboardButton,
  }) {
    if (!showHideKeyboardButton) return 0;

    // Keep the newest visible message clear of the floating keyboard button.
    return buttonBottomInset +
        smallButtonExtent +
        messageListGap +
        (showJumpToBottomButton ? buttonSpacing + smallButtonExtent : 0);
  }

  static bool isKeyboardVisible() {
    return WidgetsBinding.instance.platformDispatcher.views
        .any((view) => view.viewInsets.bottom > 0);
  }

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
    final keyboardVisible = JumpToBottomButton.isKeyboardVisible();
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
          right: JumpToBottomButton.buttonRightInset,
          bottom: JumpToBottomButton.buttonBottomInset,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (show)
                FloatingActionButton.small(
                  heroTag: 'jump_to_bottom_button',
                  onPressed: widget.scrollController.jumpToBottom,
                  child: const Icon(Icons.keyboard_arrow_down),
                ),
              if (show && showHideKeyboardButton)
                const SizedBox(height: JumpToBottomButton.buttonSpacing),
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

class JumpToBottomReservedPadding extends StatefulWidget {
  final ChatScrollController scrollController;
  final EdgeInsets basePadding;
  final ChatMessageListBuilder builder;

  const JumpToBottomReservedPadding({
    super.key,
    required this.scrollController,
    required this.basePadding,
    required this.builder,
  });

  @override
  State<JumpToBottomReservedPadding> createState() =>
      _JumpToBottomReservedPaddingState();
}

class _JumpToBottomReservedPaddingState
    extends State<JumpToBottomReservedPadding>
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
    final keyboardVisible = JumpToBottomButton.isKeyboardVisible();
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
      builder: (context, showJumpToBottomButton, _) {
        final showHideKeyboardButton =
            showKeyboardHidingButton && _keyboardVisible;
        final reservedPadding = JumpToBottomButton.reservedMessageListPadding(
          showJumpToBottomButton: showJumpToBottomButton,
          showHideKeyboardButton: showHideKeyboardButton,
        );
        return widget.builder(context, widget.basePadding, reservedPadding);
      },
    );
  }
}
