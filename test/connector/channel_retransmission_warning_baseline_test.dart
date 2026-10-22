import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Фиксируем смежный прежний warning при ВЫКЛЮЧЕННОМ режиме порога хопов.
// Отсутствие покрытия при включённом пороге будет отдельной новой регрессией.
final _channel = Channel(index: 0, name: 'baseline', psk: Uint8List(16));

ChannelMessage _message({
  bool outgoing = true,
  bool sentByRadio = true,
  int repeats = 0,
  int resends = 0,
  ChannelMessageStatus status = ChannelMessageStatus.sent,
}) => ChannelMessage(
  messageId: 'synthetic-warning-baseline',
  senderName: 'baseline',
  text: 'synthetic',
  timestamp: DateTime.utc(2026, 10, 22),
  sentByRadioAt: sentByRadio ? DateTime.utc(2026, 10, 22) : null,
  isOutgoing: outgoing,
  status: status,
  repeatCount: repeats,
  resendCount: resends,
  pathLength: repeats > 0 ? 1 : 0,
  pathHashWidth: 2,
  pathBytes: repeats > 0 ? Uint8List.fromList([0x81, 0x30]) : null,
);

Future<MeshCoreConnector> _connector(ChannelMessage message, {int warningSeconds = 7}) async {
  final settings = AppSettingsService();
  addTearDown(settings.dispose);
  await settings.updateSettings(AppSettings(
    noRetransmissionWarningSeconds: warningSeconds,
    channelMinHopsEnabled: false,
  ));
  final connector = MeshCoreConnector();
  addTearDown(connector.dispose);
  connector.attachAppSettingsServiceForTest(settings);
  connector.setChannelMessagesForTest(_channel.index, [message]);
  // publicKeyHex хранилища пуст: production guard запрещает запись в БД.
  return connector;
}

void _expire(MeshCoreConnector connector, ChannelMessage message) {
  connector.scheduleChannelNoRetransmissionWarningForTest(
    message.messageId,
    since: DateTime.now().subtract(const Duration(minutes: 1)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  for (final resends in [0, 3]) {
    test('legacy: no echo warns after the deadline, resends=$resends', () async {
      final message = _message(resends: resends);
      final connector = await _connector(message);
      _expire(connector, message);
      final updated = connector.getChannelMessages(_channel).single;
      expect(updated.noRetransmissionWarningSeconds, 7);
      expect(updated.status, ChannelMessageStatus.sent);
      expect(updated.resendCount, resends);
      expect(updated.repeatCount, 0);
      expect(updated.messageId, message.messageId);
    });

    test('legacy: one heard echo suppresses the ordinary warning, resends=$resends', () async {
      final message = _message(repeats: 1, resends: resends);
      final connector = await _connector(message);
      _expire(connector, message);
      final updated = connector.getChannelMessages(_channel).single;
      expect(updated.noRetransmissionWarningSeconds, isNull);
      expect(updated.status, ChannelMessageStatus.sent);
      expect(updated.repeatCount, 1);
      expect(updated.resendCount, resends);
    });
  }

  test('legacy: warning settings clamp 30 seconds to the existing maximum of 15', () async {
    final message = _message();
    final connector = await _connector(message, warningSeconds: 30);
    _expire(connector, message);
    expect(connector.getChannelMessages(_channel).single.noRetransmissionWarningSeconds, 15);
  });

  test('legacy: a disabled warning does not mark an unechoed message', () async {
    final message = _message(resends: 3);
    final connector = await _connector(message, warningSeconds: 0);
    _expire(connector, message);
    expect(connector.getChannelMessages(_channel).single.noRetransmissionWarningSeconds, isNull);
  });

  for (final message in [
    _message(outgoing: false),
    _message(sentByRadio: false),
    _message(status: ChannelMessageStatus.failed),
  ]) {
    test('legacy: incoming, unsent and failed guards (${message.isOutgoing}, ${message.sentByRadioAt}, ${message.status})', () async {
      final connector = await _connector(message);
      _expire(connector, message);
      expect(connector.getChannelMessages(_channel).single.noRetransmissionWarningSeconds, isNull);
    });
  }
}
