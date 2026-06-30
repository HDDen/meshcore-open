import 'dart:convert';
import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';
import 'channel_app_data_helper.dart';
import 'mcoimg_codec.dart';
import 'mcoimg_v3_codec.dart';
import 'mesh_compressor.dart';

enum ChannelBinaryDataKind { mcoImage, mcoImageV3, mcmp }

class ChannelBinaryDataOutbound {
  final int dataType;
  final Uint8List payload;
  final ChannelBinaryDataKind kind;

  const ChannelBinaryDataOutbound({
    required this.dataType,
    required this.payload,
    required this.kind,
  });
}

class ChannelBinaryDataInbound {
  final String senderName;
  final String text;
  final DateTime timestamp;
  final bool wasMcmpCompressed;
  final int payloadLength;
  final ChannelBinaryDataKind kind;

  const ChannelBinaryDataInbound({
    required this.senderName,
    required this.text,
    required this.timestamp,
    required this.wasMcmpCompressed,
    required this.payloadLength,
    required this.kind,
  });
}

class ChannelAppDataInbound {
  final String senderName;
  final int subtypeVersion;
  final ChannelAppDataSubtype subtype;
  final Uint8List body;
  final int payloadLength;
  final MCOImage? mcoImage;

  const ChannelAppDataInbound({
    required this.senderName,
    required this.subtypeVersion,
    required this.subtype,
    required this.body,
    required this.payloadLength,
    this.mcoImage,
  });
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
  static const int mcoImageV3SubtypeVersion =
      ChannelAppDataHelper.mcoImageV3SubtypeVersion;
  static const int channelDataHeaderLength = 3;
  // [cmd][channel_idx][path_len][data_type u16] for the current flood frame.
  static const int outgoingCommandHeaderLength = 5;

  static bool get isAvailable => enabled;
  static bool get canSend => isAvailable && sendEnabled;

  static ChannelBinaryDataOutbound? tryEncodeOutbound({
    required String text,
    required String senderName,
    required bool mcmpEnabled,
  }) {
    if (!canSend) return null;

    try {
      final trimmedLeft = text.trimLeft();
      if (MCOImageV3Codec.isTextPayload(trimmedLeft)) {
        return _encodeAppEnvelope(
          subtypeVersion: mcoImageV3SubtypeVersion,
          body: MCOImageV3Codec.bodyFromText(trimmedLeft),
          senderName: senderName,
          kind: ChannelBinaryDataKind.mcoImageV3,
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
          trimmed.startsWith('V1|');
      if (isStructuredPayload) return null;

      if (mcmpEnabled) {
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
    return _encodeAppEnvelope(
      subtypeVersion: image.subtypeVersion,
      body: image.body,
      senderName: senderName,
      kind: ChannelBinaryDataKind.mcoImageV3,
    );
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

  static int? mcmpPayloadLength(String text, String senderName) {
    if (!canSend) return null;
    try {
      final trimmed = text.trim();
      if (trimmed.startsWith('g:') ||
          trimmed.startsWith('m:') ||
          trimmed.startsWith('V1|') ||
          trimmed.startsWith(MCOImageCodec.prefix)) {
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
    return _envelopeLength(
      bodyLength: bodyLength,
      senderName: senderName,
    );
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

  static int uncompressedBinaryPayloadLength(
    String text,
    String senderName,
  ) {
    return channelDataHeaderLength +
        uncompressedPayloadLength(text, senderName);
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
      case ChannelAppDataSubtype.mcoImageV3:
        final MCOImage image;
        try {
          image = MCOImageV3Codec().decodeBody(envelope.body);
        } catch (_) {
          return null;
        }
        return ChannelAppDataInbound(
          senderName: envelope.senderName,
          subtypeVersion: envelope.subtypeVersion,
          subtype: ChannelAppDataSubtype.mcoImageV3,
          body: envelope.body,
          payloadLength: payload.length,
          mcoImage: image,
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
    required int subtypeVersion,
    required Uint8List body,
    required String senderName,
    required ChannelBinaryDataKind kind,
  }) {
    final Uint8List payload;
    try {
      payload = ChannelAppDataHelper.encodeEnvelope(
        senderName: senderName,
        subtypeVersion: subtypeVersion,
        body: body,
      );
    } catch (_) {
      return null;
    }

    return ChannelBinaryDataOutbound(
      dataType: appDataType,
      payload: payload,
      kind: kind,
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
