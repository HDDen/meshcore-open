import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../helpers/coordinate_text.dart';
import '../helpers/link_handler.dart';
import '../helpers/mention_autocomplete.dart';
import '../helpers/message_markup.dart';
import '../services/app_settings_service.dart';
import '../services/chat_text_scale_service.dart';
import 'formatted_message_text.dart';

class TranslatedMessageContent extends StatelessWidget {
  final String displayText;
  final String? originalText;
  final TextStyle style;
  final TextStyle? originalStyle;
  final bool showOriginalFirst;
  final VoidCallback? onSecondaryTap;

  /// Explicit text scale for the linkified body (flutter_linkify ignores the
  /// ambient MediaQuery scaler); used to apply the global UI scale.
  final TextScaler? textScaler;

  /// False renders the markup markers as literal text; see
  /// [FormattedMessageText.markupEnabled].
  final bool markupEnabled;

  const TranslatedMessageContent({
    super.key,
    required this.displayText,
    required this.style,
    this.originalText,
    this.originalStyle,
    this.showOriginalFirst = true,
    this.textScaler,
    this.onSecondaryTap,
    this.markupEnabled = true,
  });

  /// Mentions need widget spans, markup needs per-run styles and a `lat,lon`
  /// pair needs its own tap target — none of which `Linkify` can produce, so
  /// text carrying any of them is assembled span by span instead. Plain text
  /// keeps the original path, including selectable linkify on desktop.
  Widget _buildBody({
    required BuildContext context,
    required String text,
    required TextStyle style,
  }) {
    if (!MentionText.has(text) &&
        (!markupEnabled || !MessageMarkup.has(text)) &&
        !CoordinateText.has(text)) {
      return LinkHandler.buildLinkifyText(
        context: context,
        text: text,
        style: style,
        textScaler: textScaler,
        onSecondaryTap: onSecondaryTap,
      );
    }
    return FormattedMessageText(
      text: text,
      style: style,
      textScale: context.watch<ChatTextScaleService>().scale,
      simplified: context
          .watch<AppSettingsService>()
          .settings
          .simplifiedMentions,
      textScaler: textScaler,
      onSecondaryTap: onSecondaryTap,
      markupEnabled: markupEnabled,
    );
  }

  @override
  Widget build(BuildContext context) {
    final trimmedDisplay = displayText.trim();
    final trimmedOriginal = originalText?.trim();
    final shouldShowOriginal =
        trimmedOriginal != null &&
        trimmedOriginal.isNotEmpty &&
        trimmedOriginal != trimmedDisplay;
    final originalWidget = shouldShowOriginal
        ? _buildBody(
            context: context,
            text: trimmedOriginal,
            style:
                originalStyle ??
                style.copyWith(
                  fontStyle: FontStyle.italic,
                  fontSize: style.fontSize,
                ),
          )
        : null;
    final translatedWidget = _buildBody(
      context: context,
      text: trimmedDisplay,
      style: style,
    );

    if (!shouldShowOriginal) {
      return translatedWidget;
    }

    final children = showOriginalFirst
        ? [originalWidget!, const SizedBox(height: 6), translatedWidget]
        : [translatedWidget, const SizedBox(height: 6), originalWidget!];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}
