import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/services/message_retry_service.dart';

Contact _contact() => Contact(
  publicKey: Uint8List.fromList(List<int>.generate(32, (i) => 0xAA + i)),
  name: 'Test',
  type: 1,
  pathLength: -1,
  path: Uint8List(0),
  lastSeen: DateTime.now(),
);

void main() {
  late MessageRetryService service;
  late Map<String, Message> latest;
  late List<String> sentTexts;
  late bool failSends;
  late bool pauseOnFailure;
  Uint8List? selfKey;

  setUp(() {
    service = MessageRetryService();
    latest = {};
    sentTexts = [];
    failSends = false;
    pauseOnFailure = false;
    selfKey = Uint8List(32);
    service.initialize(
      RetryServiceConfig(
        sendMessage: (_, text, _, _, {required useFlood}) async {
          if (failSends) {
            // The connector pauses sending before the dropped link fails
            // the write.
            if (pauseOnFailure) service.setSendingPaused(true);
            throw StateError('Not connected');
          }
          sentTexts.add(text);
          return DateTime.now();
        },
        addMessage: (_, m) => latest[m.messageId] = m,
        updateMessage: (m) => latest[m.messageId] = m,
        getSelfPublicKey: () => selfKey,
      ),
    );
  });

  tearDown(() => service.dispose());

  Message byText(String text) =>
      latest.values.firstWhere((m) => m.text == text);

  test('failed send fails the message and frees the contact slot', () async {
    failSends = true;
    final contact = _contact();
    await service.sendMessageWithRetry(contact: contact, text: 'a');
    await pumpEventQueue();
    expect(byText('a').status, MessageStatus.failed);

    failSends = false;
    await service.sendMessageWithRetry(contact: contact, text: 'b');
    await pumpEventQueue();
    expect(sentTexts, ['b']);
  });

  test('unknown self key fails instead of waiting forever', () async {
    selfKey = null;
    await service.sendMessageWithRetry(contact: _contact(), text: 'a');
    await pumpEventQueue();
    expect(byText('a').status, MessageStatus.failed);
    expect(sentTexts, isEmpty);
    expect(service.hasPendingMessages, isFalse);
  });

  test('a send cut short by a dropped link waits for the resume', () async {
    failSends = true;
    pauseOnFailure = true;
    await service.sendMessageWithRetry(contact: _contact(), text: 'a');
    await pumpEventQueue();
    expect(byText('a').status, MessageStatus.pending);
    expect(service.hasPendingMessages, isTrue);

    failSends = false;
    service.setSendingPaused(false);
    await pumpEventQueue();
    expect(sentTexts, ['a']);
  });
}
