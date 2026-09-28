import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/heard_channel_packets.dart';

// The map of heard channel packets on its own: what makes two copies one
// packet, how a copy waits for the first copy's outcome, the claim a copy
// holds while it is processed, and how entries leave, by lifetime, by the
// cap and by a clear.

void main() {
  group('keys', () {
    test('a text key follows the channel, the packet timestamp, the sender '
        'and the raw text', () {
      String key({
        int channelIndex = 0,
        int timestampSeconds = 1700000000,
        String senderName = 'Alice',
        String rawText = 'mcmp2:abc',
      }) => HeardChannelPackets.textKey(
        channelIndex: channelIndex,
        timestampSeconds: timestampSeconds,
        senderName: senderName,
        rawText: rawText,
      );

      expect(key(), key());
      expect(key(), startsWith('t:'));
      expect(key(), isNot(key(channelIndex: 1)));
      expect(key(), isNot(key(timestampSeconds: 1700000001)));
      expect(key(), isNot(key(senderName: 'Bob')));
      expect(key(), isNot(key(rawText: 'mcmp2:abd')));
      // The raw text, not the decoded one: a compressed and a plain copy of
      // the same words are different packets.
      expect(key(rawText: 'hello'), isNot(key(rawText: 'mcmp2:hello')));
    });

  });

  group('claims', () {
    test('a packet not heard before is claimed, and the copy that follows '
        'waits for its outcome', () async {
      final heard = HeardChannelPackets();

      expect(heard.claim('k'), isNull);
      expect(heard.pendingCount, 1);
      final waiting = heard.claim('k');
      expect(waiting, isNotNull);
      var resolved = false;
      final outcome = waiting!.then((value) {
        resolved = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(resolved, isFalse);

      heard.settle('k', const HeardAsMessage('m1'));

      expect(
        await outcome,
        isA<HeardAsMessage>().having((o) => o.messageId, 'messageId', 'm1'),
      );
      expect(heard.pendingCount, 0);
    });

    test('a settled packet answers at once', () async {
      final heard = HeardChannelPackets();
      expect(heard.claim('k'), isNull);
      heard.settle('k', const HeardAsReaction());

      expect(await heard.claim('k'), isA<HeardAsReaction>());
      expect(heard.length, 1);
    });

    test('an abandoned claim frees the key and releases the waiting copy '
        'with nothing', () async {
      final heard = HeardChannelPackets();
      expect(heard.claim('k'), isNull);
      final waiting = heard.claim('k')!;

      heard.abandon('k');

      expect(await waiting, isNull);
      expect(heard.length, 0);
      expect(heard.claim('k'), isNull, reason: 'the key is free again');
    });

    test('a copy stops waiting after the processing timeout, and the claim '
        'stands', () async {
      final heard = HeardChannelPackets(
        processingTimeout: const Duration(milliseconds: 20),
      );
      expect(heard.claim('k'), isNull);

      expect(await heard.claim('k'), isNull);
      expect(heard.pendingCount, 1);

      // The first copy settles late; the next copy still gets the outcome.
      heard.settle('k', const HeardAsMessage('late'));
      expect(
        await heard.claim('k'),
        isA<HeardAsMessage>().having((o) => o.messageId, 'messageId', 'late'),
      );
    });

    test('a packet recorded at the send is a copy from its first echo on', () async {
      final heard = HeardChannelPackets();
      heard.record('k', const HeardAsMessage('sent'));

      expect(
        await heard.claim('k'),
        isA<HeardAsMessage>().having((o) => o.messageId, 'messageId', 'sent'),
      );
    });

    test('settling a key that was never claimed records it', () async {
      final heard = HeardChannelPackets();
      heard.settle('k', const HeardAsMessage('m'));

      expect(await heard.claim('k'), isA<HeardAsMessage>());
    });

    test('a held claim settles once and is abandoned only while open', () async {
      final heard = HeardChannelPackets();
      expect(heard.claim('k'), isNull);
      final claim = HeardChannelClaim(heard, 'k');
      expect(claim.isOpen, isTrue);

      claim.settle(const HeardAsMessage('first'));
      claim.settle(const HeardAsMessage('second'));
      claim.abandonIfOpen();

      expect(claim.isOpen, isFalse);
      expect(
        await heard.claim('k'),
        isA<HeardAsMessage>().having((o) => o.messageId, 'messageId', 'first'),
      );
    });

    test('a held claim left open is abandoned and frees the key', () async {
      final heard = HeardChannelPackets();
      expect(heard.claim('k'), isNull);
      final waiting = heard.claim('k')!;
      final claim = HeardChannelClaim(heard, 'k');

      claim.abandonIfOpen();

      expect(claim.isOpen, isFalse);
      expect(await waiting, isNull);
      expect(heard.claim('k'), isNull);
    });
  });

  group('lifetime', () {
    test('an entry older than the lifetime is forgotten and its key claimed '
        'anew', () {
      final heard = HeardChannelPackets(ttl: const Duration(minutes: 10));
      final t0 = DateTime(2026, 1, 1, 12);
      expect(heard.claim('k', now: t0), isNull);
      heard.settle('k', const HeardAsMessage('m'));

      expect(
        heard.claim('k', now: t0.add(const Duration(minutes: 9, seconds: 59))),
        isNotNull,
      );
      expect(
        heard.claim('k', now: t0.add(const Duration(minutes: 10, seconds: 1))),
        isNull,
      );
      expect(heard.length, 1);
      expect(heard.pendingCount, 1);
    });

    test('a claim older than the lifetime is released with nothing', () async {
      final heard = HeardChannelPackets(ttl: const Duration(minutes: 10));
      final t0 = DateTime(2026, 1, 1, 12);
      expect(heard.claim('k', now: t0), isNull);
      final waiting = heard.claim('k', now: t0)!;

      expect(
        heard.claim('other', now: t0.add(const Duration(minutes: 11))),
        isNull,
      );

      expect(await waiting, isNull);
      expect(heard.length, 1);
    });

    test('the oldest entries go when the map is full', () {
      final heard = HeardChannelPackets(maxEntries: 3);
      for (var i = 0; i < 4; i++) {
        expect(heard.claim('k$i'), isNull);
        heard.settle('k$i', HeardAsMessage('m$i'));
      }

      expect(heard.length, 3);
      expect(heard.claim('k0'), isNull, reason: 'forgotten, so claimed anew');
      expect(heard.claim('k3'), isNotNull);
    });

    test('clearing releases every waiting copy with nothing', () async {
      final heard = HeardChannelPackets();
      expect(heard.claim('k'), isNull);
      final waiting = heard.claim('k')!;

      heard.clear();

      expect(await waiting, isNull);
      expect(heard.length, 0);
      expect(heard.claim('k'), isNull);
    });
  });
}
