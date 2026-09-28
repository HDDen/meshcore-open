/// Prefix matching of path hashes against public keys.
///
/// The RX log runs these for every relayed packet against every repeater the
/// app knows, so neither builds a string per candidate: a key's bytes are
/// compared in place, and the hex form of a key is read digit by digit, in
/// either letter case.
abstract final class KeyPrefixMatch {
  /// Whether [publicKey] starts with the bytes of [prefix].
  static bool keyStartsWith(List<int> publicKey, List<int> prefix) {
    if (publicKey.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (publicKey[i] != prefix[i]) return false;
    }
    return true;
  }

  /// Whether the hex form [keyHex] of a key starts with the bytes of
  /// [prefix]. Upper and lower case digits are the same key.
  static bool hexStartsWith(String keyHex, List<int> prefix) {
    if (keyHex.length < prefix.length * 2) return false;
    for (var i = 0; i < prefix.length; i++) {
      final byte = prefix[i];
      if (_nibble(keyHex.codeUnitAt(2 * i)) != (byte >> 4) ||
          _nibble(keyHex.codeUnitAt(2 * i + 1)) != (byte & 0x0F)) {
        return false;
      }
    }
    return true;
  }

  static int _nibble(int codeUnit) {
    if (codeUnit >= 0x30 && codeUnit <= 0x39) return codeUnit - 0x30;
    if (codeUnit >= 0x61 && codeUnit <= 0x66) return codeUnit - 0x57;
    if (codeUnit >= 0x41 && codeUnit <= 0x46) return codeUnit - 0x37;
    return -1;
  }
}
