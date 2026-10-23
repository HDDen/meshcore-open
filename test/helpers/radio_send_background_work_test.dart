import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/helpers/radio_send_background_work.dart';
import 'package:meshcore_open/helpers/radio_stats_send_polling.dart';

class _SendWork {
  final tracker = BackgroundWorkTracker();
  bool connected = true;
  bool pending = false;
  int owners = 0;
  int acquisitions = 0;
  late final polling = RadioStatsSendPolling(
    isConnected: () => connected,
    hasPendingWork: () => pending,
    acquire: () {
      owners++;
      acquisitions++;
    },
    release: () => owners--,
  );
  late final work = RadioSendBackgroundWork(tracker, polling);
}

void main() {
  test('send is tracked while polling is Off and enabling keeps the same send', () async {
    final h = _SendWork();
    addTearDown(h.polling.dispose);
    final completion = Completer<void>();
    final operation = h.work.run(() => completion.future);
    expect(h.tracker.snapshot.countFor(BackgroundWorkKind.radioSend), 1);
    expect(h.tracker.activeCount, 1);
    expect(h.polling.hasActiveOperations, isTrue);
    expect(h.owners, 0);
    final revision = h.tracker.revision;
    h.polling.setEnabled(true);
    expect(h.owners, 1);
    expect(h.tracker.revision, revision);
    h.polling.setEnabled(false);
    expect(h.owners, 0);
    expect(h.tracker.activeCount, 1);
    completion.complete();
    await operation;
    expect(h.tracker.isBusy, isFalse);
    expect(h.polling.hasActiveOperations, isFalse);
  });

  test('parallel sends have separate leases and share one polling owner', () async {
    final h = _SendWork();
    addTearDown(h.polling.dispose);
    h.polling.setEnabled(true);
    final first = Completer<void>();
    final second = Completer<void>();
    final a = h.work.run(() => first.future);
    final b = h.work.run(() => second.future);
    final snapshot = h.tracker.snapshot;
    expect(snapshot.countFor(BackgroundWorkKind.radioSend), 2);
    expect(h.owners, 1);
    expect(h.acquisitions, 1);
    first.complete();
    await a;
    expect(h.tracker.activeCount, 1);
    expect(h.owners, 1);
    second.complete();
    await b;
    expect(h.tracker.isBusy, isFalse);
    expect(h.owners, 0);
    expect(snapshot.activeCount, 2);
  });

  test('synchronous operation error preserves identity and releases both owners', () async {
    final h = _SendWork();
    addTearDown(h.polling.dispose);
    h.polling.setEnabled(true);
    final failure = StateError('synthetic send failure');
    await expectLater(h.work.run(() => throw failure), throwsA(same(failure)));
    expect(h.tracker.isBusy, isFalse);
    expect(h.polling.hasActiveOperations, isFalse);
    expect(h.owners, 0);
  });

  test('asynchronous operation error preserves identity and releases both owners', () async {
    final h = _SendWork();
    addTearDown(h.polling.dispose);
    h.polling.setEnabled(true);
    final completion = Completer<void>();
    final failure = StateError('synthetic async send failure');
    final checked = expectLater(
      h.work.run(() => completion.future),
      throwsA(same(failure)),
    );
    completion.completeError(failure);
    await checked;
    expect(h.tracker.isBusy, isFalse);
    expect(h.polling.hasActiveOperations, isFalse);
    expect(h.owners, 0);
  });

  test('pending polling work outlives the completed active send', () async {
    final h = _SendWork();
    addTearDown(h.polling.dispose);
    h.polling.setEnabled(true);
    await h.work.run(() async {
      h.pending = true;
    });
    expect(h.tracker.isBusy, isFalse);
    expect(h.polling.hasActiveOperations, isFalse);
    expect(h.owners, 1);
    h.pending = false;
    h.polling.sync();
    expect(h.owners, 0);
  });

  test('close and polling dispose retain actual work and late calls add no lease', () async {
    final h = _SendWork();
    h.polling.setEnabled(true);
    final completion = Completer<void>();
    final operation = h.work.run(() => completion.future);
    h.tracker.close();
    h.polling.dispose();
    expect(h.owners, 0);
    expect(h.tracker.activeCount, 1);
    final revision = h.tracker.revision;
    var called = false;
    await h.work.run(() async {
      called = true;
    });
    expect(called, isTrue);
    expect(h.tracker.revision, revision);
    expect(h.tracker.activeCount, 1);
    completion.complete();
    await operation;
    expect(h.tracker.isBusy, isFalse);
    expect(h.owners, 0);
    expect(h.acquisitions, 1);
  });
}
