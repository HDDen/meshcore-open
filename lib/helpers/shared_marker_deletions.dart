/// "Remove for everyone" for markers shared into a channel.
///
/// The command is the marker's own text behind a `del:` prefix, sent back into
/// the channel it came from — no protocol extension, so a client that does not
/// know the convention just shows the line as text.
///
/// Two rules fall out of reading it back from the message history rather than
/// storing a decision: a command only hides markers **older than itself**, so
/// re-sharing the same pin afterwards brings it back; and deleting the command
/// from the chat undoes it, because the history no longer carries it.
class SharedMarkerDeletion {
  SharedMarkerDeletion._();

  static const String prefix = 'del:';
  static const String markerPrefix = 'm:';

  static String commandFor(String markerText) => '$prefix${markerText.trim()}';

  /// True for a shared marker itself — not a command over one.
  static bool isMarker(String text) => text.trim().startsWith(markerPrefix);

  /// True for a marker **or** a `del:` command over one. Both must stay clear
  /// of the compressors that re-encode a whole message.
  static bool isMarkerPayload(String text) {
    final trimmed = text.trim();
    return isMarker(trimmed) ||
        (targetOf(trimmed)?.startsWith(markerPrefix) ?? false);
  }

  /// Runs [encode] over the marker's label and nothing else.
  ///
  /// `m:<lat>,<lon>|<label>|<flags>` is structure everywhere but the label: a
  /// transform reaching the coordinates or the flags would make the message
  /// unparseable, so cyr2lat is applied to that one field.
  ///
  /// Only markers are ever passed here. A `del:` command travels **verbatim**:
  /// it has to repeat the label byte for byte, and the sender of the command
  /// may not be the author of the marker — a different cyr2lat profile, or one
  /// that also maps Latin letters, would rewrite an already-transliterated
  /// label and the deletion would match nothing.
  static String encodeLabel(String text, String Function(String) encode) {
    final trimmed = text.trim();
    if (!trimmed.startsWith(markerPrefix)) return text;
    final parts = trimmed.split('|');
    if (parts.length < 2) return text;
    parts[1] = encode(parts[1]);
    return parts.join('|');
  }

  /// The marker text this line deletes, or null when it is not a command.
  static String? targetOf(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith(prefix)) return null;
    final target = trimmed.substring(prefix.length).trim();
    return target.isEmpty ? null : target;
  }
}

/// The delete commands seen in one channel, and what they hide.
///
/// A command of our own that has left the radio but has not been echoed back
/// by any repeater is kept apart: nobody else has seen it yet, so it hides
/// nothing and only fades the pin.
class SharedMarkerDeletions {
  final Map<String, DateTime> _confirmedByTarget = {};
  final Map<String, DateTime> _pendingByTarget = {};

  /// Feeds one message. Returns true when it was a command rather than
  /// content, so the caller can skip it.
  bool absorb(String text, DateTime timestamp, {bool pending = false}) {
    final target = SharedMarkerDeletion.targetOf(text);
    if (target == null) return false;
    final known = pending ? _pendingByTarget : _confirmedByTarget;
    final seen = known[target];
    if (seen == null || timestamp.isAfter(seen)) {
      known[target] = timestamp;
    }
    return true;
  }

  /// True when a command covers this marker — same text, sent later than the
  /// marker itself.
  bool hides(String markerText, DateTime markerTimestamp) =>
      _covers(_confirmedByTarget, markerText, markerTimestamp);

  /// True when the only command covering this marker is still in flight.
  bool pendingHides(String markerText, DateTime markerTimestamp) =>
      _covers(_pendingByTarget, markerText, markerTimestamp);

  static bool _covers(
    Map<String, DateTime> commands,
    String markerText,
    DateTime markerTimestamp,
  ) {
    final at = commands[markerText.trim()];
    return at != null && at.isAfter(markerTimestamp);
  }
}
