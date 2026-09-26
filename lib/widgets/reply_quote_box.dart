import 'package:flutter/material.dart';

import '../helpers/gif_helper.dart';
import '../helpers/shared_marker_deletions.dart';
import '../l10n/l10n.dart';
import '../theme/mesh_theme.dart';
import 'blocked_message_body.dart';
import 'formatted_message_text.dart';
import 'gif_message.dart';
import 'mco_image_message.dart';
import 'mco_image_original.dart';
import 'mention_chip.dart';

// Replies in the direct and room chats. The channel transcript draws its
// own quote, banner and mention (upstream code, kept where it is); these
// widgets give the chats upstream has no replies in the same look.

/// The quote a message shows above its text: whom it answers and an excerpt
/// of what, tappable to reach the original.
class ReplyQuoteBox extends StatelessWidget {
  final String authorName;
  final String text;

  /// The quoted message is ours, and the author line takes the accent.
  final bool ownQuote;

  /// The quoted message sits behind a blocked-sender placeholder, so its
  /// words stay off the screen here too.
  final bool hidden;
  final bool mcoForceLora;
  final double textScale;
  final VoidCallback? onTap;

  const ReplyQuoteBox({
    super.key,
    required this.authorName,
    required this.text,
    required this.textScale,
    this.ownQuote = false,
    this.hidden = false,
    this.mcoForceLora = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final previewTextColor = colorScheme.onSurface.withValues(alpha: 0.7);
    final trimmed = text.trim();
    final gifId = hidden ? null : GifHelper.parseGif(text);
    final image = hidden || gifId != null
        ? null
        : MCOImageMessage.tryDecode(text);
    final isMarker =
        trimmed.startsWith(SharedMarkerDeletion.markerPrefix) ||
        trimmed.startsWith(SharedMarkerDeletion.markerDeletionPrefix);

    final Widget content;
    if (hidden) {
      content = BlockedQuoteBody(
        style: TextStyle(
          fontSize: 12 * textScale,
          color: previewTextColor.withValues(alpha: 0.55),
          fontStyle: FontStyle.italic,
        ),
      );
    } else if (gifId != null) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: GifMessage(
          url: 'https://media.giphy.com/media/$gifId/giphy.gif',
          backgroundColor: colorScheme.surfaceContainerHighest,
          fallbackTextColor: previewTextColor,
          maxSize: 80,
        ),
      );
    } else if (image != null) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: MCOImageOriginalOrFallback(
          text: text,
          image: image,
          maxSize: 80,
          forceLora: mcoForceLora,
        ),
      );
    } else if (isMarker) {
      content = Row(
        children: [
          Icon(Icons.location_on_outlined, size: 14, color: previewTextColor),
          const SizedBox(width: 4),
          Text(
            context.l10n.chat_location,
            style: TextStyle(fontSize: 12 * textScale, color: previewTextColor),
          ),
        ],
      );
    } else {
      content = Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12 * textScale,
          color: previewTextColor,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(MeshRadii.sm),
          border: Border(
            left: BorderSide(color: colorScheme.primary, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.chat_replyTo(authorName),
              style: TextStyle(
                fontSize: 11 * textScale,
                fontWeight: FontWeight.bold,
                color: ownQuote ? colorScheme.primary : colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            content,
          ],
        ),
      ),
    );
  }
}

/// The line above the composer while a reply is being written: whom it
/// answers, an excerpt, and a button that drops the reply.
class ReplyComposerBanner extends StatelessWidget {
  /// Height the composer gives up to the banner, [imageHeight] when it shows
  /// a picture.
  static const double height = 64;
  static const double imageHeight = 106;

  final String authorName;
  final String text;
  final bool mcoForceLora;
  final double textScale;
  final VoidCallback onCancel;

  const ReplyComposerBanner({
    super.key,
    required this.authorName,
    required this.text,
    required this.textScale,
    required this.onCancel,
    this.mcoForceLora = false,
  });

  static bool showsImage(String text) =>
      MCOImageMessage.tryDecode(text) != null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final previewTextColor = scheme.onSecondaryContainer.withValues(alpha: 0.7);
    final image = MCOImageMessage.tryDecode(text);

    final Widget preview;
    if (image != null) {
      preview = LayoutBuilder(
        builder: (context, constraints) {
          const maxHeight = 70.0;
          var width = constraints.maxWidth;
          var height = width / (image.width / image.height);
          if (height > maxHeight) {
            height = maxHeight;
            width = height * (image.width / image.height);
          }
          return Align(
            alignment: Alignment.centerLeft,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: width,
                height: height,
                child: MCOImageOriginalOrFallback(
                  text: text,
                  image: image,
                  maxSize: width > height ? width : height,
                  forceLora: mcoForceLora,
                ),
              ),
            ),
          );
        },
      );
    } else {
      preview = Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11 * textScale, color: previewTextColor),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.reply, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.chat_replyingTo(authorName),
                  style: MeshTheme.mono(
                    fontSize: 11 * textScale,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                preview,
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onCancel,
            color: scheme.onSecondaryContainer,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

/// A reply drawn as a plain mention: the chip leads the body, which still
/// goes through the mention renderer, and a translation keeps its original
/// on a line of its own.
class ReplyMentionText extends StatelessWidget {
  final String mentionName;
  final String text;
  final String? originalText;
  final TextStyle style;
  final TextStyle originalStyle;
  final double textScale;
  final TextScaler? textScaler;
  final bool simplified;
  final bool markupEnabled;
  final VoidCallback? onMentionTap;
  final VoidCallback? onSecondaryTap;

  const ReplyMentionText({
    super.key,
    required this.mentionName,
    required this.text,
    required this.style,
    required this.originalStyle,
    required this.textScale,
    required this.simplified,
    this.originalText,
    this.textScaler,
    this.markupEnabled = true,
    this.onMentionTap,
    this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    final chip = MentionChip(
      senderName: mentionName,
      textScale: textScale,
      simplified: simplified,
      textStyle: style,
      onTap: onMentionTap,
    );
    final display = text.trim();
    final body = FormattedMessageText(
      text: display,
      style: style,
      textScale: textScale,
      simplified: simplified,
      textScaler: textScaler,
      markupEnabled: markupEnabled,
      onSecondaryTap: onSecondaryTap,
      leadingSpans: [
        WidgetSpan(
          alignment: chip.alignment,
          baseline: chip.baseline,
          child: chip,
        ),
        if (display.isNotEmpty) TextSpan(text: simplified ? ' ' : '  '),
      ],
    );
    final original = originalText?.trim();
    if (original == null || original.isEmpty || original == display) {
      return body;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        body,
        const SizedBox(height: 6),
        Text(original, style: originalStyle),
      ],
    );
  }
}
