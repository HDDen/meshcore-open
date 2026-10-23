import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/helpers/sync_background_work.dart';

void main() {
  test('finishing a phase leaves actual asynchronous operations held', () async {
    final tracker = BackgroundWorkTracker();
    final sync = SyncBackgroundWork(tracker, BackgroundWorkKind.contactSync);
    sync.begin();
    final first = Completer<int>();
    final second = Completer<int>();
    final a = sync.run(() => first.future);
    final b = sync.run(() => second.future);
    expect(tracker.activeCount, 3);
    sync.finishCurrent();
    expect(tracker.activeCount, 2);
    first.complete(7);
    expect(await a, 7);
    expect(tracker.activeCount, 1);
    second.complete(9);
    expect(await b, 9);
    expect(tracker.isBusy, isFalse);
  });

  test('repeated START is idempotent and kinds are independent', () {
    final tracker = BackgroundWorkTracker();
    final contacts = SyncBackgroundWork(tracker, BackgroundWorkKind.contactSync);
    final channels = SyncBackgroundWork(tracker, BackgroundWorkKind.channelSync);
    contacts.ensureStarted();
    final revision = tracker.revision;
    contacts.ensureStarted();
    expect(tracker.revision, revision);
    channels.begin();
    expect(tracker.snapshot.countFor(BackgroundWorkKind.contactSync), 1);
    expect(tracker.snapshot.countFor(BackgroundWorkKind.channelSync), 1);
    contacts.finishCurrent();
    contacts.finishCurrent();
    expect(tracker.activeCount, 1);
    channels.finishCurrent();
    expect(tracker.isBusy, isFalse);
  });

  test('old phase and old operation cannot release a replacement phase', () async {
    final tracker = BackgroundWorkTracker();
    final sync = SyncBackgroundWork(tracker, BackgroundWorkKind.channelSync);
    final old = sync.begin();
    final completion = Completer<void>();
    final operation = sync.run(() => completion.future);
    final next = sync.begin();
    expect(old!.isReleased, isTrue);
    sync.finish(old);
    expect(tracker.activeCount, 2);
    completion.complete();
    await operation;
    expect(tracker.activeCount, 1);
    expect(next!.isReleased, isFalse);
    sync.finish(next);
    expect(tracker.isBusy, isFalse);
  });

  test('synchronous failure releases only its actual operation', () async {
    final tracker = BackgroundWorkTracker();
    final sync = SyncBackgroundWork(tracker, BackgroundWorkKind.contactSync);
    sync.begin();
    final failure = StateError('synthetic sync failure');
    await expectLater(sync.run<void>(() => throw failure), throwsA(same(failure)));
    expect(tracker.activeCount, 1);
    sync.finishCurrent();
    expect(tracker.isBusy, isFalse);
  });

  test('asynchronous failure releases only its actual operation', () async {
    final tracker = BackgroundWorkTracker();
    final sync = SyncBackgroundWork(tracker, BackgroundWorkKind.channelSync);
    sync.begin();
    final completion = Completer<void>();
    final failure = StateError('synthetic async failure');
    final checked = expectLater(
      sync.run(() => completion.future),
      throwsA(same(failure)),
    );
    completion.completeError(failure);
    await checked;
    expect(tracker.activeCount, 1);
    sync.finishCurrent();
    expect(tracker.isBusy, isFalse);
  });

  test('close preserves pending work and late operations use no new lease', () async {
    final tracker = BackgroundWorkTracker();
    final sync = SyncBackgroundWork(tracker, BackgroundWorkKind.contactSync);
    sync.begin();
    final completion = Completer<void>();
    final operation = sync.run(() => completion.future);
    tracker.close();
    expect(tracker.activeCount, 2);
    sync.finishCurrent();
    expect(tracker.activeCount, 1);
    final revision = tracker.revision;
    expect(sync.begin(), isNull);
    expect(await sync.run(() async => 3), 3);
    expect(tracker.revision, revision);
    completion.complete();
    await operation;
    expect(tracker.isBusy, isFalse);
  });
}
