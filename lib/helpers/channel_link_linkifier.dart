import 'package:flutter_linkify/flutter_linkify.dart';

import 'channel_qr_link.dart';

/// Picks `meshcore://channel/add?...` links out of message text, so a channel
/// shared into a chat is added with a tap (`LinkHandler.handleLinkTap`). The
/// URL linkifier knows only http, https and www. Only what
/// [ChannelQrLink.tryParse] accepts becomes a link, and punctuation that ends
/// the sentence around one stays text: a link the app writes ends in a hex
/// secret or a region, never in punctuation.
///
/// Fork-only, see `helpers/channel_qr_link.dart` for how to remove it.
class ChannelLinkLinkifier extends Linkifier {
  const ChannelLinkLinkifier();

  static final _candidate = RegExp(
    r'meshcore://channel/add\S*',
    caseSensitive: false,
  );
  static final _closingPunctuation = RegExp(r'''[.,;:!?)\]}'"»]+$''');

  @override
  List<LinkifyElement> parse(
    List<LinkifyElement> elements,
    LinkifyOptions options,
  ) {
    if (!ChannelQrLink.enabled) return elements;
    return [
      for (final element in elements)
        if (element is TextElement) ..._split(element.text) else element,
    ];
  }

  static List<LinkifyElement> _split(String text) {
    final elements = <LinkifyElement>[];
    var textStart = 0;
    for (final match in _candidate.allMatches(text)) {
      final link = match[0]!.replaceFirst(_closingPunctuation, '');
      if (ChannelQrLink.tryParse(link) == null) continue;
      if (match.start > textStart) {
        elements.add(TextElement(text.substring(textStart, match.start)));
      }
      elements.add(UrlElement(link));
      textStart = match.start + link.length;
    }
    if (textStart == 0) return [TextElement(text)];
    if (textStart < text.length) {
      elements.add(TextElement(text.substring(textStart)));
    }
    return elements;
  }
}
