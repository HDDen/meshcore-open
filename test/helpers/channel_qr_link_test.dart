import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_qr_link.dart';
import 'package:meshcore_open/models/channel.dart';

void main() {
  group('ChannelQrLink.toLink', () {
    final psk = Channel.parsePskHex('3cae16fd067ba9c32a98be22e9b98525');

    test('writes the name URL-encoded and the secret in lower case', () {
      expect(
        ChannelQrLink(name: '#ping', psk: psk).toLink(),
        'meshcore://channel/add?name=%23ping&secret=3cae16fd067ba9c32a98be22e9b98525',
      );
    });

    test('adds region_scope only when a region is given', () {
      expect(
        ChannelQrLink(name: '#ping', psk: psk, regionScope: ' bots ').toLink(),
        'meshcore://channel/add?name=%23ping&secret=3cae16fd067ba9c32a98be22e9b98525&region_scope=bots',
      );
      expect(
        ChannelQrLink(name: '#ping', psk: psk, regionScope: '  ').toLink(),
        isNot(contains('region_scope')),
      );
    });

    test('a written link reads back the same', () {
      final link = ChannelQrLink(
        name: 'My канал & co',
        psk: psk,
        regionScope: 'ru-south',
      );
      final parsed = ChannelQrLink.tryParse(link.toLink());
      expect(parsed!.name, link.name);
      expect(parsed.psk, link.psk);
      expect(parsed.regionScope, 'ru-south');
    });
  });

  group('ChannelQrLink.tryParse', () {
    test('reads the example from MeshCore docs/qr_codes.md', () {
      final link = ChannelQrLink.tryParse(
        'meshcore://channel/add?name=Public&secret=8b3387e9c5cdea6ac9e5edbaa115cd72',
      );
      expect(link, isNotNull);
      expect(link!.name, 'Public');
      expect(
        Channel.formatPskHex(link.psk).toLowerCase(),
        '8b3387e9c5cdea6ac9e5edbaa115cd72',
      );
      expect(link.regionScope, isNull);
      expect(link.isHashtag, isFalse);
    });

    test('decodes a URL-encoded name and an upper-case secret', () {
      final link = ChannelQrLink.tryParse(
        'meshcore://channel/add?name=My+%D0%BA%D0%B0%D0%BD%D0%B0%D0%BB&secret=8B3387E9C5CDEA6AC9E5EDBAA115CD72',
      );
      expect(link!.name, 'My канал');
      expect(
        Channel.formatPskHex(link.psk).toLowerCase(),
        '8b3387e9c5cdea6ac9e5edbaa115cd72',
      );
    });

    test('keeps the optional region scope', () {
      final link = ChannelQrLink.tryParse(
        'meshcore://channel/add?name=Local&secret=8b3387e9c5cdea6ac9e5edbaa115cd72&region_scope=ru-south',
      );
      expect(link!.regionScope, 'ru-south');
    });

    test('a hashtag link without a secret derives the key from the name', () {
      final link = ChannelQrLink.tryParse('meshcore://channel/add?name=%23test');
      expect(link, isNotNull);
      expect(link!.isHashtag, isTrue);
      expect(link.psk, Channel.derivePskFromHashtag('#test'));
    });

    test('tolerates surrounding whitespace and a trailing slash', () {
      final link = ChannelQrLink.tryParse(
        '  meshcore://channel/add/?name=A&secret=8b3387e9c5cdea6ac9e5edbaa115cd72\n',
      );
      expect(link!.name, 'A');
    });

    test('shortens an over-long name on a character boundary', () {
      const secret = '8b3387e9c5cdea6ac9e5edbaa115cd72';
      final ascii = ChannelQrLink.tryParse(
        'meshcore://channel/add?name=${'x' * 40}&secret=$secret',
      );
      expect(ascii!.name, 'x' * 31);
      // Twenty Cyrillic letters are 40 bytes; 15 of them fit into 31 bytes.
      final cyrillic = ChannelQrLink.tryParse(
        Uri(
          scheme: 'meshcore',
          host: 'channel',
          path: '/add',
          queryParameters: {'name': 'ж' * 20, 'secret': secret},
        ).toString(),
      );
      expect(cyrillic!.name, 'ж' * 15);
    });

    test('a long hashtag keeps the key of its full name', () {
      final name = '#${'a' * 40}';
      final link = ChannelQrLink.tryParse(
        'meshcore://channel/add?name=${Uri.encodeQueryComponent(name)}',
      );
      expect(link!.name.length, 31);
      expect(link.psk, Channel.derivePskFromHashtag(name));
    });

    test('rejects everything that is not a channel link', () {
      const secret = '8b3387e9c5cdea6ac9e5edbaa115cd72';
      for (final raw in [
        '',
        'hello',
        'https://example.com/channel/add?name=A&secret=$secret',
        'meshcore://contact/add?name=A&public_key=$secret$secret&type=1',
        'meshcore://channel/remove?name=A&secret=$secret',
        'meshcore://channel/add?secret=$secret',
        'meshcore://channel/add?name=&secret=$secret',
        'meshcore://channel/add?name=A',
        'meshcore://channel/add?name=A&secret=1234',
        'meshcore://channel/add?name=A&secret=zz3387e9c5cdea6ac9e5edbaa115cd72',
        'meshcore://channel/add?name=%23',
      ]) {
        expect(ChannelQrLink.tryParse(raw), isNull, reason: raw);
        expect(ChannelQrLink.isValid(raw), isFalse, reason: raw);
      }
    });
  });
}
