import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/mcoimg_codec.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/notification_service.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/utils/platform_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

// What the connector promises about a message the node hands over and the
// notification it raises, pinned before the notification leaves the path
// that advances the node's queue. CMD_SYNC_NEXT_MESSAGE is destructive, the
// node drops the message it delivered, so the next request may go out only
// once the delivered message is in the history (the iOS sync fix, 806c51fe).
// A live message raises one notification with the contact's or channel's
// name, the text and the payload the tap handler opens, and an MCOimg
// message's notification carries the picture. The real service runs here
// over a mocked plugin channel: in a test defaultTargetPlatform is Android,
// the Android plugin is registered by hand since no registrant runs here,
// and it talks to `dexterous.com/flutter/local_notifications`, which
// answers as a phone with notifications allowed would. The history goes into
// an in-memory database, so the tests are skipped on a host that cannot
// load a native sqlite3.

const int _timestamp = 1700000000;

Uint8List _key(int first) => Uint8List.fromList(
  List<int>.generate(32, (i) => i == 0 ? first : (i * 7 + first) & 0xFF),
);

Uint8List _psk(int seed) =>
    Uint8List.fromList(List<int>.generate(16, (i) => (i * 7 + seed) & 0xFF));

/// RESP_CODE_SELF_INFO: the node's type, TX power, key, position, flags,
/// radio parameters and name.
Uint8List _selfInfoFrame(Uint8List key, String name) {
  final data = ByteData(58);
  final header = data.buffer.asUint8List();
  header[0] = respCodeSelfInfo;
  header[1] = advTypeChat;
  header[2] = 20; // tx power
  header[3] = 22; // max tx power
  header.setRange(4, 36, key);
  data.setInt32(36, 55700000, Endian.little);
  data.setInt32(40, 37600000, Endian.little);
  data.setUint32(48, 869525000, Endian.little);
  data.setUint32(52, 250000, Endian.little);
  header[56] = 10; // sf
  header[57] = 5; // cr
  return Uint8List.fromList([...header, ...utf8.encode(name), 0]);
}

/// RESP_CODE_CONTACT for a contact with no route.
Uint8List _contactFrame(Uint8List key, String name, {int type = advTypeChat}) {
  final data = ByteData(1 + 32 + 3 + 64 + 32 + 4 + 12);
  final bytes = data.buffer.asUint8List();
  bytes[0] = respCodeContact;
  bytes.setRange(1, 33, key);
  bytes[33] = type;
  bytes[35] = 0xFF; // path unknown
  bytes.setRange(100, 100 + name.length, name.codeUnits);
  data.setUint32(132, _timestamp, Endian.little);
  return bytes;
}

/// CONTACT_MSG_RECV_V3 as the node delivers a direct message it decrypted:
/// the SNR, two reserved bytes, the sender's six-byte prefix, the path byte
/// (0xFF: routed directly), the text type, the packet timestamp, for a room
/// post the author's four-byte prefix, then the text.
Uint8List _contactMessageFrame({
  required Uint8List senderKey,
  required int timestampSeconds,
  required String text,
  Uint8List? roomAuthorPrefix,
}) {
  final timestamp = ByteData(4)..setUint32(0, timestampSeconds, Endian.little);
  return Uint8List.fromList([
    respCodeContactMsgRecvV3,
    32, // snr * 4
    0,
    0,
    ...senderKey.sublist(0, 6),
    0xFF,
    roomAuthorPrefix == null ? txtTypePlain : txtTypeSigned,
    ...timestamp.buffer.asUint8List(),
    ...?roomAuthorPrefix,
    ...utf8.encode(text),
    0,
  ]);
}

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
}) {
  final timestamp = ByteData(4)..setUint32(0, timestampSeconds, Endian.little);
  return Uint8List.fromList([
    respCodeChannelMsgRecvV3,
    32, // snr * 4
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

/// A two-by-two MCOimg as a message text.
String _mcoImageText() {
  final image = MCOImage(
    width: 2,
    height: 2,
    paletteProfile: PaletteProfile.mono,
    pixels: const [0, 0, 0, 0],
  );
  return MCOImageCodec().encode(image, backgroundColor: 0).text;
}

/// Lets a receive path run to the end: it awaits verification, the history
/// write and the plugin's answers, all of which complete on the event queue.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 150));

Future<void> _waitFor(bool Function() condition, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

List<File> _notificationPngs(Directory directory) => directory
    .listSync()
    .whereType<File>()
    .where((file) => file.path.contains('mcoimg_notification_'))
    .toList();

Future<String?> _sqliteProblem() async {
  try {
    final database = MessageHistoryDatabase.withExecutor(
      NativeDatabase.memory(),
    );
    await database.customSelect('SELECT 1').get();
    await database.close();
    return null;
  } catch (error) {
    return 'sqlite3 is not available to this test host: $error';
  }
}

/// The notifications plugin as a phone that allows notifications: every call
/// succeeds, and what `show` was given is kept for the test to read.
class _NotificationPlugin {
  static const MethodChannel channel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );

  final List<MethodCall> shown = [];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'initialize':
            case 'areNotificationsEnabled':
              return true;
            case 'show':
              shown.add(call);
              return null;
            default:
              return null;
          }
        });
  }

  void remove() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }

  static Map<Object?, Object?> argumentsOf(MethodCall call) =>
      call.arguments as Map<Object?, Object?>;

  static Map<Object?, Object?> androidDetailsOf(MethodCall call) =>
      argumentsOf(call)['platformSpecifics'] as Map<Object?, Object?>;
}

