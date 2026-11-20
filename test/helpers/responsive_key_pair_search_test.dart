import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/utils/keys.dart';
import 'package:meshcore_open/helpers/key_search_executor.dart';
import 'package:meshcore_open/helpers/meshcore_expanded_identity.dart';
import 'package:convert/convert.dart';

MCKeyPair _pair(int first, [int second = 0]) {
  final public = Uint8List(32);
  public[0] = first;
  public[1] = second;
  return MCKeyPair(public, Uint8List(64));
}

void main() {
  test('native cancellation stops a batch and permits a fresh worker', () async {
    final searcher = KeyPairSearcher();
    // Longer than any public key, so this cannot match by chance.
    final impossiblePrefix = List.filled(33, 'ab').join();
    final pending = searcher.findMatchingKeyPair(impossiblePrefix, 60000);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    searcher.cancel();
    expect(await pending.timeout(const Duration(seconds: 2)), isNull);
    final next = await searcher.findMatchingKeyPair('', 1000).timeout(const Duration(seconds: 5));
    expect(next, isNotNull);
    searcher.cancel();
  }, skip: !supportsKeySearchIsolates);

  test('native cancellation during spawn also completes without a late result', () async {
    final searcher = KeyPairSearcher();
    final pending = searcher.findMatchingKeyPair(List.filled(33, 'ab').join(), 60000);
    searcher.cancel();
    expect(await pending.timeout(const Duration(seconds: 2)), isNull);
    expect(await searcher.findMatchingKeyPair('', 1000).timeout(const Duration(seconds: 5)), isNotNull);
    searcher.cancel();
  }, skip: !supportsKeySearchIsolates);

  test('cooperative cancellation stops generating and restart is independent', () async {
    late KeyPairSearcher searcher;
    var generated = 0;
    var requested = false;
    searcher = KeyPairSearcher(generatePair: () {
      generated++;
      if (!requested) {
        requested = true;
        Timer.run(searcher.cancel);
      }
      return Future.value(_pair(0x12));
    });
    expect(await searcher.findMatchingKeyPair('abcd', 60000)
        .timeout(const Duration(seconds: 2)), isNull);
    final stoppedAt = generated;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(generated, stoppedAt);
    expect(await searcher.findMatchingKeyPair('12', 1000), isNotNull);
  });

  test('real generated expanded keys retain the matching public key', () async {
    final pair = await KeyPairSearcher().findMatchingKeyPair('', 1000);
    expect(pair, isNotNull);
    expect(pair!.private, hasLength(64));
    expect(pair.public, hasLength(32));
    final identity = await MeshCoreExpandedIdentity.fromHex(hex.encode(pair.private));
    expect(identity.publicKey, orderedEquals(pair.public));
  });

  test('microtask-only generation services input events before its budget expires', () async {
    var eventDelivered = false;
    var scheduled = false;
    var generated = 0;
    final miss = _pair(0x12);
    final match = _pair(0xAB, 0xC7);
    final searcher = KeyPairSearcher(generatePair: () {
      generated++;
      if (!scheduled) {
        scheduled = true;
        // Represents an input/timer event arriving after search has begun.
        Timer.run(() { eventDelivered = true; });
      }
      return Future.value(eventDelivered ? match : miss);
    });
    final result = await searcher.findMatchingKeyPair('ABc', 1000);
    expect(eventDelivered, isTrue);
    expect(generated, greaterThan(1));
    expect(result, same(match));
  });

  test('full-byte, nibble and empty prefixes retain their matching behavior', () async {
    for (final prefix in ['', 'A', 'aB', 'ABc', 'abc7']) {
      final candidate = _pair(0xAB, 0xC7);
      final searcher = KeyPairSearcher(generatePair: () => Future.value(candidate));
      expect(await searcher.findMatchingKeyPair(prefix, 1000), same(candidate));
    }
  });

  test('a finite unsuccessful chunk returns null without starving events', () async {
    var eventDelivered = false;
    var scheduled = false;
    final searcher = KeyPairSearcher(generatePair: () {
      if (!scheduled) {
        scheduled = true;
        Timer.run(() { eventDelivered = true; });
      }
      return Future.value(_pair(0x12));
    });
    expect(await searcher.findMatchingKeyPair('abcd', 40), isNull);
    expect(eventDelivered, isTrue);
  });

  test('an exhausted budget never generates a key', () async {
    var generated = 0;
    final searcher = KeyPairSearcher(generatePair: () {
      generated++;
      return Future.value(_pair(0x12));
    });
    for (final budget in [0, -1]) {
      expect(await searcher.findMatchingKeyPair('abcd', budget), isNull);
    }
    expect(generated, 0);
  });
}
