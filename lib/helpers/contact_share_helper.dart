import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';

class SharedContactInfo {
  final Uint8List publicKey;
  final int type;
  final String name;

  const SharedContactInfo({
    required this.publicKey,
    required this.type,
    required this.name,
  });

  String get publicKeyHex => pubKeyToHex(publicKey);

  String get shortPublicKey {
    final hex = publicKeyHex;
    if (hex.length <= 12) return hex;
    return '${hex.substring(0, 6)}...${hex.substring(hex.length - 6)}';
  }
}

String formatContactShareText({
  required Uint8List publicKey,
  required int type,
  required String name,
}) {
  final safeName = name.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  return '<${pubKeyToHex(publicKey)}:$type:$safeName>';
}

String formatContactShareTextForContact(Contact contact) {
  return formatContactShareText(
    publicKey: contact.publicKey,
    type: contact.type,
    name: contact.name,
  );
}

SharedContactInfo? parseSharedContactText(String text) {
  final trimmed = text.trim();
  if (!trimmed.startsWith('<') || !trimmed.endsWith('>')) return null;

  final body = trimmed.substring(1, trimmed.length - 1);
  final firstSeparator = body.indexOf(':');
  if (firstSeparator <= 0) return null;
  final secondSeparator = body.indexOf(':', firstSeparator + 1);
  if (secondSeparator <= firstSeparator + 1) return null;

  final publicKeyHex = body.substring(0, firstSeparator);
  final typeText = body.substring(firstSeparator + 1, secondSeparator);
  final name = body.substring(secondSeparator + 1).trim();
  final type = int.tryParse(typeText);
  if (type == null ||
      (type != advTypeChat &&
          type != advTypeRepeater &&
          type != advTypeRoom &&
          type != advTypeSensor)) {
    return null;
  }

  try {
    return SharedContactInfo(
      publicKey: hexToPubKey(publicKeyHex),
      type: type,
      name: name.isEmpty ? publicKeyHex.substring(0, 8) : name,
    );
  } on FormatException {
    return null;
  }
}
