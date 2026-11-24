import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/tcp_reconnect_pause.dart';

void main() {
  late Duration now;
  late TcpReconnectPause guard;
  setUp(() {
    now = Duration.zero;
    guard = TcpReconnectPause(now: () => now);
  });
  bool lose({bool synced = false, bool manual = false, String endpoint = 'node:5000'}) {
    guard.beginAttempt(endpoint);
    if (synced) guard.markSynchronized();
    return guard.endAttempt(manual: manual);
  }

  test('five incomplete syncs pause even when spread over more than a minute', () {
    for (var i = 0; i < 4; i++) {
      expect(lose(), isFalse);
      now += const Duration(minutes: 2);
    }
    expect(lose(), isTrue);
    expect(guard.remaining, const Duration(seconds: 30));
    now += const Duration(seconds: 29);
    expect(guard.isPaused, isTrue);
    now += const Duration(seconds: 1);
    expect(guard.isPaused, isFalse);
    expect(lose(), isFalse);
  });

  test('five rapid losses pause even after each session completed sync', () {
    for (var i = 0; i < 4; i++) {
      expect(lose(synced: true), isFalse);
      now += const Duration(seconds: 10);
    }
    expect(lose(synced: true), isTrue);
  });

  test('stable completed sync resets consecutive incomplete attempts', () {
    for (var i = 0; i < 4; i++) {
      lose();
      now += const Duration(minutes: 2);
    }
    expect(lose(synced: true), isFalse);
    now += const Duration(minutes: 2);
    for (var i = 0; i < 4; i++) {
      expect(lose(), isFalse);
      now += const Duration(minutes: 2);
    }
    expect(guard.isPaused, isFalse);
  });

  test('completed sessions with losses a minute apart do not pause', () {
    for (var i = 0; i < 10; i++) {
      expect(lose(synced: true), isFalse);
      now += const Duration(minutes: 1);
    }
  });

  test('manual disconnects and duplicate teardown callbacks are not failures', () {
    for (var i = 0; i < 10; i++) {
      expect(lose(manual: true), isFalse);
      expect(guard.endAttempt(manual: false), isFalse);
    }
    expect(guard.isPaused, isFalse);
    for (var i = 0; i < 4; i++) {
      expect(lose(), isFalse);
      expect(guard.endAttempt(manual: false), isFalse);
    }
    expect(lose(), isTrue);
  });

  test('manual attempts cannot clear or extend an active pause', () {
    for (var i = 0; i < 5; i++) { lose(); }
    now += const Duration(seconds: 10);
    expect(lose(), isFalse);
    expect(lose(synced: true, manual: true), isFalse);
    expect(guard.remaining, const Duration(seconds: 20));
  });

  test('changing endpoint resets counts but does not bypass an active pause', () {
    for (var i = 0; i < 4; i++) { lose(); }
    expect(lose(endpoint: 'other:5000'), isFalse);
    expect(guard.isPaused, isFalse);
    for (var i = 0; i < 4; i++) { lose(endpoint: 'other:5000'); }
    expect(guard.isPaused, isTrue);
    guard.beginAttempt('third:5000');
    expect(guard.remaining, const Duration(seconds: 30));
  });
}
