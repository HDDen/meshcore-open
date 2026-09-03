import 'dart:convert';
import 'dart:typed_data';

import '../MCOtxt/mcotxt.dart';
import 'channel_app_data_helper.dart';

class EncodedMCOtxtAppMessage {
  final Uint8List body;
  final int timestamp;
  final bool isReply;
  final String? senderName;
  final String? replyAuthorName;
  final int? replyTimestamp;

  const EncodedMCOtxtAppMessage({
    required this.body,
    required this.timestamp,
    required this.isReply,
    this.senderName,
    this.replyAuthorName,
    this.replyTimestamp,
  });
}

class DecodedMCOtxtAppMessage {
  final String text;
  final int timestamp;

  /// Sender name embedded in the body. Room posts and the binary channel
  /// envelope carry it inside; the channel text transport leaves it in the
  /// outer "Name: text" layer and reports null here, as MCMP does.
  final String? senderName;
  final String? replyAuthorName;
  final int? replyTimestamp;
  final int? unsupportedVersion;
  final bool decodeFailed;

  const DecodedMCOtxtAppMessage({
    required this.text,
    required this.timestamp,
    this.senderName,
    this.replyAuthorName,
    this.replyTimestamp,
    this.unsupportedVersion,
    this.decodeFailed = false,
  });

  bool get isReply => replyAuthorName != null && replyTimestamp != null;
  bool get isUnsupported => unsupportedVersion != null;
  int? get metadataTimestamp => isUnsupported || decodeFailed ? null : timestamp;
}

class MCOtxtAppCodec {
  MCOtxtAppCodec._();

  static const int subtypeId = 0x03;
  static const int formatVersion = 1;
  static const int wireVersion = 0x01;
  static const int subtypeVersion = (subtypeId << 4) | wireVersion;
  static const String textPrefix = 'mct:';

  static const int _flagReply = 1 << 0;
  static const int _flagSenderName = 1 << 1;
  static const int _flagTimestampInherited = 1 << 2;
  static const int _knownFlags =
      _flagReply | _flagSenderName | _flagTimestampInherited;
  static const int _stringModeMCOtxt = 0x00;
  static const int _stringModeUtf8 = 0x01;

  static String unsupportedFormatText(int receivedVersion) {
    return 'MCOtxt v$receivedVersion не поддерживается: приложение поддерживает MCOtxt v$formatVersion';
  }

  static String decodeFailedText(int receivedVersion) {
    return 'MCOtxt v$receivedVersion не удалось раскодировать';
  }

  static DecodedMCOtxtAppMessage unsupportedMessage(int receivedVersion) {
    return DecodedMCOtxtAppMessage(
      text: unsupportedFormatText(receivedVersion),
      timestamp: 0,
      unsupportedVersion: receivedVersion,
    );
  }

  static DecodedMCOtxtAppMessage failedMessage(int receivedVersion) {
    return DecodedMCOtxtAppMessage(
      text: decodeFailedText(receivedVersion),
      timestamp: 0,
      unsupportedVersion: receivedVersion,
      decodeFailed: true,
    );
  }

