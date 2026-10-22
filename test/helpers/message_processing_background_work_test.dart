import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/helpers/message_processing_background_work.dart';

void main() {
  test('processing shares the tracker without releasing another owner', () async {
    final tracker = BackgroundWorkTracker();
    final processing = MessageProcessingBackgroundWork(tracker);
    final other = tracker.begin(BackgroundWorkKind.persistence);
    final completion = Completer<void>();
    final work = processing.run(() => completion.future);
    expect(tracker.activeCount, 2);
    expect(tracker.snapshot.countFor(BackgroundWorkKind.messageSync), 1);
    completion.complete();
    await work;
    expect(tracker.activeCount, 1);
    expect(tracker.snapshot.countFor(BackgroundWorkKind.persistence), 1);
    other.release();
    expect(tracker.isBusy, isFalse);
  });

  test('closed tracking preserves late callback execution and errors', () async {
    final tracker = BackgroundWorkTracker()..close();
    final processing = MessageProcessingBackgroundWork(tracker);
    final revision = tracker.revision;
    var calls = 0;
    await processing.run(() async {
      calls++;
    });
    final failure = StateError('synthetic late processing');
    await expectLater(
      processing.run(() async {
        throw failure;
      }),
      throwsA(same(failure)),
    );
    expect(calls, 1);
    expect(tracker.revision, revision);
    expect(tracker.activeCount, 0);
  });
}