/// A connected connector whose frames go nowhere: the node is played by the
/// test through [handleFrameForTest].
class _QueueConnector extends MeshCoreConnector {
  final List<Uint8List> sent = [];

  /// Read as each CMD_SYNC_NEXT_MESSAGE goes out: how much of the watched
  /// history is stored at that moment.
  int Function()? countStored;
  final List<int> storedAtSyncNext = [];

  @override
  bool get isConnected => true;

  @override
  Future<void> sendFrame(
    Uint8List data, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {
    sent.add(Uint8List.fromList(data));
    if (data.isNotEmpty && data[0] == cmdSyncNextMessage) {
      storedAtSyncNext.add(countStored?.call() ?? -1);
    }
  }

  int get syncRequests => storedAtSyncNext.length;
}

/// A connector past its handshake, with notifications on.
class _Harness {
  _Harness(this.connector);

  final _QueueConnector connector;

  static Future<_Harness> start({bool notifications = true}) async {
    final connector = _QueueConnector();
    final settings = AppSettingsService();
    await settings.updateSettings(
      settings.settings.copyWith(
        notificationsEnabled: notifications,
        notifyOnNewMessage: true,
        notifyOnNewChannelMessage: true,
        notifyOnNewAdvert: false,
      ),
    );
    connector.attachAppSettingsServiceForTest(settings);
    // The handshake as a connection runs it: the request marks the answer
    // as the one that binds the stores to the node.
    await connector.refreshDeviceInfo();
    connector.handleFrameForTest(_selfInfoFrame(_key(1), 'Me'));
    await _settle();
    expect(connector.selfPublicKeyHex, isNotEmpty);
    return _Harness(connector);
  }

  Future<Contact> addContact(
    Uint8List key,
    String name, {
    int type = advTypeChat,
  }) async {
    connector.handleFrameForTest(_contactFrame(key, name, type: type));
    final hex = pubKeyToHex(key);
    await _waitFor(
      () => connector.getContactByPubKeyHex(hex) != null,
      'the contact $name',
    );
    return connector.getContactByPubKeyHex(hex)!;
  }

