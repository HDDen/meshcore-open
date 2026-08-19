import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:latlong2/latlong.dart';

import '../helpers/coordinate_text.dart';
import '../helpers/link_handler.dart';
import '../helpers/mention_autocomplete.dart';
import '../helpers/message_markup.dart';
import '../screens/contacts_screen.dart';
import '../screens/map_screen.dart';
import '../theme/mesh_theme.dart';
import 'mention_chip.dart';

/// Message body with inline markup applied and `@[name]` mentions drawn as
/// chips.
///
/// Mentions need a widget, not a text style, so the body is assembled as spans
/// instead of handed to `Linkify` whole. URLs and `lat,lon` pairs are picked
/// out span by span so they stay tappable alongside the chips and the styled
/// runs.
class FormattedMessageText extends StatefulWidget {
  const FormattedMessageText({
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
  State<FormattedMessageText> createState() => _FormattedMessageTextState();
}

class _FormattedMessageTextState extends State<FormattedMessageText> {
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
    // A coordinate keeps the body colour and is marked by an underline alone —
    // the look a message that is nothing but coordinates already has.
    final coordinateStyle = widget.style.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: widget.style.color,
    );
    final spans = <InlineSpan>[...widget.leadingSpans];

    // Markup is the outer layer: it decides how a run looks, and mentions and
    // links are resolved inside each run.
    for (final block in MessageMarkup.parse(widget.text)) {
      final blockStyle = _applyMarkup(widget.style, block.styles);
      for (final segment in MentionText.split(block.text)) {
        if (segment.isMention) {
          final chip = MentionChip(
            senderName: segment.text,
            textScale: widget.textScale,
            simplified: widget.simplified,
            textStyle: blockStyle,
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
                style: _applyMarkup(linkStyle, block.styles),
                recognizer: recognizer,
              ),
            );
          } else {
            // Coordinates are looked for inside plain runs only, so a pair
            // sitting in a URL stays part of that link.
            for (final part in CoordinateText.split(element.text)) {
              if (!part.isCoordinate) {
                spans.add(TextSpan(text: part.text, style: blockStyle));
                continue;
              }
              final recognizer = TapGestureRecognizer()
                ..onTap = () => _openCoordinate(context, part);
              _recognizers.add(recognizer);
              spans.add(
                TextSpan(
                  text: part.text,
                  style: _applyMarkup(coordinateStyle, block.styles),
                  recognizer: recognizer,
                ),
              );
            }
          }
        }
      }
    }

    _spans = spans;
    _builtFor = key;
    return spans;
  }

  void _openCoordinate(BuildContext context, CoordinateSegment segment) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          highlightPosition: LatLng(segment.latitude!, segment.longitude!),
          highlightLabel: segment.text.trim(),
        ),
      ),
    );
  }

  /// Folds parsed markup into a text style. Underline and strikethrough can
  /// apply at once, so decorations are combined rather than overwritten.
  static TextStyle _applyMarkup(TextStyle base, MarkupStyles styles) {
    if (styles.isPlain) return base;
    final decorations = <TextDecoration>[
      if (styles.underline) TextDecoration.underline,
      if (styles.strikethrough) TextDecoration.lineThrough,
      if (base.decoration != null && base.decoration != TextDecoration.none)
        base.decoration!,
    ];
    var style = base.copyWith(
      fontWeight: styles.bold ? FontWeight.w700 : null,
      fontStyle: styles.italic ? FontStyle.italic : null,
      decoration: decorations.isEmpty
          ? null
          : TextDecoration.combine(decorations),
      color: MarkupPalette.of(styles.color),
      decorationColor: decorations.isEmpty
          ? null
          : (MarkupPalette.of(styles.color) ?? base.color),
    );
    if (styles.mono) {
      style = style.copyWith(
        fontFamily: MeshFonts.mono,
        fontFamilyFallback: MeshFonts.monoFallback,
      );
    }
    return style;
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
