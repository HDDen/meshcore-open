import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/helpers/connection_cleanup.dart';
import 'package:meshcore_open/helpers/connection_teardown_background_work.dart';

void _expectCount(BackgroundWorkTracker tracker, int count) {
  expect(tracker.snapshot.countFor(BackgroundWorkKind.transportTeardown), count);
  expect(tracker.snapshot.activeCount, count);
}

void main() {
  test('run preserves the result and releases only after completion', () async {
    final tracker = BackgroundWorkTracker();
    final work = ConnectionTeardownBackgroundWork(tracker);
    final gate = Completer<int>();
    final result = work.run(() => gate.future);
    _expectCount(tracker, 1);
    gate.complete(42);
    expect(await result, 42);
    _expectCount(tracker, 0);
  });

  test('a null action runs synchronously inside a temporary lease', () {
    final tracker = BackgroundWorkTracker();
    final work = ConnectionTeardownBackgroundWork(tracker);
    var during = 0;
    final result = work.cleanup(() {
      during = tracker.snapshot.activeCount;
      return null;
    });
    expect(result, isNull);
    expect(during, 1);
    _expectCount(tracker, 0);
  });

  test('synchronous cleanup error keeps its identity and releases the lease', () {
    final tracker = BackgroundWorkTracker();
    final work = ConnectionTeardownBackgroundWork(tracker);
    final error = StateError('synthetic synchronous cleanup failure');
    expect(() => work.cleanup(() => throw error), throwsA(same(error)));
    _expectCount(tracker, 0);
  });

  test('run releases on asynchronous operation failure', () async {
    final tracker = BackgroundWorkTracker();
    final work = ConnectionTeardownBackgroundWork(tracker);
    final error = StateError('synthetic teardown failure');
    await expectLater(work.run(() async => throw error), throwsA(same(error)));
    _expectCount(tracker, 0);
  });

  testWidgets('timeout ends the wait but the actual cleanup consumes its late error', (tester) async {
    final tracker = BackgroundWorkTracker();
    final work = ConnectionTeardownBackgroundWork(tracker);
    final gate = Completer<void>();
    final failures = <Object>[];
    final cleanup = ConnectionCleanup(
      runAction: work.cleanup,
      onFailure: (stage, error, stack) => failures.add(error),
    );
    var finished = false;
    final result = work.run(() => cleanup.run('synthetic release', () => gate.future));
    unawaited(result.then((_) => finished = true));
    _expectCount(tracker, 2);
    await tester.pump(const Duration(seconds: 3));
    expect(finished, isTrue);
    expect(failures.single, isA<TimeoutException>());
    _expectCount(tracker, 1);
    gate.completeError(StateError('synthetic late release failure'));
    await tester.pump();
    _expectCount(tracker, 0);
    expect(failures, hasLength(1));
  });

  testWidgets('caller timeout leaves the actual run active', (tester) async {
    final tracker = BackgroundWorkTracker();
    final work = ConnectionTeardownBackgroundWork(tracker);
    final gate = Completer<void>();
    Object? error;
    final caller = work.run(() => gate.future).timeout(const Duration(milliseconds: 1));
    unawaited(caller.then<void>((_) {}, onError: (Object failure, StackTrace stack) {
      error = failure;
    }));
    await tester.pump(const Duration(milliseconds: 1));
    expect(error, isA<TimeoutException>());
    _expectCount(tracker, 1);
    gate.complete();
    await tester.pump();
    _expectCount(tracker, 0);
  });

  test('independent cleanup leases survive close and drain separately', () async {
    final tracker = BackgroundWorkTracker();
    final work = ConnectionTeardownBackgroundWork(tracker);
    final first = Completer<void>();
    final second = Completer<void>();
    final a = work.cleanup(() => first.future)!;
    final b = work.cleanup(() => second.future)!;
    tracker.close();
    _expectCount(tracker, 2);
    first.complete();
    await a;
    _expectCount(tracker, 1);
    second.complete();
    await b;
    _expectCount(tracker, 0);
  });

  test('closed tracker preserves actions and errors without new leases', () async {
    final tracker = BackgroundWorkTracker()..close();
    final work = ConnectionTeardownBackgroundWork(tracker);
    final revision = tracker.snapshot.revision;
    var calls = 0;
    expect(work.cleanup(() { calls++; return null; }), isNull);
    await work.run(() async { calls++; });
    final error = StateError('synthetic closed cleanup error');
    expect(() => work.cleanup(() => throw error), throwsA(same(error)));
    expect(calls, 2);
    expect(tracker.snapshot.revision, revision);
    _expectCount(tracker, 0);
  });
}
