import 'dart:convert';
import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';

enum ChannelAppDataSubtype {
  mcoImage(0x01),
  mcmp(0x02),
  mcotxt(0x03);

  final int id;

  const ChannelAppDataSubtype(this.id);

  /// Compatibility alias for callers written before subtype and version were
  /// represented separately. This aliases the MCOimg type; check [version]
  /// separately when routing payloads.
  @Deprecated('Use ChannelAppDataSubtype.mcoImage and check version == 3')
  static const ChannelAppDataSubtype mcoImageV3 = mcoImage;
}

class ChannelAppDataEnvelope {
  final String senderName;
  final int subtypeId;
  final int version;
  final Uint8List body;
  final ChannelAppDataSubtype? subtype;

  const ChannelAppDataEnvelope({
    required this.senderName,
    int? subtypeId,
    int? version,
    @Deprecated('Pass subtypeId and version separately') int? subtypeVersion,
    required this.body,
    required this.subtype,
  }) : assert(
         subtypeVersion != null || (subtypeId != null && version != null),
         'Provide subtypeVersion or both subtypeId and version',
       ),
       assert(
         subtypeVersion == null ||
             subtypeId == null ||
             subtypeId == (subtypeVersion >> 4),
         'subtypeId conflicts with subtypeVersion',
       ),
       assert(
         subtypeVersion == null ||
             version == null ||
             version == (subtypeVersion & 0x0f),
         'version conflicts with subtypeVersion',
       ),
       subtypeId = subtypeId ?? ((subtypeVersion ?? 0) >> 4),
       version = version ?? ((subtypeVersion ?? 0) & 0x0f);

  int get subtypeVersion => ChannelAppDataHelper.packSubtypeVersion(
    subtypeId: subtypeId,
    version: version,
  );
}

class ChannelAppDataPayload {
  final int subtypeId;
  final int version;
  final Uint8List body;
  final ChannelAppDataSubtype? subtype;

  const ChannelAppDataPayload({
    int? subtypeId,
    int? version,
    @Deprecated('Pass subtypeId and version separately') int? subtypeVersion,
    required this.body,
    required this.subtype,
  }) : assert(
         subtypeVersion != null || (subtypeId != null && version != null),
         'Provide subtypeVersion or both subtypeId and version',
       ),
       assert(
         subtypeVersion == null ||
             subtypeId == null ||
             subtypeId == (subtypeVersion >> 4),
         'subtypeId conflicts with subtypeVersion',
       ),
       assert(
         subtypeVersion == null ||
             version == null ||
             version == (subtypeVersion & 0x0f),
         'version conflicts with subtypeVersion',
       ),
       subtypeId = subtypeId ?? ((subtypeVersion ?? 0) >> 4),
       version = version ?? ((subtypeVersion ?? 0) & 0x0f);

  int get subtypeVersion => ChannelAppDataHelper.packSubtypeVersion(
    subtypeId: subtypeId,
    version: version,
  );
}

class ChannelAppDataHelper {
  ChannelAppDataHelper._();

  /// Official MeshCore application data_type reserved for MCO Advanced
  /// payloads.
  ///
  /// Envelope grammar:
  ///   senderNameLen(varuint) | senderName(utf8) | subtypeVersion(u8) | body
  ///
  /// subtypeVersion remains one byte on wire:
  ///   high nibble = content subtype, low nibble = content version.
  ///
  /// Examples:
  ///   0x13 = MCOimg v3
  ///   0x14 = MCOimg v4
  ///   0x20 = MCMP v3
  ///   0x31 = MCOtxt v1
  ///
  /// MCOimg v3/v4 bodies are binary. They can be carried either in this
  /// official binary envelope or in their Base91 text transports.
  static const int appDataType = 0x0120;

  static const int mcoImageSubtype = 0x01;
  static const int mcmpSubtype = 0x02;
  static const int mcotxtSubtype = 0x03;

  static const int mcoImageV3Version = 0x03;
  static const int mcoImageV4Version = 0x04;
  static const int mcmpV3FormatVersion = 0x03;
  static const int mcmpV3WireVersion = 0x00;
  static const int mcotxtV1WireVersion = 0x01;
  static const int mcoImageV3SubtypeVersion =
      (mcoImageSubtype << 4) | mcoImageV3Version;
  static const int mcoImageV4SubtypeVersion =
      (mcoImageSubtype << 4) | mcoImageV4Version;
  static const int mcmpV3SubtypeVersion =
      (mcmpSubtype << 4) | mcmpV3WireVersion;
  static const int mcotxtV1SubtypeVersion =
      (mcotxtSubtype << 4) | mcotxtV1WireVersion;

