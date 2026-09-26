import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/direct_flood_repeats.dart';

const _self = 0x22;
final _t0 = DateTime(2026, 9, 26, 12);

DateTime _at(int seconds) => _t0.add(Duration(seconds: seconds));

/// A TXT_MSG payload: destination hash, source hash, then MAC and
/// ciphertext, which [seed] makes unique.
Uint8List _payload(int destination, int source, int seed) =>
    Uint8List.fromList([destination, source, seed, seed + 1, seed + 2]);

/// A copy heard after [hops] one-byte repeater hashes.
DirectFloodCopy _heard(int hops) => (
  pathBytes: Uint8List.fromList([for (var i = 0; i < hops; i++) 0xA0 + i]),
  pathHashWidth: 1,
  snr: -3.5,
  rssi: -95,
);

void main() {
  const a = (conversationKey: 'aa', messageId: 'A');
  const b = (conversationKey: 'bb', messageId: 'B');
  const c = (conversationKey: 'cc', messageId: 'C');

  void expectSend(
    DirectFloodRepeats repeats,
    DirectFloodTarget target, {
    int attempt = 0,
    String? identity,
    int at = 0,
  }) {
    repeats.expectOutgoing(
      target: target,
      destinationHash: 0x11,
      sourceHash: _self,
      identity: identity ?? '${target.conversationKey}:100',
      attempt: attempt,
      at: _at(at),
    );
  }

  group('outgoing', () {
    test('every relayed copy of the sent packet counts', () {
      final repeats = DirectFloodRepeats();
      expectSend(repeats, a);
      final packet = _payload(0x11, _self, 1);
      final first = repeats.observe(
        payload: packet,
        hopCount: 1,
        at: _at(1),
        copy: _heard(1),
      );
      expect(first?.target, a);
      expect(first?.currentAttempt, true);
      final second = repeats.observe(
        payload: packet,
        hopCount: 2,
        at: _at(2),
        copy: _heard(2),
      );
      expect(second?.target, a);
      expect(second?.currentAttempt, true);
      expect(
        repeats.observe(
          payload: _payload(0x11, _self, 9),
          hopCount: 1,
          at: _at(3),
          copy: _heard(1),
        ),
        isNull,
      );
    });

    test('a new attempt starts the count over', () {
      final repeats = DirectFloodRepeats();
      expectSend(repeats, a, attempt: 0);
      final firstPacket = _payload(0x11, _self, 1);
      repeats.observe(
        payload: firstPacket,
        hopCount: 1,
        at: _at(1),
        copy: _heard(1),
      );
      expectSend(repeats, a, attempt: 1, at: 30);
      // A late copy of the first attempt keeps its message but no longer
      // counts.
      final late = repeats.observe(
        payload: firstPacket,
        hopCount: 2,
        at: _at(31),
        copy: _heard(2),
      );
      expect(late?.target, a);
      expect(late?.currentAttempt, false);
      final retry = repeats.observe(
        payload: _payload(0x11, _self, 2),
        hopCount: 1,
        at: _at(32),
        copy: _heard(1),
      );
      expect(retry?.target, a);
      expect(retry?.currentAttempt, true);
    });

    test('a planned retry stops the count before it is sent', () {
      final repeats = DirectFloodRepeats();
      expectSend(repeats, a, attempt: 0);
      final firstPacket = _payload(0x11, _self, 1);
      repeats.observe(
        payload: firstPacket,
        hopCount: 1,
        at: _at(1),
        copy: _heard(1),
      );
      repeats.planAttempt(target: a, attempt: 1);
      final late = repeats.observe(
        payload: firstPacket,
        hopCount: 2,
        at: _at(20),
        copy: _heard(2),
      );
      expect(late?.target, a);
      expect(late?.currentAttempt, false);
      expectSend(repeats, a, attempt: 1, at: 30);
      final retry = repeats.observe(
        payload: _payload(0x11, _self, 2),
        hopCount: 1,
        at: _at(31),
        copy: _heard(1),
      );
      expect(retry?.currentAttempt, true);
    });

    test('a restart at attempt zero does not revive the first packet', () {
      final repeats = DirectFloodRepeats();
      expectSend(repeats, a, attempt: 0);
      final firstPacket = _payload(0x11, _self, 1);
      repeats.observe(
        payload: firstPacket,
        hopCount: 1,
        at: _at(1),
        copy: _heard(1),
      );
      repeats.planAttempt(target: a, attempt: 1);
      repeats.planAttempt(target: a, attempt: 0);
      final late = repeats.observe(
        payload: firstPacket,
        hopCount: 2,
        at: _at(40),
        copy: _heard(2),
      );
      expect(late?.currentAttempt, false);
    });

    test('a new attempt takes over an unanswered older expectation', () {
      final repeats = DirectFloodRepeats();
      expectSend(repeats, a, attempt: 0);
      expectSend(repeats, a, attempt: 1, at: 30);
      // Only one expectation is left, so the copy binds to the new attempt
      // rather than being refused as ambiguous or tagged as the old one.
      final hit = repeats.observe(
        payload: _payload(0x11, _self, 2),
        hopCount: 1,
        at: _at(31),
        copy: _heard(1),
      );
      expect(hit?.target, a);
      expect(hit?.currentAttempt, true);
    });

    test('two messages on one pair of hashes are refused', () {
      final repeats = DirectFloodRepeats();
      for (final target in [a, b]) {
        expectSend(repeats, target, identity: '${target.conversationKey}:1');
      }
      expect(
        repeats.observe(
          payload: _payload(0x11, _self, 1),
          hopCount: 1,
          at: _at(1),
          copy: _heard(1),
        ),
        isNull,
      );
    });

    test('a decrypted copy binds to the message it names', () {
      final repeats = DirectFloodRepeats();
      expectSend(repeats, a, identity: 'k:100');
      expectSend(repeats, b, identity: 'k:200');
      final hit = repeats.observe(
        payload: _payload(0x11, _self, 1),
        hopCount: 1,
        at: _at(1),
        copy: _heard(1),
        identity: 'k:200',
      );
      expect(hit?.target, b);
    });

    test('a decrypted copy of another attempt is refused', () {
      final repeats = DirectFloodRepeats();
      expectSend(repeats, a, identity: 'k:100', attempt: 1);
      expect(
        repeats.observe(
          payload: _payload(0x11, _self, 1),
          hopCount: 1,
          at: _at(1),
          copy: _heard(1),
          identity: 'k:100',
          attempt: 0,
        ),
        isNull,
      );
      final hit = repeats.observe(
        payload: _payload(0x11, _self, 2),
        hopCount: 1,
        at: _at(2),
        copy: _heard(1),
        identity: 'k:100',
        attempt: 1,
      );
      expect(hit?.target, a);
      expect(hit?.currentAttempt, true);
    });
  });

  group('incoming', () {
    test('counts the copies after the delivered one', () {
      final repeats = DirectFloodRepeats();
      final packet = _payload(_self, 0x33, 1);
      expect(
        repeats.observe(
          payload: packet,
          hopCount: 2,
          at: _at(0),
          copy: _heard(2),
        ),
        isNull,
      );
      repeats.observe(
        payload: packet,
        hopCount: 3,
        at: _at(1),
        copy: _heard(3),
      );
      expect(
        repeats
            .bindIncoming(
              target: c,
              sourceHash: 0x33,
              destinationHash: _self,
              hopCount: 2,
              identity: 'cc:5',
              at: _at(2),
            )
            ?.relays,
        1,
      );
      final later = repeats.observe(
        payload: packet,
        hopCount: 4,
        at: _at(3),
        copy: _heard(4),
      );
      expect(later?.target, c);
      expect(later?.currentAttempt, true);
    });

    test("the sender's retry becomes the attempt that counts", () {
      final repeats = DirectFloodRepeats();
      final first = _payload(_self, 0x33, 1);
      repeats.observe(payload: first, hopCount: 2, at: _at(0), copy: _heard(2));
      repeats.bindIncoming(
        target: c,
        sourceHash: 0x33,
        destinationHash: _self,
        hopCount: 2,
        identity: 'cc:5',
        at: _at(1),
      );
      final retry = _payload(_self, 0x33, 2);
      repeats.observe(payload: retry, hopCount: 2, at: _at(30), copy: _heard(2));
      final binding = repeats.bindIncoming(
        target: c,
        sourceHash: 0x33,
        destinationHash: _self,
        hopCount: 2,
        identity: 'cc:5',
        at: _at(31),
      );
      expect(binding?.relays, 0);
      final oldCopy = repeats.observe(
        payload: first,
        hopCount: 3,
        at: _at(32),
        copy: _heard(3),
      );
      expect(oldCopy?.currentAttempt, false);
      final retryCopy = repeats.observe(
        payload: retry,
        hopCount: 3,
        at: _at(33),
        copy: _heard(3),
      );
      expect(retryCopy?.currentAttempt, true);
    });

    test('hands back every copy heard, the delivered one first', () {
      final repeats = DirectFloodRepeats();
      final packet = _payload(_self, 0x33, 1);
      repeats.observe(
        payload: packet,
        hopCount: 2,
        at: _at(0),
        copy: _heard(2),
        transportCode: 0x1234,
      );
      repeats.observe(
        payload: packet,
        hopCount: 3,
        at: _at(1),
        copy: _heard(3),
      );
      final binding = repeats.bindIncoming(
        target: c,
        sourceHash: 0x33,
        destinationHash: _self,
        hopCount: 2,
        identity: 'cc:5',
        at: _at(2),
      );
      expect(binding?.transportCode, 0x1234);
      expect(binding?.payload, packet);
      expect(binding?.copies.length, 2);
      expect(binding?.copies.first.pathBytes, _heard(2).pathBytes);
      expect(binding?.copies.last.pathBytes, _heard(3).pathBytes);
      expect(binding?.copies.first.rssi, -95);
    });

    test('a plain flood copy carries no transport code', () {
      final repeats = DirectFloodRepeats();
      repeats.observe(
        payload: _payload(_self, 0x33, 9),
        hopCount: 2,
        at: _at(0),
        copy: _heard(2),
      );
      final binding = repeats.bindIncoming(
        target: c,
        sourceHash: 0x33,
        destinationHash: _self,
        hopCount: 2,
        identity: 'cc:5',
        at: _at(1),
      );
      expect(binding?.transportCode, isNull);
      expect(binding?.copies.length, 1);
    });

    test('binds the earliest packet with the reported hop count', () {
      final repeats = DirectFloodRepeats();
      repeats.observe(
        payload: _payload(_self, 0x33, 10),
        hopCount: 2,
        at: _at(0),
        copy: _heard(2),
      );
      final second = _payload(_self, 0x33, 20);
      repeats.observe(
        payload: second,
        hopCount: 2,
        at: _at(1),
        copy: _heard(2),
      );
      repeats.observe(
        payload: second,
        hopCount: 3,
        at: _at(2),
        copy: _heard(3),
      );
      int? bind(DirectFloodTarget target, int hops) => repeats
          .bindIncoming(
            target: target,
            sourceHash: 0x33,
            destinationHash: _self,
            hopCount: hops,
            identity: '${target.messageId}:1',
            at: _at(3),
          )
          ?.relays;
      expect(bind(a, 4), isNull);
      expect(bind(a, 2), 0);
      expect(bind(b, 2), 1);
      expect(bind(c, 2), isNull);
    });

    test('a decrypted copy binds by identity, not by order', () {
      final repeats = DirectFloodRepeats();
      repeats.observe(
        payload: _payload(_self, 0x33, 10),
        hopCount: 2,
        at: _at(0),
        copy: _heard(2),
        identity: 'p:1',
      );
      repeats.observe(
        payload: _payload(_self, 0x33, 20),
        hopCount: 2,
        at: _at(1),
        copy: _heard(2),
        identity: 'p:2',
      );
      expect(
        repeats
            .bindIncoming(
              target: b,
              sourceHash: 0x33,
              destinationHash: _self,
              hopCount: 2,
              identity: 'p:2',
              at: _at(2),
            )
            ?.relays,
        0,
      );
      expect(
        repeats.observe(
          payload: _payload(_self, 0x33, 10),
          hopCount: 3,
          at: _at(3),
          copy: _heard(3),
        ),
        isNull,
      );
    });
  });

  test('forgets packets and sends past their lifetimes', () {
    final repeats = DirectFloodRepeats();
    repeats.observe(
      payload: _payload(_self, 0x33, 1),
      hopCount: 2,
      at: _at(0),
      copy: _heard(2),
    );
    expect(
      repeats.bindIncoming(
        target: c,
        sourceHash: 0x33,
        destinationHash: _self,
        hopCount: 2,
        identity: 'x',
        at: _t0.add(const Duration(minutes: 11)),
      ),
      isNull,
    );
    repeats.expectOutgoing(
      target: a,
      destinationHash: 0x11,
      sourceHash: _self,
      identity: 'aa:1',
      attempt: 0,
      at: _t0.add(const Duration(minutes: 20)),
    );
    expect(
      repeats.observe(
        payload: _payload(0x11, _self, 5),
        hopCount: 1,
        at: _t0.add(const Duration(minutes: 23)),
        copy: _heard(1),
      ),
      isNull,
    );
  });
}
