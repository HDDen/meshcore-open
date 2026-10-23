import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/helpers/outgoing_queue_background_work.dart';

void main() {
  test('nested retry and send retain separate scopes until their Future completes', () async {
    final tracker = BackgroundWorkTracker();
    final work = OutgoingQueueBackgroundWork(tracker);
    final completion = Completer<void>();
    final operation = work.runRetry(() => work.runSend(() => completion.future));
    expect(tracker.snapshot.countFor(BackgroundWorkKind.retry), 1);
    expect(tracker.snapshot.countFor(BackgroundWorkKind.radioSend), 1);
    completion.complete();
    await operation;
    expect(tracker.isBusy, isFalse);
  });

  test('parallel operations release their own holds', () async {
    final tracker = BackgroundWorkTracker();
    final work = OutgoingQueueBackgroundWork(tracker);
    final first = Completer<void>();
    final second = Completer<void>();
    final a = work.runRetry(() => first.future);
    final b = work.runRetry(() => second.future);
    expect(tracker.activeCount, 2);
    first.complete();
    await a;
    expect(tracker.activeCount, 1);
    second.complete();
    await b;
    expect(tracker.isBusy, isFalse);
  });

  test('synchronous error preserves identity and drains the send', () async {
    final tracker = BackgroundWorkTracker();
    final work = OutgoingQueueBackgroundWork(tracker);
    final failure = StateError('synthetic failure');
    await expectLater(work.runSend(() => throw failure), throwsA(same(failure)));
    expect(tracker.isBusy, isFalse);
  });

  test('asynchronous retry error preserves identity and drains', () async {
    final tracker = BackgroundWorkTracker();
    final work = OutgoingQueueBackgroundWork(tracker);
    final completion = Completer<void>();
    final failure = StateError('synthetic async failure');
    final checked = expectLater(
      work.runRetry(() => completion.future), throwsA(same(failure)),
    );
    completion.completeError(failure);
    await checked;
    expect(tracker.isBusy, isFalse);
  });

  test('caller timeout does not release the actual operation', () async {
    final tracker = BackgroundWorkTracker();
    final work = OutgoingQueueBackgroundWork(tracker);
    final completion = Completer<void>();
    final operation = work.runSend(() => completion.future);
    await expectLater(operation.timeout(Duration.zero), throwsA(isA<TimeoutException>()));
    expect(tracker.activeCount, 1);
    completion.complete();
    await operation;
    expect(tracker.isBusy, isFalse);
  });

  test('close retains existing work and late calls use the old callback without a new hold', () async {
    final tracker = BackgroundWorkTracker();
    final work = OutgoingQueueBackgroundWork(tracker);
    final completion = Completer<void>();
    final operation = work.runRetry(() => completion.future);
    tracker.close();
    final revision = tracker.revision;
    var calls = 0;
    await work.runSend(() async { calls++; });
    await work.runRetry(() async { calls++; });
    expect(calls, 2);
    expect(tracker.revision, revision);
    expect(tracker.activeCount, 1);
    completion.complete();
    await operation;
    expect(tracker.isBusy, isFalse);
  });
}
