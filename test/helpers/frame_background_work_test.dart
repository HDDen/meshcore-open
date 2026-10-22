import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/helpers/frame_background_work.dart';

void main() {
  test('an adapter shares the tracker with work owned by another mechanism', () async {
    final tracker = BackgroundWorkTracker();
    final frames = FrameBackgroundWork(tracker);
    final other = tracker.begin(BackgroundWorkKind.persistence);
    final completion = Completer<void>();
    final write = frames.write(() => completion.future);
    expect(tracker.activeCount, 2);
    completion.complete();
    await write;
    expect(tracker.activeCount, 1);
    expect(tracker.snapshot.countFor(BackgroundWorkKind.persistence), 1);
    other.release();
    expect(tracker.isBusy, isFalse);
  });

  test('closed tracking preserves late operation execution and original errors', () async {
    final tracker = BackgroundWorkTracker()..close();
    final frames = FrameBackgroundWork(tracker);
    final revision = tracker.revision;
    var writes = 0;
    await frames.write(() async { writes++; });
    final failure = StateError('Synthetic late command');
    await expectLater(frames.command(awaitsReply: true, operation: () async {
      throw failure;
    }), throwsA(same(failure)));
    expect(writes, 1);
    expect(tracker.revision, revision);
    expect(tracker.activeCount, 0);
  });
}
