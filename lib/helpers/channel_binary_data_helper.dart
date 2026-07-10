import 'dart:convert';
import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';
import 'channel_app_data_helper.dart';
import 'contact_share_helper.dart';
import 'mcoimg_codec.dart';
import 'mcoimg_v3_codec.dart';
import 'mcmp_app_codec.dart';
import 'mesh_compressor.dart';

enum ChannelBinaryDataKind { mcoImage, mcoImageV3, mcmp }

class ChannelBinaryDataOutbound {
  final int dataType;
  final Uint8List payload;
  final ChannelBinaryDataKind kind;
  final McmpSignatureStatus mcmpSignatureStatus;

  /// Canonical text representation of the exact binary payload, when the
  /// binary format also has a text fallback (currently MCOimg v3).
  ///
  /// For MCOimg v3 this contains the same packet nonce that is already present
  /// in [payload], so the local outgoing message can be matched exactly to its
  /// radio self-echo.
  final String? canonicalText;

  const ChannelBinaryDataOutbound({
    required this.dataType,
    required this.payload,
    required this.kind,
    this.mcmpSignatureStatus = McmpSignatureStatus.none,
    this.canonicalText,
  });
}

class ChannelBinaryDataInbound {
  final String senderName;
  final String text;
  final DateTime timestamp;
  final bool wasMcmpCompressed;
  final McmpSignatureStatus mcmpSignatureStatus;
  final int payloadLength;
  final ChannelBinaryDataKind kind;

  const ChannelBinaryDataInbound({
    required this.senderName,
    required this.text,
    required this.timestamp,
    required this.wasMcmpCompressed,
    this.mcmpSignatureStatus = McmpSignatureStatus.none,
    required this.payloadLength,
    required this.kind,
  });
}

class ChannelAppDataInbound {
  final String senderName;
  final int subtypeId;
  final int version;
  final ChannelAppDataSubtype subtype;
  final Uint8List body;
  final int payloadLength;
  final MCOImage? mcoImage;
  final DecodedMcmpAppMessage? mcmpMessage;
  final String? text;
  final bool wasMcmpCompressed;
  final McmpSignatureStatus mcmpSignatureStatus;

  const ChannelAppDataInbound({
    required this.senderName,
    required this.subtypeId,
    required this.version,
    required this.subtype,
    required this.body,
    required this.payloadLength,
    this.mcoImage,
    this.mcmpMessage,
    this.text,
    this.wasMcmpCompressed = false,
    this.mcmpSignatureStatus = McmpSignatureStatus.none,
  });

  int get subtypeVersion => ChannelAppDataHelper.packSubtypeVersion(
    subtypeId: subtypeId,
    version: version,
  );
}

class ChannelBinaryDataHelper {
  ChannelBinaryDataHelper._();

  // Legacy developer namespace from MeshCore's TxtDataHelpers.h. The official
  // app data_type path lives under [appDataType] and carries its own subtype
  // byte inside ChannelAppDataHelper's envelope.
  static bool enabled = true;
  static bool sendEnabled = false;
  static const int mcoImageDataType = 0xFFF0;
  static const int mcmpDataType = 0xFFF1;
  static const int appDataType = ChannelAppDataHelper.appDataType;
  static const int mcoImageSubtype = ChannelAppDataHelper.mcoImageSubtype;
  static const int mcmpSubtype = ChannelAppDataHelper.mcmpSubtype;
  static const int mcoImageV3Version = ChannelAppDataHelper.mcoImageV3Version;
  static const int mcmpV3WireVersion = ChannelAppDataHelper.mcmpV3WireVersion;
  static const int channelDataHeaderLength = 3;
  // [cmd][channel_idx][path_len][data_type u16] for the current flood frame.
  static const int outgoingCommandHeaderLength = 5;

  static bool get isAvailable => enabled;
  static bool get canSend => isAvailable && sendEnabled;

