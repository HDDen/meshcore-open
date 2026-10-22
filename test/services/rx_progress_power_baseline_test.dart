import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/direct_message_progress_helper.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/message_retry_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../tool/benchmark_rx_progress.dart' as bench;

final _timestamp = DateTime.fromMillisecondsSinceEpoch(1700000000000);
final _selfKey = Uint8List.fromList(List<int>.generate(32, (i) => 0x11 + i));

Contact _contact({int width = 1, bool flood = false, int lastByte = 0xbb}) => Contact(
  publicKey: Uint8List(32)
    ..[0] = 0xaa
    ..[31] = lastByte,
  name: 'Synthetic',
  type: 1,
  pathLength: flood ? -1 : 2,
  pathHashWidth: width,
  path: flood ? Uint8List(0)
      : Uint8List.fromList(List<int>.generate(2 * width, (i) => 0x21 + i)),
  lastSeen: _timestamp,
);

Uint8List _echo({
  int width = 1,
  int remaining = 1,
  bool scoped = false,
  List<int>? path,
  List<int> payload = const [0xaa, 0x11, 0x41, 0x42],
}) => Uint8List.fromList([
  0x88, 32, 186, scoped ? 0x0b : 0x0a,
  if (scoped) ...[1, 2, 3, 4],
  ((width - 1) << 6) | remaining,
  ...(path ?? List<int>.generate(
    remaining * width, (i) => 0x21 + (2 - remaining) * width + i,
  )),
  ...payload,
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('benchmark parser snapshot matches every field of the production parser', () {
    final accepted = <String>[];
    for (final sample in bench.rxProgressBenchmarkCorpus()) {
      final before = Uint8List.fromList(sample.frame);
      final actual = DirectMessageEcho.tryParse(sample.frame);
      final snapshot = bench.parseLegacyRxProgressEcho(sample.frame);
      expect(snapshot == null, actual == null, reason: sample.name);
      if (actual != null && snapshot != null) {
        accepted.add(sample.name);
        expect({
          'destination': snapshot.destinationHash, 'source': snapshot.sourceHash,
          'width': snapshot.pathHashWidth, 'hops': snapshot.remainingHopCount,
          'path': snapshot.remainingPath, 'payload': snapshot.payload,
        }, {
          'destination': actual.destinationHash, 'source': actual.sourceHash,
          'width': actual.pathHashWidth, 'hops': actual.remainingHopCount,
          'path': actual.remainingPath, 'payload': actual.payload,
        }, reason: sample.name);
      }
      expect(sample.frame, orderedEquals(before), reason: sample.name);
    }
    expect(accepted, [
      'direct-width-1', 'direct-width-2', 'direct-width-3', 'direct-width-4',
      'scoped-direct', 'direct-no-hops',
    ]);
  });

  for (final optimized in [false, true]) {
    group('RX progress baseline (optimized=$optimized)', () {
      late MessageRetryService service;
      late AppSettingsService settings;
      late Map<String, Message> latest;
      late List<Message> updates;
      late List<String> sent;

      setUp(() async {
        if (optimized) {
          SharedPreferences.setMockInitialValues({});
          PrefsManager.reset();
          await PrefsManager.initialize();
          settings = AppSettingsService();
          await settings.loadSettings();
          await settings.setPowerSavingProfile(PowerSavingProfile.balanced);
        }
        latest = {};
        updates = [];
        sent = [];
        service = MessageRetryService();
        service.initialize(RetryServiceConfig(
          appSettingsService: optimized ? settings : null,
          sendMessage: (_, text, _, _, {required useFlood}) async {
            sent.add(text);
            return _timestamp;
          },
          addMessage: (_, message) => latest[message.messageId] = message,
          updateMessage: (message) {
            latest[message.messageId] = message;
            updates.add(message);
          },
          getSelfPublicKey: () => _selfKey,
        ));
      });
      tearDown(() {
        service.dispose();
        if (optimized) {
          settings.dispose();
          PrefsManager.reset();
        }
      });

      Future<int> send(String id, {Contact? contact, bool confirmSent = true}) async {
        await service.sendMessageWithRetry(
          contact: contact ?? _contact(), text: id, messageId: id, timestamp: _timestamp,
        );
        await pumpEventQueue();
        final hash = MessageRetryService.computeExpectedAckHash(1700000000, 0, id, _selfKey);
        if (confirmSent) {
          expect(service.updateMessageFromSent(hash, 60000), isTrue);
        }
        return hash;
      }

      test('idle RX has no message, notification or pending-count side effects', () {
        var notifications = 0;
        var pendingNotifications = 0;
        service.addListener(() => notifications++);
        service.pendingMessageCount.addListener(() => pendingNotifications++);
        for (final sample in bench.rxProgressBenchmarkCorpus()) {
          service.handleRxLogFrame(sample.frame);
        }
        expect(latest, isEmpty);
        expect(updates, isEmpty);
        expect(sent, isEmpty);
        expect(service.hasPendingMessages, isFalse);
        expect((notifications, pendingNotifications), (0, 0));
      });

      test('a pending send has no direct tracker until SENT arrives', () async {
        final hash = await send('waiting', confirmSent: false);
        final before = updates.length;
        service.handleRxLogFrame(_echo());
        expect(service.hasPendingMessages, isTrue);
        expect(latest['waiting']!.deliveryProgressCompletedSteps, 0);
        expect(updates, hasLength(before));
        expect(service.updateMessageFromSent(hash, 60000), isTrue);
        service.handleRxLogFrame(_echo());
        expect(latest['waiting']!.deliveryProgressCompletedSteps, 1);
      });

      test('flood pending messages do not consume direct echo progress; ACK still works', () async {
        final hash = await send('flood', contact: _contact(flood: true));
        final before = updates.length;
        service.handleRxLogFrame(_echo());
        expect(service.hasPendingMessages, isTrue);
        expect(latest['flood']!.deliveryProgressCompletedSteps, 0);
        expect(updates, hasLength(before));
        expect(service.handleAckReceived(hash, 100)?.messageId, 'flood');
        expect(latest['flood']!.status, MessageStatus.delivered);
        expect(service.hasPendingMessages, isFalse);
      });

      for (final width in [1, 2, 3]) {
        test('direct progress width=$width binds payload, advances once and waits for ACK', () async {
          final hash = await send('direct-$width', contact: _contact(width: width));
          expect(latest['direct-$width']!.deliveryProgressTotalSteps, 3);
          service.handleRxLogFrame(_echo(width: width, scoped: true));
          expect(latest['direct-$width']!.deliveryProgressCompletedSteps, 1);
          final before = updates.length;
          service.handleRxLogFrame(_echo(width: width));
          service.handleRxLogFrame(_echo(width: width, remaining: 2));
          service.handleRxLogFrame(_echo(width: width, remaining: 0,
              payload: [0xaa, 0x11, 0x51, 0x52]));
          expect(updates, hasLength(before));
          service.handleRxLogFrame(_echo(width: width, remaining: 0));
          expect(latest['direct-$width']!.deliveryProgressCompletedSteps, 2);
          expect(latest['direct-$width']!.status, MessageStatus.sent);
          expect(service.handleAckReceived(hash, 100)?.messageId, 'direct-$width');
          expect(latest['direct-$width']!.deliveryProgressCompletedSteps, 3);
          expect(latest['direct-$width']!.status, MessageStatus.delivered);
          final afterAck = updates.length;
          service.handleRxLogFrame(_echo(width: width, remaining: 0));
          expect(updates, hasLength(afterAck));
          expect(service.hasPendingMessages, isFalse);
        });
      }

      test('active tracker ignores malformed frames, other addresses, widths and paths', () async {
        await send('filtered');
        final before = updates.length;
        final corpus = bench.rxProgressBenchmarkCorpus();
        for (final sample in corpus.where((sample) => !sample.name.startsWith('direct-') &&
            sample.name != 'scoped-direct')) {
          service.handleRxLogFrame(sample.frame);
        }
        service.handleRxLogFrame(_echo(payload: [0xab, 0x11, 0x41, 0x42]));
        service.handleRxLogFrame(_echo(payload: [0xaa, 0x12, 0x41, 0x42]));
        service.handleRxLogFrame(_echo(width: 2));
        service.handleRxLogFrame(_echo(path: [0x23]));
        expect(updates, hasLength(before));
        expect(latest['filtered']!.deliveryProgressCompletedSteps, 0);
        service.handleRxLogFrame(_echo());
        expect(latest['filtered']!.deliveryProgressCompletedSteps, 1);
      });

      test('a bound payload takes precedence over an unbound one-byte identity match', () async {
        await send('bound');
        service.handleRxLogFrame(_echo());
        expect(latest['bound']!.deliveryProgressCompletedSteps, 1);
        await send('unbound', contact: _contact(lastByte: 0xbc));
        service.handleRxLogFrame(_echo(remaining: 0));
        expect(latest['bound']!.deliveryProgressCompletedSteps, 2);
        expect(latest['unbound']!.deliveryProgressCompletedSteps, 0);
      });

      test('ambiguous one-byte identities stay unbound; removing one tracker permits progress', () async {
        await send('first');
        await send('second', contact: _contact(lastByte: 0xbc));
        final before = updates.length;
        service.handleRxLogFrame(_echo());
        expect(updates, hasLength(before));
        expect(latest['first']!.deliveryProgressCompletedSteps, 0);
        expect(latest['second']!.deliveryProgressCompletedSteps, 0);
        service.untrack('second');
        service.handleRxLogFrame(_echo());
        expect(latest['first']!.deliveryProgressCompletedSteps, 1);
        service.untrack('first');
        final afterCleanup = updates.length;
        service.handleRxLogFrame(_echo(remaining: 0));
        expect(updates, hasLength(afterCleanup));
        expect(service.hasPendingMessages, isFalse);
      });
    });
  }
}
