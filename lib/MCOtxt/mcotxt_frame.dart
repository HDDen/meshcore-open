import 'dart:typed_data';

import 'mcotxt_codec.dart';
import 'mcotxt_options.dart';
import 'mcotxt_result.dart';

/// Length-prefixed MCOtxt bitstream for byte-oriented containers.
///
/// An MCOtxt stream is not self-terminating: the zero bits that pad its last
/// byte read back as TOP4 tokens, so whoever embeds a stream has to record
/// its exact bit count, never its byte count. This is the one agreed way to
/// do that in a byte container: `varuint(bitLength)` followed by
/// `ceil(bitLength / 8)` bytes of stream. `MCOtxtAppCodec` frames every
/// MCOtxt string it stores this way, and a new byte container should call
/// this class rather than lay out a frame of its own. A bit-packed host such
/// as MCOimg v4 needs no byte padding and keeps only the rule: the bit count
/// travels ahead of the bits.
abstract final class MCOtxtFrame {
  /// Encodes [text] and frames the result. Stats are off by default: a
  /// container wants bytes, not diagnostics.
  static Uint8List encode(
    String text, {
    MCOtxtEncodeOptions options = const MCOtxtEncodeOptions(
      collectStats: false,
    ),
  }) {
    return wrap(MCOtxtCodec.encode(text, options: options));
  }

  /// Frames a stream that is already encoded, for instance one cut to a
  /// budget by [MCOtxtCodec.encodeToBitLimit].
  static Uint8List wrap(MCOtxtEncodeResult encoded) {
    return wrapBits(encoded.data, encoded.bitLength);
  }

  static Uint8List wrapBits(Uint8List data, int bitLength) {
    if (bitLength < 0 || bitLength > data.length * 8) {
      throw RangeError.range(bitLength, 0, data.length * 8, 'bitLength');
    }
    final payloadLength = (bitLength + 7) >> 3;
    return Uint8List.fromList(<int>[
      ..._varUint(bitLength),
      ...data.take(payloadLength),
    ]);
  }

  /// Extent of the frame that starts at [offset]. Nothing is decoded, so a
  /// container can skip or measure a string without touching the models.
  static MCOtxtFrameSpan span(Uint8List bytes, {int offset = 0}) {
    if (offset < 0 || offset > bytes.length) {
      throw RangeError.range(offset, 0, bytes.length, 'offset');
    }
    var position = offset;
    var bitLength = 0;
    var shift = 0;
    while (true) {
      if (position >= bytes.length) {
        throw const FormatException('Truncated MCOtxt frame length');
      }
      final byte = bytes[position++];
      bitLength |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
      if (shift > 28) {
        throw const FormatException('MCOtxt frame length is too long');
      }
    }
    final result = MCOtxtFrameSpan(
      offset: offset,
      headerLength: position - offset,
      bitLength: bitLength,
    );
    if (result.end > bytes.length) {
      throw const FormatException('Truncated MCOtxt frame');
    }
    return result;
  }

  /// Decodes the frame that starts at [offset]; the returned span says where
  /// the container's next field begins.
  static MCOtxtFrameText decode(Uint8List bytes, {int offset = 0}) {
    final frameSpan = span(bytes, offset: offset);
    final payload = Uint8List.sublistView(
      bytes,
      frameSpan.payloadOffset,
      frameSpan.end,
    );
    return MCOtxtFrameText(
      text: MCOtxtCodec.decode(payload, bitLength: frameSpan.bitLength).text,
      span: frameSpan,
    );
  }

  static List<int> _varUint(int value) {
    final result = <int>[];
    var remaining = value;
    do {
      var byte = remaining & 0x7f;
      remaining >>= 7;
      if (remaining != 0) byte |= 0x80;
      result.add(byte);
    } while (remaining != 0);
    return result;
  }
}

class MCOtxtFrameSpan {
  final int offset;
  final int headerLength;
  final int bitLength;

  const MCOtxtFrameSpan({
    required this.offset,
    required this.headerLength,
    required this.bitLength,
  });

  int get payloadOffset => offset + headerLength;

  /// Stream bytes, header excluded: what compression statistics count.
  int get payloadLength => (bitLength + 7) >> 3;

  int get end => payloadOffset + payloadLength;

  /// Whole frame, header included.
  int get length => headerLength + payloadLength;
}

class MCOtxtFrameText {
  final String text;
  final MCOtxtFrameSpan span;

  const MCOtxtFrameText({required this.text, required this.span});
}
