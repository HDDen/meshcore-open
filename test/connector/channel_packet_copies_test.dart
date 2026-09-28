import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/channel_echo_recovery.dart';
import 'package:meshcore_open/helpers/reaction_helper.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// What the connector promises about the copies of one channel packet, pinned
// before the copies stop going through the whole receive path. The firmware
// logs every packet its radio hears before it processes it, so a packet the
// node delivers as a frame reaches the app twice, as the RX-log copy and as
// the frame, and every repeater's retransmission adds one more RX-log copy.
// One packet must stay one message whichever copy comes first, a relayed
// copy must add its route and count a repeat, a copy must never count as
// unread, a reaction must apply once, and what only looks alike (another
// packet timestamp, another channel) must stay apart.

const int _groupTextPayloadType = 0x05;
const int _routeFlood = 0x01;
const int _timestamp = 1700000000;

Uint8List _psk(int seed) =>
    Uint8List.fromList(List<int>.generate(16, (i) => (i * 7 + seed) & 0xFF));

/// The one-byte channel hash the packet carries in front of the ciphertext.
int _channelHash(Uint8List psk) => crypto.sha256.convert(psk).bytes[0];

/// RESP_CODE_CHANNEL_INFO: the index, a 32-byte name, a 16-byte PSK.
Uint8List _channelInfoFrame(int index, String name, Uint8List psk) {
  final frame = Uint8List(50);
  frame[0] = respCodeChannelInfo;
  frame[1] = index;
  frame.setRange(2, 2 + name.length, name.codeUnits);
  frame.setRange(34, 50, psk);
  return frame;
}

/// CHANNEL_MSG_RECV_V3 as the node delivers a packet it decrypted itself:
/// the SNR, the flags, a reserved byte, the channel, the packed path byte
/// with no hops, TXT_TYPE_PLAIN, the packet timestamp and `Name: text`.
Uint8List _channelMessageFrame({
  required int channelIndex,
  required int timestampSeconds,
  required String senderName,
  required String text,
  double snr = 8,
}) {
  final timestamp = ByteData(4)..setUint32(0, timestampSeconds, Endian.little);
  return Uint8List.fromList([
    respCodeChannelMsgRecvV3,
    (snr * 4).round(),
    0, // flags: no path bytes follow
    0, // reserved
    channelIndex,
    0, // no hops
    txtTypePlain,
    ...timestamp.buffer.asUint8List(),
    ...utf8.encode('$senderName: $text'),
    0,
  ]);
}

/// PUSH_CODE_LOG_RX_DATA carrying a GRP_TXT packet as the radio heard it: the
/// reading, the packet header (flood route), the packed path byte and the
/// hops, then the channel hash and the encrypted `timestamp + type + Name:
/// text`, which every copy of one packet carries byte for byte.
Uint8List _rxLogTextFrame({
  required Uint8List psk,
  required int timestampSeconds,
  required String senderName,
  required String text,
  List<List<int>> hops = const [],
  int hashWidth = 1,
  double snr = 8,
  int rssi = -70,
}) {
  final plaintext = ChannelEchoRecovery.groupTextPlaintext(
    timestampSeconds: timestampSeconds,
    senderName: senderName,
    textBytes: Uint8List.fromList(utf8.encode(text)),
  );
  final pathLenRaw = hops.isEmpty
      ? 0
      : (((hashWidth - 1) << 6) | hops.length);
  return Uint8List.fromList([
    pushCodeLogRxData,
    (snr * 4).round(),
    rssi & 0xFF,
    (_groupTextPayloadType << 2) | _routeFlood,
    pathLenRaw,
    for (final hop in hops) ...hop,
    _channelHash(psk),
    ...ChannelEchoRecovery.encryptedPayloadFor(psk, plaintext),
  ]);
}

Uint8List _key(int first) => Uint8List.fromList(
  List<int>.generate(32, (i) => i == 0 ? first : (i * 7 + first) & 0xFF),
);

/// RESP_CODE_CONTACT for a chat contact with no route.
Uint8List _contactFrame(Uint8List key, String name) {
  final data = ByteData(1 + 32 + 3 + 64 + 32 + 4 + 12);
  final bytes = data.buffer.asUint8List();
  bytes[0] = respCodeContact;
  bytes.setRange(1, 33, key);
  bytes[33] = advTypeChat;
  bytes[35] = 0xFF; // path unknown
  bytes.setRange(100, 100 + name.length, name.codeUnits);
  data.setUint32(132, 1700000000, Endian.little);
  return bytes;
}

/// Lets the receive paths run to the end: they await verification and the
/// history write, both of which complete on the event queue here.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 150));