  static Uint8List encodeBody({
    required String text,
    required int timestamp,
    String? senderName,
    String? replyAuthorName,
    int? replyTimestamp,
    bool includeTimestamp = true,
    bool includeSenderName = true,
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

    final writesSenderName = senderName != null && includeSenderName;
    final flags =
        (replyAuthorName != null ? _flagReply : 0) |
        (writesSenderName ? _flagSenderName : 0) |
        (!includeTimestamp ? _flagTimestampInherited : 0);
    final writer = _ByteWriter()..writeByte(flags);
    if (includeTimestamp) writer.writeUint32LE(timestamp);
    if (writesSenderName) _writeString(writer, senderName);
    if (replyAuthorName != null && replyTimestamp != null) {
      _writeString(writer, replyAuthorName);
      writer.writeUint32LE(replyTimestamp);
    }
    _writeMCOtxtOnlyString(writer, text);
    return writer.toBytes();
  }

  static DecodedMCOtxtAppMessage decodeBody(
    Uint8List body, {
    int? inheritedTimestamp,
  }) {
    final reader = _ByteReader(body);
    final flags = reader.readByte();
    if ((flags & ~_knownFlags) != 0) {
      throw const FormatException('Unsupported MCOtxt app flags');
    }
    final timestamp = (flags & _flagTimestampInherited) != 0
        ? (inheritedTimestamp ?? 0)
        : reader.readUint32LE();

    final senderName =
        (flags & _flagSenderName) != 0 ? _readString(reader) : null;

    String? replyAuthorName;
    int? replyTimestamp;
    if ((flags & _flagReply) != 0) {
      replyAuthorName = _readString(reader);
      replyTimestamp = reader.readUint32LE();
    }

    final text = _readString(reader);
    if (!reader.isDone) {
      throw const FormatException('Trailing MCOtxt app bytes');
    }
    return DecodedMCOtxtAppMessage(
      text: text,
      timestamp: timestamp,
      senderName: senderName,
      replyAuthorName: replyAuthorName,
      replyTimestamp: replyTimestamp,
    );
  }

  static String textFromBody(Uint8List body) {
    final payload = ChannelAppDataHelper.appPayloadWithoutSender(
      subtypeId: subtypeId,
      version: wireVersion,
      body: body,
    );
    return '$textPrefix${_MCOtxtBase91.encode(payload)}';
  }

  static bool isTextPayload(String text) {
    final trimmedLeft = text.trimLeft();
    return trimmedLeft.startsWith(textPrefix) &&
        trimmedLeft.length > textPrefix.length;
  }

  static Uint8List bodyFromText(String text) {
    return _bodyFromTextEnvelope(text).body;
  }

  static ChannelAppDataPayload _bodyFromTextEnvelope(String text) {
    final trimmedLeft = text.trimLeft();
    if (!isTextPayload(trimmedLeft)) {
      throw const FormatException('Missing MCOtxt app text prefix');
    }
    final payload = _MCOtxtBase91.decode(
      trimmedLeft.substring(textPrefix.length),
    );
    final envelope = ChannelAppDataHelper.tryDecodeAppPayloadWithoutSender(
      payload,
    );
    if (envelope == null || envelope.subtypeId != subtypeId) {
      throw const FormatException('Missing MCOtxt app payload');
    }
    if (envelope.version != wireVersion) {
      throw MCOtxtUnsupportedFormatException(envelope.version);
    }
    return envelope;
  }

  static String encodeTextTransport({
    required String text,
    required int timestamp,
    String? senderName,
    String? replyAuthorName,
    int? replyTimestamp,
    bool includeTimestamp = false,
    bool includeSenderName = true,
  }) {
    if (text.isEmpty || isTextPayload(text)) return text;
    try {
      return textFromBody(
        encodeBody(
          text: text,
          timestamp: timestamp,
          senderName: senderName,
          replyAuthorName: replyAuthorName,
          replyTimestamp: replyTimestamp,
          includeTimestamp: includeTimestamp,
          includeSenderName: includeSenderName,
        ),
      );
    } catch (_) {
      return text;
    }
  }

  static DecodedMCOtxtAppMessage? tryDecodeTextPayloadMessage(
    String text, {
    int? inheritedTimestamp,
  }) {
    if (!isTextPayload(text)) return null;
    try {
      return decodeBody(
        bodyFromText(text),
        inheritedTimestamp: inheritedTimestamp,
      );
    } on MCOtxtUnsupportedFormatException catch (error) {
      return unsupportedMessage(error.receivedVersion);
    } catch (_) {
      try {
        final trimmedLeft = text.trimLeft();
        final payload = _MCOtxtBase91.decode(
          trimmedLeft.substring(textPrefix.length),
        );
        final envelope = ChannelAppDataHelper.tryDecodeAppPayloadWithoutSender(
          payload,
        );
        return failedMessage(envelope?.version ?? formatVersion);
      } catch (_) {
        return failedMessage(formatVersion);
      }
    }
  }

  static String? tryDecodeTextPayload(String text) {
    return tryDecodeTextPayloadMessage(text)?.text;
  }

  static int compressedTextBytesFromBody(Uint8List body) {
    final reader = _ByteReader(body);
    final flags = reader.readByte();
    if ((flags & ~_knownFlags) != 0) {
      throw const FormatException('Unsupported MCOtxt app flags');
    }
    if ((flags & _flagTimestampInherited) == 0) {
      reader.readUint32LE();
    }
    if ((flags & _flagSenderName) != 0) {
      _skipString(reader);
    }
    if ((flags & _flagReply) != 0) {
      _skipString(reader);
      reader.readUint32LE();
    }
    return _skipString(reader);
  }

  static int? compressedTextBytesFromTextPayload(String text) {
    final trimmedLeft = text.trimLeft();
    if (!isTextPayload(trimmedLeft)) return null;
    try {
      return compressedTextBytesFromBody(bodyFromText(trimmedLeft));
    } catch (_) {
      return null;
    }
  }

  static void _writeMCOtxtString(_ByteWriter writer, String text) {
    final encoded = MCOtxtCodec.encode(
      text,
      options: const MCOtxtEncodeOptions(collectStats: false),
    );
    writer
      ..writeVarUint(encoded.bitLength)
      ..writeBytes(encoded.data);
  }

  static String _readMCOtxtString(_ByteReader reader) {
    final bitLength = reader.readVarUint();
    final bytes = reader.readBytes(_bytesForBits(bitLength));
    return MCOtxtCodec.decode(bytes, bitLength: bitLength).text;
  }

  static void _writeString(_ByteWriter writer, String text) {
    final normalized = MCOtxtModelRegistry.normalizeInputText(text);
    final utf8Candidate = _buildUtf8StringCandidate(normalized);
    try {
      final mcotxtCandidate = _buildMCOtxtStringCandidate(normalized);
      writer.writeBytes(
        _preferMCOtxtStringCandidate(mcotxtCandidate, utf8Candidate)
            ? mcotxtCandidate
            : utf8Candidate,
      );
    } catch (_) {
      writer.writeBytes(utf8Candidate);
    }
  }

  static void _writeMCOtxtOnlyString(_ByteWriter writer, String text) {
    writer.writeByte(_stringModeMCOtxt);
    _writeMCOtxtString(writer, MCOtxtModelRegistry.normalizeInputText(text));
  }

  static Uint8List _buildMCOtxtStringCandidate(String normalizedText) {
    final writer = _ByteWriter()
      ..writeByte(_stringModeMCOtxt);
    _writeMCOtxtString(writer, normalizedText);
    return writer.toBytes();
  }

  static Uint8List _buildUtf8StringCandidate(String normalizedText) {
    final writer = _ByteWriter()
      ..writeByte(_stringModeUtf8)
      ..writeUtf8String(normalizedText);
    return writer.toBytes();
  }

  static bool _preferMCOtxtStringCandidate(
    Uint8List mcotxtCandidate,
    Uint8List utf8Candidate,
  ) {
    if (mcotxtCandidate.length != utf8Candidate.length) {
      return mcotxtCandidate.length < utf8Candidate.length;
    }
    return true;
  }

  static String _readString(_ByteReader reader) {
    final mode = reader.readByte();
    switch (mode) {
      case _stringModeMCOtxt:
        return _readMCOtxtString(reader);
      case _stringModeUtf8:
        return reader.readUtf8String();
      default:
        throw FormatException('Unsupported MCOtxt string mode: $mode');
    }
  }

  static int _skipString(_ByteReader reader) {
    final mode = reader.readByte();
    switch (mode) {
      case _stringModeMCOtxt:
        final bitLength = reader.readVarUint();
        final byteLength = _bytesForBits(bitLength);
        reader.skipBytes(byteLength);
        return byteLength;
      case _stringModeUtf8:
        final byteLength = reader.readVarUint();
        reader.skipBytes(byteLength);
        return byteLength;
      default:
        throw FormatException('Unsupported MCOtxt string mode: $mode');
    }
  }

  static int _bytesForBits(int bitLength) {
    if (bitLength < 0) throw RangeError.value(bitLength, 'bitLength');
    return (bitLength + 7) >> 3;
  }
}

class MCOtxtUnsupportedFormatException implements Exception {
  final int receivedVersion;

