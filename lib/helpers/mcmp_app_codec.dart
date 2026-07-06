import 'dart:convert';
import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';
import 'mesh_compressor.dart';

class EncodedMcmpAppMessage {
  final Uint8List body;
  final int timestamp;
  final bool isSigned;
  final bool isReply;
  final String? replyAuthorName;
  final int? replyTimestamp;

  const EncodedMcmpAppMessage({
    required this.body,
    required this.timestamp,
    required this.isSigned,
    required this.isReply,
    this.replyAuthorName,
    this.replyTimestamp,
  });
}

class DecodedMcmpAppMessage {
  final String text;
  final int timestamp;
  final Uint8List? signature;
  final String? replyAuthorName;
  final int? replyTimestamp;

  const DecodedMcmpAppMessage({
    required this.text,
    required this.timestamp,
    this.signature,
    this.replyAuthorName,
    this.replyTimestamp,
  });

  bool get isSigned => signature != null;
  bool get isReply => replyAuthorName != null && replyTimestamp != null;
}

class McmpAppCodec {
  McmpAppCodec._();

  static const int subtypeId = 0x02;
  static const int formatVersion = 3;
  static const int wireVersion = 0x00;
  static const int subtypeVersion = (subtypeId << 4) | wireVersion;
  static const String textPrefix = 'mcmp3:';
  static const String signingDomain = 'MCOAPP:MCMP:SIGNED:v3';

  static const int _flagReply = 1 << 0;
  static const int _flagSigned = 1 << 1;
  static const int _knownFlags = _flagReply | _flagSigned;

  static EncodedMcmpAppMessage encodeBody({
    required String text,
    required int timestamp,
    Uint8List? signature,
    String? replyAuthorName,
    int? replyTimestamp,
  }) {
    if (timestamp < 0 || timestamp > 0xffffffff) {
      throw RangeError.range(timestamp, 0, 0xffffffff, 'timestamp');
    }
    if ((replyAuthorName == null) != (replyTimestamp == null)) {
      throw ArgumentError(
        'replyAuthorName and replyTimestamp must be provided together',
      );
    }
    if (replyTimestamp != null &&
        (replyTimestamp < 0 || replyTimestamp > 0xffffffff)) {
      throw RangeError.range(replyTimestamp, 0, 0xffffffff, 'replyTimestamp');
    }
    if (signature != null && signature.length != signatureSize) {
      throw ArgumentError.value(
        signature.length,
        'signature.length',
        'MCMP app signatures must be $signatureSize bytes',
      );
    }

    var flags = 0;
    if (replyAuthorName != null) {
      flags |= _flagReply;
    }
    if (signature != null) {
      flags |= _flagSigned;
    }

    final compressed = MeshCompressor.instance.compressToBytes(text);
    final writer = _ByteWriter()
      ..writeByte(flags)
      ..writeUint32LE(timestamp);
    if (signature != null) {
      writer.writeBytes(signature);
    }
    if (replyAuthorName != null && replyTimestamp != null) {
      final replyNameBytes = utf8.encode(replyAuthorName);
      writer.writeVarUint(replyNameBytes.length);
      writer.writeBytes(replyNameBytes);
      writer.writeUint32LE(replyTimestamp);
    }
    writer.writeBytes(compressed);

    return EncodedMcmpAppMessage(
      body: writer.toBytes(),
      timestamp: timestamp,
      isSigned: signature != null,
      isReply: replyAuthorName != null,
      replyAuthorName: replyAuthorName,
      replyTimestamp: replyTimestamp,
    );
  }

  static DecodedMcmpAppMessage decodeBody(Uint8List body) {
    final reader = _ByteReader(body);
    final flags = reader.readByte();
    if ((flags & ~_knownFlags) != 0) {
      throw const FormatException('Unsupported MCMP app flags');
    }
    final timestamp = reader.readUint32LE();

    Uint8List? signature;
    if ((flags & _flagSigned) != 0) {
      signature = reader.readBytes(signatureSize);
    }

    String? replyAuthorName;
    int? replyTimestamp;
    if ((flags & _flagReply) != 0) {
      final replyNameLength = reader.readVarUint();
      replyAuthorName = utf8.decode(reader.readBytes(replyNameLength));
      replyTimestamp = reader.readUint32LE();
    }

    final compressed = reader.readRemainingBytes();
    final text = MeshCompressor.instance.decompressBytes(compressed);
    return DecodedMcmpAppMessage(
      text: text,
      timestamp: timestamp,
      signature: signature,
      replyAuthorName: replyAuthorName,
      replyTimestamp: replyTimestamp,
    );
  }

