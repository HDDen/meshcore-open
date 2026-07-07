import 'dart:convert';

import '../helpers/mcmp_app_codec.dart';
import '../helpers/mesh_compressor.dart';
import '../helpers/smaz.dart';

enum MessageCompressionType { mcmp, smaz, cyr2lat }

extension MessageCompressionTypeLabel on MessageCompressionType {
  String get label => switch (this) {
    MessageCompressionType.mcmp => 'mcmp',
    MessageCompressionType.smaz => 'smaz',
    MessageCompressionType.cyr2lat => 'cyr2lat',
  };

  static MessageCompressionType? fromJson(dynamic value) {
    if (value is! String) return null;
    for (final type in MessageCompressionType.values) {
      if (type.name == value) return type;
    }
    return null;
  }
}

class MessageCompressionMetadata {
  final MessageCompressionType type;
  final int savingsPercent;
  final int originalBytes;
  final int payloadBytes;

  const MessageCompressionMetadata({
    required this.type,
    required this.savingsPercent,
    required this.originalBytes,
    required this.payloadBytes,
  });

  static MessageCompressionMetadata? fromEncodedText({
    required String encodedText,
    required String decodedText,
    int sharedPayloadBytes = 0,
  }) {
    final type =
        MeshCompressor.instance.hasPrefix(encodedText) ||
            McmpAppCodec.isTextPayload(encodedText)
        ? MessageCompressionType.mcmp
        : Smaz.hasPrefix(encodedText)
        ? MessageCompressionType.smaz
        : null;
    if (type == null || encodedText == decodedText) return null;

    // MCMP v3 containers carry metadata (timestamp, signature, reply anchor)
    // on top of the compressed text; the ratio is computed over the text
    // segment only so overhead does not mask the actual compression.
    final mcmpV3TextBytes = McmpAppCodec.compressedTextBytesFromTextPayload(
      encodedText,
    );
    if (mcmpV3TextBytes != null) {
      return MessageCompressionMetadata.fromByteLengths(
        type: type,
        originalBytes: utf8.encode(decodedText).length,
        compressedBytes: mcmpV3TextBytes,
      );
    }

    return MessageCompressionMetadata.fromText(
      type: type,
      originalText: decodedText,
      compressedText: encodedText,
      sharedPayloadBytes: sharedPayloadBytes,
    );
  }

  factory MessageCompressionMetadata.fromText({
    required MessageCompressionType type,
    required String originalText,
    required String compressedText,
    int sharedPayloadBytes = 0,
  }) {
    return MessageCompressionMetadata.fromByteLengths(
      type: type,
      originalBytes: sharedPayloadBytes + utf8.encode(originalText).length,
      compressedBytes: sharedPayloadBytes + utf8.encode(compressedText).length,
    );
  }

  factory MessageCompressionMetadata.fromByteLengths({
    required MessageCompressionType type,
    required int originalBytes,
    required int compressedBytes,
  }) {
    final safeOriginalBytes = originalBytes < 0 ? 0 : originalBytes;
    final safeCompressedBytes = compressedBytes < 0 ? 0 : compressedBytes;
    final savings = safeOriginalBytes <= 0
        ? 0
        : (((safeOriginalBytes - safeCompressedBytes) * 100) /
                  safeOriginalBytes)
              .round()
              .clamp(0, 100)
              .toInt();
    return MessageCompressionMetadata(
      type: type,
      savingsPercent: savings,
      originalBytes: safeOriginalBytes,
      payloadBytes: safeCompressedBytes,
    );
  }
}
