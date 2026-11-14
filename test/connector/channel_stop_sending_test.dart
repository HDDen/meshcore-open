import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/models/adaptive_tx_power_settings.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/message_retry_service.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _channel = Channel(index: 0, name: 'synthetic', psk: Uint8List(16));

/// Настоящие sendChannelMessage, scope lock и ACK dispatcher; только writer
/// синтетический. Тесты с SELF_INFO используют SQLite в памяти.
class _Node extends MeshCoreConnector {
  _Node({int? txPower, bool cliSupported = false}) {
    setFrameWriterForTest((frame) async {
      frames.add(List<int>.of(frame));
      if (frame.first == cmdDeviceQuery && txPower != null) {
        final device = Uint8List(80);
        device[0] = respCodeDeviceInfo;
        device[1] = cliSupported ? 14 : 8;
        final version = cliSupported ? '1.18.0' : '1.17.1';
        device.setRange(60, 60 + version.length, version.codeUnits);
        handleFrameForTest(device);
        return;
      }
      if (frame.first == cmdAppStart && txPower != null) {
        final info = Uint8List(64);
        info[0] = respCodeSelfInfo;
        info[2] = txPower;
        info[3] = 22;
        info.fillRange(4, 36, 0x11);
        final radio = ByteData.sublistView(info);
        radio.setUint32(48, 869525000, Endian.little);
        radio.setUint32(52, 500000, Endian.little);
        info[56] = 7;
        info[57] = 5;
        info.setRange(58, 62, 'Node'.codeUnits);
        handleFrameForTest(info);
        return;
      }
      if (frame.first == cmdRunCliCommand) {
        final command = String.fromCharCodes(frame.skip(4));
        final response = switch (command) {
          'get radio.fem.rxgain' => '> off',
          'set radio.fem.rxgain on' => 'OK - LoRa FEM RX gain on',
          'set radio.fem.rxgain off' => 'OK - LoRa FEM RX gain off',
          _ => 'Error: unsupported',
        };
        handleFrameForTest([
          respCodeCliReply, ...frame.sublist(1, 4), ...response.codeUnits,
        ]);
        return;
      }
      final isData = frame[0] == cmdSendChannelTxtMsg || frame[0] == cmdSendChannelData;
      if ((holdScope && frame[0] == cmdSetFloodScope) || (holdData && isData)) {
        holdScope = false;
        holdData = false;
        gate = Completer<void>();
        await gate!.future;
      }
      handleFrameForTest(switch (frame.first) {
        cmdGetDefaultFloodScope => [respCodeDefaultFloodScope],
        cmdGetCustomVar => [respCodeCustomVars],
        cmdGetBattAndStorage => [respCodeBattAndStorage, 0x10, 0x0e],
        cmdGetAutoAddConfig => [respCodeAutoAddConfig, 0],
        cmdGetAllowedRepeatFreq => [respCodeAllowedRepeatFreq, 0, 0, 0, 0],
        _ => [respCodeOk],
      });
    });
    if (txPower == null) handleFrameForTest(_channelInfo());
  }

  static Uint8List _channelInfo() {
    final frame = Uint8List(50);
    frame[0] = respCodeChannelInfo;
    frame[1] = _channel.index;
    frame.setRange(2, 2 + _channel.name.length, _channel.name.codeUnits);
    frame.setRange(34, 50, _channel.psk);
    return frame;
  }

  late Future<void> _cachedChannelsLoad;

  @override
  Future<void> loadCachedChannels({String? publicKeyHex}) =>
      _cachedChannelsLoad = super.loadCachedChannels(publicKeyHex: publicKeyHex);

  Future<void> prepareChannelHistory() async {
    // Only SELF_INFO in response to APP_START binds history to the node key.
    await requestDeviceInfoForTest();
    await _cachedChannelsLoad;
    await handleChannelInfoForTest(_channelInfo());
  }

  final frames = <List<int>>[];
  bool holdScope = false;
  bool holdData = false;
  Completer<void>? gate;
  @override
  bool get isConnected => true;
  @override
  bool get isSessionReady => true;

  int get transmissions => frames.where((frame) =>
    frame[0] == cmdSendChannelTxtMsg || frame[0] == cmdSendChannelData).length;

