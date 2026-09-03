import 'dart:typed_data';

import 'mcotxt_errors.dart';

class BitReader {
  final Uint8List _data;
  final int _bitLength;
  int _bitIndex = 0;

  BitReader(
    this._data, {
    required int bitLength,
  }) : _bitLength = bitLength {
    if (bitLength < 0 || bitLength > _data.length * 8) {
      throw const McotxtCodecException(
        McotxtCodecError.invalidInput,
        'Invalid bitLength',
      );
    }
  }

  int get remainingBits => _bitLength - _bitIndex;

  int readBit() => readBits(1);

  int readBits(int count) {
    if (count < 0 || count > 32) {
      throw const McotxtCodecException(
        McotxtCodecError.invalidInput,
        'Invalid bit field length',
      );
    }
    if (_bitIndex + count > _bitLength) {
      throw const McotxtCodecException(
        McotxtCodecError.unexpectedEnd,
        'Unexpected end of MCOtxt bitstream',
      );
    }
    var value = 0;
    for (var i = 0; i < count; i++) {
      final byte = _data[_bitIndex >> 3];
      final bit = (byte >> (7 - (_bitIndex & 7))) & 1;
      value = (value << 1) | bit;
      _bitIndex++;
    }
    return value;
  }
}
