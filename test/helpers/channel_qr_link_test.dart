import 'dart:typed_data';

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

    test('keeps a region without the # the hash adds back', () {
      const secret = '8b3387e9c5cdea6ac9e5edbaa115cd72';
      String? regionOf(String value) => ChannelQrLink.tryParse(
        'meshcore://channel/add?name=A&secret=$secret&region_scope=$value',
      )?.regionScope;
      expect(regionOf('%23bots'), 'bots');
      expect(regionOf('%20ru-south%20'), 'ru-south');
      expect(regionOf('%23'), isNull);
      expect(regionOf('Europe'), 'Europe');
      expect(regionOf('a' * ChannelQrLink.maxRegionLength), hasLength(30));
    });

    test('refuses a link whose region the app could not use', () {
      const secret = '8b3387e9c5cdea6ac9e5edbaa115cd72';
      for (final region in [
        '%24private', // a private region: its key lives on a repeater
        'a' * (ChannelQrLink.maxRegionLength + 1),
        'two%20words',
        'a.b',
      ]) {
        expect(
          ChannelQrLink.tryParse(
            'meshcore://channel/add?name=A&secret=$secret&region_scope=$region',
          ),
          isNull,
          reason: region,
        );
      }
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

  group('ChannelQrLink.importInto', () {
    const linkSecret = '3cae16fd067ba9c32a98be22e9b98525';
    const otherSecret = '8b3387e9c5cdea6ac9e5edbaa115cd72';

    Channel channel(int index, String name, String secret) =>
        Channel(index: index, name: name, psk: Channel.parsePskHex(secret));
    final empty = Channel(index: 3, name: '', psk: Uint8List(16));

    ChannelQrLink link({String name = '#ping', String? region}) =>
        ChannelQrLink(
          name: name,
          psk: Channel.parsePskHex(linkSecret),
          regionScope: region,
        );

    ChannelQrImport importInto(
      ChannelQrLink link,
      List<Channel> channels, {
      Map<int, String> regions = const {},
    }) => link.importInto(
      channels,
      regionOf: (index) => regions[index] ?? '',
    );

    test('a new name and a new key take a free slot', () {
      final result = importInto(link(), [
        channel(0, 'Public', otherSecret),
        empty,
      ]);
      expect(result.action, ChannelQrImportAction.add);
      expect(result.existing, isNull);
    });

    test('a name the node holds under another key is offered an update', () {
      final result = importInto(link(), [
        channel(0, 'Public', otherSecret),
        channel(2, ' #Ping ', otherSecret.replaceFirst('8b', '9c')),
      ]);
      expect(result.action, ChannelQrImportAction.update);
      expect(result.existing!.index, 2);
    });

    test('the same name and key still update when the region differs', () {
      final channels = [channel(1, '#ping', linkSecret)];
      expect(
        importInto(link(region: 'bots'), channels).action,
        ChannelQrImportAction.update,
      );
      // No region in the link clears the one the channel has.
      expect(
        importInto(link(), channels, regions: {1: 'bots'}).action,
        ChannelQrImportAction.update,
      );
    });

    test('nothing to change is a channel that is already added', () {
      final channels = [channel(1, '#ping', linkSecret)];
      expect(
        importInto(link(), channels).action,
        ChannelQrImportAction.alreadyAdded,
      );
      final withRegion = importInto(
        link(region: 'bots'),
        channels,
        regions: {1: 'bots'},
      );
      expect(withRegion.action, ChannelQrImportAction.alreadyAdded);
    });

    test('a key held under another name is never written twice', () {
      final elsewhere = importInto(link(), [channel(4, 'Pings', linkSecret)]);
      expect(elsewhere.action, ChannelQrImportAction.alreadyAdded);
      expect(elsewhere.existing!.name, 'Pings');

      // Even when the name is taken too: updating that channel would leave
      // the node with the same key in two slots.
      final both = importInto(link(), [
        channel(1, '#ping', otherSecret),
        channel(4, 'Pings', linkSecret),
      ]);
      expect(both.action, ChannelQrImportAction.alreadyAdded);
      expect(both.existing!.index, 4);
    });
  });
}
