import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/contact_share_helper.dart';

final _key = Uint8List.fromList(List.generate(pubKeySize, (index) => index));
final _hex = pubKeyToHex(_key);

void main() {
  test('U32 baseline: shared cards round-trip all advertised contact types', () {
    for (final type in [advTypeChat, advTypeRepeater, advTypeRoom, advTypeSensor]) {
      final text = formatContactShareText(
        publicKey: _key,
        type: type,
        name: 'Север: репитер',
      );
      expect(text, '<$_hex:$type:Север: репитер>');
      final share = parseSharedContactText('  $text  ')!;
      expect(share.publicKey, _key);
      expect(share.type, type);
      expect(share.name, 'Север: репитер');
    }
  });

  test('U32 baseline: old card names and empty names remain readable', () {
    final share = parseSharedContactText('<${_hex.toUpperCase()}:2:Клуб <Север>>')!;
    expect(share.publicKey, _key);
    expect(share.name, 'Клуб <Север>');
    final unnamed = parseSharedContactText('<$_hex:1:>')!;
    expect(unnamed.name, _hex.substring(0, 8));
  });

  test('U32: clipboard finds one embedded card without changing chat parsing', () {
    final text = 'Sender: <${_hex.toUpperCase()}:2:Север: репитер> tail';
    final share = findSharedContactInText(text)!;
    expect(share.publicKey, _key);
    expect(share.name, 'Север: репитер');
    expect(share.type, advTypeRepeater);
    expect(parseSharedContactText(text), isNull);
    expect(
      findSharedContactInText('<$_hex:2:Клуб <Север>>')?.name,
      'Клуб <Север>',
    );
    expect(findSharedContactInText('  <$_hex:2:A>B>  ')?.name, 'A>B');
    expect(findSharedContactInText('<$_hex:2:One> <$_hex:2:Two>'), isNull);
    expect(
      findSharedContactInText('<$_hex:2:<One>> <$_hex:2:<Two>>'),
      isNull,
    );
    expect(findSharedContactInText('Hello <$_hex:5:Unknown>'), isNull);
  });

  test('U32 baseline: ordinary chat text and malformed cards are not cards', () {
    for (final text in [
      'Here is a card: <$_hex:2:Relay>',
      '<$_hex:5:Unsupported>',
      '<${_hex.substring(2)}:2:Short key>',
      '<${_hex.replaceFirst('00', 'zz')}:2:Bad key>',
    ]) {
      expect(parseSharedContactText(text), isNull, reason: text);
    }
  });
}
