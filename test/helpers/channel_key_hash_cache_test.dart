import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_key_hash_cache.dart';

void main() {
  test('Off computes every lookup; enabling, clearing and disabling discard snapshots', () {
    var calls = 0;
    final cache = ChannelKeyHashCache(compute: (key) {
      calls++;
      return crypto.sha256.convert(key).bytes[0];
    });
    final key = Uint8List.fromList(List<int>.generate(16, (i) => i * 7));
    final original = Uint8List.fromList(key);
    final expected = crypto.sha256.convert(key).bytes[0];
    expect(cache.hash(key), expected);
    expect(cache.hash(key), expected);
    expect(calls, 2);
    cache.setEnabled(true);
    expect(cache.hash(key), expected);
    cache.setEnabled(true); // Посторонние настройки не сбрасывают кэш.
    expect(cache.hash(key), expected);
    expect(calls, 3);
    cache.clear();
    expect(cache.hash(key), expected);
    expect(calls, 4);
    cache.setEnabled(false);
    expect(cache.hash(key), expected);
    expect(cache.hash(key), expected);
    expect(calls, 6);
    cache.setEnabled(true);
    expect(cache.hash(key), expected);
    expect(calls, 7);
    expect(key, orderedEquals(original));
  });

  test('mutable aliases invalidate snapshots and distinct objects stay independent', () {
    var calls = 0;
    final cache = ChannelKeyHashCache(compute: (key) {
      calls++;
      return crypto.sha256.convert(key).bytes[0];
    })..setEnabled(true);
    for (final length in [0, 16, 32]) {
      final key = Uint8List.fromList(List<int>.generate(length, (i) => i));
      var before = calls;
      expect(cache.hash(key), crypto.sha256.convert(key).bytes[0]);
      expect(cache.hash(key), crypto.sha256.convert(key).bytes[0]);
      expect(calls, before + 1);
      if (length > 0) {
        Uint8List.sublistView(key)[length - 1] ^= 0x80;
        expect(cache.hash(key), crypto.sha256.convert(key).bytes[0]);
        expect(cache.hash(key), crypto.sha256.convert(key).bytes[0]);
        expect(calls, before + 2);
      }
      before = calls;
      for (var i = 0; i < 3; i++) {
        expect(cache.hash(Uint8List.fromList(key)),
            crypto.sha256.convert(key).bytes[0]);
      }
      expect(calls, before + 3);
      expect(cache.hash(key), crypto.sha256.convert(key).bytes[0]);
      expect(calls, before + 3);
    }
  });

  test('failed computations are retried instead of populating a snapshot', () {
    var calls = 0;
    final cache = ChannelKeyHashCache(compute: (key) {
      if (++calls == 1) {
        throw StateError('synthetic failure');
      }
      return 42;
    })..setEnabled(true);
    final key = Uint8List(16);
    expect(() => cache.hash(key), throwsStateError);
    expect(cache.hash(key), 42);
    expect(cache.hash(key), 42);
    expect(calls, 2);
  });
}
