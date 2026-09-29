import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/message_retry_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// How each attempt of a direct message goes out, pinned before automatic
// routing floods until the recipient returns a route and stops writing the
// node's own route back to it. What stays: a forced flood floods every
// attempt and clears the route the node holds first, a pinned route goes out
// on every attempt, the last included, and is never cleared, an attempt takes
// the contact as it is when the attempt starts (the route the node holds, a
// route the recipient returned meanwhile, a choice the user made meanwhile),
// and an acknowledgement of an earlier attempt credits that attempt's route.

const _sentAtSeconds = 1700000000;
final _selfKey = Uint8List.fromList(List<int>.generate(32, (i) => 0x40 + i));

Contact _contact({
  int pathLength = -1,
  List<int> path = const [],
  int? pathOverride,
  List<int>? pathOverrideBytes,
}) => Contact(
  publicKey: Uint8List.fromList(List<int>.generate(32, (i) => 0xAA + i)),
  name: 'Bob',
  type: advTypeChat,
  pathLength: pathLength,
  path: Uint8List.fromList(path),
  pathOverride: pathOverride,
  pathOverrideBytes: pathOverrideBytes == null
      ? null
      : Uint8List.fromList(pathOverrideBytes),
  lastSeen: DateTime.fromMillisecondsSinceEpoch(_sentAtSeconds * 1000),
);

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// The connector as the retry service sees it: the contact as the node holds
/// it, which writing or clearing a route changes, and what reached the node,
/// in order.
class _Node {
  _Node(this.contact);

  Contact contact;
  final log = <String>[];
  final credits = <String>[];
  final messages = <String, Message>{};

  /// The recipient's answer to a flood left [route] on the node, and the app
  /// read it back (PUSH_CODE_PATH_UPDATED, then the contact re-read).
  void returnRoute(List<int> route) {
    contact = contact.copyWith(
      pathLength: route.length,
      path: Uint8List.fromList(route),
    );
  }

  Message message(String text) =>
      messages.values.singleWhere((m) => m.text == text);
}

MessageRetryService _serviceFor(_Node node, {AppSettingsService? settings}) {
  final service = MessageRetryService()..retryBackoffMs = (_) => 0;
  service.initialize(
    RetryServiceConfig(
      sendMessage: (_, _, attempt, _, {required useFlood}) async {
        node.log.add('send $attempt ${useFlood ? 'flood' : 'route'}');
        return DateTime.now();
      },
      addMessage: (_, m) => node.messages[m.messageId] = m,
      updateMessage: (m) => node.messages[m.messageId] = m,
      clearContactPath: (_) {
        node.log.add('clear');
        node.contact = node.contact.copyWith(
          pathLength: -1,
          path: Uint8List(0),
        );
      },
      setContactPath: (_, path, hops) {
        node.log.add('set ${_hex(path)}');
        node.contact = node.contact.copyWith(pathLength: hops, path: path);
      },
      findContact: (_) => node.contact,
      getSelfPublicKey: () => _selfKey,
      appSettingsService: settings,
      recordPathResult: (_, selection, success, _) => node.credits.add(
        '${success ? 'worked' : 'failed'} '
        '${selection.useFlood ? 'flood' : _hex(selection.pathBytes)}',
      ),
    ),
  );
  return service;
}

/// Sends [text] to the node's contact and lets its first attempt go out.
Future<void> _send(MessageRetryService service, _Node node, String text) async {
  await service.sendMessageWithRetry(
    contact: node.contact,
    text: text,
    timestamp: DateTime.fromMillisecondsSinceEpoch(_sentAtSeconds * 1000),
  );
  await pumpEventQueue();
}

int _ackHash(String text, int attempt) =>
    MessageRetryService.computeExpectedAckHash(
      _sentAtSeconds,
      attempt,
      text,
      _selfKey,
    );