/// A connector with [channels] installed the way a channel sync installs
/// them, each as (index, name, PSK).
Future<MeshCoreConnector> _connectorWithChannels(
  List<(int, String, Uint8List)> channels,
) async {
  final connector = MeshCoreConnector();
  for (final (index, name, psk) in channels) {
    connector.handleFrameForTest(_channelInfoFrame(index, name, psk));
  }
  await _settle();
  expect(
    connector.channels.map((channel) => channel.index).toList(),
    channels.map((channel) => channel.$1).toList(),
  );
  return connector;
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final tempDir = Directory.systemTemp.createTempSync('mco_channel_copies_');
  final psk = _psk(1);

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => tempDir.path);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(PrefsManager.reset);

  group('one packet, one message', () {
    test('the RX-log copy and the node\'s frame of one reception make one '
        'message with one repeat', () async {
      final connector = await _connectorWithChannels([(0, 'Test', psk)]);

      // Back to back, as the radio logs the packet and the node delivers it.
      connector.handleFrameForTest(
        _rxLogTextFrame(
          psk: psk,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      connector.handleFrameForTest(
        _channelMessageFrame(
          channelIndex: 0,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      await _settle();

      final messages = connector.getLoadedChannelMessages(
        connector.channels.single,
      );
      expect(messages, hasLength(1));
      expect(messages.single.senderName, 'Alice');
      expect(messages.single.text, 'hello');
      expect(messages.single.isOutgoing, isFalse);
      expect(messages.single.repeatCount, 1);
    });

    test('the frame first and the RX-log copy after it make the same message',
        () async {
      final connector = await _connectorWithChannels([(0, 'Test', psk)]);

      connector.handleFrameForTest(
        _channelMessageFrame(
          channelIndex: 0,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      await _settle();
      connector.handleFrameForTest(
        _rxLogTextFrame(
          psk: psk,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      await _settle();

      final messages = connector.getLoadedChannelMessages(
        connector.channels.single,
      );
      expect(messages, hasLength(1));
      expect(messages.single.repeatCount, 1);
    });

    test('a relayed copy adds its route with its reading and counts a repeat',
        () async {
      final connector = await _connectorWithChannels([(0, 'Test', psk)]);

      connector.handleFrameForTest(
        _rxLogTextFrame(
          psk: psk,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
          snr: 8,
          rssi: -70,
        ),
      );
      await _settle();
      connector.handleFrameForTest(
        _rxLogTextFrame(
          psk: psk,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
          hops: const [
            [0x22],
          ],
          snr: 2.5,
          rssi: -101,
        ),
      );
      await _settle();

      final message = connector
          .getLoadedChannelMessages(connector.channels.single)
          .single;
      expect(message.repeatCount, 1);
      expect(message.pathBytes, [0x22]);
      expect(message.pathObservations, hasLength(2));
      final direct = message.pathObservations.firstWhere(
        (observation) => observation.pathBytes.isEmpty,
      );
      expect(direct.snr, 8);
      expect(direct.rssi, -70);
      final relayed = message.pathObservations.firstWhere(
        (observation) => observation.pathBytes.isNotEmpty,
      );
      expect(relayed.pathBytes, [0x22]);
      expect(relayed.snr, 2.5);
      expect(relayed.rssi, -101);
    });

    test('a second relayed copy over another route counts again', () async {
      final connector = await _connectorWithChannels([(0, 'Test', psk)]);

      connector.handleFrameForTest(
        _rxLogTextFrame(
          psk: psk,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      await _settle();
      for (final hop in const [0x22, 0x33]) {
        connector.handleFrameForTest(
          _rxLogTextFrame(
            psk: psk,
            timestampSeconds: _timestamp,
            senderName: 'Alice',
            text: 'hello',
            hops: [
              [hop],
            ],
          ),
        );
        await _settle();
      }

      final message = connector
          .getLoadedChannelMessages(connector.channels.single)
          .single;
      expect(message.repeatCount, 2);
      expect(message.pathObservations, hasLength(3));
    });

    test('a copy never counts as unread', () async {
      final connector = await _connectorWithChannels([(0, 'Test', psk)]);

      connector.handleFrameForTest(
        _rxLogTextFrame(
          psk: psk,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      await _settle();
      expect(connector.channels.single.unreadCount, 1);

      connector.handleFrameForTest(
        _channelMessageFrame(
          channelIndex: 0,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      connector.handleFrameForTest(
        _rxLogTextFrame(
          psk: psk,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
          hops: const [
            [0x22],
          ],
        ),
      );
      await _settle();

      expect(connector.channels.single.unreadCount, 1);
      expect(
        connector.getLoadedChannelMessages(connector.channels.single),
        hasLength(1),
      );
    });
  });

  group('what only looks like a copy', () {
    test('the same text under a packet timestamp outside the window is a '
        'message of its own', () async {
      final connector = await _connectorWithChannels([(0, 'Test', psk)]);

      connector.handleFrameForTest(
        _rxLogTextFrame(
          psk: psk,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      await _settle();
      connector.handleFrameForTest(
        _rxLogTextFrame(
          psk: psk,
          timestampSeconds: _timestamp + 31,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      await _settle();

      final messages = connector.getLoadedChannelMessages(
        connector.channels.single,
      );
      expect(messages, hasLength(2));
      expect(messages.map((message) => message.repeatCount), [0, 0]);
    });

    test('the same packet text in two channels stays two messages', () async {
      final other = _psk(2);
      expect(_channelHash(other), isNot(_channelHash(psk)));
      final connector = await _connectorWithChannels([
        (0, 'One', psk),
        (1, 'Two', other),
      ]);

      for (final key in [psk, other]) {
        connector.handleFrameForTest(
          _rxLogTextFrame(
            psk: key,
            timestampSeconds: _timestamp,
            senderName: 'Alice',
            text: 'hello',
          ),
        );
      }
      await _settle();

      final channels = connector.channels;
      for (final channel in channels) {
        final messages = connector.getLoadedChannelMessages(channel);
        expect(messages, hasLength(1), reason: 'channel ${channel.index}');
        expect(messages.single.repeatCount, 0);
        expect(messages.single.channelIndex, channel.index);
      }
    });
  });

  group('reactions', () {
    test('a reaction applies once however many copies arrive, and is never '
        'a message', () async {
      final connector = await _connectorWithChannels([(0, 'Test', psk)]);
      connector.handleFrameForTest(
        _rxLogTextFrame(
          psk: psk,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      await _settle();

      final emoji = ReactionHelper.reactionEmojis.first;
      final reaction = ReactionHelper.encodeReaction(
        ReactionHelper.computeReactionHash(_timestamp, 'Alice', 'hello'),
        ReactionHelper.emojiToIndex(emoji)!,
      );
      // Spaced as relays space them: the receive path marks a reaction as
      // processed only after its history write, so copies inside that write
      // are a race of their own, outside what this pins.
      for (final hops in const <List<List<int>>>[
        [],
        [
          [0x22],
        ],
        [
          [0x33],
        ],
      ]) {
        connector.handleFrameForTest(
          _rxLogTextFrame(
            psk: psk,
            timestampSeconds: _timestamp + 20,
            senderName: 'Bob',
            text: reaction,
            hops: hops,
          ),
        );
        await _settle();
      }

      final messages = connector.getLoadedChannelMessages(
        connector.channels.single,
      );
      expect(messages, hasLength(1));
      expect(messages.single.text, 'hello');
      expect(messages.single.reactions[emoji], hasLength(1));
      expect(connector.channels.single.unreadCount, 1);
    });
  });

  // The short path: a copy of a packet heard before is folded into its
  // message by the heard map, before decoding, verification and the rest of
  // the receive path. Observable through the connector's counters, the
  // contact's last-message time and what a copy of a reply keeps.
  group('the short path', () {
    test('the second and every later copy of a packet fold in without the '
        'receive path', () async {
      final connector = await _connectorWithChannels([(0, 'Test', psk)]);
      connector.handleFrameForTest(
        _rxLogTextFrame(
          psk: psk,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      await _settle();
      expect(connector.heardChannelCopiesMerged, 0);

      connector.handleFrameForTest(
        _channelMessageFrame(
          channelIndex: 0,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      await _settle();
      expect(connector.heardChannelCopiesMerged, 1);

      connector.handleFrameForTest(
        _rxLogTextFrame(
          psk: psk,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
          hops: const [
            [0x22],
          ],
          snr: 2.5,
          rssi: -101,
        ),
      );
      await _settle();
      expect(connector.heardChannelCopiesMerged, 2);

      final message = connector
          .getLoadedChannelMessages(connector.channels.single)
          .single;
      expect(message.repeatCount, 2);
      expect(message.pathBytes, [0x22]);
      expect(message.pathObservations, hasLength(2));
      expect(message.snr, 2.5);
      expect(message.rssi, -101);
    });

    test('a copy heard while the first copy is still being processed waits '
        'for it and folds in', () async {
      final connector = await _connectorWithChannels([(0, 'Test', psk)]);

      connector.handleFrameForTest(
        _rxLogTextFrame(
          psk: psk,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      connector.handleFrameForTest(
        _channelMessageFrame(
          channelIndex: 0,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      await _settle();

      final messages = connector.getLoadedChannelMessages(
        connector.channels.single,
      );
      expect(messages, hasLength(1));
      expect(messages.single.repeatCount, 1);
      expect(connector.heardChannelCopiesMerged, 1);
    });

    test('a copy of a reply keeps the text and the target the first copy '
        'resolved', () async {
      final connector = await _connectorWithChannels([(0, 'Test', psk)]);
      connector.handleFrameForTest(
        _rxLogTextFrame(
          psk: psk,
          timestampSeconds: _timestamp,
          senderName: 'Bob',
          text: 'hello world',
        ),
      );
      await _settle();
      connector.handleFrameForTest(
        _rxLogTextFrame(
          psk: psk,
          timestampSeconds: _timestamp + 5,
          senderName: 'Alice',
          text: '@[Bob] >hello\nnice',
        ),
      );
      await _settle();
      final channel = connector.channels.single;
      final reply = connector
          .getLoadedChannelMessages(channel)
          .firstWhere((message) => message.senderName == 'Alice');
      expect(reply.replyToSenderName, 'Bob');
      final textBefore = reply.text;

      connector.handleFrameForTest(
        _rxLogTextFrame(
          psk: psk,
          timestampSeconds: _timestamp + 5,
          senderName: 'Alice',
          text: '@[Bob] >hello\nnice',
          hops: const [
            [0x22],
          ],
        ),
      );
      await _settle();

      final messages = connector.getLoadedChannelMessages(channel);
      expect(messages, hasLength(2));
      final replyAfter = messages.firstWhere(
        (message) => message.senderName == 'Alice',
      );
      expect(replyAfter.text, textBefore);
      expect(replyAfter.replyToSenderName, 'Bob');
      expect(replyAfter.repeatCount, 1);
      expect(connector.heardChannelCopiesMerged, 1);
    });

    test('copies of an applied reaction are dropped before the receive path',
        () async {
      final connector = await _connectorWithChannels([(0, 'Test', psk)]);
      connector.handleFrameForTest(
        _rxLogTextFrame(
          psk: psk,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      await _settle();
      final emoji = ReactionHelper.reactionEmojis.first;
      final reaction = ReactionHelper.encodeReaction(
        ReactionHelper.computeReactionHash(_timestamp, 'Alice', 'hello'),
        ReactionHelper.emojiToIndex(emoji)!,
      );

      // Back to back: the copies wait for the first copy's outcome.
      for (final hops in const <List<List<int>>>[
        [],
        [
          [0x22],
        ],
        [
          [0x33],
        ],
      ]) {
        connector.handleFrameForTest(
          _rxLogTextFrame(
            psk: psk,
            timestampSeconds: _timestamp + 20,
            senderName: 'Bob',
            text: reaction,
            hops: hops,
          ),
        );
      }
      await _settle();

      final messages = connector.getLoadedChannelMessages(
        connector.channels.single,
      );
      expect(messages, hasLength(1));
      expect(messages.single.reactions[emoji], hasLength(1));
      expect(connector.heardChannelReactionCopiesDropped, 2);
      expect(connector.heardChannelCopiesMerged, 0);
    });

    test('a contact\'s last message time is the first copy\'s', () async {
      final connector = await _connectorWithChannels([(0, 'Test', psk)]);
      connector.handleFrameForTest(_contactFrame(_key(0x33), 'Alice'));
      await _settle();
      expect(connector.contacts.map((contact) => contact.name).toList(), [
        'Alice',
      ]);

      connector.handleFrameForTest(
        _rxLogTextFrame(
          psk: psk,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      await _settle();
      final first = connector.contacts.single.lastMessageAt;

      connector.handleFrameForTest(
        _rxLogTextFrame(
          psk: psk,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
          hops: const [
            [0x22],
          ],
        ),
      );
      await _settle();
      connector.handleFrameForTest(
        _channelMessageFrame(
          channelIndex: 0,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      await _settle();

      expect(connector.contacts.single.lastMessageAt, first);
      expect(connector.heardChannelCopiesMerged, 2);
    });

    test('a channel the do-not-filter setting lists keeps the whole path',
        () async {
      final settings = AppSettingsService();
      await settings.updateSettings(
        settings.settings.copyWith(
          notificationsEnabled: false,
          notifyOnNewChannelMessage: false,
          doNotFilterMessagesOnChannels: 'Test',
        ),
      );
      final connector = await _connectorWithChannels([(0, 'Test', psk)]);
      connector.attachAppSettingsServiceForTest(settings);

      connector.handleFrameForTest(
        _rxLogTextFrame(
          psk: psk,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      await _settle();
      connector.handleFrameForTest(
        _channelMessageFrame(
          channelIndex: 0,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      await _settle();
      connector.handleFrameForTest(
        _rxLogTextFrame(
          psk: psk,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
          hops: const [
            [0x22],
          ],
        ),
      );
      await _settle();

      final messages = connector.getLoadedChannelMessages(
        connector.channels.single,
      );
      expect(messages, hasLength(1));
      expect(messages.single.repeatCount, 2);
      expect(connector.heardChannelCopiesMerged, 0);
    });
  });
}
