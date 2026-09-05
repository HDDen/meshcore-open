import 'dart:convert';
import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';
import 'channel_app_data_helper.dart';
import 'contact_share_helper.dart';
import 'mcoimg_codec.dart';
import 'mcoimg_v3_codec.dart';
import 'mcoimg_v4_codec.dart';
import 'mcoimg_v4_model.dart';
import 'mcmp_app_codec.dart';
import 'mcotxt_app_codec.dart';
import 'mesh_compressor.dart';
import 'shared_marker_deletions.dart';

enum ChannelBinaryDataKind { mcoImage, mcoImageV3, mcoImageV4, mcmp, mcotxt }

/// A channel data packet from a namespace this app knows the owner of but
/// could not read: MCO Advanced's own `0x0120` with a subtype this build does
/// not know (or a version of a known one that its codec refused), or MeshCore
/// Open's `0x0100`, whose internal layout is that app's business. What is
/// readable is kept; the payload itself stays on the message as `rawPayload`
/// for a build that can decode it.
class UnknownChannelAppData {
  /// The GROUP_DATA `data_type`, the packet's registered namespace.
  final int dataType;

  /// The envelope's outer name; null when the layout is not ours to read, and
  /// when parsed back from a sentinel, where the message carries the name.
  final String? senderName;

  /// Subtype and version from the `0x0120` envelope; null for a namespace
  /// whose layout this app does not read, and for a `0x0120` payload that is
  /// not a well-formed envelope.
  final int? subtypeId;
  final int? version;

  const UnknownChannelAppData({
    required this.dataType,
    required this.senderName,
    this.subtypeId,
    this.version,
  });

  /// `0x0120`, as the registry and the protocol documents write it.
  String get namespaceHex =>
      '0x${dataType.toRadixString(16).toUpperCase().padLeft(4, '0')}';

  /// The namespace with its registered owner: `0x0100 MeshCore Open`.
  String get namespaceLabel {
    final owner = ChannelBinaryDataHelper.knownNamespaceOwners[dataType];
    return owner == null ? namespaceHex : '$namespaceHex $owner';
  }

  /// The stored message text. The screens recognise it and show a localized
  /// placeholder instead, the way `mcoimg-unsupported:` works for images:
  /// `mcoapp-unknown:0x0120:3.2`, or `mcoapp-unknown:0x0100` when there is
  /// no subtype to name.
  String get sentinelText {
    final ids = subtypeId == null || version == null
        ? ''
        : ':$subtypeId.$version';
    return '${ChannelBinaryDataHelper.unknownAppDataPrefix}$namespaceHex$ids';
  }

