import 'package:flutter/material.dart';

import '../helpers/link_handler.dart';

class TranslatedMessageContent extends StatelessWidget {
  final String displayText;
  final String? originalText;
  final TextStyle style;
  final TextStyle? originalStyle;
  final bool showOriginalFirst;

  /// Explicit text scale for the linkified body (flutter_linkify ignores the
  /// ambient MediaQuery scaler); used to apply the global UI scale.
  final TextScaler? textScaler;

  const TranslatedMessageContent({
    super.key,
    required this.displayText,
    required this.style,
    this.originalText,
    this.originalStyle,
    this.showOriginalFirst = true,
    this.textScaler,
  });

  @override
  Widget build(BuildContext context) {
    final trimmedDisplay = displayText.trim();
    final trimmedOriginal = originalText?.trim();
    final shouldShowOriginal =
        trimmedOriginal != null &&
        trimmedOriginal.isNotEmpty &&
        trimmedOriginal != trimmedDisplay;
    final originalWidget = shouldShowOriginal
        ? LinkHandler.buildLinkifyText(
            context: context,
            text: trimmedOriginal,
            style:
                originalStyle ??
                style.copyWith(
                  fontStyle: FontStyle.italic,
                  fontSize: style.fontSize,
                ),
            textScaler: textScaler,
          )
        : null;
    final translatedWidget = LinkHandler.buildLinkifyText(
      context: context,
      text: trimmedDisplay,
      style: style,
      textScaler: textScaler,
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
