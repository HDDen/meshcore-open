import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_link_linkifier.dart';

// Channel links (meshcore://channel/add?...) picked out of message text: only
// a link the QR parser reads becomes one, the words and the punctuation
// around it stay text, and contact and web links are left to others.

const _link =
    'meshcore://channel/add?name=%23public_mco&secret=cbf8c4bc9379ab17b216721171f3ba89&region_scope=ru-kda';
const _options = LinkifyOptions(humanize: false, defaultToHttps: false);

List<LinkifyElement> _parse(
  String text, [
  List<Linkifier> linkifiers = const [ChannelLinkLinkifier()],
]) {
  var elements = <LinkifyElement>[TextElement(text)];
  for (final linkifier in linkifiers) {
    elements = linkifier.parse(elements, _options);
  }
  return elements;
}

/// The elements joined by `|`, a link as its URL in angle brackets.
String _shape(List<LinkifyElement> elements) => [
  for (final element in elements)
    element is LinkableElement ? '<${element.url}>' : element.text,
].join('|');

void main() {
  test('a channel link in a sentence becomes a link, the words around it '
      'stay text', () {
    expect(_shape(_parse('join $_link please')), 'join |<$_link>| please');
  });

  test('punctuation closing the sentence stays text', () {
    expect(_shape(_parse('here: $_link.')), 'here: |<$_link>|.');
    expect(_shape(_parse('($_link)')), '(|<$_link>|)');
  });

  test('every channel link of a message is picked', () {
    const other =
        'meshcore://channel/add?name=Local&secret=8b3387e9c5cdea6ac9e5edbaa115cd72';
    expect(_shape(_parse('$_link or $other')), '<$_link>| or |<$other>');
  });

  test('a link the parser refuses stays text', () {
    const broken = 'meshcore://channel/add?name=%23x&secret=1234';
    expect(_shape(_parse('see $broken')), 'see $broken');
  });

  test('a contact link and a web link are left alone', () {
    const text = 'meshcore://0a0b0c https://example.com';
    expect(_shape(_parse(text)), text);
  });

  test('beside the URL linkifier both kinds become links', () {
    final shape = _shape(
      _parse('$_link and https://example.com', const [
        ChannelLinkLinkifier(),
        UrlLinkifier(),
      ]),
    );
    expect(shape, '<$_link>| and |<https://example.com>');
  });
}