/// The node took attempt [attempt] of [text] (RESP_CODE_SENT) and no
/// acknowledgement came back in time, so the retry goes out.
Future<void> _noAck(
  MessageRetryService service,
  String text,
  int attempt,
) async {
  expect(service.updateMessageFromSent(_ackHash(text, attempt), 1), isTrue);
  await Future<void>.delayed(const Duration(milliseconds: 10));
  await pumpEventQueue();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a forced flood', () {
    test('floods every attempt and clears the route the node holds first, '
        'one the recipient returned included', () async {
      final node = _Node(
        _contact(pathLength: 1, path: [0x10], pathOverride: -1),
      );
      final service = _serviceFor(node);
      addTearDown(service.dispose);

      await _send(service, node, 'hi');
      node.returnRoute([0x33]);
      await _noAck(service, 'hi', 0);

      expect(node.log, ['clear', 'send 0 flood', 'clear', 'send 1 flood']);
    });
  });

  group('a pinned route', () {
    test('goes out on every attempt, the last included, and is never '
        'cleared', () async {
      final node = _Node(
        _contact(
          pathLength: 1,
          path: [0x10],
          pathOverride: 1,
          pathOverrideBytes: [0x42],
        ),
      );
      final service = _serviceFor(node)..setMaxRetries(2);
      addTearDown(service.dispose);

      await _send(service, node, 'hi');
      await _noAck(service, 'hi', 0);

      expect(node.log, ['set 42', 'send 0 route', 'set 42', 'send 1 route']);
    });

    test('outlives the last failure with clearing on the last failure '
        'switched on', () async {
      SharedPreferences.setMockInitialValues({});
      PrefsManager.reset();
      await PrefsManager.initialize();
      final settings = AppSettingsService();
      addTearDown(settings.dispose);
      await settings.setClearPathOnMaxRetry(true);

      final node = _Node(_contact(pathOverride: 1, pathOverrideBytes: [0x42]));
      final service = _serviceFor(node, settings: settings)..setMaxRetries(2);
      addTearDown(service.dispose);

      await _send(service, node, 'hi');
      await _noAck(service, 'hi', 0);
      await _noAck(service, 'hi', 1);

      expect(node.message('hi').status, MessageStatus.failed);
      expect(node.log, isNot(contains('clear')));
    });
  });

  group('automatic routing', () {
    test('the first attempt goes by the route the node holds', () async {
      final node = _Node(_contact(pathLength: 2, path: [0x10, 0x20]));
      final service = _serviceFor(node);
      addTearDown(service.dispose);

      await _send(service, node, 'hi');

      expect(node.log.last, 'send 0 route');
      expect(node.message('hi').pathBytes, [0x10, 0x20]);
    });

    test('with no route the first attempt floods, and a route the recipient '
        'returned meanwhile is the next attempt\'s', () async {
      final node = _Node(_contact());
      final service = _serviceFor(node);
      addTearDown(service.dispose);

      await _send(service, node, 'hi');
      expect(node.log.last, 'send 0 flood');

      node.returnRoute([0x33]);
      await _noAck(service, 'hi', 0);

      expect(node.log.last, 'send 1 route');
      expect(node.message('hi').pathBytes, [0x33]);
    });

    test('a route pinned while an attempt waits is the next '
        'attempt\'s', () async {
      final node = _Node(_contact(pathLength: 1, path: [0x10]));
      final service = _serviceFor(node);
      addTearDown(service.dispose);

      await _send(service, node, 'hi');
      node.contact = node.contact.copyWith(
        pathOverride: 1,
        pathOverrideBytes: Uint8List.fromList([0x42]),
      );
      await _noAck(service, 'hi', 0);

      expect(node.log.sublist(node.log.length - 2), ['set 42', 'send 1 route']);
    });

    test('a flood forced while an attempt waits is the next '
        'attempt\'s', () async {
      final node = _Node(_contact(pathLength: 1, path: [0x10]));
      final service = _serviceFor(node);
      addTearDown(service.dispose);

      await _send(service, node, 'hi');
      node.contact = node.contact.copyWith(pathOverride: -1);
      await _noAck(service, 'hi', 0);

      expect(node.log.sublist(node.log.length - 2), ['clear', 'send 1 flood']);
    });
  });

  test('an acknowledgement of the first attempt, arriving after the retry '
      'went out, delivers the message and credits the first attempt\'s '
      'route', () async {
    final node = _Node(_contact(pathLength: 1, path: [0x10]));
    final service = _serviceFor(node);
    addTearDown(service.dispose);

    await _send(service, node, 'hi');
    await _noAck(service, 'hi', 0);
    service.handleAckReceived(_ackHash('hi', 0), 1200);
    await pumpEventQueue();

    expect(node.message('hi').status, MessageStatus.delivered);
    expect(node.credits, ['failed 10', 'worked 10']);
  });
}
