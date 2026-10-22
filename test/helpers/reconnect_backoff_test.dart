import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/reconnect_backoff.dart';

void main() {
  test('all policies retain the fast prefix and only background uses the long pause', () {
    const prefix = [1000, 2000, 4000, 8000, 16000, 30000];
    for (final seconds in [30, 60, 180, 600]) {
      for (var attempt = 0; attempt < 1008; attempt++) {
        final original = attempt < 6 ? prefix[attempt] : 30000;
        expect(reconnectDelayMs(attempt, backgroundIntervalSeconds: seconds), original);
        expect(reconnectDelayMs(attempt, background: true,
            backgroundIntervalSeconds: seconds), attempt < 6 ? original : seconds * 1000);
      }
    }
  });

  testWidgets('shorter wait retains elapsed time and expires exactly once', (tester) async {
    var calls = 0;
    final wait = ReconnectWait(
      attemptIndex: 6, delay: const Duration(seconds: 600),
      onElapsed: () => calls++, now: () => tester.binding.clock.now()
          .difference(DateTime.utc(2026)),
    );
    try {
      await tester.pump(const Duration(seconds: 10));
      wait.updateDelay(const Duration(seconds: 30));
      await tester.pump(const Duration(milliseconds: 19999));
      expect(calls, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 1);
      expect(wait.isActive, isFalse);
      wait.updateDelay(const Duration(seconds: 600));
      await tester.pump(const Duration(hours: 1));
      expect(calls, 1);
    } finally {
      wait.cancel();
    }
  });

  testWidgets('longer wait and repeated changes retain the original anchor', (tester) async {
    var calls = 0;
    final wait = ReconnectWait(
      attemptIndex: 6, delay: const Duration(seconds: 30),
      onElapsed: () => calls++, now: () => tester.binding.clock.now()
          .difference(DateTime.utc(2026)),
    );
    try {
      await tester.pump(const Duration(seconds: 10));
      wait.updateDelay(const Duration(seconds: 180));
      await tester.pump(const Duration(seconds: 10));
      wait.updateDelay(const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 10));
      wait.updateDelay(const Duration(seconds: 60));
      await tester.pump(const Duration(milliseconds: 29999));
      expect(calls, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 1);
    } finally {
      wait.cancel();
    }
  });

  testWidgets('overdue wait fires once on the next timer turn without advancing time', (tester) async {
    var calls = 0;
    final wait = ReconnectWait(
      attemptIndex: 6, delay: const Duration(seconds: 600),
      onElapsed: () => calls++, now: () => tester.binding.clock.now()
          .difference(DateTime.utc(2026)),
    );
    try {
      await tester.pump(const Duration(seconds: 40));
      final now = tester.binding.clock.now();
      wait.updateDelay(const Duration(seconds: 30));
      expect(calls, 0);
      expect(wait.isActive, isTrue);
      await tester.pump(Duration.zero);
      expect(tester.binding.clock.now(), now);
      expect(calls, 1);
      expect(wait.isActive, isFalse);
      await tester.pump(Duration.zero);
      await tester.pump(const Duration(hours: 1));
      expect(calls, 1);
    } finally {
      wait.cancel();
    }
  });

  testWidgets('overdue shortening is asynchronous and cancellation still wins', (tester) async {
    var calls = 0;
    final wait = ReconnectWait(
      attemptIndex: 6, delay: const Duration(seconds: 600),
      onElapsed: () => calls++, now: () => tester.binding.clock.now()
          .difference(DateTime.utc(2026)),
    );
    try {
      await tester.pump(const Duration(seconds: 40));
      wait.updateDelay(const Duration(seconds: 30));
      expect(calls, 0);
      wait.cancel();
      wait.updateDelay(const Duration(seconds: 180));
      await tester.pump();
      await tester.pump(const Duration(hours: 1));
      expect(calls, 0);
      expect(wait.isActive, isFalse);
    } finally {
      wait.cancel();
    }
  });
}
