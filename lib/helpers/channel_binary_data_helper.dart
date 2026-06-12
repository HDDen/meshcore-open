import 'dart:convert';
import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';
import 'mcoimg_codec.dart';
import 'mesh_compressor.dart';

enum ChannelBinaryDataKind { mcoImage, mcmp }

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
  final ChannelBinaryDataKind kind;

  const ChannelBinaryDataInbound({
    required this.senderName,
    required this.text,
    required this.timestamp,
    required this.wasMcmpCompressed,
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
  static const int dataType = 0xFFFF;

  static const int _kindMcoImage = 1;
  static const int _kindMcmp = 2;
  static const List<int> _signature = [0x42, 0x30]; // B0

  static bool get isAvailable => enabled;
  static bool get canSend => isAvailable && sendEnabled;

  static ChannelBinaryDataOutbound? tryEncodeOutbound({
    required String text,
    required String senderName,
    required DateTime timestamp,
    required bool mcmpEnabled,
  }) {
    if (!canSend) return null;

    try {
      final trimmedLeft = text.trimLeft();
      if (trimmedLeft.startsWith(MCOImageCodec.prefix)) {
        final imagePayload = MCOImageCodec.binaryPayloadFromText(trimmedLeft);
        return _encodeEnvelope(
          kind: _kindMcoImage,
          body: imagePayload,
          senderName: senderName,
          timestamp: timestamp,
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
          kind: _kindMcmp,
          body: compressed,
          senderName: senderName,
          timestamp: timestamp,
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

  static ChannelBinaryDataInbound? tryDecodeInbound({
    required int dataType,
    required Uint8List payload,
  }) {
    if (!enabled || dataType != ChannelBinaryDataHelper.dataType) return null;

    try {
      final reader = _EnvelopeReader(payload);
      if (!reader.readMagic(_signature)) return null;

      final kind = reader.readByte();
      final timestampSeconds = reader.readUint32LE();
      final senderNameLength = reader.readVarUint();
      final senderName = utf8.decode(reader.readBytes(senderNameLength));
      final body = reader.readRemainingBytes();

      if (kind == _kindMcoImage) {
        final text = MCOImageCodec.textFromBinaryPayload(body);
        return ChannelBinaryDataInbound(
          senderName: senderName.isEmpty ? 'Unknown' : senderName,
          text: text,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            timestampSeconds * 1000,
          ),
          wasMcmpCompressed: false,
          kind: ChannelBinaryDataKind.mcoImage,
        );
      }

      if (kind == _kindMcmp) {
        final text = MeshCompressor.instance.decompressBytes(body);
        return ChannelBinaryDataInbound(
          senderName: senderName.isEmpty ? 'Unknown' : senderName,
          text: text,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            timestampSeconds * 1000,
          ),
          wasMcmpCompressed: true,
          kind: ChannelBinaryDataKind.mcmp,
        );
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  static int _envelopeLength({
    required int bodyLength,
    required String senderName,
  }) {
    final senderNameBytes = utf8.encode(senderName);
    return _signature.length +
        1 + // kind
        4 + // unix timestamp
        _varUint(senderNameBytes.length).length +
        senderNameBytes.length +
        bodyLength;
  }

  static ChannelBinaryDataOutbound? _encodeEnvelope({
    required int kind,
    required Uint8List body,
    required String senderName,
    required DateTime timestamp,
  }) {
    final senderNameBytes = utf8.encode(senderName);
    final bytes = <int>[
      ..._signature,
      kind,
      ..._uint32LE(timestamp.millisecondsSinceEpoch ~/ 1000),
      ..._varUint(senderNameBytes.length),
      ...senderNameBytes,
      ...body,
    ];
    final payload = Uint8List.fromList(bytes);
    if (payload.length > maxChannelDataLength) return null;

    return ChannelBinaryDataOutbound(
      dataType: dataType,
      payload: payload,
      kind: kind == _kindMcoImage
          ? ChannelBinaryDataKind.mcoImage
          : ChannelBinaryDataKind.mcmp,
    );
  }

  static List<int> _uint32LE(int value) {
    return [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];
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

  bool readMagic(List<int> magic) {
    if (_bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (_bytes[i] != magic[i]) return false;
    }
    _offset = magic.length;
    return true;
  }

  int readByte() {
    if (_offset >= _bytes.length) throw const FormatException('EOF');
    return _bytes[_offset++];
  }

  int readUint32LE() {
    if (_offset + 4 > _bytes.length) throw const FormatException('EOF');
    final value =
        _bytes[_offset] |
        (_bytes[_offset + 1] << 8) |
        (_bytes[_offset + 2] << 16) |
        (_bytes[_offset + 3] << 24);
    _offset += 4;
    return value;
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
