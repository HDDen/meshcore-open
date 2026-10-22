import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/ui_notification_batcher.dart';

void main() {
  testWidgets('continuous marks cannot postpone the selected window', (tester) async {
    var calls = 0;
    final batch = UiNotificationBatcher(onNotify: () => calls++);
    try {
      batch.setInterval(const Duration(milliseconds: 500));
      for (var i = 1; i <= 20; i++) {
        batch.mark();
        await tester.pump(const Duration(milliseconds: 50));
        expect(calls, i ~/ 10);
      }
      await tester.pump(const Duration(seconds: 2));
      expect(calls, 2);
    } finally {
      batch.dispose();
    }
  });

  testWidgets('priority shortens a long window to 50 ms from the transition',
      (tester) async {
    var calls = 0;
    final batch = UiNotificationBatcher(onNotify: () => calls++);
    try {
      batch.setInterval(const Duration(milliseconds: 500));
      batch.mark();
      await tester.pump(const Duration(milliseconds: 100));
      batch.mark(priority: true);
      await tester.pump(const Duration(milliseconds: 49));
      expect(calls, 0);
      batch.mark(priority: true);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 1);
    } finally {
      batch.dispose();
    }
  });

  testWidgets('priority cannot move an already closer deadline later', (tester) async {
    var calls = 0;
    final batch = UiNotificationBatcher(onNotify: () => calls++);
    try {
      batch.setInterval(const Duration(milliseconds: 500));
      batch.mark();
      await tester.pump(const Duration(milliseconds: 480));
      batch.mark(priority: true);
      await tester.pump(const Duration(milliseconds: 20));
      expect(calls, 1);
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls, 1);
    } finally {
      batch.dispose();
    }
  });

  testWidgets('a longer interval applies to the next window without postponing pending work',
      (tester) async {
    var calls = 0;
    final batch = UiNotificationBatcher(onNotify: () => calls++);
    try {
      batch.setInterval(const Duration(milliseconds: 100));
      batch.mark();
      await tester.pump(const Duration(milliseconds: 50));
      batch.setInterval(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls, 1);
      batch.mark();
      await tester.pump(const Duration(milliseconds: 499));
      expect(calls, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 2);
    } finally {
      batch.dispose();
    }
  });

  testWidgets('a shorter interval flushes pending work asynchronously without a fresh delay',
      (tester) async {
    var calls = 0;
    final batch = UiNotificationBatcher(onNotify: () => calls++);
    try {
      batch.setInterval(const Duration(milliseconds: 500));
      batch.mark(priority: true);
      await tester.pump(const Duration(milliseconds: 20));
      batch.setInterval(UiNotificationBatcher.minimum);
      expect(calls, 0);
      // В отличие от pump(), elapse(0) исполняет ожидающий Timer.zero.
      await tester.pump(Duration.zero);
      expect(calls, 1);
      batch.mark();
      await tester.pump(const Duration(milliseconds: 49));
      expect(calls, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 2);
    } finally {
      batch.dispose();
    }
  });

  testWidgets('the same setting does not reset a pending window', (tester) async {
    var calls = 0;
    final batch = UiNotificationBatcher(onNotify: () => calls++);
    try {
      batch.setInterval(const Duration(milliseconds: 500));
      batch.mark();
      await tester.pump(const Duration(milliseconds: 400));
      batch.setInterval(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 99));
      expect(calls, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 1);
    } finally {
      batch.dispose();
    }
  });

  testWidgets('a reentrant listener starts an independent priority window', (tester) async {
    var calls = 0;
    late UiNotificationBatcher batch;
    batch = UiNotificationBatcher(onNotify: () {
      calls++;
      if (calls == 1) {
        batch.mark(priority: true);
      }
    });
    try {
      batch.setInterval(const Duration(milliseconds: 500));
      batch.mark();
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls, 1);
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 2);
    } finally {
      batch.dispose();
    }
  });

  testWidgets('dispose cancels both deadlines and rejects later marks and settings',
      (tester) async {
    var calls = 0;
    final batch = UiNotificationBatcher(onNotify: () => calls++);
    batch.setInterval(const Duration(milliseconds: 500));
    batch.mark(priority: true);
    batch.dispose();
    batch.mark();
    batch.setInterval(UiNotificationBatcher.minimum);
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 0);
  });
}