  static int packSubtypeVersion({
    required int subtypeId,
    required int version,
  }) {
    _validateNibble(subtypeId, 'subtypeId');
    _validateNibble(version, 'version');
    return (subtypeId << 4) | version;
  }

  static int subtypeIdFromPacked(int subtypeVersion) {
    _validateByte(subtypeVersion, 'subtypeVersion');
    return subtypeVersion >> 4;
  }

  static int versionFromPacked(int subtypeVersion) {
    _validateByte(subtypeVersion, 'subtypeVersion');
    return subtypeVersion & 0x0f;
  }

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
    int? subtypeId,
    int? version,
    @Deprecated('Pass subtypeId and version separately') int? subtypeVersion,
    required Uint8List body,
  }) {
    final packed = _resolveSubtypeVersion(
      subtypeId: subtypeId,
      version: version,
      subtypeVersion: subtypeVersion,
    );
    return Uint8List.fromList(<int>[packed, ...body]);
  }

  static ChannelAppDataPayload? tryDecodeAppPayloadWithoutSender(
    Uint8List payload,
  ) {
    try {
      final reader = _AppDataReader(payload);
      final subtypeVersion = reader.readByte();
      final subtypeId = subtypeIdFromPacked(subtypeVersion);
      final version = versionFromPacked(subtypeVersion);
      final body = reader.readRemainingBytes();
      return ChannelAppDataPayload(
        subtypeId: subtypeId,
        version: version,
        body: body,
        subtype: subtypeForId(subtypeId),
      );
    } catch (_) {
      return null;
    }
  }

  static Uint8List encodeEnvelope({
    required String senderName,
    int? subtypeId,
    int? version,
    @Deprecated('Pass subtypeId and version separately') int? subtypeVersion,
    required Uint8List body,
  }) {
    final senderNameBytes = utf8.encode(senderName);
    final packed = _resolveSubtypeVersion(
      subtypeId: subtypeId,
      version: version,
      subtypeVersion: subtypeVersion,
    );
    final payload = Uint8List.fromList(<int>[
      ..._varUint(senderNameBytes.length),
      ...senderNameBytes,
      packed,
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
      final subtypeId = subtypeIdFromPacked(subtypeVersion);
      final version = versionFromPacked(subtypeVersion);
      final body = reader.readRemainingBytes();
      return ChannelAppDataEnvelope(
        senderName: senderName.isEmpty ? 'Unknown' : senderName,
        subtypeId: subtypeId,
        version: version,
        body: body,
        subtype: subtypeForId(subtypeId),
      );
    } catch (_) {
      return null;
    }
  }

  static ChannelAppDataSubtype? subtypeForId(int subtypeId) {
    for (final subtype in ChannelAppDataSubtype.values) {
      if (subtype.id == subtypeId) return subtype;
    }
    return null;
  }

  static int _resolveSubtypeVersion({
    int? subtypeId,
    int? version,
    int? subtypeVersion,
  }) {
    if (subtypeVersion != null) {
      _validateByte(subtypeVersion, 'subtypeVersion');
      final packedSubtypeId = subtypeIdFromPacked(subtypeVersion);
      final packedVersion = versionFromPacked(subtypeVersion);
      if (subtypeId != null && subtypeId != packedSubtypeId) {
        throw ArgumentError.value(
          subtypeId,
          'subtypeId',
          'Conflicts with subtypeVersion',
        );
      }
      if (version != null && version != packedVersion) {
        throw ArgumentError.value(
          version,
          'version',
          'Conflicts with subtypeVersion',
        );
      }
      return subtypeVersion;
    }

    if (subtypeId == null || version == null) {
      throw ArgumentError(
        'Provide subtypeVersion or both subtypeId and version',
      );
    }
    return packSubtypeVersion(subtypeId: subtypeId, version: version);
  }

  static void _validateNibble(int value, String name) {
    if (value < 0 || value > 0x0f) {
      throw RangeError.range(value, 0, 0x0f, name);
    }
  }

  static void _validateByte(int value, String name) {
    if (value < 0 || value > 0xff) {
      throw RangeError.range(value, 0, 0xff, name);
    }
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
