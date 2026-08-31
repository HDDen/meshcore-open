import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'channel_app_data_helper.dart';
import 'mcoimg_codec.dart';
import 'mcoimg_v3_codec.dart';
import 'mcoimg_v4_codec.dart';

/// Canonical identity hash for MCOimg payloads, used to match a received
/// LoRa image against the original file shipped in a *.mcoimg.pack.
///
/// Formula (the external contract for pack tooling / *.md5 files):
/// Lowercase hex MD5 of the canonical `.mcoimg.bin` identity. V3 zeroes its
/// one-byte nonce. V4 also excludes its transport tail and hashes
/// `[0x14][zero nonce][document length][canonical document]`. Legacy v1/v2
/// payloads have no transport metadata and are hashed as-is.
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
      if (MCOImageV4Codec.isTextPayload(trimmed)) {
        final body = const MCOImageV4Codec().bodyFromText(trimmed);
        return hashFromBinaryPayload(
          ChannelAppDataHelper.appPayloadWithoutSender(
            subtypeId: ChannelAppDataHelper.mcoImageSubtype,
            version: ChannelAppDataHelper.mcoImageV4Version,
            body: body,
          ),
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
        ChannelAppDataHelper.mcoImageV4SubtypeVersion) {
      final canonical = const MCOImageV4Codec()
          .canonicalAppPayloadWithoutSender(appPayload!.body);
      return crypto.md5.convert(canonical).toString();
    }
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