  static Uint8List canonicalSigningBytes({
    required Uint8List channelBinding,
    required String senderName,
    required int timestamp,
    required String text,
    String? replyAuthorName,
    int? replyTimestamp,
  }) {
    if ((replyAuthorName == null) != (replyTimestamp == null)) {
      throw ArgumentError(
        'replyAuthorName and replyTimestamp must be provided together',
      );
    }
    var flags = 0;
    if (replyAuthorName != null) {
      flags |= _flagReply;
    }

    final senderNameBytes = utf8.encode(senderName);
    final textBytes = utf8.encode(text);
    final writer = _ByteWriter()
      ..writeBytes(utf8.encode(signingDomain))
      ..writeBytes(channelBinding)
      ..writeVarUint(senderNameBytes.length)
      ..writeBytes(senderNameBytes)
      ..writeUint32LE(timestamp)
      ..writeByte(flags);
    if (replyAuthorName != null && replyTimestamp != null) {
      final replyNameBytes = utf8.encode(replyAuthorName);
      writer.writeVarUint(replyNameBytes.length);
      writer.writeBytes(replyNameBytes);
      writer.writeUint32LE(replyTimestamp);
    }
    writer.writeBytes(textBytes);
    return writer.toBytes();
  }

  static String textFromBody(Uint8List body) {
    return '$textPrefix${_McmpBase91.encode(body)}';
  }

  static bool isTextPayload(String text) {
    final trimmedLeft = text.trimLeft();
    return trimmedLeft.startsWith(textPrefix) &&
        trimmedLeft.length > textPrefix.length;
  }

  static Uint8List bodyFromText(String text) {
    final trimmedLeft = text.trimLeft();
    if (!isTextPayload(trimmedLeft)) {
      throw const FormatException('Missing MCMP app text prefix');
    }
    return _McmpBase91.decode(trimmedLeft.substring(textPrefix.length));
  }
}

class _ByteWriter {
  final List<int> _bytes = <int>[];

  void writeByte(int value) {
    if (value < 0 || value > 0xff) {
      throw RangeError.range(value, 0, 0xff, 'value');
    }
    _bytes.add(value);
  }

  void writeBytes(List<int> values) {
    _bytes.addAll(values);
  }

  void writeUint32LE(int value) {
    if (value < 0 || value > 0xffffffff) {
      throw RangeError.range(value, 0, 0xffffffff, 'value');
    }
    _bytes
      ..add(value & 0xff)
      ..add((value >> 8) & 0xff)
      ..add((value >> 16) & 0xff)
      ..add((value >> 24) & 0xff);
  }

  void writeVarUint(int value) {
    if (value < 0) {
      throw RangeError.value(value, 'value');
    }
    var remaining = value;
    do {
      var byte = remaining & 0x7f;
      remaining >>= 7;
      if (remaining != 0) {
        byte |= 0x80;
      }
      _bytes.add(byte);
    } while (remaining != 0);
  }

  Uint8List toBytes() {
    return Uint8List.fromList(_bytes);
  }
}

class _ByteReader {
  final Uint8List _bytes;
  int _offset = 0;

  _ByteReader(this._bytes);

  int readByte() {
    if (_offset >= _bytes.length) {
      throw const FormatException('EOF');
    }
    return _bytes[_offset++];
  }

  Uint8List readBytes(int length) {
    if (length < 0 || _offset + length > _bytes.length) {
      throw const FormatException('EOF');
    }
    final result = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return result;
  }

  int readUint32LE() {
    final b0 = readByte();
    final b1 = readByte();
    final b2 = readByte();
    final b3 = readByte();
    return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
  }

  int readVarUint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final byte = readByte();
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        return result;
      }
      shift += 7;
      if (shift > 28) {
        throw const FormatException('Varuint too long');
      }
    }
  }

  Uint8List readRemainingBytes() {
    return readBytes(_bytes.length - _offset);
  }
}

class _McmpBase91 {
  static const String _alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
      '!#\$%&()*+,./:;<=>?@[]^_`{|}~"';
  static final Map<String, int> _decode = {
    for (var i = 0; i < _alphabet.length; i++) _alphabet[i]: i,
  };

  static String encode(Uint8List data) {
    final result = StringBuffer();
    var b = 0;
    var n = 0;

    for (final byte in data) {
      b |= byte << n;
      n += 8;
      if (n > 13) {
        var value = b & 8191;
        if (value > 88) {
          b >>= 13;
          n -= 13;
        } else {
          value = b & 16383;
          b >>= 14;
          n -= 14;
        }
        result
          ..write(_alphabet[value % 91])
          ..write(_alphabet[value ~/ 91]);
      }
    }

    if (n != 0) {
      result.write(_alphabet[b % 91]);
      if (n > 7 || b > 90) {
        result.write(_alphabet[b ~/ 91]);
      }
    }
    return result.toString();
  }

  static Uint8List decode(String text) {
    final out = <int>[];
    var b = 0;
    var n = 0;
    var v = -1;

    for (final codeUnit in text.codeUnits) {
      final ch = String.fromCharCode(codeUnit);
      final decoded = _decode[ch];
      if (decoded == null) {
        throw FormatException('Invalid Base91 character: $ch');
      }
      if (v < 0) {
        v = decoded;
      } else {
        v += decoded * 91;
        b |= v << n;
        n += (v & 8191) > 88 ? 13 : 14;
        do {
          out.add(b & 0xff);
          b >>= 8;
          n -= 8;
        } while (n > 7);
        v = -1;
      }
    }

    if (v >= 0) {
      out.add((b | (v << n)) & 0xff);
    }

    return Uint8List.fromList(out);
  }
}
