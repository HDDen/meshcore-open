import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/helpers/packet_background_work.dart';

const _kinds = [
  BackgroundWorkKind.frameDispatch,
  BackgroundWorkKind.radioReceive,
  BackgroundWorkKind.messageReplay,
];

Future<void> _run(PacketBackgroundWork work, BackgroundWorkKind kind,
    Future<void> Function() operation) => switch (kind) {
  BackgroundWorkKind.frameDispatch => work.dispatch(operation),
  BackgroundWorkKind.radioReceive => work.receive(operation),
  BackgroundWorkKind.messageReplay => work.replay(operation),
  _ => throw ArgumentError.value(kind),
};

void main() {
  for (final kind in _kinds) {
    test('$kind begins before callback and drains independently', () async {
      final tracker = BackgroundWorkTracker();
      final work = PacketBackgroundWork(tracker);
      final first = Completer<void>();
      final second = Completer<void>();
      BackgroundWorkSnapshot? atEntry;
      final a = _run(work, kind, () {
        atEntry = tracker.snapshot;
        return first.future;
      });
      final b = _run(work, kind, () => second.future);
      expect(atEntry!.countFor(kind), 1);
      expect(tracker.snapshot.countFor(kind), 2);
      first.complete();
      await a;
      expect(tracker.snapshot.countFor(kind), 1);
      expect(atEntry!.activeCount, 1);
      second.complete();
      await b;
      expect(tracker.activeCount, 0);
    });

    test('$kind preserves synchronous throw and releases immediately', () {
      final tracker = BackgroundWorkTracker();
      final work = PacketBackgroundWork(tracker);
      final failure = StateError('synthetic synchronous failure');
      expect(() => _run(work, kind, () => throw failure), throwsA(same(failure)));
      expect(tracker.activeCount, 0);
      expect(tracker.revision, 2);
    });

    test('$kind preserves asynchronous error and releases on completion', () async {
      final tracker = BackgroundWorkTracker();
      final work = PacketBackgroundWork(tracker);
      final gate = Completer<void>();
      final failure = StateError('synthetic asynchronous failure');
      final result = _run(work, kind, () => gate.future);
      final checked = expectLater(result, throwsA(same(failure)));
      gate.completeError(failure);
      await checked;
      expect(tracker.activeCount, 0);
    });

    test('$kind close retains existing work and bypasses late registration', () async {
      final tracker = BackgroundWorkTracker();
      final work = PacketBackgroundWork(tracker);
      final gate = Completer<void>();
      final result = _run(work, kind, () => gate.future);
      tracker.close();
      final revision = tracker.revision;
      var called = false;
      final late = Completer<void>();
      final lateResult = _run(work, kind, () {
        called = true;
        return late.future;
      });
      expect(called, isTrue);
      expect(lateResult, same(late.future));
      expect(tracker.activeCount, 1);
      expect(tracker.revision, revision);
      final failure = StateError('synthetic closed synchronous failure');
      expect(() => _run(work, kind, () => throw failure), throwsA(same(failure)));
      gate.complete();
      late.complete();
      await result;
      await lateResult;
      expect(tracker.activeCount, 0);
      expect(tracker.isClosed, isTrue);
    });
  }

  test('nested packet kinds coexist with physical writer work', () async {
    final tracker = BackgroundWorkTracker();
    final work = PacketBackgroundWork(tracker);
    final writer = tracker.begin(BackgroundWorkKind.transportWrite);
    final gate = Completer<void>();
    final operation = work.receive(() => work.replay(
      () => work.dispatch(() => gate.future),
    ));
    expect(tracker.activeCount, 4);
    for (final kind in _kinds) {
      expect(tracker.snapshot.countFor(kind), 1);
    }
    gate.complete();
    await operation;
    expect(tracker.activeCount, 1);
    writer.release();
    expect(tracker.isBusy, isFalse);
  });
}
