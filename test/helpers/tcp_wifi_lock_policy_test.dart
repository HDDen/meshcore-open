import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/tcp_wifi_lock_policy.dart';

void main() {
  const timeout = Timeout(Duration(seconds: 10));

  test('default policy preserves explicit transport acquire and release', () async {
    final calls = <bool>[];
    final policy = TcpWifiLockPolicy(apply: (value) async { calls.add(value); });

    await policy.request(true);
    await policy.request(false);

    expect(calls, [true, false]);
  }, timeout: timeout);

  test('power saving releases an active demand and original restores it', () async {
    final calls = <bool>[];
    final policy = TcpWifiLockPolicy(apply: (value) async { calls.add(value); });

    await policy.request(true);
    await policy.setReleaseAllowed(true);
    await policy.request(true); // Recovery сохраняет demand, но не lock.
    await policy.setReleaseAllowed(false);
    await policy.request(false);

    expect(calls, [true, false, false, true, false]);
  }, timeout: timeout);

  test('changing settings without a transport never acquires a lock', () async {
    final calls = <bool>[];
    final policy = TcpWifiLockPolicy(apply: (value) async { calls.add(value); });

    await policy.setReleaseAllowed(false);
    expect(calls, isEmpty);
    await policy.setReleaseAllowed(true);
    await policy.setReleaseAllowed(true);
    await policy.setReleaseAllowed(false);

    expect(calls, [false, false]);
  }, timeout: timeout);

  test('disconnect while power saving is active prevents a later acquire', () async {
    final calls = <bool>[];
    final policy = TcpWifiLockPolicy(apply: (value) async { calls.add(value); });

    await policy.setReleaseAllowed(true);
    await policy.request(true);
    await policy.request(false);
    await policy.setReleaseAllowed(false);

    expect(calls, [false, false, false, false]);
  }, timeout: timeout);

  test('a late acquire reply cannot undo the newer release', () async {
    final entered = Completer<void>();
    final reply = Completer<void>();
    addTearDown(() {
      if (!reply.isCompleted) {
        reply.complete();
      }
    });
    final calls = <bool>[];
    var held = false;
    final policy = TcpWifiLockPolicy(apply: (value) async {
      calls.add(value);
      if (value) {
        entered.complete();
        await reply.future;
      }
      held = value;
    });

    final acquiring = policy.request(true);
    await entered.future;
    final releasing = policy.setReleaseAllowed(true);
    try {
      await Future<void>.value();
      expect(calls, [true]);
      reply.complete();
      await Future.wait([acquiring, releasing]);

      expect(calls, [true, false]);
      expect(held, isFalse);
    } finally {
      if (!reply.isCompleted) {
        reply.complete();
      }
      await Future.wait([acquiring, releasing]);
    }
  }, timeout: timeout);

  test('rapid changes keep command order and finish with transport release', () async {
    final calls = <bool>[];
    final policy = TcpWifiLockPolicy(apply: (value) async { calls.add(value); });

    await Future.wait([
      policy.request(true),
      policy.setReleaseAllowed(true),
      policy.setReleaseAllowed(false),
      policy.request(false),
    ]);

    expect(calls, [true, false, true, false]);
  }, timeout: timeout);

  test('one rejected command does not poison subsequent commands', () async {
    final calls = <bool>[];
    final policy = TcpWifiLockPolicy(apply: (value) async {
      calls.add(value);
      if (value) {
        throw StateError('synthetic acquire failure');
      }
    });

    await expectLater(policy.request(true), throwsStateError);
    await policy.request(false);

    expect(calls, [true, false]);
  }, timeout: timeout);
}
