import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/ios_frame_diagnostics.dart';

void main() {
  test('idle time and repeated gate events do not invent frames or reset the window', () {
    var now = 100;
    final stats = IosFrameDiagnostics(nowMs: () => now);
    stats.presentationChanged(false);
    now = 3100;
    stats.presentationChanged(false);
    final snapshot = stats.snapshot;
    expect(snapshot['gateEpoch'], 1);
    expect(snapshot['gatedElapsedMs'], 3000);
    expect(snapshot['beginCallbacks'], 0);
    expect(snapshot['drawCallbacks'], 0);
  });

  test('delivered callbacks distinguish warmup suppressed draws and pipeline passes', () {
    var now = 0;
    final stats = IosFrameDiagnostics(nowMs: () => now);
    stats.beginFrame(warmUp: false);
    stats.drawFrame(suppressed: false);
    stats.presentationChanged(false);
    stats.beginFrame(warmUp: false);
    stats.drawFrame(suppressed: true);
    stats.beginFrame(warmUp: true);
    stats.drawFrame(suppressed: true);
    now = 2000;
    stats.presentationChanged(true);
    now = 8000;
    expect(stats.snapshot, {
      'frameSchema': 1, 'gateEpoch': 1, 'presentationAllowed': true,
      'beginCallbacks': 3, 'warmUpCallbacks': 1, 'drawCallbacks': 3,
      'pipelinePasses': 1, 'suppressedDraws': 2, 'gatedElapsedMs': 2000,
      'gatedBeginCallbacks': 2, 'gatedWarmUpCallbacks': 1,
      'gatedDrawCallbacks': 2, 'gatedSuppressedDraws': 2,
    });
  });

  test('a new gated window resets only its counters and snapshot copies are independent', () {
    var now = 0;
    final stats = IosFrameDiagnostics(nowMs: () => now);
    stats.presentationChanged(false);
    stats.beginFrame(warmUp: false);
    stats.drawFrame(suppressed: true);
    now = 500;
    stats.presentationChanged(true);
    final first = stats.snapshot;
    first['beginCallbacks'] = 900;
    now = 1000;
    stats.presentationChanged(false);
    expect(stats.snapshot['gateEpoch'], 2);
    expect(stats.snapshot['gatedBeginCallbacks'], 0);
    expect(stats.snapshot['beginCallbacks'], 1);
    now = 900;
    expect(stats.snapshot['gatedElapsedMs'], 0);
    expect(stats.summary, contains('suppressedDraws=1'));
  });
}
