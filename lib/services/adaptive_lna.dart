import 'adaptive_tx_power.dart';

typedef LnaCliAction = Future<void> Function(
  Future<String> Function(String command) send,
);

/// Shares the node's RX gain across overlapping boosted retry series.
/// The connector calls these methods under its radio command lock.
class AdaptiveLna {
  AdaptiveLna({required this.currentSession, required this.runCli});

  final TxPowerSession? Function() currentSession;
  final Future<void> Function(
    TxPowerSession session,
    LnaCliAction action,
  ) runCli;

  static const _getGain = 'get radio.fem.rxgain';
  static const _enableGain = 'set radio.fem.rxgain on';
  static const _disableGain = 'set radio.fem.rxgain off';
  static final _gainReply = RegExp(
    r'^(?:>\s*|(?:ok\s*-\s*)?(?:lora fem )?rx gain )?(on|off)$',
    caseSensitive: false,
  );

  final Set<Object> _owners = Set.identity();
  final _restoreOff = <String, TxPowerSession>{};
  final _recoveryAttempted = <String>{};
  TxPowerSession? _ownerSession;
  bool _checked = false;

  static bool? _parseGain(String reply) {
    final state = _gainReply.firstMatch(reply.trim())?.group(1);
    return state == null ? null : state.toLowerCase() == 'on';
  }

  Future<void> acquire(Object owner, TxPowerSession session, {
    required bool enabled,
    bool Function()? canProceed,
  }) async {
    if (currentSession() != session) return;
    if (_ownerSession != session) {
      _ownerSession = session;
      _owners.clear();
      _checked = false;
    }
    _owners.add(owner);
    if (!enabled || _checked || canProceed?.call() == false) return;
    await runCli(session, (send) async {
      if (canProceed?.call() == false) return;
      _checked = true;
      final gain = _parseGain(await send(_getGain));
      if (currentSession() != session || canProceed?.call() == false) {
        _checked = false;
        return;
      }
      if (gain != false) return;
      // A lost reply does not tell us whether the change took effect.
      _restoreOff[session.nodeKey] = session;
      _recoveryAttempted.remove(session.nodeKey);
      if (_parseGain(await send(_enableGain)) != true) {
        throw StateError('LNA enable was not confirmed');
      }
    });
  }

  Future<void> release(Object owner) async {
    if (!_owners.remove(owner) || _owners.isNotEmpty) return;
    _checked = false;
    final session = _ownerSession;
    if (session != null && currentSession() == session) {
      await _restore(session);
    }
  }

  bool needsReconnectRestore(TxPowerSession session) {
    final previous = _restoreOff[session.nodeKey];
    return previous != null && previous != session &&
        !_recoveryAttempted.contains(session.nodeKey) &&
        (_ownerSession != session || _owners.isEmpty);
  }

  Future<void> restoreAfterReconnect(TxPowerSession session) async {
    if (currentSession() != session || !needsReconnectRestore(session)) return;
    // A failed CLI request can restart the transport. Limit unattended
    // recovery to one attempt per interrupted change.
    _recoveryAttempted.add(session.nodeKey);
    await _restore(session);
  }

  Future<void> _restore(TxPowerSession session) async {
    if (!_restoreOff.containsKey(session.nodeKey)) return;
    await runCli(session, (send) async {
      if (_parseGain(await send(_disableGain)) != false) {
        throw StateError('LNA restore was not confirmed');
      }
    });
    _restoreOff.remove(session.nodeKey);
    _recoveryAttempted.remove(session.nodeKey);
  }
}
