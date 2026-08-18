import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';

import '../helpers/link_handler.dart';
import '../helpers/mention_autocomplete.dart';
import '../screens/contacts_screen.dart';
import 'mention_chip.dart';

/// Message body with `@[name]` mentions drawn as chips.
///
/// Mentions need a widget, not a text style, so the body is assembled as spans
/// instead of handed to `Linkify` whole. URLs are linkified span by span so
/// they stay tappable alongside the chips.
class MentionMessageText extends StatefulWidget {
  const MentionMessageText({
    super.key,
    required this.text,
    required this.style,
    required this.textScale,
    required this.simplified,
    this.textScaler,
    this.leadingSpans = const [],
    this.onSecondaryTap,
  });

  final String text;
  final TextStyle style;

  /// Chat text zoom, applied to the chip's own sizing.
  final double textScale;
  final bool simplified;
  final TextScaler? textScaler;

  /// Spans placed before the body — the reply chip, when there is one.
  final List<InlineSpan> leadingSpans;
  final VoidCallback? onSecondaryTap;

  @override
  State<MentionMessageText> createState() => _MentionMessageTextState();
}

class _MentionMessageTextState extends State<MentionMessageText> {
  static const _options = LinkifyOptions(
    humanize: false,
    defaultToHttps: false,
  );
  static const _linkifiers = [UrlLinkifier(), EmailLinkifier()];

  final List<TapGestureRecognizer> _recognizers = [];
  List<InlineSpan> _spans = const [];
  Object? _builtFor;

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  /// `flutter_linkify` re-exports the element and linkifier types but not its
  /// `linkify()` entry point, so the linkifiers are run by hand here — same
  /// pipeline the `Linkify` widget uses, just producing spans we can mix chips
  /// into.
  List<LinkifyElement> _linkifySegment(String text) {
    if (text.isEmpty) return const [];
    var elements = <LinkifyElement>[TextElement(text)];
    for (final linkifier in _linkifiers) {
      elements = linkifier.parse(elements, _options);
    }
    return elements;
  }

  /// Spans are cached because each rebuild would otherwise allocate a fresh set
  /// of tap recognizers, and the old ones have to be disposed by hand.
  List<InlineSpan> _spansFor(BuildContext context) {
    final key = Object.hash(
      widget.text,
      widget.simplified,
      widget.textScale,
      widget.style,
      widget.leadingSpans.length,
      Theme.of(context).brightness,
    );
    if (_builtFor == key) return _spans;

    _disposeRecognizers();
    final linkStyle = LinkHandler.defaultLinkStyle(context, widget.style);
    final spans = <InlineSpan>[...widget.leadingSpans];

    for (final segment in MentionText.split(widget.text)) {
      if (segment.isMention) {
        final chip = MentionChip(
          senderName: segment.text,
          textScale: widget.textScale,
          simplified: widget.simplified,
          textStyle: widget.style,
          onTap: () => ContactsScreen.openWithSearch(context, segment.text),
        );
        spans.add(
          WidgetSpan(
            alignment: chip.alignment,
            baseline: chip.baseline,
            child: chip,
          ),
        );
        continue;
      }
      for (final element in _linkifySegment(segment.text)) {
        if (element is LinkableElement) {
          final recognizer = TapGestureRecognizer()
            ..onTap = () =>
                unawaited(LinkHandler.handleLinkTap(context, element.url));
          _recognizers.add(recognizer);
          spans.add(
            TextSpan(
              text: element.text,
              style: linkStyle,
              recognizer: recognizer,
            ),
          );
        } else {
          spans.add(TextSpan(text: element.text));
        }
      }
    }

    _spans = spans;
    _builtFor = key;
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final body = Text.rich(
      TextSpan(style: widget.style, children: _spansFor(context)),
      textScaler: widget.textScaler,
    );
    if (widget.onSecondaryTap == null) return body;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.buttons & kSecondaryMouseButton != 0) {
          widget.onSecondaryTap!();
        }
      },
      child: body,
    );
  }
}
