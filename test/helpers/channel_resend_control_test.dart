import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_resend_control.dart';

void main() {
  testWidgets('echo wakes one wait without cancelling the next, stop is permanent', (tester) async {
    final control = ChannelResendControl(minHops: 2);
    var completed = 0;
    final first = control.wait(const Duration(seconds: 30)).then((_) => completed++);
    control.wake();
    await tester.pump();
    await first;
    expect(completed, 1);
    expect(control.cancelled, isFalse);
    final second = control.wait(const Duration(seconds: 30)).then((_) => completed++);
    await tester.pump(const Duration(seconds: 1));
    expect(completed, 1);
    control.cancel();
    control.cancel();
    await tester.pump();
    await second;
    expect(control.cancelled, isTrue);
    await control.wait(const Duration(hours: 1));
    // Ending this widget test also checks that no cancelled deadline timer remains.
    expect(completed, 2);
  });
}
