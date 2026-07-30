import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'channel_app_data_helper.dart';
import 'mcoimg_codec.dart';
import 'mcoimg_v3_codec.dart';

/// Canonical identity hash for MCOimg payloads, used to match a received
/// LoRa image against the original file shipped in a *.mcoimg.pack.
///
/// Formula (the external contract for pack tooling / *.md5 files):
/// lowercase hex MD5 of the `.mcoimg.bin` bytes, where for v3 payloads the
/// one-byte transport nonce is zeroed before hashing. The bin file is the
/// app payload without sender (`[subtypeVersion 0x13][body]`), and the v3
/// nonce is `body[0]`, i.e. the byte at index 1 of the file. Legacy v1/v2
/// payloads have no nonce and are hashed as-is.
class MCOImageIdentity {
  MCOImageIdentity._();

  /// Hash from a chat text payload (`im3:` Base91 wrapper or a legacy
  /// `mcoimg` text). Returns null when [text] is not a parsable MCOimg
  /// payload.
  static String? hashFromText(String text) {
    final trimmed = text.trimLeft();
    try {
      if (MCOImageV3Codec.isTextPayload(trimmed)) {
        return hashFromBinaryPayload(
          MCOImageV3Codec.appPayloadWithoutSenderFromText(trimmed),
        );
      }
      if (trimmed.startsWith(MCOImageCodec.prefix)) {
        return hashFromBinaryPayload(
          MCOImageCodec.binaryPayloadFromText(trimmed),
        );
      }
    } catch (_) {
      // Fall through: unparsable payloads have no identity.
    }
    return null;
  }

  /// Hash from binary payload bytes (the `.mcoimg.bin` file contents).
  static String hashFromBinaryPayload(Uint8List payload) {
    final normalized = Uint8List.fromList(payload);
    final appPayload = ChannelAppDataHelper.tryDecodeAppPayloadWithoutSender(
      normalized,
    );
    if (appPayload?.subtypeVersion ==
            ChannelAppDataHelper.mcoImageV3SubtypeVersion &&
        normalized.length >= 2) {
      // The v3 body starts with a one-byte packet nonce right after the
      // subtypeVersion byte; zero it so the identity is transport-stable.
      normalized[1] = 0;
    }
    return crypto.md5.convert(normalized).toString();
  }

  /// True when [value] looks like a canonical hash (32 hex chars).
  static bool isValidHash(String value) {
    if (value.length != 32) return false;
    for (final codeUnit in value.codeUnits) {
      final isDigit = codeUnit >= 0x30 && codeUnit <= 0x39;
      final isLowerHex = codeUnit >= 0x61 && codeUnit <= 0x66;
      final isUpperHex = codeUnit >= 0x41 && codeUnit <= 0x46;
      if (!isDigit && !isLowerHex && !isUpperHex) return false;
    }
    return true;
  }
}
