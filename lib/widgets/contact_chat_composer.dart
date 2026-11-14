import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../connector/meshcore_protocol.dart';
import '../helpers/gif_helper.dart';
import '../helpers/inserted_text_limiter.dart';
import '../l10n/l10n.dart';
import '../theme/mesh_theme.dart';
import 'byte_count_input.dart';
import 'chat_additional_actions_menu.dart';
import 'composer_text_builder.dart';
import 'gif_message.dart';

class ContactChatComposer extends StatelessWidget {
  const ContactChatComposer({
    super.key,
    required this.contactName,
    required this.controller,
    required this.focusNode,
    required this.maxBytes,
    required this.onSend,
    this.encoder,
    this.actions,
    this.translationButton,
    this.onQuickAnswers,
    this.replyBannerHeight = 0,
    this.insertedTextLimit,
    this.showRetryLimit = true,
    this.enabled = true,
  });

  final String contactName;
  final TextEditingController controller;
  final FocusNode focusNode;
  final int maxBytes;
  final VoidCallback? onSend;
  final String Function(String)? encoder;
  final Widget? actions;
  final Widget? translationButton;
  final VoidCallback? onQuickAnswers;
  final double replyBannerHeight;
  final int? insertedTextLimit;
  final bool showRetryLimit;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final media = MediaQuery.of(context);
    final maxInputHeight =
        (media.size.height -
                media.padding.top -
                kToolbarHeight -
                media.viewInsets.bottom -
                replyBannerHeight -
                48)
            .clamp(56.0, 240.0)
            .toDouble();
    final textLimit = insertedTextLimit;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (actions != null) ChatComposerSideAction(child: actions!),
            ?translationButton,
            Expanded(
              child: ComposerTextBuilder(
                controller: controller,
                builder: (context, text) {
                  final gifId = GifHelper.parseGif(text);
                  if (gifId != null) return _gifPreview(gifId, scheme);
                  return ByteCountedTextField(
                    maxBytes: maxBytes,
                    softLimitBytes: showRetryLimit
                        ? maxTextPayloadBytesAfterFullLengthAttempts
                        : null,
                    softLimitNote: showRetryLimit
                        ? l10n.chat_longMessageRetryNote(maxFullLengthTextAttempt + 1)
                        : null,
                    controller: controller,
                    focusNode: focusNode,
                    enabled: enabled,
                    maxHeight: maxInputHeight,
                    onSubmitted: (_) => onSend?.call(),
                    extraFormatters: textLimit == null
                        ? const []
                        : [InsertedTextLimiter(maxInsertedChars: textLimit)],
                    encoder: encoder,
                    decoration: InputDecoration(
                      hintText: l10n.chat_typeMessage,
                      hintMaxLines: 1,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(MeshRadii.md),
                      ),
                      filled: true,
                      fillColor: scheme.surfaceContainerLow,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            ChatComposerSideAction(
              child: ChatComposerSendButton(
                tooltip: l10n.chat_sendMessage,
                semanticLabel: l10n.chat_sendMessageTo(contactName),
                onPressed: onSend,
                onLongPress: onQuickAnswers,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gifPreview(String gifId, ColorScheme scheme) => Focus(
    autofocus: true,
    onKeyEvent: (node, event) {
      if (event is KeyDownEvent &&
          (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
        onSend?.call();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GifMessage(
              url: 'https://media.giphy.com/media/$gifId/giphy.gif',
              backgroundColor: scheme.surfaceContainerHighest,
              fallbackTextColor: scheme.onSurface.withValues(alpha: 0.6),
              maxSize: 160,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            controller.clear();
            focusNode.requestFocus();
          },
        ),
      ],
    ),
  );
}
