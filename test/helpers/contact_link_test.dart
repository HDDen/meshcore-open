import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/contact_link.dart';

// A contact shared as a meshcore:// link, in its two forms: the advert packet
// as hex, which the node imports and verifies, and the MeshCore app's
// contact/add link, which names a key, a type and a name. Each is read for
// what the question before adding shows, and anything that is neither stays
// text.

/// A real advert packet: header 0x11 (an advert, flooded), no path, the key,
/// the timestamp, the signature, flags 0x81 (a companion with a name) and
/// the name "QRL".
const _advertHex =
    '1100afdad95d3a1e3ee4c5152e45dbfd89b3ef584d542c958e90c4b90feb6a1bc023'
    '6139c96ac2b0a6fea46b4a4b4e93aa0e40074ee0a4b25f9f2caa1b1ceed6900fa548'
    'b759d3a8cb5d968fc118012b50c4e7a2ef4ae68b40587935b71f282e6ef48286530'
    'c8151524c';
const _advertKey =
    'afdad95d3a1e3ee4c5152e45dbfd89b3ef584d542c958e90c4b90feb6a1bc023';
const _advert = 'meshcore://$_advertHex';

const _addKey =
    '0946621c621e4410ee1f43cec55d463b1e8b7006ca8014057306383a95b8b725';
const _add =
    'meshcore://contact/add?name=%F0%9F%A4%94&public_key=$_addKey&type=1';

void main() {
  test('an advert packet: the key, the type and the name are read off it, '
      'and the packet is kept whole for the node', () {
    final link = ContactLink.tryParse(_advert);
    expect(link, isA<ContactAdvertLink>());
    link as ContactAdvertLink;
    expect(link.publicKeyHex, _advertKey);
    expect(link.type, advTypeChat);
    expect(link.name, 'QRL');
    expect(link.packet, hex2Uint8List(_advertHex));
    expect(link.shortPublicKey, 'afdad9...1bc023');
  });

  test("the MeshCore app's link: the name URL-decoded, the key, the type", () {
    final link = ContactLink.tryParse(_add);
    expect(link, isA<ContactAddLink>());
    link as ContactAddLink;
    expect(link.name, '\u{1F914}');
    expect(link.publicKeyHex, _addKey);
    expect(link.publicKey, hex2Uint8List(_addKey));
    expect(link.type, advTypeChat);

    final repeater = ContactLink.tryParse(
      'meshcore://contact/add?name=Example+Contact&public_key=$_addKey&type=2',
    );
    expect(repeater?.name, 'Example Contact');
    expect(repeater?.type, advTypeRepeater);
  });

  test('a link without a name names the contact by its key, one without a '
      'type names a companion', () {
    final link = ContactLink.tryParse(
      'meshcore://contact/add?public_key=${_addKey.toUpperCase()}',
    );
    expect(link?.name, _addKey.substring(0, 8));
    expect(link?.type, advTypeChat);
    expect(link?.publicKeyHex, _addKey);
  });

  test('a short or malformed key, an unknown type: not a link', () {
    expect(
      ContactLink.tryParse(
        'meshcore://contact/add?name=x&public_key=${_addKey.substring(1)}',
      ),
      isNull,
    );
    expect(
      ContactLink.tryParse(
        'meshcore://contact/add?name=x&public_key=$_addKey&type=9',
      ),
      isNull,
    );
    expect(ContactLink.tryParse('meshcore://contact/add?name=x'), isNull);
  });

  test('hex that is not an advert packet is not a link', () {
    expect(ContactLink.tryParse('meshcore://0a0b0c'), isNull);
    // The same packet under a text message header.
    expect(
      ContactLink.tryParse('meshcore://09${_advertHex.substring(2)}'),
      isNull,
    );
    expect(ContactLink.tryParse('meshcore://${_advertHex}0'), isNull);
    expect(
      ContactLink.tryParse('meshcore://${_advertHex.replaceRange(4, 6, 'zz')}'),
      isNull,
    );
  });

  test('a channel link and a web link are not contact links', () {
    expect(
      ContactLink.tryParse(
        'meshcore://channel/add?name=Public&secret=8b3387e9c5cdea6ac9e5edbaa115cd72',
      ),
      isNull,
    );
    expect(ContactLink.tryParse('https://example.com/$_addKey'), isNull);
  });

  test('whitespace around the link is ignored, the scheme in any case', () {
    expect(ContactLink.tryParse('  $_add\n'), isA<ContactAddLink>());
    expect(
      ContactLink.tryParse('MESHCORE://contact/add?public_key=$_addKey'),
      isA<ContactAddLink>(),
    );
    expect(
      ContactLink.tryParse('Meshcore://$_advertHex'),
      isA<ContactAdvertLink>(),
    );
  });
}
