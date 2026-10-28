import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _channel = Channel(index: 0, name: 'synthetic', psk: Uint8List(16));

/// Настоящие sendChannelMessage, scope lock и ACK dispatcher; только writer
/// синтетический. Пустой ключ ноды не позволяет открыть реальное хранилище.
class _Node extends MeshCoreConnector {
  _Node() {
    setFrameWriterForTest((frame) async {
      frames.add(List<int>.of(frame));
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
