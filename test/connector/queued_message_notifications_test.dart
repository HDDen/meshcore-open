import 'dart:async';
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
import 'package:meshcore_open/helpers/blocked_senders.dart';
import 'package:meshcore_open/helpers/mcoimg_codec.dart';
import 'package:meshcore_open/helpers/mcotxt_app_codec.dart';
import 'package:meshcore_open/helpers/channel_app_data_helper.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/message_filter.dart';
import 'package:meshcore_open/services/message_filter/message_filter_service.dart';
import 'package:meshcore_open/services/message_filter/ngram_spam_classifier.dart';
import 'package:meshcore_open/storage/channel_identity_store.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/notification_service.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/channel_message_store.dart';
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
// load a native sqlite3. The last group is the change: the notification is
// shown off the receive path, so the next request goes out while the plugin
// still holds the notification, and an MCOimg notification deletes the
// picture files of earlier ones after a day.

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
  final List<int> cancelledIds = [];

  /// While set, `show` records its call and completes only with this.
  Completer<void>? hold;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'initialize':
            case 'areNotificationsEnabled':
              return true;
            case 'show':
              shown.add(call);
              final pending = hold;
              if (pending != null) await pending.future;
              return null;
            case 'cancel':
              cancelledIds.add((call.arguments as Map)['id'] as int);
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
  _QueueConnector({super.messageFilterService});

  final List<Uint8List> sent = [];

  /// Read as each CMD_SYNC_NEXT_MESSAGE goes out: how much of the watched
  /// history is stored at that moment.
  int Function()? countStored;
  final List<int> storedAtSyncNext = [];
  Future<void> Function()? beforeQueueRequest;

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
      await beforeQueueRequest?.call();
      storedAtSyncNext.add(countStored?.call() ?? -1);
    }
  }

  int get syncRequests => storedAtSyncNext.length;
}

class _RecordingMessageFilter extends MessageFilterService {
  int evaluations = 0;

  @override
  FilterVerdict? evaluate({
    required String channelId,
    required String sender,
    required String text,
    DateTime? sentAt,
    DateTime? receivedAt,
    String? verifiedSenderKey,
    String? binaryPublicationKey,
    bool isAddressed = false,
  }) {
    evaluations++;
    return super.evaluate(
      channelId: channelId,
      sender: sender,
      text: text,
      sentAt: sentAt,
      receivedAt: receivedAt,
      verifiedSenderKey: verifiedSenderKey,
      binaryPublicationKey: binaryPublicationKey,
      isAddressed: isAddressed,
    );
  }
}

/// A connector past its handshake, with notifications on.
class _Harness {
  _Harness(this.connector, this.settings);

  final _QueueConnector connector;
  final AppSettingsService settings;

