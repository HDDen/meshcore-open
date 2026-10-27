import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/helpers/cpu_sleep_binding.dart';

void main() {
  test('default run remains synchronous until its original first await', () async {
    final tracker = BackgroundWorkTracker();
    var entered = false;
    final future = tracker.run(BackgroundWorkKind.persistence, () { entered = true; });
    expect(entered, isTrue);
    await future;
    expect(tracker.isBusy, isFalse);
  });

  test('protected async work waits for native acknowledgement and releases on error', () async {
    final tracker = BackgroundWorkTracker();
    final acquired = Completer<void>();
    var entered = false;
    tracker.prepareOperation = (_) => acquired.future;
    final future = tracker.run(BackgroundWorkKind.persistence, () {
      entered = true;
      throw StateError('synthetic persistence failure');
    });
    expect(entered, isFalse);
    expect(cpuHasProtectedWork(tracker.snapshot), isTrue);
    final checked = expectLater(future, throwsStateError);
    acquired.complete();
    await checked;
    expect(entered, isTrue);
    expect(tracker.isBusy, isFalse);
    expect(tracker.runningCountFor(BackgroundWorkKind.persistence), 0);
  });

  test('passive retry does not hold CPU but its actual operation does', () async {
    final tracker = BackgroundWorkTracker();
    final passive = tracker.begin(BackgroundWorkKind.retry);
    expect(cpuHasProtectedWork(tracker.snapshot), isFalse);
    final completion = Completer<void>();
    final active = tracker.run(BackgroundWorkKind.retry, () => completion.future);
    expect(cpuHasProtectedWork(tracker.snapshot,
      runningRetry: tracker.runningCountFor(BackgroundWorkKind.retry)), isTrue);
    completion.complete();
    await active;
    expect(cpuHasProtectedWork(tracker.snapshot,
      runningRetry: tracker.runningCountFor(BackgroundWorkKind.retry)), isFalse);
    passive.release();
  });

  test('close retains active hold until completion and refuses new run counts', () async {
    final tracker = BackgroundWorkTracker();
    final completion = Completer<void>();
    final pending = tracker.run(BackgroundWorkKind.persistence, () => completion.future);
    tracker.close();
    expect(cpuHasProtectedWork(tracker.snapshot), isTrue);
    await expectLater(tracker.run(BackgroundWorkKind.retry, () {}), throwsStateError);
    expect(tracker.runningCountFor(BackgroundWorkKind.retry), 0);
    completion.complete();
    await pending;
    expect(tracker.isBusy, isFalse);
  });
}
