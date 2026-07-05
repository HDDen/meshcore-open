import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';

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
