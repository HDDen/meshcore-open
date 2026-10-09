import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/mesh_link_linkifier.dart';

// meshcore:// links picked out of message text: a channel link the QR parser
// reads and a contact link in either of its forms become links, the words
// and the punctuation around them stay text, anything else behind the
// scheme stays text too, and web links are left to the URL linkifier.

const _channel =
    'meshcore://channel/add?name=%23public_mco&secret=cbf8c4bc9379ab17b216721171f3ba89&region_scope=ru-kda';
const _contact =
    'meshcore://contact/add?name=%F0%9F%A4%94&public_key=0946621c621e4410ee1f43cec55d463b1e8b7006ca8014057306383a95b8b725&type=1';
const _advert =
    'meshcore://1100afdad95d3a1e3ee4c5152e45dbfd89b3ef584d542c958e90c4b90feb6a1bc023'
    '6139c96ac2b0a6fea46b4a4b4e93aa0e40074ee0a4b25f9f2caa1b1ceed6900fa548'
    'b759d3a8cb5d968fc118012b50c4e7a2ef4ae68b40587935b71f282e6ef48286530'
    'c8151524c';
const _options = LinkifyOptions(humanize: false, defaultToHttps: false);

List<LinkifyElement> _parse(
  String text, [
  List<Linkifier> linkifiers = const [MeshLinkLinkifier()],
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
    expect(
      _shape(_parse('join $_channel please')),
      'join |<$_channel>| please',
    );
  });

  test("a contact link in a sentence, the app's form or the advert, becomes "
      'a link, the words around it stay text', () {
    expect(
      _shape(_parse('всем привет, $_contact пишите мне')),
      'всем привет, |<$_contact>| пишите мне',
    );
    expect(_shape(_parse('my node: $_advert')), 'my node: |<$_advert>');
  });

  test('punctuation closing the sentence stays text', () {
    expect(_shape(_parse('here: $_channel.')), 'here: |<$_channel>|.');
    expect(_shape(_parse('($_channel)')), '(|<$_channel>|)');
    expect(_shape(_parse('$_advert, add me!')), '<$_advert>|, add me!');
    expect(_shape(_parse('$_contact.')), '<$_contact>|.');
  });

  test('every link of a message is picked', () {
    const other =
        'meshcore://channel/add?name=Local&secret=8b3387e9c5cdea6ac9e5edbaa115cd72';
    expect(
      _shape(_parse('$_channel or $other')),
      '<$_channel>| or |<$other>',
    );
    expect(
      _shape(_parse('$_contact and $_advert')),
      '<$_contact>| and |<$_advert>',
    );
  });

  test('a link neither parser reads stays text', () {
    const broken = 'meshcore://channel/add?name=%23x&secret=1234';
    expect(_shape(_parse('see $broken')), 'see $broken');
    const short = 'meshcore://0a0b0c https://example.com';
    expect(_shape(_parse(short)), short);
    const badKey =
        'meshcore://contact/add?name=x&public_key=0946621c&type=1 hi';
    expect(_shape(_parse(badKey)), badKey);
  });

  test('a message without the scheme is one piece of text', () {
    expect(_parse('hello https://example.com'), hasLength(1));
  });

  test('beside the URL linkifier both kinds become links', () {
    final shape = _shape(
      _parse('$_channel and https://example.com', const [
        MeshLinkLinkifier(),
        UrlLinkifier(),
      ]),
    );
    expect(shape, '<$_channel>| and |<https://example.com>');
    expect(
      _shape(
        _parse('$_contact and https://example.com', const [
          MeshLinkLinkifier(),
          UrlLinkifier(),
        ]),
      ),
      '<$_contact>| and |<https://example.com>',
    );
  });
}