  static ChannelBinaryDataOutbound? tryEncodeOutbound({
    required String text,
    required String senderName,
    required bool mcmpEnabled,
    int mcmpVersion = 2,
    bool mcmpUseSign = true,
    int? timestamp,
    Uint8List? signature,
    String? replyAuthorName,
    int? replyTimestamp,
  }) {
    if (!canSend) return null;

    try {
      final trimmedLeft = text.trimLeft();
      if (MCOImageV3Codec.isTextPayload(trimmedLeft)) {
        final body = MCOImageV3Codec.refreshPacketNonce(
          MCOImageV3Codec.bodyFromText(trimmedLeft),
        );
        return _encodeAppEnvelope(
          subtypeId: mcoImageSubtype,
          version: mcoImageV3Version,
          body: body,
          senderName: senderName,
          kind: ChannelBinaryDataKind.mcoImageV3,
          canonicalText: MCOImageV3Codec.textFromBody(body),
        );
      }
      if (trimmedLeft.startsWith(MCOImageCodec.prefix)) {
        final imagePayload = MCOImageCodec.binaryPayloadFromText(trimmedLeft);
        return _encodeEnvelope(
          dataType: mcoImageDataType,
          body: imagePayload,
          senderName: senderName,
        );
      }

      final trimmed = text.trim();
      final isStructuredPayload =
          trimmed.startsWith('g:') ||
          trimmed.startsWith('m:') ||
          trimmed.startsWith('V1|') ||
          // Shared contact payloads (<pubkey:type:name>) must travel as
          // plain text so receivers can parse them.
          parseSharedContactText(trimmed) != null;
      if (isStructuredPayload) return null;

      if (mcmpEnabled) {
        if (mcmpVersion == 3) {
          final hasReply = replyAuthorName != null && replyTimestamp != null;
          return tryEncodeMcmpV3AppOutbound(
            text: text,
            senderName: senderName,
            timestamp:
                timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
            signature: mcmpUseSign ? signature : null,
            replyAuthorName: hasReply ? replyAuthorName : null,
            replyTimestamp: hasReply ? replyTimestamp : null,
          );
        }
        final compressed = MeshCompressor.instance.compressToBytes(text);
        return _encodeEnvelope(
          dataType: mcmpDataType,
          body: compressed,
          senderName: senderName,
        );
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  static ChannelBinaryDataOutbound? tryEncodeMcoImageV3Outbound({
    required EncodedMCOImageV3 image,
    required String senderName,
  }) {
    if (!canSend) return null;
    final body = MCOImageV3Codec.refreshPacketNonce(image.body);
    return _encodeAppEnvelope(
      subtypeId: image.subtypeId,
      version: image.version,
      body: body,
      senderName: senderName,
      kind: ChannelBinaryDataKind.mcoImageV3,
      canonicalText: MCOImageV3Codec.textFromBody(body),
    );
  }

  static ChannelBinaryDataOutbound? tryEncodeMcmpV3AppOutbound({
    required String text,
    required String senderName,
    required int timestamp,
    Uint8List? signature,
    String? replyAuthorName,
    int? replyTimestamp,
  }) {
    if (!canSend) return null;
    try {
      final encoded = McmpAppCodec.encodeBody(
        text: text,
        timestamp: timestamp,
        signature: signature,
        replyAuthorName: replyAuthorName,
        replyTimestamp: replyTimestamp,
      );
      // Outgoing messages: we produced the signature ourselves, so a present
      // signature is by definition valid.
      return _encodeAppEnvelope(
        subtypeId: mcmpSubtype,
        version: mcmpV3WireVersion,
        body: encoded.body,
        senderName: senderName,
        kind: ChannelBinaryDataKind.mcmp,
        mcmpSignatureStatus: encoded.isSigned
            ? McmpSignatureStatus.valid
            : McmpSignatureStatus.unsigned,
      );
    } catch (_) {
      return null;
    }
  }

  static int? mcoImagePayloadLength(String text, String senderName) {
    if (!canSend) return null;
    try {
      final trimmedLeft = text.trimLeft();
      if (MCOImageV3Codec.isTextPayload(trimmedLeft)) {
        return ChannelAppDataHelper.envelopeLength(
          bodyLength: MCOImageV3Codec.bodyFromText(trimmedLeft).length,
          senderName: senderName,
        );
      }
      if (!trimmedLeft.startsWith(MCOImageCodec.prefix)) return null;
      final imagePayload = MCOImageCodec.binaryPayloadFromText(trimmedLeft);
      return _envelopeLength(
        bodyLength: imagePayload.length,
        senderName: senderName,
      );
    } catch (_) {
      return null;
    }
  }

  static int? mcoImageV3PayloadLength(
    EncodedMCOImageV3 image,
    String senderName,
  ) {
    if (!canSend) return null;
    return ChannelAppDataHelper.envelopeLength(
      bodyLength: image.body.length,
      senderName: senderName,
    );
  }

  /// Estimated binary payload length for an MCMP v3 app envelope. When
  /// [includeSignature] is true a placeholder of the exact wire size is
  /// counted, so composer counters reflect the signed container.
  static int? mcmpV3AppPayloadLength(
    String text,
    String senderName, {
    bool includeSignature = false,
    String? replyAuthorName,
    int? replyTimestamp,
  }) {
    if (!canSend) return null;
    try {
      final trimmed = text.trim();
      if (trimmed.startsWith('g:') ||
          trimmed.startsWith('m:') ||
          trimmed.startsWith('V1|') ||
          trimmed.startsWith(MCOImageCodec.prefix) ||
          parseSharedContactText(trimmed) != null) {
        return null;
      }
      final hasReply = replyAuthorName != null && replyTimestamp != null;
      final encoded = McmpAppCodec.encodeBody(
        text: text,
        timestamp: 0,
        signature: includeSignature ? Uint8List(signatureSize) : null,
        replyAuthorName: hasReply ? replyAuthorName : null,
        replyTimestamp: hasReply ? replyTimestamp : null,
      );
      return ChannelAppDataHelper.envelopeLength(
        bodyLength: encoded.body.length,
        senderName: senderName,
      );
    } catch (_) {
      return null;
    }
  }

  static int? mcmpPayloadLength(String text, String senderName) {
    if (!canSend) return null;
    try {
      final trimmed = text.trim();
      if (trimmed.startsWith('g:') ||
          trimmed.startsWith('m:') ||
          trimmed.startsWith('V1|') ||
          trimmed.startsWith(MCOImageCodec.prefix) ||
          parseSharedContactText(trimmed) != null) {
        return null;
      }
      final compressed = MeshCompressor.instance.compressToBytes(text);
      return _envelopeLength(
        bodyLength: compressed.length,
        senderName: senderName,
      );
    } catch (_) {
      return null;
    }
  }

  static int uncompressedPayloadLength(String text, String senderName) {
    return _envelopeLength(
      bodyLength: utf8.encode(text).length,
      senderName: senderName,
    );
  }

  static int finalBinaryPayloadLength(int envelopeLength) {
    return channelDataHeaderLength + envelopeLength;
  }

  static int binaryEnvelopeLength({
    required int bodyLength,
    required String senderName,
  }) {
    return _envelopeLength(bodyLength: bodyLength, senderName: senderName);
  }

  static int appBinaryEnvelopeLength({
    required int bodyLength,
    required String senderName,
  }) {
    return ChannelAppDataHelper.envelopeLength(
      bodyLength: bodyLength,
      senderName: senderName,
    );
  }

  static int outgoingCommandFrameLength(
    int envelopeLength, {
    int pathLength = 0,
  }) {
    return outgoingCommandHeaderLength + pathLength + envelopeLength;
  }

  static int uncompressedBinaryPayloadLength(String text, String senderName) {
    return channelDataHeaderLength +
        uncompressedPayloadLength(text, senderName);
  }

  static int uncompressedAppBinaryPayloadLength(
    String text,
    String senderName,
  ) {
    return channelDataHeaderLength +
        appBinaryEnvelopeLength(
          bodyLength: 1 + 4 + utf8.encode(text).length,
          senderName: senderName,
        );
  }

  static ChannelBinaryDataInbound? tryDecodeInbound({
    required int dataType,
    required Uint8List payload,
  }) {
    if (!enabled) return null;
    if (dataType == appDataType) return null;
    final kind = _kindForDataType(dataType);
    if (kind == null) return null;

    try {
      final reader = _EnvelopeReader(payload);
      final senderNameLength = reader.readVarUint();
      final senderName = utf8.decode(reader.readBytes(senderNameLength));
      final body = reader.readRemainingBytes();
      final timestamp = DateTime.now();

      if (kind == ChannelBinaryDataKind.mcoImage) {
        final text = MCOImageCodec.textFromBinaryPayload(body);
        return ChannelBinaryDataInbound(
          senderName: senderName.isEmpty ? 'Unknown' : senderName,
          text: text,
          timestamp: timestamp,
          wasMcmpCompressed: false,
          mcmpSignatureStatus: McmpSignatureStatus.none,
          payloadLength: payload.length,
          kind: ChannelBinaryDataKind.mcoImage,
        );
      }

      if (kind == ChannelBinaryDataKind.mcmp) {
        final text = MeshCompressor.instance.decompressBytes(body);
        return ChannelBinaryDataInbound(
          senderName: senderName.isEmpty ? 'Unknown' : senderName,
          text: text,
          timestamp: timestamp,
          wasMcmpCompressed: true,
          mcmpSignatureStatus: McmpSignatureStatus.none,
          payloadLength: payload.length,
          kind: ChannelBinaryDataKind.mcmp,
        );
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  static ChannelAppDataInbound? tryDecodeAppData({
    required int dataType,
    required Uint8List payload,
  }) {
    if (!enabled || dataType != appDataType) return null;
    return _tryDecodeAppData(payload);
  }

  static ChannelAppDataInbound? _tryDecodeAppData(Uint8List payload) {
    final envelope = ChannelAppDataHelper.tryDecodeEnvelope(payload);
    if (envelope == null) return null;

    switch (envelope.subtype) {
      case ChannelAppDataSubtype.mcoImage:
        if (envelope.version != mcoImageV3Version) return null;
        final MCOImage image;
        try {
          image = MCOImageV3Codec().decodeBody(envelope.body);
        } catch (_) {
          return null;
        }
        return ChannelAppDataInbound(
          senderName: envelope.senderName,
          subtypeId: envelope.subtypeId,
          version: envelope.version,
          subtype: ChannelAppDataSubtype.mcoImage,
          body: envelope.body,
          payloadLength: payload.length,
          mcoImage: image,
        );
      case ChannelAppDataSubtype.mcmp:
        if (envelope.version != mcmpV3WireVersion) return null;
        final DecodedMcmpAppMessage decoded;
        try {
          decoded = McmpAppCodec.decodeBody(envelope.body);
        } catch (_) {
          return null;
        }
        return ChannelAppDataInbound(
          senderName: envelope.senderName,
          subtypeId: envelope.subtypeId,
          version: envelope.version,
          subtype: ChannelAppDataSubtype.mcmp,
          body: envelope.body,
          payloadLength: payload.length,
          mcmpMessage: decoded,
          text: decoded.text,
          wasMcmpCompressed: true,
          mcmpSignatureStatus: decoded.signatureStatus,
        );
      case null:
        return null;
    }
  }

  static int _envelopeLength({
    required int bodyLength,
    required String senderName,
  }) {
    final senderNameBytes = utf8.encode(senderName);
    return _varUint(senderNameBytes.length).length +
        senderNameBytes.length +
        bodyLength;
  }

  static ChannelBinaryDataOutbound? _encodeEnvelope({
    required int dataType,
    required Uint8List body,
    required String senderName,
  }) {
    final senderNameBytes = utf8.encode(senderName);
    final bytes = <int>[
      ..._varUint(senderNameBytes.length),
      ...senderNameBytes,
      ...body,
    ];
    final payload = Uint8List.fromList(bytes);
    if (payload.length > maxChannelDataLength) return null;

    return ChannelBinaryDataOutbound(
      dataType: dataType,
      payload: payload,
      kind: _kindForDataType(dataType)!,
    );
  }

  static ChannelBinaryDataOutbound? _encodeAppEnvelope({
    required int subtypeId,
    required int version,
    required Uint8List body,
    required String senderName,
    required ChannelBinaryDataKind kind,
    McmpSignatureStatus mcmpSignatureStatus = McmpSignatureStatus.none,
    String? canonicalText,
  }) {
    final Uint8List payload;
    try {
      payload = ChannelAppDataHelper.encodeEnvelope(
        senderName: senderName,
        subtypeId: subtypeId,
        version: version,
        body: body,
      );
    } catch (_) {
      return null;
    }

    return ChannelBinaryDataOutbound(
      dataType: appDataType,
      payload: payload,
      kind: kind,
      mcmpSignatureStatus: mcmpSignatureStatus,
      canonicalText: canonicalText,
    );
  }

  static ChannelBinaryDataKind? _kindForDataType(int dataType) {
    return switch (dataType) {
      mcoImageDataType => ChannelBinaryDataKind.mcoImage,
      mcmpDataType => ChannelBinaryDataKind.mcmp,
      _ => null,
    };
  }

  static List<int> _varUint(int value) {
    final result = <int>[];
    var remaining = value;
    do {
      var byte = remaining & 0x7F;
      remaining >>= 7;
      if (remaining != 0) byte |= 0x80;
      result.add(byte);
    } while (remaining != 0);
    return result;
  }
}

class _EnvelopeReader {
  final Uint8List _bytes;
  int _offset = 0;

  _EnvelopeReader(this._bytes);

  int readByte() {
    if (_offset >= _bytes.length) throw const FormatException('EOF');
    return _bytes[_offset++];
  }

  int readVarUint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final byte = readByte();
      result |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) return result;
      shift += 7;
      if (shift > 28) throw const FormatException('Varuint too long');
    }
  }

  Uint8List readBytes(int length) {
    if (length < 0 || _offset + length > _bytes.length) {
      throw const FormatException('EOF');
    }
    final result = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return result;
  }

  Uint8List readRemainingBytes() {
    return readBytes(_bytes.length - _offset);
  }
}
