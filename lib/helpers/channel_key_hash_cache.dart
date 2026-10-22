import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// Кэш только первого байта SHA256; проверка MAC и расшифровка ему не доверяют.
class ChannelKeyHashCache {
  ChannelKeyHashCache({int Function(Uint8List)? compute})
      : _compute = compute ?? _sha256FirstByte;

  final int Function(Uint8List) _compute;
  Expando<_HashSnapshot> _entries = Expando<_HashSnapshot>();
  bool _enabled = false;

  void setEnabled(bool enabled) {
    if (_enabled == enabled) {
      return;
    }
    _enabled = enabled;
    clear();
  }

  void clear() => _entries = Expando<_HashSnapshot>();

  int hash(Uint8List key) {
    if (!_enabled) {
      return _compute(key);
    }
    final entry = _entries[key];
    // Uint8List может измениться через alias, сохранив identity.
    if (entry != null && _sameBytes(entry.bytes, key)) {
      return entry.hash;
    }
    final hash = _compute(key);
    _entries[key] = _HashSnapshot(key, hash);
    return hash;
  }

  static int _sha256FirstByte(Uint8List key) =>
      crypto.sha256.convert(key).bytes[0];

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

class _HashSnapshot {
  _HashSnapshot(Uint8List key, this.hash) : bytes = Uint8List.fromList(key);
  final Uint8List bytes;
  final int hash;
}
