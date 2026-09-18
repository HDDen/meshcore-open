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
/// Fork-only for now. Everything about channel QR codes lives in this file, in
/// `screens/channel_qr_scanner_screen.dart` (scanning) and
/// `screens/channel_share_screen.dart` (showing), and behind the
/// `channel-qr-scan` / `channel-qr-share` marks in `screens/channels_screen.dart`
/// and `screens/channel_chat_screen.dart`, so it can be dropped in one go if
/// upstream ships its own version. The share screen is also the only caller of
/// `qr_bitmap.dart` and `image_clipboard.dart`, which are generic on purpose.
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

  /// What a region name holds, the limit the region screen types under.
  static const int maxRegionLength = 30;

  final String name;
  final Uint8List psk;

  /// Region the channel floods in, the way the app keeps regions, without
  /// the leading `#`; null when the link names none.
  final String? regionScope;

  bool get isHashtag => name.startsWith('#');

  /// The link for this channel, the way the MeshCore app writes it: the name
  /// URL-encoded, the secret as 32 lower-case hex characters, and
  /// `region_scope` only when a region is given.
  String toLink() => Uri(
    scheme: 'meshcore',
    host: 'channel',
    path: '/add',
    queryParameters: {
      'name': name,
      'secret': Channel.formatPskHex(psk).toLowerCase(),
      if ((regionScope ?? '').trim().isNotEmpty)
        'region_scope': regionScope!.trim(),
    },
  ).toString();

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

    final region = _regionOf(query['region_scope'] ?? '');
    if (region == null) return null;
    return ChannelQrLink(
      name: _fitName(fullName),
      psk: psk,
      regionScope: region.isEmpty ? null : region,
    );
  }

  /// What scanning this link should do to [channels], the node's current ones.
  /// [regionOf] tells the region a channel has now, empty for none.
  ///
  /// The key is the channel, so a key the node already holds under another
  /// name is never written a second time. A name the node already holds is
  /// offered an update instead of a second slot: the link replaces the key
  /// and the region of that channel. Names are compared the way
  /// `ChannelIdentityMatcher` compares them, trimmed and without case.
  ChannelQrImport importInto(
    List<Channel> channels, {
    required String Function(int channelIndex) regionOf,
  }) {
    final pskHex = Channel.formatPskHex(psk).toLowerCase();
    final nameKey = name.trim().toLowerCase();
    Channel? sameKey;
    Channel? sameName;
    for (final channel in channels) {
      if (channel.isEmpty) continue;
      if (channel.pskHex.toLowerCase() == pskHex) sameKey ??= channel;
      if (channel.name.trim().toLowerCase() == nameKey) sameName ??= channel;
    }
    if (sameKey != null && sameKey.index != sameName?.index) {
      return ChannelQrImport(ChannelQrImportAction.alreadyAdded, sameKey);
    }
    if (sameName == null) {
      return const ChannelQrImport(ChannelQrImportAction.add, null);
    }
    final nothingToChange =
        sameKey != null &&
        regionOf(sameName.index).trim() == (regionScope ?? '');
    return ChannelQrImport(
      nothingToChange
          ? ChannelQrImportAction.alreadyAdded
          : ChannelQrImportAction.update,
      sameName,
    );
  }

  /// The scope a link names, without the leading `#` the hash adds back by
  /// itself. Empty when the link names none; null when it names one the app
  /// could not use: longer than a region name gets, a private `$` region
  /// whose key lives on a repeater, or characters no region name has. The
  /// byte rule is the one regions fetched from a repeater are held to. A link
  /// like that is refused whole, because an update takes "no region" as an
  /// order to clear the one the channel has.
  static String? _regionOf(String raw) {
    var region = raw.trim();
    if (region.startsWith('#')) region = region.substring(1).trim();
    if (region.isEmpty) return '';
    if (region.startsWith(r'$')) return null;
    final bytes = utf8.encode(region);
    if (bytes.length > maxRegionLength) return null;
    final usable = bytes.every(
      (byte) =>
          byte == 0x2D || (byte >= 0x30 && byte <= 0x39) || byte >= 0x41,
    );
    return usable ? region : null;
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

enum ChannelQrImportAction { add, update, alreadyAdded }

/// The verdict of [ChannelQrLink.importInto]: what to do, and for anything
/// but [ChannelQrImportAction.add] the channel it is about.
class ChannelQrImport {
  const ChannelQrImport(this.action, this.existing);

  final ChannelQrImportAction action;
  final Channel? existing;
}
