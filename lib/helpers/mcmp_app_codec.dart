import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../connector/meshcore_protocol.dart';
import 'mesh_compressor.dart';

/// Serialized by name in message stores; only append new values and never
/// rename existing ones (unknown names fall back to [none] on older builds).
enum McmpSignatureStatus {
  none,
  unsigned,
  valid,
  invalid,
  unverifiable,
  transportAuthenticated,
}

/// Signing context. DM payloads are never signed: the ECDH transport already
/// authenticates the sender.
enum McmpSigningContext {
  channel(0x01),
  room(0x02);

  final int id;

  const McmpSigningContext(this.id);
}

class EncodedMcmpAppMessage {
  final Uint8List body;
  final int timestamp;
  final bool isSigned;
  final bool isReply;
  final String? senderName;
  final String? replyAuthorName;
  final int? replyTimestamp;

  const EncodedMcmpAppMessage({
    required this.body,
    required this.timestamp,
    required this.isSigned,
    required this.isReply,
    this.senderName,
    this.replyAuthorName,
    this.replyTimestamp,
  });
}

class DecodedMcmpAppMessage {
  final String text;
  final int timestamp;

  /// Sender name embedded in the body. Present only for transports that do
  /// not carry the author name outside of the MCMP payload (room servers).
  final String? senderName;
  final Uint8List? signature;
  final McmpSignatureStatus signatureStatus;
  final String? replyAuthorName;
  final int? replyTimestamp;

