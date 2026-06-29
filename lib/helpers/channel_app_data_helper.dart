import 'dart:convert';
import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';

enum ChannelAppDataSubtype { mcoImageV3 }

class ChannelAppDataEnvelope {
  final String senderName;
  final int subtypeVersion;
  final Uint8List body;
  final ChannelAppDataSubtype? subtype;

  const ChannelAppDataEnvelope({
    required this.senderName,
    required this.subtypeVersion,
    required this.body,
    required this.subtype,
  });
}

class ChannelAppDataPayload {
  final int subtypeVersion;
  final Uint8List body;
  final ChannelAppDataSubtype? subtype;

  const ChannelAppDataPayload({
    required this.subtypeVersion,
    required this.body,
    required this.subtype,
  });
}

class ChannelAppDataHelper {
  ChannelAppDataHelper._();

  /// Official MeshCore application data_type reserved for MCO Advanced payloads.
  ///
  /// Payload grammar:
  ///   senderNameLen(varuint) | senderName(utf8) | subtypeVersion(u8) | body
  ///
  /// subtypeVersion packs content type and version:
  ///   high nibble = content subtype, low nibble = content version.
  ///
  /// 0x13 is MCOimg v3. The v3 image body is binary-only and does not carry
  /// the old text/base91 wrapper.
  static const int appDataType = 0x0120;
  static const int mcoImageSubtype = 0x01;
  static const int mcoImageV3Version = 0x03;
  static const int mcoImageV3SubtypeVersion =
      (mcoImageSubtype << 4) | mcoImageV3Version;

  static int envelopeLength({
    required int bodyLength,
    required String senderName,
  }) {
    final senderNameBytes = utf8.encode(senderName);
    return _varUintLength(senderNameBytes.length) +
        senderNameBytes.length +
        1 +
        bodyLength;
  }

  static int appPayloadLengthWithoutSender({required int bodyLength}) {
    return 1 + bodyLength;
  }

  static Uint8List appPayloadWithoutSender({
    required int subtypeVersion,
    required Uint8List body,
  }) {
    return Uint8List.fromList(<int>[subtypeVersion, ...body]);
  }

  static ChannelAppDataPayload? tryDecodeAppPayloadWithoutSender(
    Uint8List payload,
  ) {
    try {
      final reader = _AppDataReader(payload);
      final subtypeVersion = reader.readByte();
      final body = reader.readRemainingBytes();
      return ChannelAppDataPayload(
        subtypeVersion: subtypeVersion,
        body: body,
        subtype: subtypeForVersion(subtypeVersion),
      );
    } catch (_) {
      return null;
    }
  }

  static Uint8List encodeEnvelope({
    required String senderName,
    required int subtypeVersion,
    required Uint8List body,
  }) {
    final senderNameBytes = utf8.encode(senderName);
    final payload = Uint8List.fromList(<int>[
      ..._varUint(senderNameBytes.length),
      ...senderNameBytes,
      subtypeVersion,
      ...body,
    ]);
    if (payload.length > maxChannelDataLength) {
      throw const FormatException('Channel app payload is too large');
    }
    return payload;
  }

  static ChannelAppDataEnvelope? tryDecodeEnvelope(Uint8List payload) {
    try {
      final reader = _AppDataReader(payload);
      final senderNameLength = reader.readVarUint();
      final senderName = utf8.decode(reader.readBytes(senderNameLength));
      final subtypeVersion = reader.readByte();
      final body = reader.readRemainingBytes();
      return ChannelAppDataEnvelope(
        senderName: senderName.isEmpty ? 'Unknown' : senderName,
        subtypeVersion: subtypeVersion,
        body: body,
        subtype: subtypeForVersion(subtypeVersion),
      );
    } catch (_) {
      return null;
    }
  }

  static ChannelAppDataSubtype? subtypeForVersion(int subtypeVersion) {
    return switch (subtypeVersion) {
      mcoImageV3SubtypeVersion => ChannelAppDataSubtype.mcoImageV3,
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

  static int _varUintLength(int value) {
    var length = 0;
    var remaining = value;
    do {
      remaining >>= 7;
      length++;
    } while (remaining != 0);
    return length;
  }
}

class _AppDataReader {
  final Uint8List _bytes;
  int _offset = 0;

  _AppDataReader(this._bytes);

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
      if (shift > 28) throw const FormatException('varuint too large');
    }
  }

  Uint8List readBytes(int length) {
    if (length < 0 || _offset + length > _bytes.length) {
      throw const FormatException('EOF');
    }
    final result = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return Uint8List.fromList(result);
  }

  Uint8List readRemainingBytes() {
    final result = Uint8List.sublistView(_bytes, _offset);
    _offset = _bytes.length;
    return Uint8List.fromList(result);
  }
}
