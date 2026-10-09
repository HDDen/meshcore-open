import 'dart:convert';
import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';

/// A contact shared as a `meshcore://` link, in the two forms the mesh uses:
///
/// ```
/// meshcore://1100afdad95d…8286530c8151524c
/// meshcore://contact/add?name=Example+Contact&public_key=9cd8…65b1&type=1
/// ```
///
/// The first is the contact's advert packet as hex, header and path
/// included: what the contacts and discovery screens copy to the clipboard,
/// and what the node imports and verifies itself, signature and all
/// (CMD_IMPORT_CONTACT). The second is the MeshCore mobile app's link
/// (MeshCore `docs/qr_codes.md`): a name, URL-encoded, a 32-byte public key
/// as 64 hex characters and the numeric type, 1 companion, 2 repeater,
/// 3 room server, 4 sensor; the app writes such a contact itself, unsigned,
/// as it does from a shared contact card.
sealed class ContactLink {
  const ContactLink();

  static const String scheme = 'meshcore://';
  static const String _addPrefix = 'contact/add';

  /// The contact's key, 64 lower-case hex characters.
  String get publicKeyHex;

  /// One of the four advert types.
  int get type;

  /// The name the link carries, or the key's first eight characters.
  String get name;

  String get shortPublicKey =>
      '${publicKeyHex.substring(0, 6)}...'
      '${publicKeyHex.substring(publicKeyHex.length - 6)}';

  /// Null for anything that is not a well-formed contact link.
  static ContactLink? tryParse(String raw) {
    final text = raw.trim();
    if (text.length <= scheme.length ||
        text.substring(0, scheme.length).toLowerCase() != scheme) {
      return null;
    }
    final rest = text.substring(scheme.length);
    if (rest.length > _addPrefix.length &&
        rest.substring(0, _addPrefix.length).toLowerCase() == _addPrefix) {
      return ContactAddLink._tryParse(text);
    }
    return ContactAdvertLink._tryParse(rest);
  }

  static bool isKnownType(int type) =>
      type == advTypeChat ||
      type == advTypeRepeater ||
      type == advTypeRoom ||
      type == advTypeSensor;

  static String _nameFor(String name, String publicKeyHex) =>
      name.trim().isEmpty ? publicKeyHex.substring(0, 8) : name.trim();
}

/// `meshcore://<hex>`: the contact's advert packet, for the node to import.
final class ContactAdvertLink extends ContactLink {
  const ContactAdvertLink._({
    required this.packet,
    required this.publicKeyHex,
    required this.type,
    required this.name,
  });

  /// The packet as the link carries it, header and path included, which is
  /// what CMD_IMPORT_CONTACT takes.
  final Uint8List packet;

  @override
  final String publicKeyHex;

  @override
  final int type;

  @override
  final String name;

  static const int _payloadTypeAdvert = 0x04;
  static const int _signatureSize = 64;

  /// Header, path length, key, timestamp, signature and flags: the shortest
  /// advert packet there is.
  static const int _minLength = 2 + pubKeySize + 4 + _signatureSize + 1;

  /// More than any frame carries.
  static const int _maxLength = 256;

  static final RegExp _hex = RegExp(r'^[0-9a-fA-F]+$');

  static ContactAdvertLink? _tryParse(String hex) {
    if (hex.length.isOdd ||
        hex.length < _minLength * 2 ||
        hex.length > _maxLength * 2 ||
        !_hex.hasMatch(hex)) {
      return null;
    }
    final packet = hex2Uint8List(hex);
    if ((packet[0] >> 2) & 0x0F != _payloadTypeAdvert) return null;
    // The path byte packs the hop count with the hash width in its top bits.
    final pathByte = packet[1];
    var i = 2 + (pathByte & 0x3F) * ((pathByte >> 6) + 1);
    if (packet.length < i + pubKeySize + 4 + _signatureSize + 1) return null;
    final key = packet.sublist(i, i + pubKeySize);
    i += pubKeySize + 4 + _signatureSize;
    final flags = packet[i++];
    final type = flags & 0x0F;
    if (!ContactLink.isKnownType(type)) return null;
    if (flags & 0x10 != 0) i += 8; // latitude and longitude
    if (flags & 0x20 != 0) i += 2; // feature 1
    if (flags & 0x40 != 0) i += 2; // feature 2
    if (i > packet.length) return null;
    var name = '';
    if (flags & 0x80 != 0) {
      var end = packet.indexOf(0, i);
      if (end < 0) end = packet.length;
      name = utf8.decode(packet.sublist(i, end), allowMalformed: true);
    }
    final publicKeyHex = pubKeyToHex(key);
    return ContactAdvertLink._(
      packet: packet,
      publicKeyHex: publicKeyHex,
      type: type,
      name: ContactLink._nameFor(name, publicKeyHex),
    );
  }
}

/// `meshcore://contact/add?name=…&public_key=…&type=…`: the MeshCore app's
/// link, a name, a key and a type and nothing the node could verify.
final class ContactAddLink extends ContactLink {
  const ContactAddLink._({
    required this.publicKey,
    required this.publicKeyHex,
    required this.type,
    required this.name,
  });

  final Uint8List publicKey;

  @override
  final String publicKeyHex;

  @override
  final int type;

  @override
  final String name;

  static final RegExp _key = RegExp(r'^[0-9a-fA-F]{64}$');

  static ContactAddLink? _tryParse(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'meshcore' ||
        uri.host.toLowerCase() != 'contact') {
      return null;
    }
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

    final keyHex = (query['public_key'] ?? '').trim();
    if (!_key.hasMatch(keyHex)) return null;
    // A link without a type names a companion node, the common case.
    final typeText = (query['type'] ?? '').trim();
    final type = typeText.isEmpty ? advTypeChat : int.tryParse(typeText);
    if (type == null || !ContactLink.isKnownType(type)) return null;

    final publicKeyHex = keyHex.toLowerCase();
    return ContactAddLink._(
      publicKey: hex2Uint8List(publicKeyHex),
      publicKeyHex: publicKeyHex,
      type: type,
      name: ContactLink._nameFor(query['name'] ?? '', publicKeyHex),
    );
  }
}
