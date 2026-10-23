import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/helpers/retry_background_work.dart';

void main() {
  test('waiting ids are independent and synchronization is idempotent', () {
    final tracker = BackgroundWorkTracker();
    final work = RetryBackgroundWork()..attach(tracker, ['a', 'b', 'a']);
    expect(tracker.snapshot.countFor(BackgroundWorkKind.retry), 2);
    final revision = tracker.revision;
    work.begin('a');
    work.synchronize(['b', 'a']);
    expect(tracker.revision, revision);
    work.synchronize(['b', 'c']);
    expect(tracker.activeCount, 2);
    work.finish('a');
    expect(tracker.activeCount, 2);
    work.finish('b');
    work.finish('b');
    expect(tracker.activeCount, 1);
    work.close();
    expect(tracker.isBusy, isFalse);
    expect(tracker.isClosed, isFalse);
  });

  test('logical finish and suspend leave actual attempts until their completion', () async {
    final tracker = BackgroundWorkTracker();
    final work = RetryBackgroundWork()..attach(tracker, ['a', 'b']);
    final first = Completer<void>();
    final second = Completer<void>();
    final a = work.run(() => first.future);
    final b = work.run(() => second.future);
    expect(tracker.activeCount, 4);
    work.finish('a');
    work.finishAll();
    expect(tracker.activeCount, 2);
    work.synchronize(['b']);
    expect(tracker.activeCount, 3);
    first.complete();
    await a;
    expect(tracker.activeCount, 2);
    second.complete();
    await b;
    expect(tracker.activeCount, 1);
    work.finishAll();
    expect(tracker.isBusy, isFalse);
  });

  test('rebind moves logical waits while old attempts retain their original tracker', () async {
    final old = BackgroundWorkTracker();
    final next = BackgroundWorkTracker();
    final work = RetryBackgroundWork()..attach(old, ['a']);
    final completion = Completer<void>();
    final attempt = work.run(() => completion.future);
    work.attach(next, ['a', 'b']);
    expect(old.activeCount, 1);
    expect(next.activeCount, 2);
    old.close();
    completion.complete();
    await attempt;
    expect(old.isBusy, isFalse);
    expect(next.activeCount, 2);
    work.attach(null, []);
    expect(next.isBusy, isFalse);
  });

  test('synchronous failure releases only its actual attempt', () async {
    final tracker = BackgroundWorkTracker();
    final work = RetryBackgroundWork()..attach(tracker, ['a']);
    final failure = StateError('synthetic retry failure');
    await expectLater(work.run(() => throw failure), throwsA(same(failure)));
    expect(tracker.activeCount, 1);
    work.finishAll();
    expect(tracker.isBusy, isFalse);
  });

  test('asynchronous failure releases only its actual attempt', () async {
    final tracker = BackgroundWorkTracker();
    final work = RetryBackgroundWork()..attach(tracker, ['a']);
    final completion = Completer<void>();
    final failure = StateError('synthetic async retry failure');
    final checked = expectLater(work.run(() => completion.future), throwsA(same(failure)));
    completion.completeError(failure);
    await checked;
    expect(tracker.activeCount, 1);
    work.close();
    expect(tracker.isBusy, isFalse);
  });

  test('unconfigured and closed tracker execute callbacks without new leases', () async {
    final work = RetryBackgroundWork();
    var calls = 0;
    await work.run(() async { calls++; });
    work.begin('unconfigured');
    final tracker = BackgroundWorkTracker()..close();
    final revision = tracker.revision;
    work.attach(tracker, ['a']);
    work.begin('b');
    await work.run(() async { calls++; });
    expect(calls, 2);
    expect(tracker.revision, revision);
    expect(tracker.isBusy, isFalse);
  });

  test('service close releases waits but not actual work or the shared tracker', () async {
    final tracker = BackgroundWorkTracker();
    final work = RetryBackgroundWork()..attach(tracker, ['a']);
    final other = tracker.begin(BackgroundWorkKind.persistence);
    final completion = Completer<void>();
    final operation = work.run(() => completion.future);
    work.close();
    work.close();
    expect(tracker.activeCount, 2);
    final revision = tracker.revision;
    work.begin('late');
    work.attach(tracker, ['late']);
    var called = false;
    await work.run(() async { called = true; });
    expect(called, isTrue);
    expect(tracker.revision, revision);
    completion.complete();
    await operation;
    expect(tracker.snapshot.countFor(BackgroundWorkKind.retry), 0);
    expect(tracker.isClosed, isFalse);
    expect(tracker.activeCount, 1);
    other.release();
    expect(tracker.isBusy, isFalse);
  });
}
