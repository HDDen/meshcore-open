import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';

void main() {
  test('independent leases of the same kind cannot release one another', () {
    final tracker = BackgroundWorkTracker();
    final first = tracker.begin(BackgroundWorkKind.radioSend);
    final second = tracker.begin(BackgroundWorkKind.radioSend);
    expect(tracker.snapshot.countFor(BackgroundWorkKind.radioSend), 2);
    expect(tracker.activeCount, 2);
    expect(tracker.revision, 2);
    first.release();
    expect(first.isReleased, isTrue);
    expect(second.isReleased, isFalse);
    expect(tracker.isBusy, isTrue);
    expect(tracker.activeCount, 1);
    final revision = tracker.revision;
    first.release();
    expect(tracker.revision, revision);
    expect(tracker.snapshot.countFor(BackgroundWorkKind.radioSend), 1);
    second.release();
    expect(tracker.isBusy, isFalse);
    expect(tracker.snapshot.counts, isEmpty);
    expect(tracker.revision, revision + 1);
  });

  test('snapshot is immutable and does not change with subsequent work', () {
    final tracker = BackgroundWorkTracker();
    final first = tracker.begin(BackgroundWorkKind.messageSync);
    final snapshot = tracker.snapshot;
    final second = tracker.begin(BackgroundWorkKind.persistence);
    first.release();
    expect(snapshot.revision, 1);
    expect(snapshot.activeCount, 1);
    expect(snapshot.countFor(BackgroundWorkKind.messageSync), 1);
    expect(snapshot.countFor(BackgroundWorkKind.persistence), 0);
    expect(() => snapshot.counts.clear(), throwsUnsupportedError);
    expect(tracker.snapshot.countFor(BackgroundWorkKind.persistence), 1);
    second.release();
  });

  test('all work kinds retain their own independent counts', () {
    final tracker = BackgroundWorkTracker();
    final leases = [for (final kind in BackgroundWorkKind.values) tracker.begin(kind)];
    final snapshot = tracker.snapshot;
    expect(snapshot.activeCount, BackgroundWorkKind.values.length);
    for (final kind in BackgroundWorkKind.values) {
      expect(snapshot.countFor(kind), 1);
    }
    for (final lease in leases.reversed) {
      lease.release();
    }
    expect(tracker.activeCount, 0);
    expect(tracker.snapshot.counts, isEmpty);
  });

  test('run holds through preparation and nested work and returns its value', () async {
    final tracker = BackgroundWorkTracker();
    final result = await tracker.run(BackgroundWorkKind.radioSend, () async {
      expect(tracker.snapshot.countFor(BackgroundWorkKind.radioSend), 1);
      final inner = await tracker.run(BackgroundWorkKind.radioSend, () {
        expect(tracker.snapshot.countFor(BackgroundWorkKind.radioSend), 2);
        return 41;
      });
      expect(tracker.activeCount, 1);
      return inner + 1;
    });
    expect(result, 42);
    expect(tracker.isBusy, isFalse);
    expect(tracker.revision, 4);
  });

  test('synchronous and asynchronous failures release only the failed work', () async {
    final tracker = BackgroundWorkTracker();
    final remaining = tracker.begin(BackgroundWorkKind.commandReply);
    final error = StateError('Synthetic operation error');
    await expectLater(
      tracker.run<void>(BackgroundWorkKind.persistence, () => throw error),
      throwsA(same(error)),
    );
    final completion = Completer<void>();
    final operation = tracker.run(BackgroundWorkKind.persistence, () => completion.future);
    final failure = expectLater(operation, throwsA(same(error)));
    expect(tracker.activeCount, 2);
    completion.completeError(error);
    await failure;
    expect(tracker.activeCount, 1);
    expect(tracker.snapshot.countFor(BackgroundWorkKind.commandReply), 1);
    remaining.release();
    expect(tracker.isBusy, isFalse);
  });

  test('close rejects new work but unfinished work drains normally', () async {
    final tracker = BackgroundWorkTracker();
    final completion = Completer<int>();
    final operation = tracker.run(BackgroundWorkKind.persistence, () => completion.future);
    tracker.close();
    final revision = tracker.revision;
    tracker.close();
    expect(tracker.revision, revision);
    expect(tracker.isClosed, isTrue);
    expect(tracker.snapshot.isClosed, isTrue);
    expect(tracker.isBusy, isTrue);
    expect(() => tracker.begin(BackgroundWorkKind.persistence), throwsStateError);
    var invoked = false;
    await expectLater(tracker.run(BackgroundWorkKind.notification, () {
      invoked = true;
    }), throwsStateError);
    expect(invoked, isFalse);
    completion.complete(7);
    expect(await operation, 7);
    expect(tracker.isBusy, isFalse);
    expect(tracker.revision, revision + 1);
  });

  testWidgets('caller timeout does not finish the underlying operation', (tester) async {
    final tracker = BackgroundWorkTracker();
    final completion = Completer<int>();
    final operation = tracker.run(BackgroundWorkKind.messageSync, () => completion.future);
    try {
      final timeout = expectLater(
        operation.timeout(const Duration(seconds: 1)),
        throwsA(isA<TimeoutException>()),
      );
      await tester.pump(const Duration(seconds: 1));
      await timeout;
      expect(tracker.isBusy, isTrue);
      expect(tracker.activeCount, 1);
    } finally {
      completion.complete(9);
      expect(await operation, 9);
    }
    expect(tracker.isBusy, isFalse);
  });

  test('completion in an old tracker cannot release work in a new one', () {
    final oldTracker = BackgroundWorkTracker();
    final oldWork = oldTracker.begin(BackgroundWorkKind.transportSetup);
    oldTracker.close();
    final newTracker = BackgroundWorkTracker();
    final newWork = newTracker.begin(BackgroundWorkKind.transportSetup);
    oldWork.release();
    oldWork.release();
    expect(newTracker.activeCount, 1);
    expect(newWork.isReleased, isFalse);
    expect(oldTracker.isBusy, isFalse);
    newWork.release();
    expect(newTracker.isBusy, isFalse);
  });
}
