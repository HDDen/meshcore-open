import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/helpers/image_transfer_background_work.dart';

void main() {
  test('retains the actual Future and preserves true and false results', () async {
    final tracker = BackgroundWorkTracker();
    final work = ImageTransferBackgroundWork(tracker);
    final completion = Completer<bool>();
    final operation = work.run(() => completion.future);
    expect(tracker.snapshot.countFor(BackgroundWorkKind.imageTransfer), 1);
    completion.complete(true);
    expect(await operation, isTrue);
    expect(tracker.isBusy, isFalse);
    expect(await work.run(() async => false), isFalse);
    expect(tracker.isBusy, isFalse);
  });

  test('parallel images release independent leases', () async {
    final tracker = BackgroundWorkTracker();
    final work = ImageTransferBackgroundWork(tracker);
    final first = Completer<bool>();
    final second = Completer<bool>();
    final a = work.run(() => first.future);
    final b = work.run(() => second.future);
    expect(tracker.activeCount, 2);
    first.complete(false);
    expect(await a, isFalse);
    expect(tracker.activeCount, 1);
    second.complete(true);
    expect(await b, isTrue);
    expect(tracker.isBusy, isFalse);
  });

  test('synchronous error preserves identity and releases its lease', () async {
    final tracker = BackgroundWorkTracker();
    final work = ImageTransferBackgroundWork(tracker);
    final failure = StateError('synthetic sync error');
    await expectLater(work.run<bool>(() => throw failure), throwsA(same(failure)));
    expect(tracker.isBusy, isFalse);
  });

  test('asynchronous error preserves identity and releases its lease', () async {
    final tracker = BackgroundWorkTracker();
    final work = ImageTransferBackgroundWork(tracker);
    final completion = Completer<bool>();
    final failure = StateError('synthetic async error');
    final checked = expectLater(
      work.run(() => completion.future), throwsA(same(failure)),
    );
    completion.completeError(failure);
    await checked;
    expect(tracker.isBusy, isFalse);
  });

  test('caller timeout leaves the actual image held', () async {
    final tracker = BackgroundWorkTracker();
    final work = ImageTransferBackgroundWork(tracker);
    final completion = Completer<bool>();
    final operation = work.run(() => completion.future);
    await expectLater(operation.timeout(Duration.zero), throwsA(isA<TimeoutException>()));
    expect(tracker.activeCount, 1);
    completion.complete(true);
    expect(await operation, isTrue);
    expect(tracker.isBusy, isFalse);
  });

  test('close retains actual work and late callbacks add no new lease', () async {
    final tracker = BackgroundWorkTracker();
    final work = ImageTransferBackgroundWork(tracker);
    final completion = Completer<bool>();
    final operation = work.run(() => completion.future);
    tracker.close();
    final revision = tracker.revision;
    expect(await work.run(() async => false), isFalse);
    expect(tracker.revision, revision);
    expect(tracker.activeCount, 1);
    completion.complete(true);
    expect(await operation, isTrue);
    expect(tracker.isBusy, isFalse);
  });
}
