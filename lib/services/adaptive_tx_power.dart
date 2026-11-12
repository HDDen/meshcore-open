import 'dart:async';

import '../models/adaptive_tx_power_settings.dart';

typedef TxPowerSession = ({String nodeKey, int revision});
typedef TxPowerRecovery = ({TxPowerSession session, int current, int initial});

/// Serializes changes to the companion's global TX power. A lease lasts until
/// the retry series has heard sufficient echoes/an ACK, timed out, or stopped.
class AdaptiveTxPower {
  AdaptiveTxPower({
    required this.currentSession,
    required this.currentPower,
    required this.maximumPower,
    required this.readBaseline,
    required this.writeBaseline,
    required this.setPower,
  });

  final TxPowerSession? Function() currentSession;
  final int Function() currentPower;
  final int Function() maximumPower;
  final Future<int?> Function(String nodeKey) readBaseline;
  final Future<void> Function(String nodeKey, int? power) writeBaseline;
  final Future<void> Function(TxPowerSession session, int power) setPower;

  Future<void> _tail = Future.value();
  final Set<Object> _owners = Set.identity();
  TxPowerSession? _session;
  int? _baseline;
  bool _powerUnconfirmed = false;

  Future<T> _locked<T>(Future<T> Function() action) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      final session = currentSession();
      if (_session != session) {
        _session = session;
        _owners.clear();
        _baseline = null;
        _powerUnconfirmed = false;
      }
      return await action();
    } finally {
      done.complete();
    }
  }

  static bool isInLastRetries({
    required int retry,
    required int maxRetries,
    required int boostedRetries,
  }) => retry > 0 && retry <= maxRetries && retry > maxRetries - boostedRetries;

  int _targetPower(int target) => AdaptiveTxPowerSettings.normalizeTarget(target)
      .clamp(-9, maximumPower().clamp(-9, AdaptiveTxPowerSettings.maxTargetDbm))
      .toInt();

  int? get leasedBaseline =>
      _owners.isNotEmpty && _session == currentSession() ? _baseline : null;

  bool canRaise(int target) {
    final session = currentSession();
    if (session == null || _hasUnconfirmedBaseline(session)) return false;
    return _targetPower(target) > (leasedBaseline ?? currentPower());
  }

  bool _hasUnconfirmedBaseline(TxPowerSession session) =>
      _session == session && _owners.isEmpty && _powerUnconfirmed;

  Future<bool> acquire(Object owner, int target) {
    final requestedSession = currentSession();
    return _locked(() async {
      final session = _session;
      if (session == null || session != requestedSession ||
          _hasUnconfirmedBaseline(session)) {
        return false;
      }
      final power = _targetPower(target);
      final current = currentPower();
      if (power <= (_baseline ?? current)) return false;
      if (_owners.isEmpty) {
        // An interrupted session must be resolved before opening another lease.
        if (await readBaseline(session.nodeKey) != null) return false;
        if (currentSession() != session) return false;
        await writeBaseline(session.nodeKey, current);
        _baseline = current;
      }
      _owners.add(owner);
      if (_powerUnconfirmed || power > current) {
        await _apply(session, power);
      }
      return true;
    });
  }

  Future<void> release(Object owner) => _locked(() async {
    final session = _session;
    final baseline = _baseline;
    if (!_owners.remove(owner) || _owners.isNotEmpty ||
        session == null || baseline == null) {
      return;
    }
    if (_powerUnconfirmed || currentPower() != baseline) {
      await _apply(session, baseline);
    }
    await writeBaseline(session.nodeKey, null);
    _baseline = null;
  });

  Future<void> setManualPower(int power, {void Function()? validate}) {
    final requestedSession = currentSession();
    return _locked(() async {
      final session = _session;
      if (session == null || session != requestedSession) {
        throw StateError('Radio session changed');
      }
      validate?.call();
      final hasBaseline = _baseline != null ||
          await readBaseline(session.nodeKey) != null;
      if (currentSession() != session) throw StateError('Radio session changed');
      validate?.call();
      if (hasBaseline) {
        await writeBaseline(session.nodeKey, power);
        _baseline = power;
      }
      // A manual edit changes the baseline immediately. Keep an active
      // lease elevated until the last owner finishes.
      if (_owners.isEmpty || power > currentPower()) {
        await _apply(session, power);
      }
      if (hasBaseline && _owners.isEmpty) {
        await writeBaseline(session.nodeKey, null);
        _baseline = null;
      }
    });
  }

  Future<TxPowerRecovery?> pendingRecovery() => _locked(() async {
    final session = _session;
    if (session == null || _owners.isNotEmpty) return null;
    final initial = await readBaseline(session.nodeKey);
    if (initial == null || currentSession() != session) return null;
    final current = currentPower();
    if (current == initial && !_powerUnconfirmed) {
      await writeBaseline(session.nodeKey, null);
      _baseline = null;
      return null;
    }
    return (session: session, current: current, initial: initial);
  });

  Future<void> resolveRecovery(TxPowerRecovery recovery, {required bool restore}) =>
      _locked(() async {
        final session = recovery.session;
        if (_session != session || _owners.isNotEmpty ||
            await readBaseline(session.nodeKey) != recovery.initial ||
            currentSession() != session) {
          return;
        }
        if (restore) await _apply(session, recovery.initial);
        await writeBaseline(session.nodeKey, null);
        _baseline = null;
        _powerUnconfirmed = false;
      });

  Future<void> _apply(TxPowerSession session, int power) async {
    _powerUnconfirmed = true;
    await setPower(session, power);
    _powerUnconfirmed = false;
  }
}