  const DecodedMcmpAppMessage({
    required this.text,
    required this.timestamp,
    this.senderName,
    this.signature,
    this.signatureStatus = McmpSignatureStatus.unsigned,
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
  static const String bindingDomain = 'MCOAPP:MCMP:BIND:v3';
  static const int signingBindingSize = 32;

  static const int _flagReply = 1 << 0;
  static const int _flagSigned = 1 << 1;
  static const int _flagSenderName = 1 << 2;
  static const int _knownFlags = _flagReply | _flagSigned | _flagSenderName;

  /// Packs the wire flags byte. The exact same byte is covered by the
  /// signature via [canonicalSigningBytes], so encode and verify paths must
  /// derive it through this single helper.
  static int packFlags({
    required bool hasReply,
    required bool isSigned,
    required bool hasSenderName,
  }) {
    var flags = 0;
    if (hasReply) flags |= _flagReply;
    if (isSigned) flags |= _flagSigned;
    if (hasSenderName) flags |= _flagSenderName;
    return flags;
  }

  /// Signing binding for channel messages: full HMAC-SHA256 of the binding
  /// domain keyed with the 16-byte channel PSK.
  static Uint8List channelSigningBinding(Uint8List psk) {
    final hmac = crypto.Hmac(crypto.sha256, psk);
    return Uint8List.fromList(hmac.convert(utf8.encode(bindingDomain)).bytes);
  }

  /// Signing binding for room-server messages: the room's 32-byte public key.
  static Uint8List roomSigningBinding(Uint8List roomPublicKey) {
    if (roomPublicKey.length != signingBindingSize) {
      throw ArgumentError.value(
        roomPublicKey.length,
        'roomPublicKey.length',
        'Room binding requires a $signingBindingSize-byte public key',
      );
    }
    return Uint8List.fromList(roomPublicKey);
  }

  static EncodedMcmpAppMessage encodeBody({
    required String text,
    required int timestamp,
    String? senderName,
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

    final flags = packFlags(
      hasReply: replyAuthorName != null,
      isSigned: signature != null,
      hasSenderName: senderName != null,
    );

    final compressed = MeshCompressor.instance.compressToBytes(text);
    final writer = _ByteWriter()
      ..writeByte(flags)
      ..writeUint32LE(timestamp);
    if (senderName != null) {
      final senderNameBytes = utf8.encode(senderName);
      writer.writeVarUint(senderNameBytes.length);
      writer.writeBytes(senderNameBytes);
    }
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
      senderName: senderName,
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

    String? senderName;
    if ((flags & _flagSenderName) != 0) {
      final senderNameLength = reader.readVarUint();
      senderName = utf8.decode(reader.readBytes(senderNameLength));
    }

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
      senderName: senderName,
      signature: signature,
      signatureStatus: signature == null
          ? McmpSignatureStatus.unsigned
          : McmpSignatureStatus.invalid,
      replyAuthorName: replyAuthorName,
      replyTimestamp: replyTimestamp,
    );
  }

  /// Canonical bytes covered by the Ed25519 signature.
  ///
  /// Nothing here travels on the wire as-is: both signer and verifier rebuild
  /// these bytes from their own context. [binding] pins the destination
  /// (channel PSK derivation or room public key), so a signature made for one
  /// destination can never verify in another. [flags] must be the exact wire
  /// flags byte of the body (see [packFlags]). [senderName] always
  /// participates regardless of whether the body embeds it; the verifier takes
  /// it from the body (room) or from the transport layer (channel envelope /
  /// outer text). [text] is the original uncompressed message text.
  static Uint8List canonicalSigningBytes({
    required McmpSigningContext context,
    required Uint8List binding,
    required String senderName,
    required int timestamp,
    required int flags,
    required String text,
    String? replyAuthorName,
    int? replyTimestamp,
  }) {
    if (binding.length != signingBindingSize) {
      throw ArgumentError.value(
        binding.length,
        'binding.length',
        'Signing binding must be $signingBindingSize bytes',
      );
    }
    if ((replyAuthorName == null) != (replyTimestamp == null)) {
      throw ArgumentError(
        'replyAuthorName and replyTimestamp must be provided together',
      );
    }
    if (((flags & _flagReply) != 0) != (replyAuthorName != null)) {
      throw ArgumentError('flags reply bit conflicts with reply arguments');
    }
    if ((flags & ~_knownFlags) != 0) {
      throw ArgumentError.value(flags, 'flags', 'Unknown flag bits');
    }

    final senderNameBytes = utf8.encode(senderName);
    final textBytes = utf8.encode(text);
    final writer = _ByteWriter()
      ..writeBytes(utf8.encode(signingDomain))
      ..writeByte(context.id)
      ..writeBytes(binding)
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

  /// Byte length of the compressed text segment inside a v3 body, excluding
  /// all container metadata (flags, timestamp, sender name, signature and
  /// reply anchor). Used by compression statistics so the ratio reflects the
  /// text itself rather than the container overhead.
  static int compressedTextBytesFromBody(Uint8List body) {
    final reader = _ByteReader(body);
    final flags = reader.readByte();
    if ((flags & ~_knownFlags) != 0) {
      throw const FormatException('Unsupported MCMP app flags');
    }
    reader.readUint32LE(); // timestamp
    if ((flags & _flagSenderName) != 0) {
      reader.readBytes(reader.readVarUint());
    }
    if ((flags & _flagSigned) != 0) {
      reader.readBytes(signatureSize);
    }
    if ((flags & _flagReply) != 0) {
      reader.readBytes(reader.readVarUint());
      reader.readUint32LE();
    }
    return reader.readRemainingBytes().length;
  }

  /// Same as [compressedTextBytesFromBody] for the `mcmp3:` text transport;
  /// null when [text] is not a parsable v3 payload.
  static int? compressedTextBytesFromTextPayload(String text) {
    final trimmedLeft = text.trimLeft();
    if (!isTextPayload(trimmedLeft)) return null;
    try {
      return compressedTextBytesFromBody(bodyFromText(trimmedLeft));
    } catch (_) {
      return null;
    }
  }

  /// Encodes [text] into the `mcmp3:` text transport.
  ///
  /// When the v3 format is selected the container is always used, signed or
  /// not: it carries the timestamp (reply anchor) and, when present, the
  /// sender name and signature — there is no "only if smaller" gate. The
  /// original text is returned only for empty/already-encoded inputs or when
  /// encoding fails.
  static String encodeTextTransport({
    required String text,
    required int timestamp,
    String? senderName,
    Uint8List? signature,
    String? replyAuthorName,
    int? replyTimestamp,
  }) {
    if (text.isEmpty ||
        isTextPayload(text) ||
        MeshCompressor.instance.hasPrefix(text)) {
      return text;
    }
    try {
      final encoded = encodeBody(
        text: text,
        timestamp: timestamp,
        senderName: senderName,
        signature: signature,
        replyAuthorName: replyAuthorName,
        replyTimestamp: replyTimestamp,
      );
      return textFromBody(encoded.body);
    } catch (_) {
      // Fall through to original text.
    }
    return text;
  }

  static String encodeDirectContactText({
    required String text,
    required int timestamp,
  }) {
    return encodeTextTransport(text: text, timestamp: timestamp);
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

  static String? tryDecodeTextPayload(String text) {
    return tryDecodeTextPayloadMessage(text)?.text;
  }

  static DecodedMcmpAppMessage? tryDecodeTextPayloadMessage(String text) {
    if (!isTextPayload(text)) return null;
    try {
      return decodeBody(bodyFromText(text));
    } catch (_) {
      return null;
    }
  }

  static McmpSignatureStatus signatureStatusFromTextPayload(String text) {
    return tryDecodeTextPayloadMessage(text)?.signatureStatus ??
        McmpSignatureStatus.none;
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
