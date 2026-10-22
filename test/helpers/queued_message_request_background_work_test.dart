import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/helpers/queued_message_request_background_work.dart';

void main() {
  test('a superseded token cannot finish the new request', () {
    final tracker = BackgroundWorkTracker();
    final requests = QueuedMessageRequestBackgroundWork(tracker);
    final first = requests.begin()!;
    final before = tracker.snapshot;
    final second = requests.begin()!;
    expect(first.isReleased, isTrue);
    expect(second.isReleased, isFalse);
    expect(tracker.activeCount, 1);
    final revision = tracker.revision;
    requests.finish(first);
    expect(tracker.revision, revision);
    expect(tracker.activeCount, 1);
    expect(before.countFor(BackgroundWorkKind.queuedMessageRequest), 1);
    requests.finish(second);
    expect(tracker.isBusy, isFalse);
  });

  test('finishing the current request is idempotent and preserves other work', () {
    final tracker = BackgroundWorkTracker();
    final requests = QueuedMessageRequestBackgroundWork(tracker);
    final other = tracker.begin(BackgroundWorkKind.transportWrite);
    requests.begin();
    expect(tracker.activeCount, 2);
    requests.finish(other);
    expect(tracker.activeCount, 2);
    expect(other.isReleased, isFalse);
    requests.finishCurrent();
    final revision = tracker.revision;
    requests.finishCurrent();
    requests.finish(null);
    expect(tracker.revision, revision);
    expect(tracker.activeCount, 1);
    expect(other.isReleased, isFalse);
    other.release();
    expect(tracker.isBusy, isFalse);
  });

  test('closing the tracker preserves a pending wait until its owner finishes', () {
    final tracker = BackgroundWorkTracker();
    final requests = QueuedMessageRequestBackgroundWork(tracker);
    final request = requests.begin()!;
    tracker.close();
    expect(tracker.activeCount, 1);
    expect(request.isReleased, isFalse);
    requests.finishCurrent();
    expect(tracker.activeCount, 0);
  });

  test('late begin after close adds no holding and supersedes the old wait', () {
    final tracker = BackgroundWorkTracker();
    final requests = QueuedMessageRequestBackgroundWork(tracker);
    final old = requests.begin()!;
    tracker.close();
    expect(requests.begin(), isNull);
    expect(old.isReleased, isTrue);
    expect(tracker.activeCount, 0);
    final revision = tracker.revision;
    requests.finish(old);
    expect(requests.begin(), isNull);
    expect(tracker.revision, revision);
  });
}
