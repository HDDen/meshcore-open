import 'dart:async';

import '../../models/message_filter.dart';
import '../../utils/app_logger.dart';

/// Debounces history updates and serializes batches across rule edits.
class ChannelRuleVerdictWriter {
  ChannelRuleVerdictWriter(this._collect, this._write);

  final ChannelRuleVerdictUpdates Function() _collect;
  final Future<void> Function(ChannelRuleVerdictUpdates) _write;
  final ChannelRuleVerdictUpdates _pending = {};
  Timer? _timer;
  Future<void> _tail = Future.value();

  void schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 1), () => unawaited(flush()));
  }

  Future<void> flush() {
    if (_timer != null) {
      _timer?.cancel();
      _timer = null;
      for (final entry in _collect().entries) {
        (_pending[entry.key] ??= {}).addAll(entry.value);
      }
    }
    if (_pending.isEmpty) return _tail;
    // Collect before yielding so a node switch cannot rebind these updates.
    _tail = _tail.then((_) async {
      if (_pending.isEmpty) return;
      final batch = Map.of(_pending);
      _pending.clear();
      try {
        await _write(batch);
      } catch (error) {
        // Retry at the next flush. A newer edit wins for the same row.
        for (final entry in batch.entries) {
          final newer = _pending[entry.key] ??= {};
          for (final row in entry.value.entries) {
            newer.putIfAbsent(row.key, () => row.value);
          }
        }
        appLogger.warn('Could not save channel rule verdicts: $error');
      }
    });
    return _tail;
  }
}
