import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/radio_stats_send_polling.dart';

class _Polling {
  bool connected = true;
  bool pending = false;
  int owners = 0;
  int acquisitions = 0;
  late final policy = RadioStatsSendPolling(
    isConnected: () => connected,
    hasPendingWork: () => pending,
    acquire: () {
      owners++;
      acquisitions++;
    },
    release: () => owners--,
  );
}

void main() {
  test('off never acquires, enabling during preparation acquires once', () async {
    final polling = _Polling();
    addTearDown(polling.policy.dispose);
    final finish = Completer<void>();
    final operation = polling.policy.run(() => finish.future);
    expect(polling.policy.hasActiveOperations, isTrue);
    expect(polling.owners, 0);
    polling.policy.setEnabled(true);
    polling.policy.sync();
    expect(polling.owners, 1);
    expect(polling.acquisitions, 1);
    finish.complete();
    await operation;
    expect(polling.policy.hasActiveOperations, isFalse);
    expect(polling.owners, 0);
  });

  test('parallel preparations share ownership until both complete', () async {
    final polling = _Polling();
    polling.policy.setEnabled(true);
    addTearDown(polling.policy.dispose);
    final first = Completer<void>();
    final second = Completer<void>();
    final a = polling.policy.run(() => first.future);
    final b = polling.policy.run(() => second.future);
    expect(polling.owners, 1);
    expect(polling.acquisitions, 1);
    first.complete();
    await a;
    expect(polling.owners, 1);
    second.complete();
    await b;
    expect(polling.owners, 0);
  });

  test('queued work retains ownership after preparation and releases on cleanup',
      () async {
    final polling = _Polling();
    polling.policy.setEnabled(true);
    addTearDown(polling.policy.dispose);
    await polling.policy.run(() async {
      polling.pending = true;
    });
    expect(polling.owners, 1);
    expect(polling.policy.hasActiveOperations, isFalse);
    polling.pending = false;
    polling.policy.sync();
    expect(polling.owners, 0);
  });

  test('operation errors propagate and release their ownership', () async {
    final polling = _Polling();
    polling.policy.setEnabled(true);
    addTearDown(polling.policy.dispose);
    final failure = StateError('synthetic preparation failure');
    await expectLater(
      polling.policy.run(() async => throw failure),
      throwsA(same(failure)),
    );
    expect(polling.owners, 0);
    expect(polling.policy.hasActiveOperations, isFalse);
  });

  test('disconnect, reconnect and disabling balance the work owner', () {
    final polling = _Polling()..pending = true;
    addTearDown(polling.policy.dispose);
    polling.policy.setEnabled(true);
    expect(polling.owners, 1);
    polling.connected = false;
    polling.policy.sync();
    expect(polling.owners, 0);
    polling.connected = true;
    polling.policy.sync();
    expect(polling.owners, 1);
    polling.policy.setEnabled(false);
    expect(polling.owners, 0);
  });

  test('dispose releases once and late completion cannot acquire again',
      () async {
    final polling = _Polling();
    polling.policy.setEnabled(true);
    final finish = Completer<void>();
    final operation = polling.policy.run(() => finish.future);
    expect(polling.owners, 1);
    polling.policy.dispose();
    polling.policy.dispose();
    polling.pending = true;
    finish.complete();
    await operation;
    polling.policy.setEnabled(true);
    polling.policy.sync();
    expect(polling.owners, 0);
    expect(polling.acquisitions, 1);
  });
}
