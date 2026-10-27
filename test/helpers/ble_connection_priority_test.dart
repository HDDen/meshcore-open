import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/ble_connection_priority.dart';
import 'package:meshcore_open/models/ble_power_options.dart';

void main() {
  for (final android in [false, true]) {
    for (final mode in BleConnectionPriorityMode.values) {
      test('request mapping: android=$android mode=${mode.name}', () async {
        final requests = <ConnectionPriority>[];
        await applyBleConnectionPriority(
          mode: mode, isAndroid: android, isCurrentSession: () => true,
          request: (value) async { requests.add(value); },
        );
        if (!android || mode == BleConnectionPriorityMode.original) {
          expect(requests, isEmpty);
        } else {
          expect(requests.single.name, mode.name);
        }
      });
    }
  }

  test('stale session makes no request; errors are nonfatal without retry', () async {
    var count = 0;
    Future<void> fail(ConnectionPriority value) async {
      count++;
      throw StateError('synthetic adapter refusal');
    }
    await applyBleConnectionPriority(
      mode: BleConnectionPriorityMode.lowPower, isAndroid: true,
      isCurrentSession: () => false, request: fail,
    );
    expect(count, 0);
    final warnings = <String>[];
    await applyBleConnectionPriority(
      mode: BleConnectionPriorityMode.lowPower, isAndroid: true,
      isCurrentSession: () => true, request: fail, onWarning: warnings.add,
    );
    expect(count, 1);
    expect(warnings.single, contains('failed'));
  });

  testWidgets('timeout returns and late completion cannot update the next session',
      (tester) async {
    final gate = Completer<void>();
    var current = true;
    var completed = false;
    final warnings = <String>[];
    final info = <String>[];
    final operation = applyBleConnectionPriority(
      mode: BleConnectionPriorityMode.high, isAndroid: true,
      isCurrentSession: () => current, request: (_) => gate.future,
      onWarning: warnings.add, onInfo: info.add,
    );
    unawaited(operation.then((_) { completed = true; }));
    await tester.pump(const Duration(seconds: 2));
    expect(completed, isTrue);
    expect(warnings, hasLength(1));
    expect(info, isEmpty);
    current = false;
    gate.complete();
    await tester.pump();
    expect(warnings, hasLength(1));
    expect(info, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('a session lost during the request suppresses late success', (tester) async {
    final gate = Completer<void>();
    var current = true;
    final info = <String>[];
    var completed = false;
    unawaited(applyBleConnectionPriority(
      mode: BleConnectionPriorityMode.lowPower, isAndroid: true,
      isCurrentSession: () => current, request: (_) => gate.future,
      onInfo: info.add,
    ).then((_) { completed = true; }));
    current = false;
    gate.complete();
    await tester.pump();
    expect(completed, isTrue);
    expect(info, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a new successful session is not suppressed by the previous request', () async {
    var count = 0;
    for (var session = 0; session < 2; session++) {
      await applyBleConnectionPriority(
        mode: BleConnectionPriorityMode.balanced, isAndroid: true,
        isCurrentSession: () => true, request: (_) async { count++; },
      );
    }
    expect(count, 2);
  });
}
