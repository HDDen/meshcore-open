import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/adaptive_tx_power.dart';

class _Radio {
  TxPowerSession? session = (nodeKey: 'node-a', revision: 1);
  int power = 11;
  final baseline = <String, int>{};
  final events = <String>[];
  bool rejectPower = false;

  late final coordinator = AdaptiveTxPower(
    currentSession: () => session,
    currentPower: () => power,
    maximumPower: () => 20,
    readBaseline: (nodeKey) async => baseline[nodeKey],
    writeBaseline: (nodeKey, value) async {
      events.add('journal:$nodeKey:$value');
      if (value == null) {
        baseline.remove(nodeKey);
      } else {
        baseline[nodeKey] = value;
      }
    },
    setPower: (session, value) async {
      if (this.session != session || rejectPower) {
        throw StateError('Power write not confirmed');
      }
      events.add('radio:$value');
      power = value;
    },
  );
}

void main() {
  test('only the last two of three resends are eligible for a boost', () {
    expect(
      [
        for (final retry in [0, 1, 2, 3])
          AdaptiveTxPower.isInLastRetries(
            retry: retry,
            maxRetries: 3,
            boostedRetries: 2,
          ),
      ],
      [false, false, true, true],
    );
  });

  for (final firstFinishesFirst in [true, false]) {
    test('parallel sends restore only after both finish ($firstFinishesFirst)',
        () async {
      final radio = _Radio();
      final first = Object();
      final second = Object();
      expect(
        await Future.wait([
          radio.coordinator.acquire(first, 22),
          radio.coordinator.acquire(second, 22),
        ]),
        [true, true],
      );
      expect(radio.events, ['journal:node-a:11', 'radio:20']);
      await radio.coordinator.release(firstFinishesFirst ? first : second);
      expect(radio.power, 20);
      expect(radio.baseline, {'node-a': 11});
      await radio.coordinator.release(firstFinishesFirst ? second : first);
      expect(radio.power, 11);
      expect(radio.baseline, isEmpty);
    });
  }

  test('a target at or below the current power needs no journal', () async {
    final radio = _Radio();
    final owner = Object();
    expect(await radio.coordinator.acquire(owner, 11), isFalse);
    expect(await radio.coordinator.acquire(owner, 2), isFalse);
    await radio.coordinator.release(owner);
    expect(radio.events, isEmpty);
  });

  test('manual power becomes the restoration target', () async {
    final radio = _Radio();
    final owner = Object();
    await radio.coordinator.acquire(owner, 20);
    await radio.coordinator.setManualPower(13);
    expect(radio.baseline, {'node-a': 13});
    expect(radio.power, 20);
    expect(await radio.coordinator.acquire(owner, 20), isTrue);
    await radio.coordinator.release(owner);
    expect(radio.power, 13);
    expect(radio.baseline, isEmpty);
  });

  for (final restore in [true, false]) {
    test('an interrupted boost is scoped to its node (restore: $restore)',
        () async {
      final radio = _Radio();
      final owner = Object();
      await radio.coordinator.acquire(owner, 18);
      radio.session = null;
      await radio.coordinator.release(owner);
      expect(radio.baseline, {'node-a': 11});
      radio.session = (nodeKey: 'node-b', revision: 2);
      expect(await radio.coordinator.pendingRecovery(), isNull);
      radio.session = (nodeKey: 'node-a', revision: 3);
      final recovery = (await radio.coordinator.pendingRecovery())!;
      expect((recovery.current, recovery.initial), (18, 11));
      expect(await radio.coordinator.acquire(Object(), 22), isFalse);
      await radio.coordinator.resolveRecovery(recovery, restore: restore);
      expect(radio.power, restore ? 11 : 18);
      expect(radio.baseline, isEmpty);
    });
  }

  test('an unconfirmed manual write cannot become a boost baseline', () async {
    final radio = _Radio()..rejectPower = true;
    await expectLater(radio.coordinator.setManualPower(14), throwsStateError);
    expect(radio.coordinator.canRaise(20), isFalse);
    expect(await radio.coordinator.acquire(Object(), 20), isFalse);
    expect(radio.baseline, isEmpty);
  });

  test('a rejected restoration keeps the journal until recovery', () async {
    final radio = _Radio();
    final owner = Object();
    await radio.coordinator.acquire(owner, 18);
    radio.rejectPower = true;
    await expectLater(radio.coordinator.release(owner), throwsStateError);
    expect(radio.baseline, {'node-a': 11});
    expect((await radio.coordinator.pendingRecovery())?.initial, 11);
  });
}
