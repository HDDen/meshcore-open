import 'dart:convert';

import 'cp866_codec.dart';
import 'mesh_compressor.dart';
import 'smaz.dart';

class DecodedSenderText {
  final String senderName;
  final String text;

  const DecodedSenderText({required this.senderName, required this.text});
}

class MessageTextCodec {
  static String decodeIncomingBytes(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      // Legacy Cyrillic clients may send raw CP866 bytes instead of UTF-8.
      return Cp866Codec.decode(bytes);
    }
  }

  static String? tryDecodeKnownCompression(String text) {
    return MeshCompressor.instance.tryDecodePrefixed(text) ??
        Smaz.tryDecodePrefixed(text);
  }

  static DecodedSenderText splitChannelTextBytes(List<int> bytes) {
    final colonIndex = bytes.indexOf(0x3A);
    if (colonIndex > 0 && colonIndex < bytes.length - 1 && colonIndex < 50) {
      final senderName = decodeIncomingBytes(bytes.sublist(0, colonIndex));
      if (!RegExp(r'[:\[\]]').hasMatch(senderName)) {
        final textOffset =
            colonIndex + 1 < bytes.length && bytes[colonIndex + 1] == 0x20
            ? colonIndex + 2
            : colonIndex + 1;
        return DecodedSenderText(
          senderName: senderName,
          text: decodeIncomingBytes(bytes.sublist(textOffset)),
        );
      }
    }
    return DecodedSenderText(
      senderName: 'Unknown',
      text: decodeIncomingBytes(bytes),
    );
  }
}