  static UnknownChannelAppData? parseSentinel(String text) {
    const prefix = ChannelBinaryDataHelper.unknownAppDataPrefix;
    final trimmed = text.trim();
    if (!trimmed.startsWith(prefix)) return null;
    final parts = trimmed.substring(prefix.length).split(':');
    if (parts.length > 2 || !parts[0].startsWith('0x')) return null;
    final dataType = int.tryParse(parts[0].substring(2), radix: 16);
    if (dataType == null) return null;
    int? subtypeId;
    int? version;
    if (parts.length == 2) {
      final ids = parts[1].split('.');
      if (ids.length != 2) return null;
      subtypeId = int.tryParse(ids[0]);
      version = int.tryParse(ids[1]);
      if (subtypeId == null || version == null) return null;
    }
    return UnknownChannelAppData(
      dataType: dataType,
      senderName: null,
      subtypeId: subtypeId,
      version: version,
    );
  }
}

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
  final DecodedMCOImageV4? mcoImageV4;
  final DecodedMcmpAppMessage? mcmpMessage;
  final DecodedMCOtxtAppMessage? mcotxtMessage;
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
    this.mcoImageV4,
    this.mcmpMessage,
    this.mcotxtMessage,
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

  static const String unsupportedMcoImagePrefix = 'mcoimg-unsupported:';
  static const String unknownAppDataPrefix = 'mcoapp-unknown:';

  /// GROUP_DATA namespaces whose owner this app knows, from MeshCore's
  /// `docs/number_allocations.md`. A packet from one of them that nothing
  /// here can read gets a placeholder in the chat rather than silence; any
  /// other data type stays ignored, as before.
  static const int meshCoreOpenDataType = 0x0100;
  static const Map<int, String> knownNamespaceOwners = {
    meshCoreOpenDataType: 'MeshCore Open',
    appDataType: 'MCO Advanced',
  };

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
  static const int mcotxtSubtype = ChannelAppDataHelper.mcotxtSubtype;
  static const int mcoImageV3Version = ChannelAppDataHelper.mcoImageV3Version;
  static const int mcoImageV4Version = ChannelAppDataHelper.mcoImageV4Version;
  static const int mcmpV3WireVersion = ChannelAppDataHelper.mcmpV3WireVersion;
  static const int mcotxtV1WireVersion =
      ChannelAppDataHelper.mcotxtV1WireVersion;
  static const int channelDataHeaderLength = 3;
  // [cmd][channel_idx][path_len][data_type u16] for the current flood frame.
  static const int outgoingCommandHeaderLength = 5;

  static bool get isAvailable => enabled;
  static bool get canSend => isAvailable && sendEnabled;

  static ChannelBinaryDataOutbound? tryEncodeOutbound({
    required String text,
    required String senderName,
    required bool mcmpEnabled,
    bool mcotxtEnabled = false,
    int mcmpVersion = 2,
    bool mcmpUseSign = true,
    int? timestamp,
    Uint8List? signature,
    String? replyAuthorName,
    int? replyTimestamp,
    bool allowMarkerPayload = false,
  }) {
    if (!canSend) return null;

    try {
      final trimmedLeft = text.trimLeft();
      if (MCOImageV4Codec.isTextPayload(trimmedLeft)) {
        final body = const MCOImageV4Codec().refreshPacketNonce(
          const MCOImageV4Codec().bodyFromText(trimmedLeft),
        );
        return _encodeAppEnvelope(
          subtypeId: mcoImageSubtype,
          version: mcoImageV4Version,
          body: body,
          senderName: senderName,
          kind: ChannelBinaryDataKind.mcoImageV4,
          canonicalText: const MCOImageV4Codec().textFromBody(body),
        );
      }
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
          // A marker and its `del:` command normally travel as plain text so
          // every client can read them. [allowMarkerPayload] is the caller
          // saying it has a signature to put around this one — that envelope
          // is what proves who ordered a pin removed.
          (!allowMarkerPayload &&
              SharedMarkerDeletion.isMarkerPayload(trimmed)) ||
          trimmed.startsWith('V1|') ||
          // Shared contact payloads (<pubkey:type:name>) must travel as
          // plain text so receivers can parse them.
          parseSharedContactText(trimmed) != null ||
          MeshCompressor.instance.hasPrefix(trimmed) ||
          McmpAppCodec.isTextPayload(trimmed) ||
          MCOtxtAppCodec.isTextPayload(trimmed);
      if (isStructuredPayload) return null;

      if (mcotxtEnabled) {
        final encoded = MCOtxtAppCodec.encodeBody(
          text: text,
          timestamp:
              timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
          senderName: senderName,
          replyAuthorName: replyAuthorName,
          replyTimestamp: replyTimestamp,
        );
        return _encodeAppEnvelope(
          subtypeId: mcotxtSubtype,
          version: mcotxtV1WireVersion,
          body: encoded,
          senderName: '',
          kind: ChannelBinaryDataKind.mcotxt,
        );
      }

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

  static ChannelBinaryDataOutbound? tryEncodeMcoImageV4Outbound({
    required EncodedMCOImageV4 image,
    required String senderName,
  }) {
    if (!canSend) return null;
    try {
      final body = const MCOImageV4Codec().refreshPacketNonce(image.body);
      return _encodeAppEnvelope(
        subtypeId: mcoImageSubtype,
        version: mcoImageV4Version,
        body: body,
        senderName: senderName,
        kind: ChannelBinaryDataKind.mcoImageV4,
        canonicalText: const MCOImageV4Codec().textFromBody(body),
      );
    } catch (_) {
      return null;
    }
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
      if (MCOImageV4Codec.isTextPayload(trimmedLeft)) {
        return ChannelAppDataHelper.envelopeLength(
          bodyLength: const MCOImageV4Codec()
              .bodyFromText(trimmedLeft)
              .length,
          senderName: senderName,
        );
      }
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
          parseSharedContactText(trimmed) != null ||
          MeshCompressor.instance.hasPrefix(trimmed) ||
          McmpAppCodec.isTextPayload(trimmed) ||
          MCOtxtAppCodec.isTextPayload(trimmed)) {
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
          parseSharedContactText(trimmed) != null ||
          MeshCompressor.instance.hasPrefix(trimmed) ||
          McmpAppCodec.isTextPayload(trimmed) ||
          MCOtxtAppCodec.isTextPayload(trimmed)) {
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

  static int? mcotxtAppPayloadLength(
    String text,
    String senderName, {
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
          parseSharedContactText(trimmed) != null ||
          MeshCompressor.instance.hasPrefix(trimmed) ||
          McmpAppCodec.isTextPayload(trimmed) ||
          MCOtxtAppCodec.isTextPayload(trimmed)) {
        return null;
      }
      final hasReply = replyAuthorName != null && replyTimestamp != null;
      final encoded = MCOtxtAppCodec.encodeBody(
        text: text,
        timestamp: 0,
        senderName: senderName,
        replyAuthorName: hasReply ? replyAuthorName : null,
        replyTimestamp: hasReply ? replyTimestamp : null,
      );
      return ChannelAppDataHelper.envelopeLength(
        bodyLength: encoded.length,
        senderName: '',
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

  /// Describes a packet from a namespace in [knownNamespaceOwners] after
  /// [tryDecodeInbound] and [tryDecodeAppData] both returned null for it: the
  /// packet comes from an app this one knows, so what it carries is worth a
  /// placeholder in the chat rather than silence. For our own [appDataType]
  /// the envelope's sender name, subtype and version are read when the
  /// envelope parses; another owner's layout is not read at all. Null for
  /// any other data type. MCOimg and MCOtxt report their own unsupported
  /// versions before this point.
  static UnknownChannelAppData? tryDescribeUnknownAppData({
    required int dataType,
    required Uint8List payload,
  }) {
    if (!enabled || !knownNamespaceOwners.containsKey(dataType)) return null;
    final envelope = dataType == appDataType
        ? ChannelAppDataHelper.tryDecodeEnvelope(payload)
        : null;
    return UnknownChannelAppData(
      dataType: dataType,
      senderName: envelope?.senderName,
      subtypeId: envelope?.subtypeId,
      version: envelope?.version,
    );
  }

  static ChannelAppDataInbound? _tryDecodeAppData(Uint8List payload) {
    final envelope = ChannelAppDataHelper.tryDecodeEnvelope(payload);
    if (envelope == null) return null;

    switch (envelope.subtype) {
      case ChannelAppDataSubtype.mcoImage:
        if (envelope.version == mcoImageV4Version) {
          final DecodedMCOImageV4 decoded;
          try {
            decoded = const MCOImageV4Codec().decodeBody(envelope.body);
          } on MCOImageUnsupportedFormatException {
            return ChannelAppDataInbound(
              senderName: envelope.senderName,
              subtypeId: envelope.subtypeId,
              version: envelope.version,
              subtype: ChannelAppDataSubtype.mcoImage,
              body: envelope.body,
              payloadLength: payload.length,
              text: '$unsupportedMcoImagePrefix${envelope.version}',
            );
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
            mcoImageV4: decoded,
          );
        }
        if (envelope.version != mcoImageV3Version) {
          return ChannelAppDataInbound(
            senderName: envelope.senderName,
            subtypeId: envelope.subtypeId,
            version: envelope.version,
            subtype: ChannelAppDataSubtype.mcoImage,
            body: envelope.body,
            payloadLength: payload.length,
            text: '$unsupportedMcoImagePrefix${envelope.version}',
          );
        }
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
      case ChannelAppDataSubtype.mcotxt:
        if (envelope.version != mcotxtV1WireVersion) {
          return ChannelAppDataInbound(
            senderName: envelope.senderName,
            subtypeId: envelope.subtypeId,
            version: envelope.version,
            subtype: ChannelAppDataSubtype.mcotxt,
            body: envelope.body,
            payloadLength: payload.length,
            text: MCOtxtAppCodec.unsupportedFormatText(envelope.version),
          );
        }
        final DecodedMCOtxtAppMessage decoded;
        try {
          decoded = MCOtxtAppCodec.decodeBody(envelope.body);
        } catch (_) {
          return ChannelAppDataInbound(
            senderName: envelope.senderName,
            subtypeId: envelope.subtypeId,
            version: envelope.version,
            subtype: ChannelAppDataSubtype.mcotxt,
            body: envelope.body,
            payloadLength: payload.length,
            text: MCOtxtAppCodec.decodeFailedText(envelope.version),
          );
        }
        return ChannelAppDataInbound(
          senderName: decoded.senderName ?? envelope.senderName,
          subtypeId: envelope.subtypeId,
          version: envelope.version,
          subtype: ChannelAppDataSubtype.mcotxt,
          body: envelope.body,
          payloadLength: payload.length,
          mcotxtMessage: decoded,
          text: decoded.text,
          wasMcmpCompressed: true,
          mcmpSignatureStatus: McmpSignatureStatus.none,
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
