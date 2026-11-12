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
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _channel = Channel(index: 0, name: 'synthetic', psk: Uint8List(16));

/// Настоящие sendChannelMessage, scope lock и ACK dispatcher; только writer
/// синтетический. Тесты с SELF_INFO используют SQLite в памяти.
class _Node extends MeshCoreConnector {
  _Node({int? txPower, bool cliSupported = false}) {
    if (cliSupported) {
      final device = Uint8List(80);
      device[0] = respCodeDeviceInfo;
      device[1] = 14;
      device.setRange(60, 66, '1.18.0'.codeUnits);
      handleFrameForTest(device);
    }
    if (txPower != null) {
      final info = Uint8List(64);
      info[0] = respCodeSelfInfo;
      info[2] = txPower;
      info[3] = 22;
      info.fillRange(4, 36, 0x11);
      info.setRange(58, 62, 'Node'.codeUnits);
      handleFrameForTest(info);
    }
    setFrameWriterForTest((frame) async {
      frames.add(List<int>.of(frame));
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
      handleFrameForTest([frame[0] == cmdGetDefaultFloodScope
        ? respCodeDefaultFloodScope : respCodeOk]);
    });
    final frame = Uint8List(50);
    frame[0] = respCodeChannelInfo;
    frame[1] = _channel.index;
    frame.setRange(2, 2 + _channel.name.length, _channel.name.codeUnits);
    handleFrameForTest(frame);
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
          await _until(tester, () => node.channels.any((channel) =>
            channel.index == _channel.index && channel.name == _channel.name) &&
            node.backgroundWorkSnapshot.countFor(BackgroundWorkKind.channelSync) == 0,
            stage: 'CHANNEL_INFO settings/history');
          final wallStart = DateTime.now();
          final fakeStart = tester.binding.clock.now();
          node.setChannelResendClockForTest(() =>
            wallStart.add(tester.binding.clock.now().difference(fakeStart)));

          await node.sendChannelMessage(_channel, 'adaptive TX test', region: '');
          await tester.pump(const Duration(seconds: 21));
          await _until(tester, () => node.transmissions == 2, stage: 'normal retry');
          expect(node.currentTxPower, 11);

          await tester.pump(const Duration(seconds: 21));
          await _until(tester, () => node.transmissions == 3, stage: 'first boost');
          expect(node.currentTxPower, 18);
          expect(await storage.readAdaptiveTxPowerBaseline(node.selfPublicKeyHex), 11);

          await tester.pump(const Duration(seconds: 21));
          await _until(tester, () => node.transmissions == 4, stage: 'second boost');
          await tester.pump(const Duration(seconds: 21));
          await _until(tester, () => node.currentTxPower == 11 &&
            (!usesLna || node.frames.last.first == cmdRunCliCommand),
            stage: 'restore');
          expect(await storage.readAdaptiveTxPowerBaseline(node.selfPublicKeyHex), isNull);
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
