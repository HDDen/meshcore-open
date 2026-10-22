import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/direct_message_progress_helper.dart';
import 'package:meshcore_open/helpers/direct_progress_rx_parser.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/message_retry_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ObservedSettings extends AppSettingsService {
  final trackedListeners = <VoidCallback>[];

  @override
  void addListener(VoidCallback listener) {
    trackedListeners.add(listener);
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    trackedListeners.remove(listener);
    super.removeListener(listener);
  }
}

final _timestamp = DateTime.fromMillisecondsSinceEpoch(1700000000000);
final _selfKey = Uint8List(32)..[0] = 0x11;
final _frame = Uint8List.fromList([0x88, 32, 186, 0x0a, 1, 0x21, 0xaa, 0x11, 0x41, 0x42]);

Contact _contact({bool flood = false}) => Contact(
  publicKey: Uint8List(32)..[0] = 0xaa,
  name: 'Synthetic', type: 1,
  pathLength: flood ? -1 : 2,
  path: Uint8List.fromList(flood ? [] : [0x20, 0x21]),
  lastSeen: _timestamp,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ObservedSettings settings;
  late MessageRetryService service;
  late DirectProgressRxParser<DirectMessageEcho> parser;
  late Map<String, Message> latest;
  late int parses;
  late bool disposed;

  RetryServiceConfig config(AppSettingsService? options) => RetryServiceConfig(
    appSettingsService: options,
    sendMessage: (_, _, _, _, {required useFlood}) async => _timestamp,
    addMessage: (_, message) => latest[message.messageId] = message,
    updateMessage: (message) => latest[message.messageId] = message,
    getSelfPublicKey: () => _selfKey,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    settings = _ObservedSettings();
    await settings.loadSettings();
    latest = {};
    parses = 0;
    disposed = false;
    service = MessageRetryService()..initialize(config(settings));
    parser = DirectProgressRxParser((frame) {
      parses++;
      return DirectMessageEcho.tryParse(frame);
    });
    service.attachRxProgressParserForTest(parser);
  });
  tearDown(() {
    if (!disposed) {
      service.dispose();
    }
    settings.dispose();
    PrefsManager.reset();
  });

  Future<int> send(String id, {bool flood = false}) async {
    await service.sendMessageWithRetry(
      contact: _contact(flood: flood), text: id, messageId: id, timestamp: _timestamp,
    );
    await pumpEventQueue();
    return MessageRetryService.computeExpectedAckHash(1700000000, 0, id, _selfKey);
  }

  test('live profiles skip only idle parsing and keep SENT, direct progress and ACK', () async {
    service.handleRxLogFrame(_frame);
    expect(parses, 1);
    await settings.setSkipIdleDirectProgressParsing(true);
    service.handleRxLogFrame(_frame); // Off сохраняет прежний разбор.
    expect(parses, 2);
    await settings.setPowerSavingProfile(PowerSavingProfile.custom);
    service.handleRxLogFrame(_frame);
    expect(parses, 2);
    final hash = await send('direct');
    expect(service.hasPendingMessages, isTrue);
    service.handleRxLogFrame(_frame); // До SENT ещё нет трекера.
    expect(parses, 2);
    expect(service.updateMessageFromSent(hash, 60000), isTrue);
    service.handleRxLogFrame(_frame);
    expect(parses, 3);
    expect(latest['direct']!.deliveryProgressCompletedSteps, 1);
    await settings.setSkipIdleDirectProgressParsing(false);
    service.handleRxLogFrame(_frame);
    expect(parses, 4);
    await settings.setSkipIdleDirectProgressParsing(true);
    service.handleRxLogFrame(_frame);
    expect(parses, 5);
    expect(latest['direct']!.deliveryProgressCompletedSteps, 1);
    expect(service.handleAckReceived(hash, 100)?.messageId, 'direct');
    expect(latest['direct']!.status, MessageStatus.delivered);
    expect(latest['direct']!.deliveryProgressCompletedSteps, 3);
    service.handleRxLogFrame(_frame);
    expect(parses, 5);
    await settings.setPowerSavingProfile(PowerSavingProfile.disabled);
    service.handleRxLogFrame(_frame);
    expect(parses, 6);
    await settings.setPowerSavingProfile(PowerSavingProfile.balanced);
    await settings.setCacheChannelKeyHashes(true);
    service.handleRxLogFrame(_frame);
    expect(parses, 6);
  });

  test('pending flood has no direct tracker and ordinary ACK is unaffected', () async {
    await settings.setPowerSavingProfile(PowerSavingProfile.balanced);
    final hash = await send('flood', flood: true);
    expect(service.updateMessageFromSent(hash, 60000), isTrue);
    service.handleRxLogFrame(_frame);
    expect(parses, 0);
    expect(service.hasPendingMessages, isTrue);
    expect(service.handleAckReceived(hash, 100)?.messageId, 'flood');
    expect(latest['flood']!.status, MessageStatus.delivered);
  });

  test('reinitialize replaces one settings listener and missing settings restores Off', () async {
    await settings.setPowerSavingProfile(PowerSavingProfile.balanced);
    service.initialize(config(settings));
    expect(settings.trackedListeners, hasLength(1));
    service.handleRxLogFrame(_frame);
    expect(parses, 0);
    final other = _ObservedSettings();
    await other.loadSettings();
    addTearDown(other.dispose);
    await other.setPowerSavingProfile(PowerSavingProfile.disabled);
    service.initialize(config(other));
    expect(settings.trackedListeners, isEmpty);
    expect(other.trackedListeners, hasLength(1));
    service.handleRxLogFrame(_frame);
    expect(parses, 1);
    await other.setPowerSavingProfile(PowerSavingProfile.balanced);
    service.handleRxLogFrame(_frame);
    expect(parses, 1);
    service.initialize(config(null));
    expect(other.trackedListeners, isEmpty);
    service.handleRxLogFrame(_frame);
    expect(parses, 2);
  });

  test('dispose removes the settings listener and later changes cannot update the helper', () async {
    await settings.setPowerSavingProfile(PowerSavingProfile.balanced);
    expect(settings.trackedListeners, hasLength(1));
    service.dispose();
    disposed = true;
    expect(settings.trackedListeners, isEmpty);
    await settings.setPowerSavingProfile(PowerSavingProfile.disabled);
    expect(parser.parse(_frame, hasTrackers: false), isNull);
    expect(parses, 0);
  });
}
