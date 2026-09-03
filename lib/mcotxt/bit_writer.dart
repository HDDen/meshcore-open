import 'dart:math' as math;
import 'dart:typed_data';

import 'mcotxt_errors.dart';

class BitWriter {
  final List<int> _bytes = <int>[];
  final StringBuffer _bitString = StringBuffer();
  int _current = 0;
  int _bitOffset = 0;

  int get bitLength => _bytes.length * 8 + _bitOffset;

  String get bitString => _bitString.toString();

  void writeBit(int value) {
    if (value != 0 && value != 1) {
      throw const McotxtCodecException(
        McotxtCodecError.invalidInput,
        'Bit value must be 0 or 1',
      );
    }
    writeBits(value, 1);
  }

  void writeBits(int value, int count) {
    if (count < 0 || count > 32 || value < 0) {
      throw const McotxtCodecException(
        McotxtCodecError.invalidInput,
        'Invalid bit field',
      );
    }
    if (count < 32 && value >= (1 << count)) {
      throw const McotxtCodecException(
        McotxtCodecError.invalidInput,
        'Bit field overflow',
      );
    }
    for (var shift = count - 1; shift >= 0; shift--) {
      final bit = (value >> shift) & 1;
      _current |= bit << (7 - _bitOffset);
      _bitOffset++;
      _bitString.write(bit);
      if (_bitOffset == 8) {
        _bytes.add(_current);
        _current = 0;
        _bitOffset = 0;
      }
    }
  }

  void writeBytes(Uint8List bytes, int bitLength) {
    if (bitLength < 0 || bitLength > bytes.length * 8) {
      throw const McotxtCodecException(
        McotxtCodecError.invalidInput,
        'Invalid source bitstream length',
      );
    }
    var remaining = bitLength;
    var index = 0;
    while (remaining > 0) {
      final take = math.min(8, remaining);
      writeBits(bytes[index] >> (8 - take), take);
      remaining -= take;
      index++;
    }
  }

  Uint8List toBytes() {
    final result = <int>[..._bytes];
    if (_bitOffset != 0) result.add(_current);
    return Uint8List.fromList(result);
  }
}
