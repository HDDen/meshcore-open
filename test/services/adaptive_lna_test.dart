import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/adaptive_lna.dart';
import 'package:meshcore_open/services/adaptive_tx_power.dart';

const _get = 'get radio.fem.rxgain';
const _on = 'set radio.fem.rxgain on';
const _off = 'set radio.fem.rxgain off';
const _session = (nodeKey: 'node-a', revision: 1);

class _Radio {
  TxPowerSession? session = _session;
  String readReply = '> off';
  bool loseEnableReply = false;
  final commands = <String>[];

  late final lna = AdaptiveLna(
    currentSession: () => session,
    runCli: (target, action) async {
      expect(target, session);
      await action((command) async {
        commands.add(command);
        if (command == _on && loseEnableReply) {
          throw StateError('Reply lost');
        }
        return switch (command) {
          _get => readReply,
          _on => 'OK - LoRa FEM RX gain on',
          _off => 'OK - LoRa FEM RX gain off',
          _ => throw ArgumentError.value(command),
        };
      });
    },
  );
}

void main() {
  for (final reply in ['> on', 'RX gain on', 'Error: unsupported']) {
    test('leaves RX gain unchanged after the reply "$reply"', () async {
      final radio = _Radio()..readReply = reply;
      final owner = Object();
      await radio.lna.acquire(owner, _session, enabled: true);
      await radio.lna.release(owner);
      expect(radio.commands, [_get]);
    });
  }

  for (final firstFinishesFirst in [true, false]) {
    test('LNA stays on until both retries finish ($firstFinishesFirst)', () async {
      final radio = _Radio()..readReply = 'RX gain off';
      final first = Object();
      final second = Object();
      await radio.lna.acquire(first, _session, enabled: true);
      await radio.lna.acquire(second, _session, enabled: true);
      await radio.lna.acquire(first, _session, enabled: true);
      await radio.lna.release(firstFinishesFirst ? first : second);
      expect(radio.commands, [_get, _on]);
      await radio.lna.release(firstFinishesFirst ? second : first);
      expect(radio.commands, [_get, _on, _off]);
    });
  }

  test('switching the option off preserves an active overlapping retry', () async {
    final radio = _Radio();
    final first = Object();
    final second = Object();
    await radio.lna.acquire(second, _session, enabled: false);
    expect(radio.commands, isEmpty);
    await radio.lna.acquire(first, _session, enabled: true);
    await radio.lna.release(first);
    expect(radio.commands, [_get, _on]);
    await radio.lna.release(second);
    expect(radio.commands, [_get, _on, _off]);
  });

  test('cancellation during the status query skips the write', () async {
    var canProceed = true;
    final commands = <String>[];
    final lna = AdaptiveLna(
      currentSession: () => _session,
      runCli: (_, action) => action((command) async {
        commands.add(command);
        canProceed = false;
        return '> off';
      }),
    );
    final owner = Object();
    await lna.acquire(owner, _session,
      enabled: true, canProceed: () => canProceed);
    await lna.release(owner);
    expect(commands, [_get]);
  });

  test('a lost enable reply still permits restoration', () async {
    final radio = _Radio()..loseEnableReply = true;
    final owner = Object();
    await expectLater(radio.lna.acquire(owner, _session, enabled: true),
      throwsStateError);
    await radio.lna.release(owner);
    expect(radio.commands, [_get, _on, _off]);
  });

  test('an interrupted restore runs only on the original node', () async {
    final radio = _Radio();
    final owner = Object();
    await radio.lna.acquire(owner, _session, enabled: true);
    radio.session = (nodeKey: 'node-b', revision: 2);
    await radio.lna.release(owner);
    await radio.lna.restoreAfterReconnect(radio.session!);
    expect(radio.commands, [_get, _on]);
    radio.session = (nodeKey: 'node-a', revision: 3);
    await radio.lna.restoreAfterReconnect(radio.session!);
    await radio.lna.restoreAfterReconnect(radio.session!);
    expect(radio.commands, [_get, _on, _off]);
  });
}
