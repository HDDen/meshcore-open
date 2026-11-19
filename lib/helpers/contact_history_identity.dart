import '../models/message.dart';
import '../storage/shared_message_history_helper.dart';

/// Builds display-only provenance relative to the identity of the open chat.
/// Keep stored/shared snapshots unchanged: actions still receive the original.
Message contactHistoryForIdentity(
  Message message, {
  required String? selectedIdentityKey,
  required String radioKey,
  required String? radioName,
}) {
  var origin = message.sharedHistorySourceKey;
  if (origin == null && message.messageId.startsWith('identity:')) {
    final parts = message.messageId.split(':');
    if (parts.length == 3) origin = parts[1];
  }
  // Older external projections may have only a label. Preserve it rather
  // than guessing an identity from a display name.
  if (origin == null && message.sharedHistorySourceName != null) return message;
  final fromRadio = origin == null || _sameIdentity(origin, radioKey);
  origin ??= radioKey;
  final active = selectedIdentityKey ?? radioKey;
  final own = selectedIdentityKey == null && fromRadio ||
      _sameIdentity(origin, active);
  final label = own
      ? null
      : message.sharedHistorySourceName ??
          (fromRadio ? radioName : null) ??
          (origin.isEmpty ? null : origin.substring(0, origin.length < 6 ? origin.length : 6).toUpperCase());
  return label == message.sharedHistorySourceName
      ? message
      : message.copyWith(sharedHistorySourceName: label);
}

bool _sameIdentity(String left, String right) {
  final a = left.trim().toLowerCase();
  final b = right.trim().toLowerCase();
  if (a.isEmpty || b.isEmpty) return false;
  if (a.length == SharedMessageHistoryHelper.scopeLength ||
      b.length == SharedMessageHistoryHelper.scopeLength) {
    return SharedMessageHistoryHelper.scopeFor(a) ==
        SharedMessageHistoryHelper.scopeFor(b);
  }
  return a == b;
}
