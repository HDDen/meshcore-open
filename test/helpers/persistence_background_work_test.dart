import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/helpers/persistence_background_work.dart';

void main() {
  test('late attach adopts an existing write and repeated attach is idempotent', () async {
    final work = PersistenceBackgroundWork();
    final tracker = BackgroundWorkTracker();
    final completion = Completer<bool>();
    final operation = work.run(() => completion.future);
    work.attach(tracker);
    expect(tracker.snapshot.countFor(BackgroundWorkKind.persistence), 1);
    final revision = tracker.revision;
    work.attach(tracker);
    expect(tracker.revision, revision);
    completion.complete(true);
    expect(await operation, isTrue);
    expect(tracker.isBusy, isFalse);
  });

  test('parallel writes release independent leases', () async {
    final work = PersistenceBackgroundWork();
    final tracker = BackgroundWorkTracker();
    work.attach(tracker);
    final first = Completer<void>();
    final second = Completer<void>();
    final a = work.run(() => first.future);
    final b = work.run(() => second.future);
    expect(tracker.activeCount, 2);
    first.complete();
    await a;
    expect(tracker.activeCount, 1);
    second.complete();
    await b;
    expect(tracker.isBusy, isFalse);
  });

  test('detach retains an old write but stops new registrations for that observer', () async {
    final work = PersistenceBackgroundWork();
    final first = BackgroundWorkTracker();
    final second = BackgroundWorkTracker();
    work.attach(first);
    work.attach(second);
    final completion = Completer<void>();
    final operation = work.run(() => completion.future);
    work.detach(first);
    expect(first.activeCount, 1);
    await work.run(() async {
      expect(first.activeCount, 1);
      expect(second.activeCount, 2);
    });
    expect(second.activeCount, 1);
    completion.complete();
    await operation;
    expect(first.isBusy, isFalse);
    expect(second.isBusy, isFalse);
  });

  test('reattach does not duplicate a retained lease for the same write', () async {
    final work = PersistenceBackgroundWork();
    final tracker = BackgroundWorkTracker();
    work.attach(tracker);
    final completion = Completer<void>();
    final operation = work.run(() => completion.future);
    final revision = tracker.revision;
    work.detach(tracker);
    work.attach(tracker);
    expect(tracker.activeCount, 1);
    expect(tracker.revision, revision);
    completion.complete();
    await operation;
    expect(tracker.isBusy, isFalse);
  });

  test('replacement observer sees a pending write while the closed owner retains its lease', () async {
    final work = PersistenceBackgroundWork();
    final old = BackgroundWorkTracker();
    final replacement = BackgroundWorkTracker();
    work.attach(old);
    final completion = Completer<void>();
    final operation = work.run(() => completion.future);
    old.close();
    work.detach(old);
    work.attach(old);
    work.attach(replacement);
    expect(old.activeCount, 1);
    expect(replacement.activeCount, 1);
    final oldRevision = old.revision;
    await work.run(() async {
      expect(old.revision, oldRevision);
      expect(replacement.activeCount, 2);
    });
    completion.complete();
    await operation;
    expect(old.isBusy, isFalse);
    expect(replacement.isBusy, isFalse);
  });

  test('unbound writes keep their results and completed writes are not adopted', () async {
    final work = PersistenceBackgroundWork();
    expect(await work.run(() async => false), isFalse);
    final tracker = BackgroundWorkTracker();
    work.attach(tracker);
    expect(tracker.activeCount, 0);
    expect(tracker.revision, 0);
  });

  test('synchronous error retains identity and releases every observer', () async {
    final work = PersistenceBackgroundWork();
    final first = BackgroundWorkTracker();
    final second = BackgroundWorkTracker();
    work.attach(first);
    work.attach(second);
    final failure = StateError('synthetic sync error');
    await expectLater(work.run<void>(() => throw failure), throwsA(same(failure)));
    expect(first.isBusy, isFalse);
    expect(second.isBusy, isFalse);
  });

  test('asynchronous error retains identity and releases the write', () async {
    final work = PersistenceBackgroundWork();
    final tracker = BackgroundWorkTracker();
    work.attach(tracker);
    final completion = Completer<void>();
    final failure = StateError('synthetic async error');
    final checked = expectLater(
      work.run(() => completion.future), throwsA(same(failure)),
    );
    completion.completeError(failure);
    await checked;
    expect(tracker.isBusy, isFalse);
  });

  test('caller timeout does not release an unfinished write', () async {
    final work = PersistenceBackgroundWork();
    final tracker = BackgroundWorkTracker();
    work.attach(tracker);
    final completion = Completer<void>();
    final operation = work.run(() => completion.future);
    await expectLater(operation.timeout(Duration.zero), throwsA(isA<TimeoutException>()));
    expect(tracker.activeCount, 1);
    completion.complete();
    await operation;
    expect(tracker.isBusy, isFalse);
  });

  test('detachAll retains started leases until the actual write finishes', () async {
    final work = PersistenceBackgroundWork();
    final tracker = BackgroundWorkTracker();
    work.attach(tracker);
    final completion = Completer<void>();
    final operation = work.run(() => completion.future);
    work.detachAll();
    final revision = tracker.revision;
    await work.run(() async {});
    expect(tracker.revision, revision);
    expect(tracker.activeCount, 1);
    completion.complete();
    await operation;
    expect(tracker.isBusy, isFalse);
  });
}