  Future<void> addChannel(int index, String name, Uint8List psk) async {
    connector.handleFrameForTest(_channelInfoFrame(index, name, psk));
    await _waitFor(
      () => connector.channels.any((channel) => channel.index == index),
      'the channel $name',
    );
    // The channel is listed before its history is read from the database,
    // and that read replaces the list in memory; let it finish first.
    await _settle();
  }
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = await _sqliteProblem();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final tempDir = Directory.systemTemp.createTempSync('mco_queue_notify_');
  final plugin = _NotificationPlugin();
  final aliceKey = _key(2);

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => tempDir.path);
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    plugin.install();
  });

  tearDownAll(() {
    plugin.remove();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    tempDir.deleteSync(recursive: true);
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    await MessageHistoryStorage.instance.resetForTesting();
    await MessageHistoryStorage.instance.initializeAndMigrate(
      databaseFactory: () =>
          MessageHistoryDatabase.withExecutor(NativeDatabase.memory()),
    );
    NotificationService().resetForTest();
    plugin.shown.clear();
    for (final file in _notificationPngs(tempDir)) {
      file.deleteSync();
    }
  });

  tearDown(() async {
    await MessageHistoryStorage.instance.resetForTesting();
    PrefsManager.reset();
  });

  group('the node\'s queue', () {
    test('a queued direct message is in the history before the next request '
        'goes out, and the end of the queue asks for nothing more', () async {
      final harness = await _Harness.start();
      final connector = harness.connector;
      final alice = await harness.addContact(aliceKey, 'Alice');
      connector.countStored = () => connector.getLoadedMessages(alice).length;

      await connector.syncQueuedMessages();
      expect(connector.syncRequests, 1);

      connector.handleFrameForTest(
        _contactMessageFrame(
          senderKey: aliceKey,
          timestampSeconds: _timestamp,
          text: 'hello',
        ),
      );
      await _waitFor(() => connector.syncRequests == 2, 'the next request');

      expect(connector.getLoadedMessages(alice).single.text, 'hello');
      expect(
        connector.storedAtSyncNext,
        [0, 1],
        reason: 'the second request went out with the message stored',
      );
      await _waitFor(() => plugin.shown.length == 1, 'the notification');

      connector.handleFrameForTest(
        Uint8List.fromList([respCodeNoMoreMessages]),
      );
      await _settle();
      expect(connector.syncRequests, 2);

      // A message the node pushes outside a sync advances nothing.
      connector.handleFrameForTest(
        _contactMessageFrame(
          senderKey: aliceKey,
          timestampSeconds: _timestamp + 1,
          text: 'again',
        ),
      );
      await _waitFor(
        () => connector.getLoadedMessages(alice).length == 2,
        'the live message',
      );
      await _settle();
      expect(connector.syncRequests, 2);
    });

    test('a queued channel message is in the history before the next request '
        'goes out', () async {
      final harness = await _Harness.start();
      final connector = harness.connector;
      await harness.addChannel(0, 'Test', _psk(1));
      final channel = connector.channels.single;
      connector.countStored = () =>
          connector.getLoadedChannelMessages(channel).length;

      await connector.syncQueuedMessages();
      expect(connector.syncRequests, 1);

      connector.handleFrameForTest(
        _channelMessageFrame(
          channelIndex: 0,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      await _waitFor(() => connector.syncRequests == 2, 'the next request');

      expect(connector.getLoadedChannelMessages(channel).single.text, 'hello');
      expect(connector.storedAtSyncNext, [0, 1]);
      await _waitFor(() => plugin.shown.length == 1, 'the notification');

      connector.handleFrameForTest(
        Uint8List.fromList([respCodeNoMoreMessages]),
      );
      await _settle();
      expect(connector.syncRequests, 2);
    });
  }, skip: skip);

  group('what a notification says', () {
    test('a direct message names the contact, quotes the text and opens '
        'the chat', () async {
      final harness = await _Harness.start();
      await harness.addContact(aliceKey, 'Alice');

      harness.connector.handleFrameForTest(
        _contactMessageFrame(
          senderKey: aliceKey,
          timestampSeconds: _timestamp,
          text: 'hello',
        ),
      );
      await _waitFor(() => plugin.shown.length == 1, 'the notification');

      final arguments = _NotificationPlugin.argumentsOf(plugin.shown.single);
      expect(arguments['title'], 'Alice');
      expect(arguments['body'], 'hello');
      expect(arguments['payload'], 'message:${pubKeyToHex(aliceKey)}');
    });

    test('a room post names the room', () async {
      final harness = await _Harness.start();
      final roomKey = _key(3);
      await harness.addContact(roomKey, 'Room', type: advTypeRoom);

      harness.connector.handleFrameForTest(
        _contactMessageFrame(
          senderKey: roomKey,
          timestampSeconds: _timestamp,
          text: 'hello',
          roomAuthorPrefix: Uint8List.fromList([1, 2, 3, 4]),
        ),
      );
      await _waitFor(() => plugin.shown.length == 1, 'the notification');

      final arguments = _NotificationPlugin.argumentsOf(plugin.shown.single);
      expect(arguments['title'], 'Room');
      expect(arguments['body'], 'hello');
      expect(arguments['payload'], 'message:${pubKeyToHex(roomKey)}');
    });

    test('a channel message names the channel and the sender', () async {
      final harness = await _Harness.start();
      await harness.addChannel(0, 'Test', _psk(1));

      harness.connector.handleFrameForTest(
        _channelMessageFrame(
          channelIndex: 0,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      await _waitFor(() => plugin.shown.length == 1, 'the notification');

      final arguments = _NotificationPlugin.argumentsOf(plugin.shown.single);
      expect(arguments['title'], 'Test');
      expect(arguments['body'], 'Alice: hello');
      expect(arguments['payload'], 'channel:0');
    });

    test('an MCOimg message carries the picture', () async {
      final harness = await _Harness.start();
      await harness.addContact(aliceKey, 'Alice');

      harness.connector.handleFrameForTest(
        _contactMessageFrame(
          senderKey: aliceKey,
          timestampSeconds: _timestamp,
          text: _mcoImageText(),
        ),
      );
      await _waitFor(() => plugin.shown.length == 1, 'the notification');

      final call = plugin.shown.single;
      expect(_NotificationPlugin.argumentsOf(call)['body'], 'MCOimg');
      final details = _NotificationPlugin.androidDetailsOf(call);
      expect(details['style'], AndroidNotificationStyle.bigPicture.index);
      final style = details['styleInformation'] as Map<Object?, Object?>;
      expect(style['bigPicture'], isA<Uint8List>());
      expect(style['bigPicture'] as Uint8List, isNotEmpty);
      expect(details['largeIcon'] as Uint8List, isNotEmpty);

      // Apple's attachment and the Windows toast take the picture as a file
      // in the temporary directory; the host writes it as those platforms do.
      if (PlatformInfo.isWindows || PlatformInfo.isMacOS) {
        expect(_notificationPngs(tempDir), hasLength(1));
      }
    });

    test('with notifications off nothing is shown', () async {
      final harness = await _Harness.start(notifications: false);
      final alice = await harness.addContact(aliceKey, 'Alice');

      harness.connector.handleFrameForTest(
        _contactMessageFrame(
          senderKey: aliceKey,
          timestampSeconds: _timestamp,
          text: 'hello',
        ),
      );
      await _waitFor(
        () => harness.connector.getLoadedMessages(alice).length == 1,
        'the message',
      );
      await _settle();

      expect(plugin.shown, isEmpty);
    });
  }, skip: skip);
}
