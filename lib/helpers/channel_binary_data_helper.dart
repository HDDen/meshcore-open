import 'dart:convert';
import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';
import 'channel_app_data_helper.dart';
import 'mcoimg_codec.dart';
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

class ChannelBinaryDataHelper {
  ChannelBinaryDataHelper._();

  // Developer namespace from MeshCore's TxtDataHelpers.h. Keep all custom
  // routing behind this helper so it can be disabled when upstream adds an
  // official channel binary transport.
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

  static int? mcoImagePayloadLength(String text, String senderName) {
    if (!canSend) return null;
    try {
      final trimmedLeft = text.trimLeft();
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
    if (dataType == appDataType) {
      return _tryDecodeAppData(payload);
    }
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

  static ChannelBinaryDataInbound? _tryDecodeAppData(Uint8List payload) {
    final envelope = ChannelAppDataHelper.tryDecodeEnvelope(payload);
    if (envelope == null) return null;

    switch (envelope.subtype) {
      case ChannelAppDataSubtype.mcoImageV3:
        // MCOimg v3 is handled by the future binary-only v3 codec. Until that
        // decoder is wired in, keep the official app data_type safely ignored
        // instead of trying to pass it through the legacy v1/v2 decoder.
        return null;
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
