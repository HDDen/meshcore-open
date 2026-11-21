/// Optional MCMP identity attached to a sender rule. Never trust an unverified
/// claimed key: callers provide a key only after successful verification.
class SenderFilterIdentity {
  static final _key = RegExp(r'^[0-9a-fA-F]{64}$');

  static String? normalizeKey(Object? value) {
    if (value is! String) { return null; }
    final key = value.trim();
    return _key.hasMatch(key) ? key.toLowerCase() : null;
  }

  static String? keyFromJson(Object? value) {
    if (value == null) { return null; }
    final key = normalizeKey(value);
    if (key == null) { throw const FormatException('Invalid sender filter key'); }
    return key;
  }

  static bool matches({
    required String? boundKey,
    required String? verifiedKey,
    required bool nameMatches,
  }) => boundKey != null && verifiedKey != null
      ? boundKey.toLowerCase() == verifiedKey
      : nameMatches;
}
