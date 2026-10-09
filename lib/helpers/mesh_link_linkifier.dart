import 'package:flutter_linkify/flutter_linkify.dart';

import 'channel_qr_link.dart'; // channel-qr-chat
import 'contact_link.dart';

/// Picks `meshcore://` links out of message text, so a channel or a contact
/// shared into a chat is added with a tap (`LinkHandler.handleLinkTap`); the
/// URL linkifier knows only http, https and www. A channel link is what
/// [ChannelQrLink.tryParse] reads, a contact link what [ContactLink.tryParse]
/// reads, the contact's advert as hex or the MeshCore app's `contact/add`
/// form; anything else behind the scheme stays text, and so does punctuation
/// closing the sentence around a link: a link the app writes ends in hex, a
/// name, a region or a type, never in punctuation.
///
/// Every message body comes through here on every build, so a text without
/// the scheme, which is nearly all of them, is answered by one substring
/// search before any pattern or parser runs. The scheme is matched as the
/// apps write it, in lower case.
class MeshLinkLinkifier extends Linkifier {
  const MeshLinkLinkifier();

  static const String _scheme = 'meshcore://';
  static final RegExp _candidate = RegExp(r'meshcore://\S+');
  static final RegExp _closingPunctuation = RegExp(r'''[.,;:!?)\]}'"»]+$''');

  @override
  List<LinkifyElement> parse(
    List<LinkifyElement> elements,
    LinkifyOptions options,
  ) => [
    for (final element in elements)
      if (element is TextElement) ..._split(element.text) else element,
  ];

  static List<LinkifyElement> _split(String text) {
    if (!text.contains(_scheme)) return [TextElement(text)];
    final elements = <LinkifyElement>[];
    var textStart = 0;
    for (final match in _candidate.allMatches(text)) {
      final link = match[0]!.replaceFirst(_closingPunctuation, '');
      if (!_isLink(link)) continue;
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

  static bool _isLink(String link) =>
      ContactLink.tryParse(link) != null ||
      // channel-qr-chat
      (ChannelQrLink.enabled && ChannelQrLink.tryParse(link) != null);
}
