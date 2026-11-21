import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/aeic_chunk_resends.dart';

void main() {
  test('coverage is per exact channel and packet, including parity', () {
    final tracker = AeicChunkResends();
    final blob = Uint8List.fromList([1, 2, 3]);
    final data = tracker.track(0, blob, selfKey: Uint8List.fromList([0xAA, 0xAA]));
    final parity = tracker.track(0, Uint8List.fromList([1, 2, 4]));
    final otherChannel = tracker.track(1, blob);
    void echo(List<int> path, {int width = 2}) => tracker.heard(0, blob,
      pathBytes: Uint8List.fromList(path), hopCount: path.length ~/ width,
      hashWidth: width);
    echo([0xAA, 0xAA]); // our own prefix is not a nearby repeater
    echo([0x10, 0x20]);
    echo([0x10, 0x20]); // repeated reception is still one repeater
    expect(data.distinctRepeaters, 1);
    expect(data.satisfied(minHops: 3, countRepeaters: true, minRepeaters: 2), isFalse);
    echo([0x10, 0x21]); // full two-byte prefix is significant
    expect(data.satisfied(minHops: 3, countRepeaters: true, minRepeaters: 2), isTrue);
    expect(data.satisfied(minHops: 3, countRepeaters: false, minRepeaters: 2), isFalse);
    echo([0x10, 0x20, 0x30, 0x40, 0x50, 0x60]);
    expect(data.maxHops, 3);
    expect(data.satisfied(minHops: 3, countRepeaters: false, minRepeaters: 2), isTrue);
    expect(parity.maxHops, 0);
    expect(otherChannel.maxHops, 0);
    tracker.cancelAll();
  });

  for (final width in [1, 2, 3]) {
    test('validates path geometry for $width-byte hashes', () {
      final tracker = AeicChunkResends();
      final blob = Uint8List.fromList([7]);
      final packet = tracker.track(0, blob);
      tracker.heard(0, blob, pathBytes: Uint8List(width), hopCount: 2, hashWidth: width);
      expect(packet.maxHops, 0);
      tracker.heard(0, blob, pathBytes: Uint8List(width * 2), hopCount: 2, hashWidth: width);
      expect(packet.maxHops, 2);
      tracker.cancelAll();
    });
  }

  testWidgets('only insufficient chunks retry, unchanged, up to the limit', (tester) async {
    final tracker = AeicChunkResends();
    final data = tracker.track(0, Uint8List.fromList([1, 2]));
    final parity = tracker.track(0, Uint8List.fromList([3, 4]));
    final retries = <List<int>>[];
    Future<void> watch(AeicChunkResend packet) => packet.watch(
      maxResends: 2,
      delay: () => const Duration(seconds: 3),
      now: tester.binding.clock.now,
      canContinue: () => true,
      isSatisfied: () => packet.satisfied(minHops: 2, countRepeaters: false, minRepeaters: 2),
      resend: (_) async { retries.add(List<int>.of(packet.blob)); },
    );
    final running = Future.wait([watch(data), watch(parity)]);
    tracker.heard(0, data.blob, pathBytes: Uint8List.fromList([1, 2]), hopCount: 2, hashWidth: 1);
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 3));
    }
    await running;
    expect(retries, [[3, 4], [3, 4]]);
    tracker.cancelAll();
  });

  testWidgets('insufficient echoes retain the deadline; enough echoes wake immediately', (tester) async {
    final tracker = AeicChunkResends();
    final packet = tracker.track(0, Uint8List.fromList([1]));
    var resends = 0;
    var finished = false;
    final running = packet.watch(
      maxResends: 2,
      delay: () => const Duration(seconds: 10),
      now: tester.binding.clock.now,
      canContinue: () => true,
      isSatisfied: () => packet.satisfied(minHops: 3, countRepeaters: true, minRepeaters: 2),
      resend: (_) async { resends++; },
    ).then((_) { finished = true; });
    await tester.pump(const Duration(seconds: 6));
    tracker.heard(0, packet.blob, pathBytes: Uint8List.fromList([0x11]), hopCount: 1, hashWidth: 1);
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(resends, 1);
    tracker.heard(0, packet.blob, pathBytes: Uint8List.fromList([0x22]), hopCount: 1, hashWidth: 1);
    await tester.pump();
    expect(finished, isTrue);
    await running;
    tracker.cancelAll();
  });

  testWidgets('disconnect cancellation wakes waits without a late resend', (tester) async {
    final tracker = AeicChunkResends();
    final packet = tracker.track(0, Uint8List.fromList([1]));
    var resends = 0;
    final running = packet.watch(
      maxResends: 2,
      delay: () => const Duration(seconds: 30),
      now: tester.binding.clock.now,
      canContinue: () => true,
      isSatisfied: () => false,
      resend: (_) async { resends++; },
    );
    tracker.cancelAll();
    await tester.pump();
    await running;
    expect(resends, 0);
    expect(packet.cancelled, isTrue);
  });
}
