import 'dart:convert';
import 'dart:typed_data';

import '../models/channel.dart';

/// A channel shared as a link or QR code, in the format the MeshCore mobile app
/// reads and writes (MeshCore `docs/qr_codes.md`):
///
/// ```
/// meshcore://channel/add?name=Public&secret=8b3387e9c5cdea6ac9e5edbaa115cd72
/// ```
///
/// `name` is URL-encoded, `secret` is the 16-byte channel key as 32 hex
/// characters, and `region_scope` is optional (MeshCore app 1.47.0 and newer).
/// A hashtag channel is the same link: its name starts with `#` and its secret
/// is the usual SHA-256 derivation. A hashtag link that carries no secret is
/// still accepted, because the key follows from the name.
///
/// Fork-only for now. Everything about scanning a channel QR lives in this file,
/// in `screens/channel_qr_scanner_screen.dart` and behind the `channel-qr-scan`
/// marks in `screens/channels_screen.dart`, so it can be dropped in one go if
/// upstream ships its own version.
class ChannelQrLink {
  const ChannelQrLink({
    required this.name,
    required this.psk,
    this.regionScope,
  });

  /// Turns the whole feature off without touching the call sites.
  static const bool enabled = true;

  /// The node stores a channel name in 32 bytes, terminator included.
  static const int maxNameLength = 31;

  final String name;
  final Uint8List psk;

  /// Region the channel floods in; null when the link names none.
  final String? regionScope;

  bool get isHashtag => name.startsWith('#');

  static bool isValid(String raw) => tryParse(raw) != null;

  /// Null for anything that is not a well-formed channel link.
  static ChannelQrLink? tryParse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'meshcore') return null;
    // `meshcore://channel/add`: the host is `channel`, the path is `/add`.
    if (uri.host.toLowerCase() != 'channel') return null;
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    if (path.toLowerCase() != '/add') return null;

    final Map<String, String> query;
    try {
      query = uri.queryParameters;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }

    final fullName = (query['name'] ?? '').trim();
    if (fullName.isEmpty) return null;

    final secret = (query['secret'] ?? '').trim();
    final Uint8List psk;
    if (secret.isEmpty) {
      // The key of a hashtag channel follows from its whole name, so derive it
      // before the name is cut to what the node can store.
      if (!fullName.startsWith('#') || fullName.length < 2) return null;
      psk = Channel.derivePskFromHashtag(fullName);
    } else {
      if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(secret)) return null;
      psk = Channel.parsePskHex(secret);
    }

    final region = (query['region_scope'] ?? '').trim();
    return ChannelQrLink(
      name: _fitName(fullName),
      psk: psk,
      regionScope: region.isEmpty ? null : region,
    );
  }

  /// The secret is what identifies a channel, the name is only a label, so an
  /// over-long one is shortened rather than refused. The cut lands on a
  /// character boundary: the frame writer would otherwise split a multi-byte
  /// character when it truncates to the node's field.
  static String _fitName(String name) {
    final buffer = StringBuffer();
    var used = 0;
    for (final rune in name.runes) {
      final character = String.fromCharCode(rune);
      final size = utf8.encode(character).length;
      if (used + size > maxNameLength) break;
      buffer.write(character);
      used += size;
    }
    return buffer.toString().trimRight();
  }
}