  const MCOtxtUnsupportedFormatException(this.receivedVersion);

  @override
  String toString() {
    return 'Unsupported MCOtxt format version: $receivedVersion';
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
    if (value < 0) throw RangeError.value(value, 'value');
    var remaining = value;
    do {
      var byte = remaining & 0x7f;
      remaining >>= 7;
      if (remaining != 0) byte |= 0x80;
      _bytes.add(byte);
    } while (remaining != 0);
  }

  void writeUtf8String(String value) {
    final bytes = utf8.encode(value);
    writeVarUint(bytes.length);
    writeBytes(bytes);
  }

  Uint8List toBytes() {
    return Uint8List.fromList(_bytes);
  }
}

class _ByteReader {
  final Uint8List _bytes;
  int _offset = 0;

  _ByteReader(this._bytes);

  bool get isDone => _offset == _bytes.length;

  int readByte() {
    if (_offset >= _bytes.length) throw const FormatException('EOF');
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

  void skipBytes(int length) {
    readBytes(length);
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
      if ((byte & 0x80) == 0) return result;
      shift += 7;
      if (shift > 28) throw const FormatException('Varuint too long');
    }
  }

  String readUtf8String() {
    return utf8.decode(readBytes(readVarUint()));
  }
}

class _MCOtxtBase91 {
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