  void release() {
    final pending = gate;
    if (pending != null && !pending.isCompleted) { pending.complete(); }
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready, {
  String stage = 'transport',
}) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(ready(), isTrue, reason: 'Synthetic $stage stage did not complete');
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  group('adaptive TX power', () {
    final storage = MessageHistoryStorage.instance;

    setUp(() async {
      await storage.resetForTesting();
      await storage.initializeAndMigrate(
        databaseFactory: () => MessageHistoryDatabase.withExecutor(
          NativeDatabase.memory(),
        ),
      );
    });
    tearDown(storage.resetForTesting);

    testWidgets('Flood Auto without a route raises TX before the retry and restores after ACK', (
      tester,
    ) async {
      final node = _Node(txPower: 11);
      final settings = AppSettingsService();
      final retry = MessageRetryService()..retryBackoffMs = (_) => 0;
      final peerKey = Uint8List(32)..fillRange(0, 32, 0x22);
      final peerKeyHex = pubKeyToHex(peerKey);
      try {
        await settings.updateSettings(AppSettings(
          maxMessageRetries: 2,
          automaticDirectFloodRetries: 5,
          channelMinHopsEnabled: true,
          notifyOnNewAdvert: false,
          adaptiveTxPower: const AdaptiveTxPowerSettings(
            enabled: true,
            targetDbm: 18,
            directEnabled: true,
            forcedFloodRetries: 1,
          ),
        ));
        node.attachAppSettingsServiceForTest(settings);
        node.attachRetryServiceForTest(retry);
        retry.setMaxRetries(2);
        await node.prepareChannelHistory();

        node.handleFrameForTest(Uint8List(148)
          ..[0] = respCodeContact
          ..setRange(1, 33, peerKey)
          ..[33] = advTypeChat
          ..[35] = 0xff
          ..setRange(100, 104, 'Peer'.codeUnits));
        final peer = node.getContactByPubKeyHex(peerKeyHex)!;
        expect(peer.pathLength, -1);
        expect(peer.pathOverride, isNull);

        // Reuse the transport from the channel tests and hold SENT for the
        // two personal sends so the test observes the live state as well.
        final textFrames = <Uint8List>[];
        node.setFrameWriterForTest((frame) async {
          node.frames.add(frame);
          if (frame.first == cmdSendTxtMsg) {
            textFrames.add(frame);
            return;
          }
          node.handleFrameForTest([respCodeOk]);
        });
        // The default scope is already known in this scenario. A Flood SENT
        // can stamp the message without starting a separate stream waiter.
        await node.setDefaultRegionScope(null);

        int acknowledgeEnqueue(Uint8List frame) {
          final reader = BufferReader(frame)..skipBytes(2);
          final attempt = reader.readByte();
          final timestamp = reader.readUInt32LE();
          reader.skipBytes(6);
          final hash = MessageRetryService.computeExpectedAckHash(
            timestamp, attempt, reader.readCString(), node.selfPublicKey!,
          );
          final sent = BufferWriter()
            ..writeByte(respCodeSent)
            ..writeByte(1)
            ..writeUInt32LE(hash)
            ..writeUInt32LE(1000);
          node.handleFrameForTest(sent.toBytes());
          return hash;
        }

        Message message() => node.getMessages(peer).single;
        await node.sendMessage(peer, 'Flood Auto');
        await _until(tester, () => textFrames.length == 1, stage: 'ordinary send');
        expect(node.currentTxPower, 11);
        final firstHash = acknowledgeEnqueue(textFrames.first);
        expect(message().status, MessageStatus.sent);
        expect(message().expectedAckHash, firstHash);
        expect(message().activeTxBoostWithLna, isNull);
        final timeout = message().estimatedTimeoutMs;
        expect(timeout, greaterThan(0), reason: 'SENT must arm the ACK timer');
        await tester.pump(Duration(milliseconds: timeout!));
        await _until(tester, () => textFrames.length == 2, stage: 'boosted retry');

        expect(node.currentTxPower, 18);
        expect(message().activeTxBoostWithLna, isNull);
        expect(textFrames.map((frame) => frame[2]), [0, 1]);
        final hash = acknowledgeEnqueue(textFrames.last);
        expect(message().expectedAckHash, hash);
        expect(message().activeTxBoostWithLna, isFalse);
        expect(message().sentWithTxPowerBoost, isFalse);

        final ack = BufferWriter()
          ..writeByte(pushCodeSendConfirmed)
          ..writeUInt32LE(hash)
          ..writeUInt32LE(1200);
        node.handleFrameForTest(ack.toBytes());
        await _until(tester, () => node.currentTxPower == 11, stage: 'restore');
        expect(await storage.readAdaptiveTxPowerBaseline(node.selfPublicKeyHex), isNull);
        expect(message().status, MessageStatus.delivered);
        expect(message().tripTimeMs, 1200);
        expect(message().activeTxBoostWithLna, isNull);
        expect(message().sentWithTxPowerBoost, isTrue);
        expect([
          for (final frame in node.frames)
            if (frame.first == cmdSetRadioTxPower)
              'TX ${frame[1]}'
            else if (frame.first == cmdSendTxtMsg)
              'send ${frame[2]}',
        ], ['send 0', 'TX 18', 'send 1', 'TX 11']);
      } finally {
        retry.setSendingPaused(true);
        // On an earlier assertion failure, a held SENT may still own the
        // command lock. Let its timeout finish before disposing the node.
        await tester.pump();
        if (node.pendingCommandReplyCountForTest > 0) {
          await tester.pump(const Duration(seconds: 5));
        }
        node.dispose();
        retry.dispose();
        settings.dispose();
        await tester.pump();
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    for (final (cliSupported, tryLna) in [(false, true), (true, false), (true, true)]) {
      final usesLna = cliSupported && tryLna;
      testWidgets('boosted channel retries use LNA only when enabled and supported '
          '(CLI: $cliSupported, option: $tryLna)', (tester) async {
        final node = _Node(txPower: 11, cliSupported: cliSupported);
        final settings = AppSettingsService();
        try {
          await settings.updateSettings(AppSettings(
            channelMinHopsEnabled: true,
            channelMinHopsRetries: 3,
            channelMinHopsDelaySeconds: 20,
            noRetransmissionWarningSeconds: 0,
            channelsSendAsBinary: false,
            adaptiveTxPower: AdaptiveTxPowerSettings(
              enabled: true,
              targetDbm: 18,
              channelRetries: 2,
              tryLna: tryLna,
            ),
          ));
          node.attachAppSettingsServiceForTest(settings);
          await node.prepareChannelHistory();
          expect(node.hasCompletedSelfInfoHandshake, isTrue);
          final wallStart = DateTime.now();
          final fakeStart = tester.binding.clock.now();
          node.setChannelResendClockForTest(() =>
            wallStart.add(tester.binding.clock.now().difference(fakeStart)));

          await node.sendChannelMessage(_channel, 'adaptive TX test', region: '');
          await tester.pump(const Duration(seconds: 21));
          await _until(tester, () => node.transmissions == 2, stage: 'normal retry');
          expect(node.currentTxPower, 11);
          expect(node.getChannelMessages(_channel).single.sentWithTxPowerBoost, isFalse);

          node.holdData = true;
          await tester.pump(const Duration(seconds: 21));
          await _until(tester, () => node.transmissions == 3, stage: 'first boost');
          expect(node.currentTxPower, 18);
          expect(node.getChannelMessages(_channel).single.sentWithTxPowerBoost, isFalse);
          node.release();
          await _until(tester,
            () => node.getChannelMessages(_channel).single.sentWithTxPowerBoost,
            stage: 'boosted send confirmation');
          expect(await storage.readAdaptiveTxPowerBaseline(node.selfPublicKeyHex), 11);

          await tester.pump(const Duration(seconds: 21));
          await _until(tester, () => node.transmissions == 4, stage: 'second boost');
          await tester.pump(const Duration(seconds: 21));
          await _until(tester, () => node.currentTxPower == 11 &&
            (!usesLna || node.frames.last.first == cmdRunCliCommand),
            stage: 'restore');
          expect(await storage.readAdaptiveTxPowerBaseline(node.selfPublicKeyHex), isNull);
          expect(node.getChannelMessages(_channel).single.sentWithTxPowerBoost, isTrue);
          final saved = await node.loadLatestPersistedChannelMessages(
            _channel.index, limit: 1,
          );
          expect(saved, hasLength(1));
          expect(saved.single.messageId, node.getChannelMessages(_channel).single.messageId);
          expect(saved.single.sentWithTxPowerBoost, isTrue);
          expect(saved.single.sentWithAdaptiveLna, usesLna);
          final commands = [
            for (final frame in node.frames)
              if (frame.first == cmdSetRadioTxPower)
                'TX ${frame[1]}'
              else if (frame.first == cmdSendChannelTxtMsg)
                'send'
              else if (frame.first == cmdRunCliCommand)
                String.fromCharCodes(frame.skip(4)),
          ];
          expect(commands, [
            'send',
            'send',
            if (usesLna) ...['get radio.fem.rxgain', 'set radio.fem.rxgain on'],
            'TX 18',
            'send',
            'send',
            'TX 11',
            if (usesLna) 'set radio.fem.rxgain off',
          ]);
          if (usesLna) expect(node.companionCli.entries(shared: true), isEmpty);
        } finally {
          node.release();
          node.dispose();
          settings.dispose();
          await tester.pump(const Duration(seconds: 21));
        }
      });
    }
  });

  for (final stage in ['first ACK', 'retry scope', 'retry ACK']) {
    testWidgets('stop at $stage prevents all later transmissions and retains sent history', (tester) async {
      final settings = AppSettingsService();
      final node = _Node();
      try {
        await settings.updateSettings(AppSettings(
          channelMinHopsEnabled: true, channelMinHops: 2,
          channelMinHopsRetries: 3, channelMinHopsDelaySeconds: 20,
          noRetransmissionWarningSeconds: 0,
        ));
        node.attachAppSettingsServiceForTest(settings);
        // CHANNEL_INFO загружает настройки/историю асинхронно и заменяет
        // окно сообщений. Готовим ноду до TX, а не одновременно с отправкой.
        await _until(tester, () => node.channels.any((channel) =>
          channel.index == _channel.index && channel.name == _channel.name) &&
          node.backgroundWorkSnapshot.countFor(BackgroundWorkKind.channelSync) == 0,
          stage: 'CHANNEL_INFO settings/history');
        expect(node.frames, isEmpty);
        expect(node.getChannelMessages(_channel), isEmpty);
        final wallStart = DateTime.now();
        final fakeStart = tester.binding.clock.now();
        node.setChannelResendClockForTest(() =>
          wallStart.add(tester.binding.clock.now().difference(fakeStart)));
        node.holdData = stage == 'first ACK';
        var initialFinished = false;
        Object? sendError;
        // Регион задан явно: проверяем SET_SCOPE/TX/ACK и их отмену,
        // а не независимый GET_DEFAULT_SCOPE с broadcast.cancel вне FakeAsync.
        unawaited(node.sendChannelMessage(_channel, 'Synthetic stop test', region: '').then<void>(
          (_) { initialFinished = true; },
          onError: (Object error, StackTrace stack) {
            sendError = error;
            initialFinished = true;
          },
        ));
        await _until(tester, () => stage == 'first ACK'
          ? node.gate != null : initialFinished);
        expect(sendError, isNull);
        expect(node.frames.first.first, cmdSetFloodScope);
        expect(node.getChannelMessages(_channel), hasLength(1),
          reason: 'The transmitted message must remain in the prepared history window');
        final original = node.getChannelMessages(_channel).single;
        if (stage != 'first ACK') {
          node.holdScope = stage == 'retry scope';
          node.holdData = stage == 'retry ACK';
          await tester.pump(const Duration(seconds: 21));
          await _until(tester, () => node.gate != null);
        }
        expect(node.canStopChannelSending(original.messageId), isTrue);
        final transmissions = stage == 'retry ACK' ? 2 : 1;
        expect(node.transmissions, transmissions);
        if (stage == 'retry scope') {
          expect(node.frames.last.first, cmdSetFloodScope);
        }
        node.stopSendingChannelMessage(original.messageId);
        expect(node.channelResendProgress(original.messageId), isNull);
        if (stage != 'first ACK') {
          // Stop отменяет серию, но удержанный writer/scope всё ещё выполняется.
          expect(node.backgroundWorkSnapshot.countFor(BackgroundWorkKind.retry), 1);
        }
        node.release();
        await _until(tester, () => initialFinished);
        await tester.pump();
        expect(node.backgroundWorkSnapshot.countFor(BackgroundWorkKind.retry), 0);
        await tester.pump(const Duration(minutes: 3));
        expect(node.transmissions, transmissions);
        expect(node.canStopChannelSending(original.messageId), isFalse);
        final saved = node.getChannelMessages(_channel).single;
        expect(saved.status, ChannelMessageStatus.sent);
        expect(saved.messageId, original.messageId);
        expect(saved.timestamp, original.timestamp);
        expect(saved.resendCount, transmissions - 1);
        expect(node.channelHopShortfall(saved.messageId), (hops: 0, required: 2));
        expect(sendError, isNull);
      } finally {
        for (final message in node.getChannelMessages(_channel)) {
          node.stopSendingChannelMessage(message.messageId);
        }
        node.release();
        await tester.pump(const Duration(seconds: 10));
        node.dispose();
        settings.dispose();
        await tester.pump();
      }
    });
  }
}