  static Future<_Harness> start({
    bool notifications = true,
    MessageFilterService? messageFilterService,
    int nodeSeed = 1,
  }) async {
    final connector = _QueueConnector(
      messageFilterService: messageFilterService,
    );
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
    connector.handleFrameForTest(_selfInfoFrame(_key(nodeSeed), 'Me'));
    await _settle();
    expect(connector.selfPublicKeyHex, isNotEmpty);
    return _Harness(connector, settings);
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
  late MessageHistoryDatabase historyDatabase;

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
      databaseFactory: () => historyDatabase =
          MessageHistoryDatabase.withExecutor(NativeDatabase.memory()),
    );
    ChannelIdentities.instance.resetForTesting();
    await ChannelIdentities.instance.load();
    NotificationService().resetForTest();
    plugin.shown.clear();
    plugin.cancelledIds.clear();
    plugin.hold = null;
    for (final file in _notificationPngs(tempDir)) {
      file.deleteSync();
    }
  });

  tearDown(() async {
    ChannelIdentities.instance.resetForTesting();
    await MessageHistoryStorage.instance.resetForTesting();
    PrefsManager.reset();
  });

  group('the node\'s queue', () {
    Future<void> waitForInboxEmpty(String nodeKey) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while ((await MessageHistoryStorage.instance.readPendingChannelFrames(nodeKey)).isNotEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          fail('retained channel inbox did not finish');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('a failed inbox commit stops the destructive queue', () async {
      final harness = await _Harness.start(notifications: false);
      final connector = harness.connector;
      addTearDown(connector.dispose);
      await historyDatabase.customStatement(
        "CREATE TRIGGER reject_pending BEFORE INSERT ON pending_channel_frames "
        "BEGIN SELECT RAISE(ABORT, 'synthetic inbox failure'); END",
      );
      await connector.syncQueuedMessages();
      expect(connector.syncRequests, 1);
      connector.handleFrameForTest(_channelMessageFrame(
        channelIndex: 2, timestampSeconds: _timestamp,
        senderName: 'Alice', text: 'cannot retain',
      ));
      await _waitFor(() => !connector.isSyncingQueuedMessages, 'the failed queue to stop');
      expect(connector.syncRequests, 1);
      expect(await MessageHistoryStorage.instance.readPendingChannelFrames(connector.selfPublicKeyHex), isEmpty);
    });

    for (final format in ['legacy text', 'binary MCOtxt']) {
      test('$format is retained and replayed through its original parser', () async {
        final harness = await _Harness.start(notifications: false);
        final connector = harness.connector;
        addTearDown(connector.dispose);
        final Uint8List frame;
        if (format == 'legacy text') {
          final time = ByteData(4)..setUint32(0, _timestamp, Endian.little);
          frame = Uint8List.fromList([
            respCodeChannelMsgRecv, 2, 0xFF, txtTypePlain,
            ...time.buffer.asUint8List(), ...utf8.encode('Alice: retained text'), 0,
          ]);
        } else {
          final body = MCOtxtAppCodec.encodeBody(text: 'retained text', timestamp: _timestamp);
          final payload = ChannelAppDataHelper.encodeEnvelope(
            senderName: 'Alice', subtypeId: MCOtxtAppCodec.subtypeId,
            version: MCOtxtAppCodec.wireVersion, body: body,
          );
          final type = ChannelAppDataHelper.appDataType;
          frame = Uint8List.fromList([
            respCodeChannelDataRecv, 32, 0, 0, 2, 0xFF,
            type & 0xFF, type >> 8, payload.length, ...payload,
          ]);
        }
        await connector.syncQueuedMessages();
        connector.handleFrameForTest(frame);
        await _waitFor(() => connector.syncRequests == 2, 'the next request');
        connector.handleFrameForTest(Uint8List.fromList([respCodeNoMoreMessages]));
        expect(await MessageHistoryStorage.instance.readPendingChannelFrames(connector.selfPublicKeyHex), hasLength(1));
        await harness.addChannel(2, 'Recovered', _psk(1));
        await waitForInboxEmpty(connector.selfPublicKeyHex);
        final channel = connector.channels.singleWhere((channel) => channel.index == 2);
        expect(connector.getLoadedChannelMessages(channel).single.text, 'retained text');
      });
    }

    test('unknown channel is on disk before the next destructive request and replays once', () async {
      final harness = await _Harness.start(notifications: false);
      final connector = harness.connector;
      addTearDown(connector.dispose);
      final scope = connector.selfPublicKeyHex;
      final pendingAtRequest = <int>[];
      connector.beforeQueueRequest = () async {
        pendingAtRequest.add(
          (await MessageHistoryStorage.instance.readPendingChannelFrames(scope)).length,
        );
      };
      await connector.syncQueuedMessages();
      final frame = _channelMessageFrame(
        channelIndex: 2, timestampSeconds: _timestamp,
        senderName: 'Alice', text: 'retained text',
      );
      connector.handleFrameForTest(frame);
      await _waitFor(() => connector.syncRequests == 2, 'the next request after retention');
      expect(pendingAtRequest, [0, 1]);
      final retained = (await MessageHistoryStorage.instance.readPendingChannelFrames(scope)).single;
      expect(retained.frame, orderedEquals(frame));
      expect(connector.sent.where((frame) => frame.first == cmdGetChannel && frame[1] == 2), hasLength(1));
      connector.handleFrameForTest(Uint8List.fromList([respCodeNoMoreMessages]));

      await harness.addChannel(2, 'Recovered', _psk(1));
      await waitForInboxEmpty(scope);
      final channel = connector.channels.singleWhere((channel) => channel.index == 2);
      final loaded = connector.getLoadedChannelMessages(channel);
      expect(loaded.single.text, 'retained text');
      expect(loaded.single.receivedAt.millisecondsSinceEpoch, retained.receivedAt.millisecondsSinceEpoch);
      final history = ChannelMessageStore()..setPublicKeyHex = scope;
      history.registerChannel(channel);
      expect((await history.loadChannelMessages(2)).single.text, 'retained text');

      // Ordinary repeated delivery follows existing deduplication, not a second row.
      connector.handleFrameForTest(frame);
      await _settle();
      expect(await history.loadChannelMessages(2), hasLength(1));
      expect(plugin.shown, isEmpty);
    });

    test('a replacement connector recovers an unresolved channel from the same node', () async {
      final first = await _Harness.start(notifications: false);
      final scope = first.connector.selfPublicKeyHex;
      try {
        await first.connector.syncQueuedMessages();
        first.connector.handleFrameForTest(_channelMessageFrame(
          channelIndex: 2, timestampSeconds: _timestamp,
          senderName: 'Alice', text: 'survives reconnect',
        ));
        await _waitFor(() => first.connector.syncRequests == 2, 'the retained frame');
        first.connector.handleFrameForTest(Uint8List.fromList([respCodeNoMoreMessages]));
        await _settle();
      } finally {
        first.connector.dispose();
      }
      final restored = await _Harness.start(notifications: false);
      addTearDown(restored.connector.dispose);
      expect(await MessageHistoryStorage.instance.readPendingChannelFrames(scope), hasLength(1));
      await restored.addChannel(2, 'Recovered', _psk(1));
      await waitForInboxEmpty(scope);
      final channel = restored.connector.channels.singleWhere((channel) => channel.index == 2);
      expect(restored.connector.getLoadedChannelMessages(channel).single.text, 'survives reconnect');
    });

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

    test(
      'U27 baseline: a blocked post is committed before the next queue request',
      () async {
        final harness = await _Harness.start();
        final connector = harness.connector;
        addTearDown(harness.settings.dispose);
        addTearDown(connector.dispose);
        await harness.addChannel(0, 'Test', _psk(1));

        final history = ChannelMessageStore()
          ..setPublicKeyHex = connector.selfPublicKeyHex
          ..registerChannel(connector.channels.single);
        final blocked = BlockedSenders.instance;
        await blocked.blockName('Alice');
        try {
          final blockedAtRequest = <bool?>[];
          connector.beforeQueueRequest = () async {
            final page = await history.loadLatestChannelMessages(0, limit: 1);
            blockedAtRequest.add(page.isEmpty ? null : page.single.wasBlocked);
          };
          await connector.syncQueuedMessages();
          connector.handleFrameForTest(
            _channelMessageFrame(
              channelIndex: 0,
              timestampSeconds: _timestamp,
              senderName: 'Alice',
              text: 'blocked post',
            ),
          );
          await _waitFor(
            () => connector.syncRequests == 2,
            'the request after the blocked post was committed',
          );
          connector.handleFrameForTest(
            Uint8List.fromList([respCodeNoMoreMessages]),
          );
          await _settle();

          expect(blockedAtRequest, [null, true]);
          expect(connector.getUnreadCountForChannelIndex(0), 0);
          expect(plugin.shown, isEmpty);
          await blocked.unblock('Alice');
          final stored = (await history.loadChannelMessages(0)).single;
          expect(stored.text, 'blocked post');
          expect(stored.wasBlocked, isTrue);
        } finally {
          await blocked.unblock('Alice');
        }
      },
    );

    test('U27: a filtered queued post is persisted once without an alert', () async {
      final filter = _RecordingMessageFilter();
      addTearDown(filter.dispose);
      await filter.updateSettings(const MessageFilterSettings(enabled: true));
      await filter.replaceRules(const [
        FilterRule(id: 'ad', pattern: 'bonus', match: FilterRuleMatch.wholeWord),
      ]);
      final harness = await _Harness.start(messageFilterService: filter);
      final connector = harness.connector;
      addTearDown(harness.settings.dispose);
      addTearDown(connector.dispose);
      await harness.addChannel(0, 'Test', _psk(1));

      final history = ChannelMessageStore()
        ..setPublicKeyHex = connector.selfPublicKeyHex
        ..registerChannel(connector.channels.single);
      final filteredAtRequest = <bool?>[];
      connector.beforeQueueRequest = () async {
        final page = await history.loadLatestChannelMessages(0, limit: 1);
        filteredAtRequest.add(page.isEmpty ? null : page.single.isFiltered);
      };
      final frame = _channelMessageFrame(
        channelIndex: 0,
        timestampSeconds: _timestamp,
        senderName: 'Alice',
        text: 'Win a bonus',
      );
      await connector.syncQueuedMessages();
      connector.handleFrameForTest(frame);
      await _waitFor(() => connector.syncRequests == 2, 'the next request');
      connector.handleFrameForTest(Uint8List.fromList([respCodeNoMoreMessages]));
      await _settle();

      expect(filteredAtRequest, [null, true]);
      expect(connector.getUnreadCountForChannelIndex(0), 0);
      expect(plugin.shown, isEmpty);
      expect(filter.evaluations, 1);
      final first = (await history.loadChannelMessages(0)).single;
      expect(first.text, 'Win a bonus');
      expect(first.wasBlocked, isFalse);
      expect(
        first.filterVerdict,
        const FilterVerdict(reason: FilterReason.textRule, detail: 'bonus'),
      );

      await filter.replaceRules(const [
        FilterRule(id: 'new', pattern: 'different rule'),
      ]);
      connector.handleFrameForTest(frame);
      await _settle();
      final replayed = (await history.loadChannelMessages(0)).single;
      expect(replayed.messageId, first.messageId);
      expect(replayed.filterVerdict, first.filterVerdict);
      expect(filter.evaluations, 1);
      expect(connector.getUnreadCountForChannelIndex(0), 0);
      expect(plugin.shown, isEmpty);
    });
  }, skip: skip);

  test('U27d: manual spam feedback can filter a later channel post', () async {
    final filter = MessageFilterService(
      trainer: (_) async => const SpamModel({}, 8),
    );
    addTearDown(filter.dispose);
    await filter.updateSettings(
      const MessageFilterSettings(enabled: true, learning: true),
    );
    final harness = await _Harness.start(messageFilterService: filter);
    final connector = harness.connector;
    addTearDown(harness.settings.dispose);
    addTearDown(connector.dispose);
    await harness.addChannel(0, 'Test', _psk(1));
    final channel = connector.channels.single;
    final history = ChannelMessageStore()
      ..setPublicKeyHex = connector.selfPublicKeyHex
      ..registerChannel(channel);

    const texts = ['buy cheap radios', 'claim a free prize', 'weather is nice'];
    for (final (i, text) in texts.indexed) {
      connector.handleFrameForTest(_channelMessageFrame(
        channelIndex: channel.index,
        timestampSeconds: _timestamp + i * 10,
        senderName: 'Alice',
        text: text,
      ));
      await _waitFor(() => plugin.shown.length == i + 1, 'initial notification');
    }
    final initial = await history.loadChannelMessages(channel.index);
    for (final message in initial.take(2)) {
      expect(
        await connector.setChannelMessageFilterVerdict(
          channel,
          message,
          const FilterVerdict(reason: FilterReason.manual),
        ),
        isTrue,
      );
    }

    await _waitFor(
      () => filter.evaluate(
        channelId: channel.storageId!,
        sender: 'Alice',
        text: 'another spam post',
      )?.reason == FilterReason.learned,
      'the learned model',
    );
    final unreadBefore = connector.getUnreadCountForChannelIndex(channel.index);
    connector.handleFrameForTest(_channelMessageFrame(
      channelIndex: channel.index,
      timestampSeconds: _timestamp + 30,
      senderName: 'Alice',
      text: 'another spam post',
    ));
    await _settle();

    final saved = await history.loadChannelMessages(channel.index);
    expect(saved, hasLength(4));
    expect(saved.last.filterVerdict?.reason, FilterReason.learned);
    expect(saved.last.text, 'another spam post');
    expect(connector.getUnreadCountForChannelIndex(channel.index), unreadBefore);
    expect(plugin.shown, hasLength(3));
  }, skip: skip);

  test('U27c: a second publication is hidden but a packet copy stays merged', () async {
    final filter = _RecordingMessageFilter();
    addTearDown(filter.dispose);
    await filter.updateSettings(
      const MessageFilterSettings(enabled: true, duplicates: true),
    );
    final harness = await _Harness.start(messageFilterService: filter);
    final connector = harness.connector;
    addTearDown(harness.settings.dispose);
    addTearDown(connector.dispose);
    await harness.addChannel(0, 'Test', _psk(1));
    final channel = connector.channels.single;
    final history = ChannelMessageStore()
      ..setPublicKeyHex = connector.selfPublicKeyHex
      ..registerChannel(channel);
    const text = 'Anyone on the hill repeater?';
    Uint8List publication(int timestampSeconds) => _channelMessageFrame(
      channelIndex: 0,
      timestampSeconds: timestampSeconds,
      senderName: 'Alice',
      text: text,
    );

    connector.handleFrameForTest(publication(_timestamp));
    await _settle();
    connector.handleFrameForTest(publication(_timestamp));
    await _settle();
    expect((await history.loadChannelMessages(0)).single.isFiltered, isFalse);
    expect(filter.evaluations, 1);
    expect(connector.getUnreadCountForChannelIndex(0), 1);
    expect(plugin.shown, hasLength(1));

    connector.handleFrameForTest(publication(_timestamp + 10));
    await _settle();
    final messages = await history.loadChannelMessages(0);
    expect(messages, hasLength(2));
    expect(messages.first.isFiltered, isFalse);
    expect(messages.last.filterVerdict?.reason, FilterReason.duplicate);
    expect(messages.last.text, text);
    expect(filter.evaluations, 2);
    expect(connector.getUnreadCountForChannelIndex(0), 1);
    expect(plugin.shown, hasLength(1));
  }, skip: skip);

  test('U33: a replay from another radio slot is not a new publication',
      () async {
    final filter = MessageFilterService();
    addTearDown(filter.dispose);
    await filter.updateSettings(
      const MessageFilterSettings(enabled: true, duplicates: true),
    );

    const text = 'Anyone on the hill repeater?';
    Future<List<ChannelMessage>> receive(
      int nodeSeed,
      int slot,
      List<int> timestamps,
    ) async {
      final harness = await _Harness.start(
        notifications: false,
        messageFilterService: filter,
        nodeSeed: nodeSeed,
      );
      final connector = harness.connector;
      addTearDown(harness.settings.dispose);
      addTearDown(connector.dispose);
      await harness.addChannel(slot, 'Test', _psk(1));
      final history = ChannelMessageStore()
        ..setPublicKeyHex = connector.selfPublicKeyHex
        ..registerChannel(connector.channels.single);
      for (final timestamp in timestamps) {
        connector.handleFrameForTest(_channelMessageFrame(
          channelIndex: slot,
          timestampSeconds: timestamp,
          senderName: 'Alice',
          text: text,
        ));
        await _settle();
      }
      return history.loadChannelMessages(slot);
    }

    final original = await receive(1, 0, [_timestamp]);
    expect(original.single.filterVerdict, isNull);
    final replayAndResend = await receive(8, 3, [_timestamp, _timestamp + 10]);
    expect(replayAndResend, hasLength(2));
    expect(replayAndResend.first.filterVerdict, isNull);
    expect(replayAndResend.last.filterVerdict?.reason, FilterReason.duplicate);
  }, skip: skip);

  test('U33: replies and plain mentions of our node remain visible', () async {
    final filter = MessageFilterService();
    addTearDown(filter.dispose);
    await filter.updateSettings(
      const MessageFilterSettings(enabled: true, duplicates: true),
    );
    final harness = await _Harness.start(
      notifications: false,
      messageFilterService: filter,
    );
    final connector = harness.connector;
    addTearDown(harness.settings.dispose);
    addTearDown(connector.dispose);
    await harness.addChannel(0, 'Test', _psk(1));
    final history = ChannelMessageStore()
      ..setPublicKeyHex = connector.selfPublicKeyHex
      ..registerChannel(connector.channels.single);

    const text = 'Anyone on the hill repeater?';
    final texts = [
      '@[Me] $text',
      '@[Other] $text',
      '$text @Me',
      '$text @Me',
      text,
      text,
    ];
    for (final (index, body) in texts.indexed) {
      connector.handleFrameForTest(_channelMessageFrame(
        channelIndex: 0,
        timestampSeconds: _timestamp + index * 10,
        senderName: 'Alice',
        text: body,
      ));
      await _settle();
    }

    final saved = await history.loadChannelMessages(0);
    expect(saved, hasLength(texts.length));
    expect(saved.first.replyToSenderName, 'Me');
    expect(saved.take(5).every((message) => !message.isFiltered), isTrue);
    expect(saved.last.filterVerdict?.reason, FilterReason.duplicate);
  }, skip: skip);

  test('U27b: hiding a page keeps its SQL cursor and the preview', () async {
    final filter = MessageFilterService();
    addTearDown(filter.dispose);
    await filter.updateSettings(
      const MessageFilterSettings(enabled: true, hideFiltered: true),
    );
    final harness = await _Harness.start(messageFilterService: filter);
    final connector = harness.connector;
    addTearDown(harness.settings.dispose);
    addTearDown(connector.dispose);
    await harness.addChannel(0, 'Test', _psk(1));
    final channel = connector.channels.single;
    final history = ChannelMessageStore()
      ..setPublicKeyHex = connector.selfPublicKeyHex
      ..registerChannel(channel);
    final time = DateTime.utc(2026, 1, 1);
    final older = ChannelMessage(
      channelIndex: channel.index,
      messageId: 'older',
      senderName: 'Alice',
      text: 'normal conversation',
      timestamp: time,
      receivedAt: time,
      isOutgoing: false,
    );
    const verdict = FilterVerdict(reason: FilterReason.manual);
    final newest = ChannelMessage(
      channelIndex: channel.index,
      messageId: 'newest',
      senderName: 'Bob',
      text: 'filtered body',
      timestamp: time.add(const Duration(seconds: 1)),
      receivedAt: time.add(const Duration(seconds: 1)),
      isOutgoing: false,
      filterVerdict: verdict,
    );
    await history.saveChannelMessages(channel.index, [older, newest]);
    connector.setChannelMessagesForTest(channel.index, [newest]);

    expect(connector.getChannelMessageTimeline(channel), isEmpty);
    expect(connector.getChannelMergedMessages(channel).single.messageId, 'newest');
    expect(connector.latestChannelPreviewMessage(channel), isNull);

    final page = await connector.loadOlderChannelMessages(channel.index, count: 1);
    expect(page.single.messageId, 'older');
    expect(connector.getChannelMessageTimeline(channel).single.messageId, 'older');
    expect(connector.latestChannelPreviewMessage(channel)?.messageId, 'older');

    await filter.updateSettings(
      filter.settings.copyWith(excludedChannelIds: {channel.storageId!}),
    );
    expect(connector.getChannelMessageTimeline(channel), hasLength(2));
    expect(connector.latestChannelPreviewMessage(channel)?.messageId, 'newest');
    await filter.updateSettings(
      filter.settings.copyWith(excludedChannelIds: const {}),
    );
    expect(connector.getChannelMessageTimeline(channel), hasLength(1));

    expect(
      await connector.setChannelMessageFilterVerdict(channel, newest, null),
      isTrue,
    );
    expect(connector.getChannelMessageTimeline(channel), hasLength(2));
    expect(
      await connector.setChannelMessageFilterVerdict(channel, newest, verdict),
      isTrue,
    );
    final saved = await history.loadChannelMessages(channel.index);
    expect(saved.map((message) => message.messageId), ['older', 'newest']);
    expect(saved.first.text, older.text);
    expect(saved.last.text, newest.text);
    expect(saved.last.filterVerdict, verdict);
    expect(saved.last.wasBlocked, isFalse);
  }, skip: skip);

  test('U34 baseline: only inactive conversations count new posts as unread', () async {
    final harness = await _Harness.start(notifications: false);
    final connector = harness.connector;
    addTearDown(harness.settings.dispose);
    addTearDown(connector.dispose);
    final contact = await harness.addContact(aliceKey, 'Alice');
    await harness.addChannel(0, 'Test', _psk(1));
    final channel = connector.channels.single;
    await connector.loadUnreadState();

    Future<void> receive(int number) async {
      connector.handleFrameForTest(_contactMessageFrame(
        senderKey: aliceKey,
        timestampSeconds: _timestamp + number,
        text: 'Direct post $number',
      ));
      connector.handleFrameForTest(_channelMessageFrame(
        channelIndex: channel.index,
        timestampSeconds: _timestamp + number,
        senderName: 'Alice',
        text: 'Channel post $number',
      ));
      await _waitFor(() =>
          connector.getLoadedMessages(contact).length == number &&
          connector.getLoadedChannelMessages(channel).length == number,
        'both incoming posts');
    }

    connector.setActiveContact(contact.publicKeyHex);
    connector.setActiveChannel(channel.index);
    await _settle();
    await receive(1);
    expect(connector.getUnreadCountForContact(contact), 0);
    expect(connector.getUnreadCountForChannel(channel), 0);

    connector.setActiveContact(null);
    connector.setActiveChannel(null);
    await receive(2);
    expect(connector.getUnreadCountForContact(contact), 1);
    expect(connector.getUnreadCountForChannel(channel), 1);

    connector.setActiveContact(contact.publicKeyHex);
    connector.setActiveChannel(channel.index);
    expect(connector.getUnreadCountForContact(contact), 0);
    expect(connector.getUnreadCountForChannel(channel), 0);
  }, skip: skip);

  test('U34: covered chat routes count incoming posts until the user returns', () async {
    final harness = await _Harness.start(notifications: false);
    final connector = harness.connector;
    addTearDown(harness.settings.dispose);
    addTearDown(connector.dispose);
    final contact = await harness.addContact(aliceKey, 'Alice');
    await harness.addChannel(0, 'Test', _psk(1));
    final channel = connector.channels.single;
    await connector.loadUnreadState();

    var visible = true;
    addTearDown(connector.trackContactChatRoute(contact.publicKeyHex, () => visible));
    addTearDown(connector.trackChannelChatRoute(channel.index, () => visible));
    connector.setActiveContact(contact.publicKeyHex);
    connector.setActiveChannel(channel.index);
    await _settle();

    visible = false;
    connector.handleFrameForTest(_contactMessageFrame(
      senderKey: aliceKey,
      timestampSeconds: _timestamp,
      text: 'Direct post while covered',
    ));
    connector.handleFrameForTest(_channelMessageFrame(
      channelIndex: channel.index,
      timestampSeconds: _timestamp,
      senderName: 'Alice',
      text: 'Channel post while covered',
    ));
    await _waitFor(() =>
        connector.getLoadedMessages(contact).isNotEmpty &&
        connector.getLoadedChannelMessages(channel).isNotEmpty,
      'both covered conversations');
    expect(connector.getUnreadCountForContact(contact), 1);
    expect(connector.getUnreadCountForChannel(channel), 1);

    visible = true;
    connector.setActiveContact(contact.publicKeyHex);
    connector.setActiveChannel(channel.index);
    expect(connector.getUnreadCountForContact(contact), 0);
    expect(connector.getUnreadCountForChannel(channel), 0);
  }, skip: skip);

  test('U34: bulk delete resolves projected rows and preserves unloaded history', () async {
    final harness = await _Harness.start();
    final connector = harness.connector;
    addTearDown(harness.settings.dispose);
    addTearDown(connector.dispose);
    await harness.addChannel(0, 'Test', _psk(1));
    final channel = connector.channels.single;
    final history = ChannelMessageStore()
      ..setPublicKeyHex = connector.selfPublicKeyHex
      ..registerChannel(channel);
    final other = ChannelMessageStore()
      ..setPublicKeyHex = List.filled(32, 'ee').join()
      ..registerChannel(channel);
    ChannelMessage post(String id, int second) {
      final time = DateTime.utc(2026, 1, 1, 0, 0, second);
      return ChannelMessage(
        channelIndex: channel.index,
        messageId: id,
        senderName: 'Alice',
        text: 'Post $id',
        timestamp: time,
        receivedAt: time,
        isOutgoing: false,
      );
    }

    final older = post('older', 0);
    final first = post('first', 1);
    final second = post('second', 2);
    final shared = post('shared', 3);
    await history.saveChannelMessages(channel.index, [older, first, second]);
    await other.saveChannelMessages(channel.index, [first, shared]);
    connector.setChannelMessagesForTest(channel.index, [first, second]);
    connector.scheduleChannelMessage(
      channel,
      'Delayed post',
      inputText: 'Delayed post',
      delaySeconds: 120,
      region: '',
    );
    final pending = connector.getPendingChannelMessages(channel.index).single;

    final deleted = await connector.deleteSelectedChannelMessages(channel, [
      first,
      second.copyWith(filterVerdict: const FilterVerdict(reason: FilterReason.textRule)),
      shared.copyWith(sharedHistorySourceName: 'Another node'),
      pending,
    ]);
    expect(deleted, isTrue);
    expect(connector.getLoadedChannelMessages(channel), isEmpty);
    expect(connector.getPendingChannelMessages(channel.index), isEmpty);
    expect(connector.pendingChannelSendAt(pending.messageId), isNull);
    expect((await history.loadChannelMessages(channel.index)).single.messageId, 'older');
    expect(
      (await other.loadChannelMessages(channel.index)).map((message) => message.messageId),
      ['first', 'shared'],
    );
  }, skip: skip);

  test('U27e: current rules project immediately and persist after flush', () async {
    final filter = MessageFilterService();
    addTearDown(filter.dispose);
    await filter.updateSettings(
      const MessageFilterSettings(enabled: true, hideFiltered: true),
    );
    final harness = await _Harness.start(messageFilterService: filter);
    final connector = harness.connector;
    addTearDown(harness.settings.dispose);
    addTearDown(connector.dispose);
    await harness.addChannel(0, 'Test', _psk(1));
    final channel = connector.channels.single;
    final history = ChannelMessageStore()
      ..setPublicKeyHex = connector.selfPublicKeyHex
      ..registerChannel(channel);
    final time = DateTime.utc(2026, 1, 1);
    ChannelMessage post(String id, int seconds, {FilterVerdict? verdict}) {
      final at = time.add(Duration(seconds: seconds));
      return ChannelMessage(
        channelIndex: channel.index,
        messageId: id,
        senderName: 'Alice',
        text: 'buy this now',
        timestamp: at,
        receivedAt: at,
        isOutgoing: false,
        filterVerdict: verdict,
      );
    }

    const manual = FilterVerdict(reason: FilterReason.manual);
    final older = post('older', 0);
    final marked = post('manual', 1, verdict: manual);
    final newest = post('newest', 2);
    await history.saveChannelMessages(channel.index, [older, marked, newest]);
    connector.setChannelMessagesForTest(channel.index, [marked, newest]);

    List<String> visibleIds() => connector
        .getChannelMessageTimeline(channel)
        .map((message) => message.messageId)
        .toList();

    expect(visibleIds(), ['newest']);
    expect(
      (await history.loadChannelMessages(channel.index))
          .map((message) => message.filterVerdict),
      [null, manual, null],
    );

    const rules = [FilterRule(id: 'sales', pattern: 'buy this')];
    await filter.replaceRules(rules);
    expect(visibleIds(), isEmpty);
    expect(connector.latestChannelPreviewMessage(channel), isNull);

    final page = await connector.loadOlderChannelMessages(
      channel.index,
      count: 1,
    );
    expect(page.map((message) => message.messageId), [older.messageId]);
    expect(visibleIds(), isEmpty);
    expect(
      connector.getChannelMergedMessages(channel).first.filterVerdict?.reason,
      FilterReason.textRule,
    );

    await connector.flushChannelRuleVerdicts();
    const sales = FilterVerdict(reason: FilterReason.textRule, detail: 'buy this');
    final persisted = await history.loadChannelMessages(channel.index);
    expect(
      persisted.map((message) => message.filterVerdict),
      [sales, manual, sales],
    );
    expect(
      persisted.map((message) => message.text),
      everyElement('buy this now'),
    );
    expect(visibleIds(), isEmpty);

    final reviewed = connector.getLoadedFilteredChannelMessages(channel).first;
    expect(reviewed.messageId, newest.messageId);
    expect(
      await connector.setChannelMessageFilterVerdict(channel, reviewed, null),
      isTrue,
    );
    expect(visibleIds(), ['newest']);
    final restored = await history.loadChannelMessages(channel.index);
    expect(restored.last.filterRestored, isTrue);
    connector.setChannelMessagesForTest(channel.index, restored);
    expect(visibleIds(), ['newest']);
    expect(connector.latestChannelPreviewMessage(channel)?.messageId, 'newest');

    await filter.replaceRules(const []);
    expect(visibleIds(), ['older', 'newest']);
    await connector.flushChannelRuleVerdicts();
    final afterRemoval = await history.loadChannelMessages(channel.index);
    expect(
      afterRemoval.map((message) => message.filterVerdict),
      [null, manual, null],
    );
    expect(afterRemoval.last.filterRestored, isTrue);
    expect(
      connector.getLoadedFilteredChannelMessages(channel).single.filterVerdict,
      manual,
    );
    expect(connector.getUnreadCountForChannelIndex(channel.index), 0);
    expect(plugin.shown, isEmpty);
  }, skip: skip);

  group('U05 baseline: fork channel mute and mentions', () {
    for (final sample in [
      (label: 'unmuted ordinary text', muted: false, text: 'hello', shown: true),
      (label: 'muted ordinary text', muted: true, text: 'hello', shown: false),
      (label: 'muted inline self mention', muted: true, text: 'hello @[Me]', shown: true),
      (label: 'muted mention with spaces and case', muted: true, text: 'hello @[ mE ]', shown: true),
      (label: 'muted different full name', muted: true, text: 'hello @[Member]', shown: false),
      (label: 'muted plain at-name now has the mention exception', muted: true, text: 'hello @Me', shown: true),
    ]) {
      test(sample.label, () async {
        final harness = await _Harness.start();
        addTearDown(harness.connector.dispose);
        addTearDown(harness.settings.dispose);
        await harness.addChannel(0, 'Test', _psk(1));
        if (sample.muted) {
          await harness.settings.muteChannel('Test');
        }
        harness.connector.handleFrameForTest(_channelMessageFrame(
          channelIndex: 0, timestampSeconds: _timestamp,
          senderName: 'Alice', text: sample.text,
        ));
        final channel = harness.connector.channels.singleWhere((c) => c.index == 0);
        await _waitFor(
          () => harness.connector.getLoadedChannelMessages(channel).length == 1,
          'the persisted channel message',
        );
        if (sample.shown) {
          await _waitFor(() => plugin.shown.length == 1, 'the mention notification');
        } else {
          await _settle();
          expect(plugin.shown, isEmpty);
        }
        expect(plugin.shown, hasLength(sample.shown ? 1 : 0));
        // Notification filtering must not discard the received history row.
        expect(harness.connector.getLoadedChannelMessages(channel), hasLength(1));
      });
    }

    for (final text in ['hello', 'hello @[Me]', 'hello @Me']) {
      test('fully muted channel suppresses even mentions: $text', () async {
        final harness = await _Harness.start();
        addTearDown(harness.connector.dispose);
        addTearDown(harness.settings.dispose);
        await harness.addChannel(0, 'Test', _psk(1));
        await harness.settings.setChannelNotificationMode('Test', ChannelNotificationMode.muted);
        harness.connector.handleFrameForTest(_channelMessageFrame(
          channelIndex: 0, timestampSeconds: _timestamp,
          senderName: 'Alice', text: text,
        ));
        final channel = harness.connector.channels.singleWhere((c) => c.index == 0);
        await _waitFor(
          () => harness.connector.getLoadedChannelMessages(channel).length == 1,
          'the silenced channel history row',
        );
        await _settle();
        expect(plugin.shown, isEmpty);
      });
    }

    test('muted channel accepts its configured sender name', () async {
      final harness = await _Harness.start();
      addTearDown(harness.connector.dispose);
      addTearDown(harness.settings.dispose);
      await harness.addChannel(0, 'Test', _psk(1));
      await harness.connector.setChannelSenderName(0, 'Alias');
      await harness.settings.muteChannel('Test');
      harness.connector.handleFrameForTest(_channelMessageFrame(
        channelIndex: 0, timestampSeconds: _timestamp,
        senderName: 'Alice', text: 'hello @[ Alias ]',
      ));
      await _waitFor(() => plugin.shown.length == 1, 'the channel alias mention');
      expect(_NotificationPlugin.argumentsOf(plugin.shown.single)['payload'], 'channel:0');
    });

    test('completed channel sync links a rename and keeps the old name mute', () async {
      final harness = await _Harness.start();
      addTearDown(harness.connector.dispose);
      addTearDown(harness.settings.dispose);
      await harness.addChannel(0, 'Before', _psk(1));
      final before = harness.connector.channels.singleWhere((c) => c.index == 0);
      final beforeIdentity = ChannelIdentity.of(before)!;
      await harness.settings.muteChannel('Before');
      // External renames are reconciled from complete channel lists, not
      // isolated unsolicited slot frames (which may be part of a slot move).
      await harness.connector.getChannels(maxChannels: 1, force: true);
      await harness.addChannel(0, 'After', _psk(1));
      await _waitFor(
        () => !harness.connector.isSyncingChannels,
        'the completed channel sync and identity reconciliation',
      );
      final after = harness.connector.channels.singleWhere((c) => c.index == 0);
      final afterIdentity = ChannelIdentity.of(after)!;
      expect(ChannelIdentities.instance.sameChannel(beforeIdentity, afterIdentity), isTrue);
      expect(ChannelIdentities.instance.namesOf(afterIdentity), contains('Before'));
      harness.connector.handleFrameForTest(_channelMessageFrame(
        channelIndex: 0, timestampSeconds: _timestamp,
        senderName: 'Alice', text: 'ordinary text after rename',
      ));
      final channel = harness.connector.channels.singleWhere((c) => c.index == 0);
      await _waitFor(
        () => harness.connector.getLoadedChannelMessages(channel).length == 1,
        'the renamed channel message',
      );
      await _settle();
      expect(plugin.shown, isEmpty);
    });
  }, skip: skip);

  group('what a notification says', () {
    test('U06c1: a location summary keeps the original channel text in SQL', () async {
      const original = 'm:45.5,-122.6|Camp|poi';
      final harness = await _Harness.start();
      await harness.addChannel(0, 'Test', _psk(1));
      harness.connector.handleFrameForTest(
        _channelMessageFrame(
          channelIndex: 0,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: original,
        ),
      );
      await _waitFor(() => plugin.shown.length == 1, 'the location notification');
      final args = _NotificationPlugin.argumentsOf(plugin.shown.single);
      expect(args['body'], 'Alice: Shared a location: Camp');
      expect(args['payload'], 'channel:0');
      final channel = harness.connector.channels.singleWhere((c) => c.index == 0);
      expect(harness.connector.getLoadedChannelMessages(channel).single.text, original);
      final history = ChannelMessageStore()
        ..setPublicKeyHex = harness.connector.selfPublicKeyHex;
      history.registerChannel(channel);
      expect((await history.loadChannelMessages(0)).single.text, original);
    });

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

    test('U34: reusing a channel slot cancels the former notification', () async {
      final harness = await _Harness.start();
      final connector = harness.connector;
      addTearDown(harness.settings.dispose);
      addTearDown(connector.dispose);
      await harness.addChannel(0, 'Old channel', _psk(1));
      connector.handleFrameForTest(_channelMessageFrame(
        channelIndex: 0,
        timestampSeconds: _timestamp,
        senderName: 'Alice',
        text: 'Old post',
      ));
      await _waitFor(() => plugin.shown.length == 1, 'the old notification');

      await harness.addChannel(0, 'Renamed channel', _psk(1));
      expect(plugin.cancelledIds, isEmpty);
      await harness.addChannel(0, 'Replacement', _psk(2));
      await _waitFor(() => plugin.cancelledIds.isNotEmpty, 'slot notification cancellation');
      expect(plugin.cancelledIds, [0.hashCode]);
      expect(connector.channels.single.name, 'Replacement');
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
      // Every message notification is a MessagingStyle conversation (Android
      // Auto and the reply actions need it), so the picture rides as the
      // large icon rather than a big picture.
      final details = _NotificationPlugin.androidDetailsOf(call);
      expect(details['style'], AndroidNotificationStyle.messaging.index);
      final style = details['styleInformation'] as Map<Object?, Object?>;
      final messages = style['messages'] as List<Object?>;
      expect(messages, hasLength(1));
      expect((messages.single as Map<Object?, Object?>)['text'], 'MCOimg');
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

  group('the notification is shown off the receive path', () {
    test('a queued direct message: the next request goes out while the '
        'plugin still holds the notification', () async {
      final harness = await _Harness.start();
      final connector = harness.connector;
      final alice = await harness.addContact(aliceKey, 'Alice');
      connector.countStored = () => connector.getLoadedMessages(alice).length;
      final hold = plugin.hold = Completer<void>();

      await connector.syncQueuedMessages();
      connector.handleFrameForTest(
        _contactMessageFrame(
          senderKey: aliceKey,
          timestampSeconds: _timestamp,
          text: 'hello',
        ),
      );
      // Nothing completes the hold before this returns, so the request went
      // out with the notification still in the plugin's hands.
      await _waitFor(() => connector.syncRequests == 2, 'the next request');

      expect(connector.storedAtSyncNext, [0, 1]);
      await _waitFor(() => plugin.shown.length == 1, 'the notification');
      final arguments = _NotificationPlugin.argumentsOf(plugin.shown.single);
      expect(arguments['title'], 'Alice');
      hold.complete();
      await _settle();

      connector.handleFrameForTest(
        Uint8List.fromList([respCodeNoMoreMessages]),
      );
      await _settle();
      expect(connector.syncRequests, 2);
    });

    test('a queued channel message: the next request goes out while the '
        'plugin still holds the notification', () async {
      final harness = await _Harness.start();
      final connector = harness.connector;
      await harness.addChannel(0, 'Test', _psk(1));
      final channel = connector.channels.single;
      connector.countStored = () =>
          connector.getLoadedChannelMessages(channel).length;
      final hold = plugin.hold = Completer<void>();

      await connector.syncQueuedMessages();
      connector.handleFrameForTest(
        _channelMessageFrame(
          channelIndex: 0,
          timestampSeconds: _timestamp,
          senderName: 'Alice',
          text: 'hello',
        ),
      );
      await _waitFor(() => connector.syncRequests == 2, 'the next request');

      expect(connector.storedAtSyncNext, [0, 1]);
      await _waitFor(() => plugin.shown.length == 1, 'the notification');
      final arguments = _NotificationPlugin.argumentsOf(plugin.shown.single);
      expect(arguments['title'], 'Test');
      hold.complete();
      await _settle();

      connector.handleFrameForTest(
        Uint8List.fromList([respCodeNoMoreMessages]),
      );
      await _settle();
      expect(connector.syncRequests, 2);
    });

    test(
      'an MCOimg notification deletes the pictures of earlier ones after '
      'a day and keeps the younger ones',
      () async {
        final stale = File('${tempDir.path}/mcoimg_notification_1.png')
          ..writeAsBytesSync(const [1]);
        stale.setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 25)),
        );
        final young = File('${tempDir.path}/mcoimg_notification_2.png')
          ..writeAsBytesSync(const [1]);
        young.setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 23)),
        );
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
        await _waitFor(() => !stale.existsSync(), 'the stale picture to go');

        expect(young.existsSync(), isTrue);
        expect(_notificationPngs(tempDir), hasLength(2));
      },
      skip: PlatformInfo.isWindows || PlatformInfo.isMacOS
          ? null
          : 'this host writes no picture file',
    );
  }, skip: skip);
}
