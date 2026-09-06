// MCOimg v4 command-level tests.
//
// Every expected stream is assembled here from the field lists of
// docs/mcoimg_v4_reference.md with a bit writer that knows nothing of the
// codec, so a failure points at the codec or at the reference, never at a
// stale constant. Positive cases pin the exact bytes the reference encoder
// produces where its choice among the alternate forms is unambiguous, decode
// hand-assembled streams for every form the decoder must accept, and round
// trip documents through encode and decode. Negative cases assert the failure
// class the reference names: damaged input is MCOImageInvalidPayloadException,
// an unsupported extension is MCOImageUnsupportedFormatException.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/MCOtxt/mcotxt.dart';
import 'package:meshcore_open/helpers/mcoimg_palette.dart';
import 'package:meshcore_open/helpers/mcoimg_types.dart';
import 'package:meshcore_open/helpers/mcoimg_v3_codec.dart';
import 'package:meshcore_open/helpers/mcoimg_v4_codec.dart';
import 'package:meshcore_open/helpers/mcoimg_v4_model.dart';

const MCOImageV4Codec _codec = MCOImageV4Codec();

// ---------------------------------------------------------------------------
// Wire assembly, from the reference alone.

/// Least-significant-bit-first writer, as the canonical document is packed.
class _Bits {
  final List<int> _bytes = <int>[];
  int _current = 0;
  int _offset = 0;

  void write(int value, int bits) {
    for (var i = 0; i < bits; i++) {
      if ((value >> i) & 1 != 0) _current |= 1 << _offset;
      _offset++;
      if (_offset == 8) {
        _bytes.add(_current);
        _current = 0;
        _offset = 0;
      }
    }
  }

  void bit(bool value) => write(value ? 1 : 0, 1);

  /// ZigZag-coded signed value in [bits] bits.
  void zz(int value, int bits) =>
      write(value >= 0 ? value << 1 : ((-value) << 1) - 1, bits);

  /// `bitCompactUint`: 0+2 bits, 10+4 bits, 110+8 bits, 111+bitVarUint7.
  void compact(int value) {
    if (value <= 3) {
      write(0, 1);
      write(value, 2);
    } else if (value <= 19) {
      write(1, 1);
      write(0, 1);
      write(value - 4, 4);
    } else if (value <= 275) {
      write(1, 1);
      write(1, 1);
      write(0, 1);
      write(value - 20, 8);
    } else {
      write(1, 1);
      write(1, 1);
      write(1, 1);
      varUint7(value);
    }
  }

  void varUint7(int value) {
    var remaining = value;
    do {
      var byte = remaining & 0x7f;
      remaining >>= 7;
      if (remaining != 0) byte |= 0x80;
      write(byte, 8);
    } while (remaining != 0);
  }

  void bytes(List<int> data) {
    for (final byte in data) {
      write(byte, 8);
    }
  }

  /// An MCOtxt stream is packed most-significant bit first; it is embedded one
  /// bit at a time.
  void mcotxt(Uint8List data, int bitLength) {
    for (var i = 0; i < bitLength; i++) {
      write((data[i >> 3] >> (7 - (i & 7))) & 1, 1);
    }
  }

  void end() => write(_opEnd, 4);

  /// The canonical document: what was written, zero-padded to a byte.
  Uint8List finish() {
    final out = <int>[..._bytes];
    if (_offset != 0) out.add(_current);
    return Uint8List.fromList(out);
  }

  /// A v4 body with nonce 0 and no transport tail.
  Uint8List body() => Uint8List.fromList(<int>[0, ...finish()]);
}

/// Derived widths of a canvas, as the reference defines them.
class _Canvas {
  final int width;
  final int height;
  final PaletteProfile profile;

  const _Canvas(this.width, this.height, [this.profile = PaletteProfile.master8]);

  static int margin(int size) => math.min(16, math.max(1, (size + 7) ~/ 8));
  static int coordinateBits(int size) =>
      math.max(1, (size + 2 * margin(size) - 1).bitLength);

  int get xBits => coordinateBits(width);
  int get yBits => coordinateBits(height);
  int get scalarBits => math.max(1, (math.max(width, height) - 1).bitLength);
  int get colorBits =>
      math.max(1, (MCOImagePalette.colorsFor(profile).length - 1).bitLength);

  /// mode(2) paletteProfile(4) dimensions hasBackgroundOverride(1) [...]
  /// `background` is the profile color reference; `transparent` writes the
  /// override with a cleared presence bit.
  void header(
    _Bits b, {
    int mode = 0,
    int? background,
    bool transparent = false,
  }) {
    b.write(mode, 2);
    b.write(profile.index, 4);
    dimensions(b);
    final override = background != null || transparent;
    b.bit(override);
    if (override) {
      b.bit(background != null);
      if (background != null) b.write(background, colorBits);
    }
  }

  void dimensions(_Bits b) {
    if (width == height && width <= 64) {
      b.write(0, 2);
      b.write(width - 1, 6);
    } else if (width <= 32 && height <= 32) {
      b.write(1, 2);
      b.write(width - 1, 5);
      b.write(height - 1, 5);
    } else if (width <= 64 && height <= 64) {
      b.write(2, 2);
      b.write(width - 1, 6);
      b.write(height - 1, 6);
    } else {
      b.write(3, 2);
      b.bit(width != height);
      b.write(width - 1, 8);
      if (width != height) b.write(height - 1, 8);
    }
  }

  void point(_Bits b, int x, int y) {
    b.write(x + margin(width), xBits);
    b.write(y + margin(height), yBits);
  }

  void x(_Bits b, int value) => b.write(value + margin(width), xBits);
  void y(_Bits b, int value) => b.write(value + margin(height), yBits);

  void color(_Bits b, int? ref) {
    b.bit(ref != null);
    if (ref != null) b.write(ref, colorBits);
  }

  void scalar(_Bits b, int value) => b.write(value - 1, scalarBits);
}

// Base opcodes and extended sub-opcodes, straight from the command table.
const int _opEnd = 0;
const int _opSetFill = 1;
const int _opSetStroke = 2;
const int _opSetStrokeWidth = 3;
const int _opDot = 4;
const int _opLine = 5;
const int _opRect = 6;
const int _opEllipse = 7;
const int _opRectAxisAligned = 8;
const int _opPathAbsolute = 9;
const int _opPathDelta = 10;
const int _opWave = 11;
const int _opRepeatLast = 12;
const int _opEllipseAxisAligned = 13;
const int _opRepeatShort = 14;
const int _opExtended = 15;

const int _extLineDelta = 0;
const int _extLineAxisDelta = 1;
const int _extAreaDelta = 2;
const int _extWaveDelta = 3;
const int _extPathOrthogonal = 4;
const int _extPathBounds = 5;
const int _extPathBoundsDelta = 6;
const int _extLineAxisAbsolute = 7;
const int _extEllipseDepth = 8;
const int _extRepeatBack = 9;
const int _extDotRun = 10;
const int _extSetStyle = 11;
const int _extRepeatColorRun = 12;
const int _extGroup = 13;
const int _extRasterLayer = 14;
const int _extEscape = 15;
const int _ext2Text = 0;

void _ext(_Bits b, int sub) {
  b.write(_opExtended, 4);
  b.write(sub, 4);
}

// ---------------------------------------------------------------------------
// Documents.

const _Canvas _small = _Canvas(16, 16); // point 10 bits, scalar 4, color 3
const _Canvas _large = _Canvas(128, 128); // point 16 bits, scalar 7, color 3

/// Profile color ids of the test palette: white and black of master8, then
/// three more colors. Local indexes follow the list order.
const int _white = 0;
const int _black = 2;
const int _colorA = 3;
const int _colorB = 4;
const int _colorC = 5;
const List<int> _palette = <int>[_white, _black, _colorA, _colorB, _colorC];
const int _localWhite = 0;
const int _localBlack = 1;
const int _localA = 2;
const int _localB = 3;
const int _localC = 4;

const MCOImageV4Style _ink = MCOImageV4Style(strokeColor: _localBlack);

MCOImageV4Document _doc(
  _Canvas canvas,
  List<MCOImageV4Figure> figures, {
  int? background = _localWhite,
  MCOImageV4Mode mode = MCOImageV4Mode.vector,
}) {
  return MCOImageV4Document(
    mode: mode,
    width: canvas.width,
    height: canvas.height,
    paletteProfile: canvas.profile,
    palette: _palette,
    backgroundColor: background,
    initialStyle: _ink,
    figures: figures,
  );
}

MCOImageV4Dot _dot(int x, int y, {MCOImageV4Style style = _ink}) =>
    MCOImageV4Dot(point: MCOImageV4Point(x, y), style: style);

MCOImageV4Line _line(
  int x1,
  int y1,
  int x2,
  int y2, {
  MCOImageV4Style style = _ink,
}) =>
    MCOImageV4Line(
      start: MCOImageV4Point(x1, y1),
      end: MCOImageV4Point(x2, y2),
      style: style,
    );

MCOImageV4Path _path(List<(int, int)> points, {bool closed = false}) =>
    MCOImageV4Path(
      points: <MCOImageV4Point>[
        for (final (x, y) in points) MCOImageV4Point(x, y),
      ],
      closed: closed,
      style: _ink,
    );

// ---------------------------------------------------------------------------
// Comparing documents across the palette rebuild: colors as profile ids.

String _styleText(MCOImageV4Style style, List<int> palette) {
  String color(int? local) => local == null ? '-' : '${palette[local]}';
  return 'fill=${color(style.fillColor)} stroke=${color(style.strokeColor)} '
      'width=${style.strokeWidth}';
}

String _pointText(MCOImageV4Point point) => '(${point.x},${point.y})';

String _figureText(MCOImageV4Figure figure, List<int> palette) {
  final style = _styleText(figure.style, palette);
  switch (figure) {
    case MCOImageV4Dot(:final point):
      return 'dot ${_pointText(point)} $style';
    case MCOImageV4Line(:final start, :final end):
      return 'line ${_pointText(start)} ${_pointText(end)} $style';
    case MCOImageV4Rect(:final first, :final second, :final third):
      return 'rect ${_pointText(first)} ${_pointText(second)} '
          '${_pointText(third)} $style';
    case MCOImageV4Ellipse(:final first, :final second, :final third):
      return 'ellipse ${_pointText(first)} ${_pointText(second)} '
          '${_pointText(third)} $style';
    case MCOImageV4Path(:final points, :final closed):
      return 'path ${closed ? 'closed' : 'open'} '
          '${points.map(_pointText).join(' ')} $style';
    case MCOImageV4Wave(:final start, :final end, :final depth, :final closed):
      return 'wave ${closed ? 'closed' : 'open'} ${_pointText(start)} '
          '${_pointText(end)} depth=$depth $style';
    case MCOImageV4Text(
      :final origin,
      :final width,
      :final fontSize,
      :final align,
      :final text,
    ):
      return 'text ${_pointText(origin)} width=$width font=$fontSize '
          'align=${align.name} "$text" $style';
    case MCOImageV4RasterLayer(
      :final x,
      :final y,
      :final width,
      :final height,
      :final pixels,
      :final transparentColor,
    ):
      return 'raster ($x,$y) ${width}x$height ${pixels.join(',')} '
          'transparent=$transparentColor';
    case MCOImageV4Group(:final figures):
      // A group's own style is not on the wire; its children's are.
      final children = figures
          .where((child) => child.visible)
          .map((child) => _figureText(child, palette))
          .join('; ');
      return 'group[$children]';
  }
}

List<String> _documentText(MCOImageV4Document document) => <String>[
  for (final figure in document.figures)
    if (figure.visible) _figureText(figure, document.palette),
];

int? _backgroundOf(MCOImageV4Document document) {
  final local = document.backgroundColor;
  return local == null ? null : document.palette[local];
}

/// Encodes, decodes, and checks the decoded document says the same as the
/// input once local color indexes are mapped back to profile colors.
DecodedMCOImageV4 _expectRoundTrip(MCOImageV4Document document) {
  final encoded = _codec.encode(document, nonce: 0);
  final decoded = _codec.decodeBody(encoded.body);
  expect(decoded.document.width, document.width);
  expect(decoded.document.height, document.height);
  expect(decoded.document.paletteProfile, document.paletteProfile);
  expect(_backgroundOf(decoded.document), _backgroundOf(document));
  expect(_documentText(decoded.document), _documentText(document));
  return decoded;
}

/// The encoder's exact bytes for [document], and the round trip on top.
void _expectExact(MCOImageV4Document document, _Bits expected) {
  final encoded = _codec.encode(document, nonce: 0);
  expect(encoded.canonicalDocument, equals(expected.finish()));
  expect(encoded.body[0], 0);
  expect(encoded.body.length, encoded.canonicalDocument.length + 1);
  _expectRoundTrip(document);
}

MCOImageV4Document _decode(_Bits stream) =>
    _codec.decodeBody(stream.body()).document;

Matcher get _damaged => throwsA(isA<MCOImageInvalidPayloadException>());
Matcher get _unsupported =>
    throwsA(isA<MCOImageUnsupportedFormatException>());
Matcher get _badInput => throwsA(isA<MCOImageInvalidInputException>());

void main() {
  group('header', () {
    test('an empty vector document is header, END and padding', () {
      final expected = _Bits();
      _small.header(expected);
      expected.end();
      // 2 + 4 + 2 + 6 + 1 + 4 = 19 bits: three bytes.
      expect(expected.finish().length, 3);

      final decoded = _codec.decodeBody(
        _codec.encode(_doc(_small, const <MCOImageV4Figure>[]), nonce: 0).body,
      );
      _expectExact(_doc(_small, const <MCOImageV4Figure>[]), expected);
      expect(decoded.document.figures, isEmpty);
      expect(decoded.document.mode, MCOImageV4Mode.vector);
      // White is registered first, then black for the initial style.
      expect(decoded.document.palette, <int>[_white, _black]);
      expect(decoded.document.backgroundColor, 0);
      expect(decoded.document.initialStyle, const MCOImageV4Style(strokeColor: 1));
    });

    test('dimension modes take the shortest canonical form', () {
      for (final canvas in const <_Canvas>[
        _Canvas(16, 16), // square up to 64
        _Canvas(20, 10), // non-square up to 32
        _Canvas(40, 64), // non-square up to 64
        _Canvas(33, 8), // one side past 32 needs the 64 mode
        _Canvas(100, 100), // extended square
        _Canvas(100, 200), // extended rectangle
        _Canvas(256, 1), // the largest canvas, the thinnest
      ]) {
        final expected = _Bits();
        canvas.header(expected);
        expected.end();
        _expectExact(_doc(canvas, const <MCOImageV4Figure>[]), expected);
      }
    });

    test('non-canonical dimensions are rejected', () {
      // Each stream writes a dimension mode by hand that a shorter mode
      // could have expressed.
      void reject(void Function(_Bits b) dims) {
        final stream = _Bits();
        stream.write(0, 2);
        stream.write(PaletteProfile.master8.index, 4);
        dims(stream);
        stream.bit(false);
        stream.end();
        expect(() => _decode(stream), _damaged);
      }

      reject((b) {
        b.write(1, 2); // small rectangle mode with equal sides
        b.write(9, 5);
        b.write(9, 5);
      });
      reject((b) {
        b.write(2, 2); // medium mode with equal sides
        b.write(39, 6);
        b.write(39, 6);
      });
      reject((b) {
        b.write(2, 2); // medium mode for a pair that fits the small one
        b.write(19, 6);
        b.write(9, 6);
      });
      reject((b) {
        b.write(3, 2); // extended square of 64 or less
        b.bit(false);
        b.write(63, 8);
      });
      reject((b) {
        b.write(3, 2); // extended rectangle with equal sides
        b.bit(true);
        b.write(99, 8);
        b.write(99, 8);
      });
      reject((b) {
        b.write(3, 2); // extended rectangle that fits the medium mode
        b.bit(true);
        b.write(39, 8);
        b.write(63, 8);
      });
    });

    test('a background other than profile white is an override', () {
      final expected = _Bits();
      _small.header(expected, background: _colorA);
      expected.end();
      _expectExact(
        _doc(_small, const <MCOImageV4Figure>[], background: _localA),
        expected,
      );
    });

    test('a transparent background is an override with no color', () {
      final expected = _Bits();
      _small.header(expected, transparent: true);
      expected.end();
      _expectExact(
        _doc(_small, const <MCOImageV4Figure>[], background: null),
        expected,
      );
    });

    test('the decoder registers white, the background, then black', () {
      final stream = _Bits();
      _small.header(stream, background: _colorA);
      stream.end();
      final document = _decode(stream);
      expect(document.palette, <int>[_white, _colorA, _black]);
      expect(document.backgroundColor, 1);
      expect(document.initialStyle, const MCOImageV4Style(strokeColor: 2));
    });

    test('every palette profile round-trips and writes its own code', () {
      for (final profile in PaletteProfile.values) {
        final canvas = _Canvas(16, 16, profile);
        final white = MCOImagePalette.whiteIndexFor(profile);
        final black = MCOImagePalette.blackIndexFor(profile);
        final document = MCOImageV4Document(
          width: 16,
          height: 16,
          paletteProfile: profile,
          palette: <int>[white, black],
          backgroundColor: 0,
          initialStyle: const MCOImageV4Style(strokeColor: 1),
          figures: const <MCOImageV4Figure>[],
        );
        final expected = _Bits();
        canvas.header(expected);
        expected.end();
        final encoded = _codec.encode(document, nonce: 0);
        expect(
          encoded.canonicalDocument,
          equals(expected.finish()),
          reason: profile.name,
        );
        final decoded = _codec.decodeBody(encoded.body).document;
        expect(decoded.paletteProfile, profile);
        expect(decoded.palette, <int>[white, black], reason: profile.name);
      }
    });

    test('modes 2 and 3 are unsupported, not damage', () {
      for (final mode in const <int>[2, 3]) {
        final stream = _Bits();
        _small.header(stream, mode: mode);
        stream.end();
        expect(() => _decode(stream), _unsupported);
      }
    });

    test('a mixed document without a raster layer is rejected', () {
      final stream = _Bits();
      _small.header(stream, mode: 1);
      stream.end();
      expect(() => _decode(stream), _damaged);
    });
  });

  group('style commands', () {
    test('one changed field costs a separate SET command', () {
      // SET_FILL is 8 bits, SET_STYLE with one field 15; the second dot sits
      // far enough from the first that no repeat form beats a full DOT.
      final document = _doc(_small, <MCOImageV4Figure>[
        _dot(2, 2),
        _dot(
          14,
          13,
          style: const MCOImageV4Style(fillColor: _localA, strokeColor: _localBlack),
        ),
      ]);
      final expected = _Bits();
      _small.header(expected);
      expected.write(_opDot, 4);
      _small.point(expected, 2, 2);
      expected.write(_opSetFill, 4);
      _small.color(expected, _colorA);
      expected.write(_opDot, 4);
      _small.point(expected, 14, 13);
      expected.end();
      _expectExact(document, expected);
    });

    test('three changed fields cost one SET_STYLE', () {
      // 24 bits as three commands, 23 as one.
      final document = _doc(_small, <MCOImageV4Figure>[
        _dot(2, 2),
        _dot(
          14,
          13,
          style: const MCOImageV4Style(
            fillColor: _localA,
            strokeColor: _localB,
            strokeWidth: 2,
          ),
        ),
      ]);
      final expected = _Bits();
      _small.header(expected);
      expected.write(_opDot, 4);
      _small.point(expected, 2, 2);
      _ext(expected, _extSetStyle);
      expected.write(0x07, 3);
      _small.color(expected, _colorA);
      _small.color(expected, _colorB);
      _small.scalar(expected, 2);
      expected.write(_opDot, 4);
      _small.point(expected, 14, 13);
      expected.end();
      _expectExact(document, expected);
    });

    test('the decoder applies SET_FILL, SET_STROKE and SET_STROKE_WIDTH', () {
      final stream = _Bits();
      _small.header(stream);
      stream.write(_opSetFill, 4);
      _small.color(stream, _colorA);
      stream.write(_opSetStroke, 4);
      _small.color(stream, _colorB);
      stream.write(_opSetStrokeWidth, 4);
      _small.scalar(stream, 5);
      stream.write(_opDot, 4);
      _small.point(stream, 3, 4);
      stream.end();
      final document = _decode(stream);
      expect(_documentText(document), <String>[
        'dot (3,4) fill=$_colorA stroke=$_colorB width=5',
      ]);
    });

    test('a cleared stroke leaves a line with no outline', () {
      final stream = _Bits();
      _small.header(stream);
      stream.write(_opSetStroke, 4);
      _small.color(stream, null);
      stream.write(_opLine, 4);
      _small.point(stream, 1, 1);
      _small.point(stream, 5, 6);
      stream.end();
      expect(_documentText(_decode(stream)), <String>[
        'line (1,1) (5,6) fill=- stroke=- width=1',
      ]);
    });

    test('SET_STYLE with an empty mask is rejected', () {
      final stream = _Bits();
      _small.header(stream);
      _ext(stream, _extSetStyle);
      stream.write(0, 3);
      stream.end();
      expect(() => _decode(stream), _damaged);
    });

    test('a stroke width above the canvas is rejected', () {
      // 20x10: scalarBits is 5, so the field reaches 32 while the limit is 20.
      const canvas = _Canvas(20, 10);
      final stream = _Bits();
      canvas.header(stream);
      stream.write(_opSetStrokeWidth, 4);
      canvas.scalar(stream, 25);
      stream.write(_opDot, 4);
      canvas.point(stream, 1, 1);
      stream.end();
      expect(() => _decode(stream), _damaged);
    });
  });

  group('figures', () {
    test('DOT', () {
      final expected = _Bits();
      _small.header(expected);
      expected.write(_opDot, 4);
      _small.point(expected, 3, 4);
      expected.end();
      _expectExact(_doc(_small, <MCOImageV4Figure>[_dot(3, 4)]), expected);
    });

    test('LINE', () {
      // Deltas (6, 7) need 4-bit fields, so LINE_DELTA costs 28 bits to the
      // full form's 24; not axis-aligned, so no axis form is offered.
      final expected = _Bits();
      _small.header(expected);
      expected.write(_opLine, 4);
      _small.point(expected, 1, 2);
      _small.point(expected, 7, 9);
      expected.end();
      _expectExact(_doc(_small, <MCOImageV4Figure>[_line(1, 2, 7, 9)]), expected);
    });

    test('RECT with a free third corner', () {
      // A delta of 5 forces 4-bit deltas: AREA_DELTA 37 bits, RECT 34.
      final rect = MCOImageV4Rect(
        first: const MCOImageV4Point(2, 2),
        second: const MCOImageV4Point(9, 7),
        third: const MCOImageV4Point(8, 3),
        style: _ink,
      );
      final expected = _Bits();
      _small.header(expected);
      expected.write(_opRect, 4);
      _small.point(expected, 2, 2);
      _small.point(expected, 9, 7);
      _small.point(expected, 8, 3);
      expected.end();
      _expectExact(_doc(_small, <MCOImageV4Figure>[rect]), expected);
    });

    test('ELLIPSE with a free third point', () {
      final ellipse = MCOImageV4Ellipse(
        first: const MCOImageV4Point(2, 2),
        second: const MCOImageV4Point(9, 7),
        third: const MCOImageV4Point(8, 3),
        style: _ink,
      );
      final expected = _Bits();
      _small.header(expected);
      expected.write(_opEllipse, 4);
      _small.point(expected, 2, 2);
      _small.point(expected, 9, 7);
      _small.point(expected, 8, 3);
      expected.end();
      _expectExact(_doc(_small, <MCOImageV4Figure>[ellipse]), expected);
    });

    test('RECT_AXIS_ALIGNED, both corner choices', () {
      for (final swapped in const <bool>[false, true]) {
        final third = swapped
            ? const MCOImageV4Point(9, 2)
            : const MCOImageV4Point(2, 7);
        final rect = MCOImageV4Rect(
          first: const MCOImageV4Point(2, 2),
          second: const MCOImageV4Point(9, 7),
          third: third,
          style: _ink,
        );
        final expected = _Bits();
        _small.header(expected);
        expected.write(_opRectAxisAligned, 4);
        expected.bit(swapped);
        _small.point(expected, 2, 2);
        _small.point(expected, 9, 7);
        expected.end();
        _expectExact(_doc(_small, <MCOImageV4Figure>[rect]), expected);
      }
    });

    test('ELLIPSE_AXIS_ALIGNED', () {
      final ellipse = MCOImageV4Ellipse(
        first: const MCOImageV4Point(2, 2),
        second: const MCOImageV4Point(9, 7),
        third: const MCOImageV4Point(2, 7),
        style: _ink,
      );
      final expected = _Bits();
      _small.header(expected);
      expected.write(_opEllipseAxisAligned, 4);
      expected.bit(false);
      _small.point(expected, 2, 2);
      _small.point(expected, 9, 7);
      expected.end();
      _expectExact(_doc(_small, <MCOImageV4Figure>[ellipse]), expected);
    });

    test('WAVE, open with a positive depth and closed with a negative one', () {
      // Deltas (8, 4) need 5-bit fields: WAVE_DELTA 36 bits, WAVE 30.
      for (final (depth, closed) in const <(int, bool)>[(3, false), (-2, true)]) {
        final wave = MCOImageV4Wave(
          start: const MCOImageV4Point(2, 2),
          end: const MCOImageV4Point(10, 6),
          depth: depth,
          closed: closed,
          style: _ink,
        );
        final expected = _Bits();
        _small.header(expected);
        expected.write(_opWave, 4);
        expected.bit(closed);
        _small.point(expected, 2, 2);
        _small.point(expected, 10, 6);
        expected.bit(depth < 0);
        _small.scalar(expected, depth.abs());
        expected.end();
        _expectExact(_doc(_small, <MCOImageV4Figure>[wave]), expected);
      }
    });

    test('duplicate area control points are rejected', () {
      final stream = _Bits();
      _small.header(stream);
      stream.write(_opRect, 4);
      _small.point(stream, 2, 2);
      _small.point(stream, 2, 2);
      _small.point(stream, 5, 5);
      stream.end();
      expect(() => _decode(stream), _damaged);
    });

    test('a dot without a stroke color is rejected', () {
      final stream = _Bits();
      _small.header(stream);
      stream.write(_opSetStroke, 4);
      _small.color(stream, null);
      stream.write(_opDot, 4);
      _small.point(stream, 2, 2);
      stream.end();
      expect(() => _decode(stream), _damaged);
    });

    test('a wave depth above the canvas is rejected', () {
      const canvas = _Canvas(20, 10);
      final stream = _Bits();
      canvas.header(stream);
      stream.write(_opWave, 4);
      stream.bit(false);
      canvas.point(stream, 1, 1);
      canvas.point(stream, 9, 3);
      stream.bit(false);
      canvas.scalar(stream, 25);
      stream.end();
      expect(() => _decode(stream), _damaged);
    });

    test('the encoder refuses a wave of depth zero', () {
      final wave = MCOImageV4Wave(
        start: const MCOImageV4Point(2, 2),
        end: const MCOImageV4Point(10, 6),
        depth: 0,
        closed: false,
        style: _ink,
      );
      expect(() => _codec.encode(_doc(_small, <MCOImageV4Figure>[wave])), _badInput);
    });
  });

  group('alternate figure forms', () {
    test('LINE_DELTA', () {
      final stream = _Bits();
      _small.header(stream);
      _ext(stream, _extLineDelta);
      stream.write(0, 2); // 3-bit deltas
      _small.point(stream, 2, 2);
      stream.zz(3, 3);
      stream.zz(-2, 3);
      stream.end();
      expect(_documentText(_decode(stream)), <String>[
        'line (2,2) (5,0) fill=- stroke=$_black width=1',
      ]);
    });

    test('LINE_DELTA wins on a large canvas', () {
      // 16-bit points: LINE 36 bits, LINE_DELTA with 3-bit deltas 32.
      final expected = _Bits();
      _large.header(expected);
      _ext(expected, _extLineDelta);
      expected.write(0, 2);
      _large.point(expected, 10, 10);
      expected.zz(3, 3);
      expected.zz(2, 3);
      expected.end();
      _expectExact(_doc(_large, <MCOImageV4Figure>[_line(10, 10, 13, 12)]), expected);
    });

    test('LINE_AXIS_ABSOLUTE, vertical and horizontal', () {
      final vertical = _Bits();
      _small.header(vertical);
      _ext(vertical, _extLineAxisAbsolute);
      vertical.bit(true);
      _small.x(vertical, 2);
      _small.y(vertical, 1);
      _small.y(vertical, 9);
      vertical.end();
      expect(_documentText(_decode(vertical)), <String>[
        'line (2,1) (2,9) fill=- stroke=$_black width=1',
      ]);

      final horizontal = _Bits();
      _small.header(horizontal);
      _ext(horizontal, _extLineAxisAbsolute);
      horizontal.bit(false);
      _small.y(horizontal, 3);
      _small.x(horizontal, 1);
      _small.x(horizontal, 9);
      horizontal.end();
      expect(_documentText(_decode(horizontal)), <String>[
        'line (1,3) (9,3) fill=- stroke=$_black width=1',
      ]);
    });

    test('LINE_AXIS_DELTA', () {
      final stream = _Bits();
      _small.header(stream);
      _ext(stream, _extLineAxisDelta);
      stream.bit(true); // vertical
      stream.write(1, 2); // 4-bit delta
      _small.point(stream, 2, 1);
      stream.zz(6, 4);
      stream.end();
      expect(_documentText(_decode(stream)), <String>[
        'line (2,1) (2,7) fill=- stroke=$_black width=1',
      ]);
    });

    test('AREA_DELTA, rectangle and ellipse', () {
      for (final ellipse in const <bool>[false, true]) {
        final stream = _Bits();
        _small.header(stream);
        _ext(stream, _extAreaDelta);
        stream.bit(ellipse);
        stream.write(0, 2);
        _small.point(stream, 2, 2);
        stream.zz(3, 3);
        stream.zz(0, 3);
        stream.zz(0, 3);
        stream.zz(3, 3);
        stream.end();
        expect(_documentText(_decode(stream)), <String>[
          '${ellipse ? 'ellipse' : 'rect'} (2,2) (5,2) (5,5) '
              'fill=- stroke=$_black width=1',
        ]);
      }
    });

    test('AREA_DELTA wins for a small rectangle', () {
      // AREA_DELTA with 3-bit deltas is 33 bits, the three-point RECT 34.
      final rect = MCOImageV4Rect(
        first: const MCOImageV4Point(2, 2),
        second: const MCOImageV4Point(5, 4),
        third: const MCOImageV4Point(4, 1),
        style: _ink,
      );
      final expected = _Bits();
      _small.header(expected);
      _ext(expected, _extAreaDelta);
      expected.bit(false);
      expected.write(0, 2);
      _small.point(expected, 2, 2);
      expected.zz(3, 3);
      expected.zz(2, 3);
      expected.zz(-1, 3);
      expected.zz(-3, 3);
      expected.end();
      _expectExact(_doc(_small, <MCOImageV4Figure>[rect]), expected);
    });

    test('WAVE_DELTA', () {
      final stream = _Bits();
      _small.header(stream);
      _ext(stream, _extWaveDelta);
      stream.bit(true); // closed
      stream.bit(true); // negative
      _small.scalar(stream, 3);
      stream.write(0, 2);
      _small.point(stream, 2, 2);
      stream.zz(3, 3);
      stream.zz(1, 3);
      stream.end();
      expect(_documentText(_decode(stream)), <String>[
        'wave closed (2,2) (5,3) depth=-3 fill=- stroke=$_black width=1',
      ]);
    });

    test('ELLIPSE_DEPTH', () {
      // Axis (2,4)-(10,4): the normal is (0, 1), so depth 3 puts the third
      // point at (6, 7). 33 bits against 34 for the three-point form.
      final ellipse = MCOImageV4Ellipse(
        first: const MCOImageV4Point(2, 4),
        second: const MCOImageV4Point(10, 4),
        third: const MCOImageV4Point(6, 7),
        style: _ink,
      );
      final expected = _Bits();
      _small.header(expected);
      _ext(expected, _extEllipseDepth);
      _small.point(expected, 2, 4);
      _small.point(expected, 10, 4);
      expected.bit(false);
      _small.scalar(expected, 3);
      expected.end();
      _expectExact(_doc(_small, <MCOImageV4Figure>[ellipse]), expected);
    });

    test('ELLIPSE_DEPTH on the other side of the axis', () {
      final stream = _Bits();
      _small.header(stream);
      _ext(stream, _extEllipseDepth);
      _small.point(stream, 2, 4);
      _small.point(stream, 10, 4);
      stream.bit(true);
      _small.scalar(stream, 2);
      stream.end();
      expect(_documentText(_decode(stream)), <String>[
        'ellipse (2,4) (10,4) (6,2) fill=- stroke=$_black width=1',
      ]);
    });

    test('an ellipse depth off the integer grid is rejected', () {
      // Axis (0,0)-(3,0) has its midpoint at x = 1.5.
      final stream = _Bits();
      _small.header(stream);
      _ext(stream, _extEllipseDepth);
      _small.point(stream, 0, 0);
      _small.point(stream, 3, 0);
      stream.bit(false);
      _small.scalar(stream, 1);
      stream.end();
      expect(() => _decode(stream), _damaged);
    });

    test('DOT_RUN with deltas', () {
      // Three diagonal dots: 36 bits as a run, 38 as a dot and two repeats.
      final document = _doc(_small, <MCOImageV4Figure>[
        _dot(2, 2),
        _dot(3, 3),
        _dot(4, 4),
      ]);
      final expected = _Bits();
      _small.header(expected);
      _ext(expected, _extDotRun);
      expected.bit(true);
      expected.write(0, 2);
      expected.compact(1);
      _small.point(expected, 2, 2);
      expected.zz(1, 3);
      expected.zz(1, 3);
      expected.zz(1, 3);
      expected.zz(1, 3);
      expected.end();
      _expectExact(document, expected);
    });

    test('DOT_RUN with absolute points', () {
      // Four dots whose steps need 5-bit deltas: 54 bits as a delta run, 56
      // as four plain dots (a repeat costs 16 there), 52 absolute. Three dots
      // would tie the run with three plain dots, and a tie keeps the dots.
      final document = _doc(_small, <MCOImageV4Figure>[
        _dot(2, 2),
        _dot(12, 3),
        _dot(3, 12),
        _dot(13, 13),
      ]);
      final expected = _Bits();
      _small.header(expected);
      _ext(expected, _extDotRun);
      expected.bit(false);
      expected.compact(2);
      _small.point(expected, 2, 2);
      _small.point(expected, 12, 3);
      _small.point(expected, 3, 12);
      _small.point(expected, 13, 13);
      expected.end();
      _expectExact(document, expected);
    });

    test('a coordinate rebuilt from a delta must stay in range', () {
      final stream = _Bits();
      _small.header(stream);
      _ext(stream, _extLineDelta);
      stream.write(0, 2);
      _small.point(stream, 15, 15);
      stream.zz(3, 3); // 18 is past the margin of 2
      stream.zz(0, 3);
      stream.end();
      expect(() => _decode(stream), _damaged);
    });
  });

  group('paths', () {
    test('PATH_ABSOLUTE', () {
      final stream = _Bits();
      _small.header(stream);
      stream.write(_opPathAbsolute, 4);
      stream.bit(true);
      stream.compact(1); // four points, minimum three when closed
      _small.point(stream, 1, 1);
      _small.point(stream, 6, 1);
      _small.point(stream, 6, 6);
      _small.point(stream, 1, 6);
      stream.end();
      expect(_documentText(_decode(stream)), <String>[
        'path closed (1,1) (6,1) (6,6) (1,6) fill=- stroke=$_black width=1',
      ]);
    });

    test('PATH_DELTA with the per-component escape', () {
      final stream = _Bits();
      _small.header(stream);
      stream.write(_opPathDelta, 4);
      stream.bit(false);
      stream.write(0, 2);
      stream.compact(1); // three points
      _small.point(stream, 1, 1);
      stream.bit(false);
      stream.zz(1, 3);
      stream.bit(false);
      stream.zz(1, 3);
      stream.bit(true); // a jump of 10 does not fit: absolute x
      _small.x(stream, 12);
      stream.bit(false);
      stream.zz(0, 3);
      stream.end();
      expect(_documentText(_decode(stream)), <String>[
        'path open (1,1) (2,2) (12,2) fill=- stroke=$_black width=1',
      ]);
    });

    test('PATH_ORTHOGONAL', () {
      // An L on the small canvas: 32 bits orthogonal, 36 delta, 38 absolute.
      final expected = _Bits();
      _small.header(expected);
      _ext(expected, _extPathOrthogonal);
      expected.bit(false);
      expected.write(0, 2);
      expected.compact(1);
      _small.point(expected, 1, 1);
      expected.bit(false); // horizontal
      expected.zz(3, 3);
      expected.bit(true); // vertical
      expected.zz(3, 3);
      expected.end();
      _expectExact(
        _doc(_small, <MCOImageV4Figure>[
          _path(const <(int, int)>[(1, 1), (4, 1), (4, 4)]),
        ]),
        expected,
      );
    });

    test('PATH_ORTHOGONAL closed', () {
      final stream = _Bits();
      _small.header(stream);
      _ext(stream, _extPathOrthogonal);
      stream.bit(true);
      stream.write(0, 2);
      stream.compact(1); // four points
      _small.point(stream, 1, 1);
      stream.bit(false);
      stream.zz(3, 3);
      stream.bit(true);
      stream.zz(3, 3);
      stream.bit(false);
      stream.zz(-3, 3);
      stream.end();
      expect(_documentText(_decode(stream)), <String>[
        'path closed (1,1) (4,1) (4,4) (1,4) fill=- stroke=$_black width=1',
      ]);
    });

    test('PATH_BOUNDS', () {
      final stream = _Bits();
      _small.header(stream);
      _ext(stream, _extPathBounds);
      stream.bit(true);
      stream.compact(1); // four points
      _small.point(stream, 3, 3); // origin
      stream.write(4, _small.xBits); // bounds width 5: local x in 3 bits
      stream.write(2, _small.yBits); // bounds height 3: local y in 2 bits
      for (final (x, y) in const <(int, int)>[(0, 0), (4, 0), (4, 2), (0, 2)]) {
        stream.write(x, 3);
        stream.write(y, 2);
      }
      stream.end();
      expect(_documentText(_decode(stream)), <String>[
        'path closed (3,3) (7,3) (7,5) (3,5) fill=- stroke=$_black width=1',
      ]);
    });

    test('PATH_BOUNDS_DELTA', () {
      final stream = _Bits();
      _small.header(stream);
      _ext(stream, _extPathBoundsDelta);
      stream.bit(false);
      stream.write(1, 2); // 4-bit deltas: a step of 4 needs them
      stream.compact(1); // three points
      _small.point(stream, 3, 3);
      stream.write(4, _small.xBits);
      stream.write(2, _small.yBits);
      stream.write(0, 3);
      stream.write(0, 2);
      stream.zz(4, 4);
      stream.zz(0, 4);
      stream.zz(0, 4);
      stream.zz(2, 4);
      stream.end();
      expect(_documentText(_decode(stream)), <String>[
        'path open (3,3) (7,3) (7,5) fill=- stroke=$_black width=1',
      ]);
    });

    test('a bounds box past the coordinate range is rejected', () {
      final stream = _Bits();
      _small.header(stream);
      _ext(stream, _extPathBounds);
      stream.bit(false);
      stream.compact(0);
      _small.point(stream, 14, 14);
      stream.write(7, _small.xBits); // 14 + 7 = 21, past the margin
      stream.write(1, _small.yBits);
      stream.write(0, 3);
      stream.write(0, 1);
      stream.write(1, 3);
      stream.write(1, 1);
      stream.end();
      expect(() => _decode(stream), _damaged);
    });

    test('a local offset outside the bounds box is rejected', () {
      final stream = _Bits();
      _small.header(stream);
      _ext(stream, _extPathBounds);
      stream.bit(false);
      stream.compact(0);
      _small.point(stream, 3, 3);
      stream.write(4, _small.xBits); // width 5, local x in 3 bits
      stream.write(0, _small.yBits); // height 1, local y in 1 bit
      stream.write(0, 3);
      stream.write(0, 1);
      stream.write(5, 3); // 5 is not below the width
      stream.write(0, 1);
      stream.end();
      expect(() => _decode(stream), _damaged);
    });

    test('bitCompactUint reaches every form through the point count', () {
      // n - min of 4 (10 + 4 bits), 20 (110 + 8 bits) and 276 (111 + varuint).
      for (final extra in const <int>[4, 20, 276]) {
        final count = extra + 2;
        final stream = _Bits();
        _small.header(stream);
        stream.write(_opPathAbsolute, 4);
        stream.bit(false);
        stream.compact(extra);
        for (var i = 0; i < count; i++) {
          _small.point(stream, i % 16, (i ~/ 16) % 16);
        }
        stream.end();
        final path = _decode(stream).figures.single as MCOImageV4Path;
        expect(path.points.length, count, reason: '$extra');
      }
    });

    test('non-canonical bitCompactUint and bitVarUint7 are rejected', () {
      void reject(void Function(_Bits b) count) {
        final stream = _Bits();
        _small.header(stream);
        stream.write(_opPathAbsolute, 4);
        stream.bit(false);
        count(stream);
        stream.end();
        expect(() => _decode(stream), _damaged);
      }

      reject((b) {
        b.write(7, 3); // 111 form for a value the 8-bit form holds
        b.varUint7(275);
      });
      reject((b) {
        b.write(7, 3); // a leading zero group
        b.bytes(const <int>[0x80, 0x00]);
      });
      reject((b) {
        b.write(7, 3); // a sixth byte
        b.bytes(const <int>[0x80, 0x80, 0x80, 0x80, 0x80, 0x01]);
      });
    });

    test('a point count the stream cannot hold is rejected', () {
      final stream = _Bits();
      _small.header(stream);
      stream.write(_opPathAbsolute, 4);
      stream.bit(false);
      stream.compact(300);
      _small.point(stream, 1, 1);
      stream.end();
      expect(() => _decode(stream), _damaged);
    });

    test('the encoder refuses paths with too few points', () {
      expect(
        () => _codec.encode(
          _doc(_small, <MCOImageV4Figure>[_path(const <(int, int)>[(1, 1)])]),
        ),
        _badInput,
      );
      expect(
        () => _codec.encode(
          _doc(_small, <MCOImageV4Figure>[
            _path(const <(int, int)>[(1, 1), (4, 4)], closed: true),
          ]),
        ),
        _badInput,
      );
    });
  });

  group('repeats', () {
    test('REPEAT_SHORT follows a dot', () {
      // Two dots one cell apart: 26 bits as DOT + REPEAT_SHORT, 30 as a run.
      final expected = _Bits();
      _small.header(expected);
      expected.write(_opDot, 4);
      _small.point(expected, 2, 2);
      expected.write(_opRepeatShort, 4);
      expected.write(0, 2);
      expected.zz(1, 3);
      expected.zz(0, 3);
      expected.end();
      _expectExact(_doc(_small, <MCOImageV4Figure>[_dot(2, 2), _dot(3, 2)]), expected);
    });

    test('REPEAT_LAST carries an offset too wide for the short form', () {
      // The L path costs 40 bits orthogonal; a shift of 40 cells does not fit
      // six bits, so the repeat is REPEAT_LAST at 22 bits.
      final expected = _Bits();
      _large.header(expected);
      _ext(expected, _extPathOrthogonal);
      expected.bit(false);
      expected.write(1, 2); // 4-bit deltas
      expected.compact(1);
      _large.point(expected, 0, 0);
      expected.bit(false);
      expected.zz(5, 4);
      expected.bit(true);
      expected.zz(5, 4);
      expected.write(_opRepeatLast, 4);
      expected.zz(40, _large.xBits + 1);
      expected.zz(0, _large.yBits + 1);
      expected.end();
      _expectExact(
        _doc(_large, <MCOImageV4Figure>[
          _path(const <(int, int)>[(0, 0), (5, 0), (5, 5)]),
          _path(const <(int, int)>[(40, 0), (45, 0), (45, 5)]),
        ]),
        expected,
      );
    });

    test('REPEAT_LAST decodes against the last figure', () {
      final stream = _Bits();
      _small.header(stream);
      stream.write(_opDot, 4);
      _small.point(stream, 2, 2);
      stream.write(_opRepeatLast, 4);
      stream.zz(3, _small.xBits + 1);
      stream.zz(-1, _small.yBits + 1);
      stream.end();
      expect(_documentText(_decode(stream)), <String>[
        'dot (2,2) fill=- stroke=$_black width=1',
        'dot (5,1) fill=- stroke=$_black width=1',
      ]);
    });

    test('REPEAT_BACK reaches past an intervening figure', () {
      // Path, dot, the path shifted by (1,1): the repeat two places back costs
      // 20 bits against 32 for the path itself.
      final expected = _Bits();
      _small.header(expected);
      _ext(expected, _extPathOrthogonal);
      expected.bit(false);
      expected.write(0, 2);
      expected.compact(1);
      _small.point(expected, 1, 1);
      expected.bit(false);
      expected.zz(3, 3);
      expected.bit(true);
      expected.zz(3, 3);
      expected.write(_opDot, 4);
      _small.point(expected, 10, 10);
      _ext(expected, _extRepeatBack);
      expected.write(1, 3); // distance 2
      expected.bit(true);
      expected.write(0, 2);
      expected.zz(1, 3);
      expected.zz(1, 3);
      expected.end();
      _expectExact(
        _doc(_small, <MCOImageV4Figure>[
          _path(const <(int, int)>[(1, 1), (4, 1), (4, 4)]),
          _dot(10, 10),
          _path(const <(int, int)>[(2, 2), (5, 2), (5, 5)]),
        ]),
        expected,
      );
    });

    test('REPEAT_BACK with a full-width offset', () {
      final stream = _Bits();
      _small.header(stream);
      stream.write(_opDot, 4);
      _small.point(stream, 2, 2);
      stream.write(_opDot, 4);
      _small.point(stream, 9, 9);
      _ext(stream, _extRepeatBack);
      stream.write(1, 3);
      stream.bit(false);
      stream.zz(1, _small.xBits + 1);
      stream.zz(1, _small.yBits + 1);
      stream.end();
      expect(_documentText(_decode(stream)).last, 'dot (3,3) fill=- stroke=$_black width=1');
    });

    test('a repeated figure takes the current style', () {
      final stream = _Bits();
      _small.header(stream);
      stream.write(_opDot, 4);
      _small.point(stream, 2, 2);
      stream.write(_opSetStroke, 4);
      _small.color(stream, _colorA);
      stream.write(_opRepeatShort, 4);
      stream.write(0, 2);
      stream.zz(1, 3);
      stream.zz(1, 3);
      stream.end();
      expect(_documentText(_decode(stream)), <String>[
        'dot (2,2) fill=- stroke=$_black width=1',
        'dot (3,3) fill=- stroke=$_colorA width=1',
      ]);
    });

    test('REPEAT_COLOR_RUN over strokes', () {
      // A line and three copies stepping by (1,1) in three stroke colors: the
      // run costs 30 bits, three SET_STROKE + REPEAT_SHORT pairs 52.
      MCOImageV4Style stroke(int local) => MCOImageV4Style(strokeColor: local);
      final document = _doc(_small, <MCOImageV4Figure>[
        _line(1, 1, 6, 4),
        _line(2, 2, 7, 5, style: stroke(_localA)),
        _line(3, 3, 8, 6, style: stroke(_localB)),
        _line(4, 4, 9, 7, style: stroke(_localC)),
      ]);
      final expected = _Bits();
      _small.header(expected);
      expected.write(_opLine, 4);
      _small.point(expected, 1, 1);
      _small.point(expected, 6, 4);
      expected.write(_opSetStroke, 4);
      _small.color(expected, _colorA);
      _ext(expected, _extRepeatColorRun);
      expected.bit(true); // stroke run
      expected.bit(true); // short offset
      expected.write(0, 2);
      expected.zz(1, 3);
      expected.zz(1, 3);
      expected.compact(1); // three repeats
      expected.bit(true); // colors follow for the second and third
      _small.color(expected, _colorB);
      _small.color(expected, _colorC);
      expected.end();
      _expectExact(document, expected);
    });

    test('REPEAT_COLOR_RUN over fills, and what it leaves as current style', () {
      final stream = _Bits();
      _small.header(stream);
      stream.write(_opLine, 4);
      _small.point(stream, 1, 1);
      _small.point(stream, 4, 1);
      _ext(stream, _extRepeatColorRun);
      stream.bit(false); // fill run
      stream.bit(false); // full-width offset
      stream.zz(0, _small.xBits + 1);
      stream.zz(2, _small.yBits + 1);
      stream.compact(0); // two repeats
      stream.bit(true);
      _small.color(stream, _colorC); // the second repeat only
      stream.write(_opDot, 4);
      _small.point(stream, 9, 9);
      stream.end();
      expect(_documentText(_decode(stream)), <String>[
        'line (1,1) (4,1) fill=- stroke=$_black width=1',
        'line (1,3) (4,3) fill=- stroke=$_black width=1',
        'line (1,5) (4,5) fill=$_colorC stroke=$_black width=1',
        'dot (9,9) fill=$_colorC stroke=$_black width=1',
      ]);
    });

    test('REPEAT_COLOR_RUN without color changes', () {
      final stream = _Bits();
      _small.header(stream);
      stream.write(_opDot, 4);
      _small.point(stream, 1, 1);
      _ext(stream, _extRepeatColorRun);
      stream.bit(true);
      stream.bit(true);
      stream.write(0, 2);
      stream.zz(2, 3);
      stream.zz(0, 3);
      stream.compact(1);
      stream.bit(false);
      stream.end();
      expect(_documentText(_decode(stream)), <String>[
        'dot (1,1) fill=- stroke=$_black width=1',
        'dot (3,1) fill=- stroke=$_black width=1',
        'dot (5,1) fill=- stroke=$_black width=1',
        'dot (7,1) fill=- stroke=$_black width=1',
      ]);
    });

    test('a repeat with nothing to repeat is rejected', () {
      final last = _Bits();
      _small.header(last);
      last.write(_opRepeatLast, 4);
      last.zz(1, _small.xBits + 1);
      last.zz(1, _small.yBits + 1);
      last.end();
      expect(() => _decode(last), _damaged);

      final run = _Bits();
      _small.header(run);
      _ext(run, _extRepeatColorRun);
      run.bit(true);
      run.bit(true);
      run.write(0, 2);
      run.zz(1, 3);
      run.zz(1, 3);
      run.compact(0);
      run.bit(false);
      run.end();
      expect(() => _decode(run), _damaged);
    });

    test('REPEAT_BACK needs a distance of at least 2 within the history', () {
      void reject(int distanceMinus1, int dots) {
        final stream = _Bits();
        _small.header(stream);
        for (var i = 0; i < dots; i++) {
          stream.write(_opDot, 4);
          _small.point(stream, 2 + i, 2);
        }
        _ext(stream, _extRepeatBack);
        stream.write(distanceMinus1, 3);
        stream.bit(true);
        stream.write(0, 2);
        stream.zz(1, 3);
        stream.zz(1, 3);
        stream.end();
        expect(() => _decode(stream), _damaged);
      }

      reject(0, 2); // distance 1 is REPEAT_LAST's job
      reject(2, 2); // distance 3 with two figures behind
    });

    test('a repeat that leaves the coordinate range is rejected', () {
      final stream = _Bits();
      _small.header(stream);
      stream.write(_opDot, 4);
      _small.point(stream, 15, 15);
      stream.write(_opRepeatShort, 4);
      stream.write(0, 2);
      stream.zz(3, 3);
      stream.zz(3, 3);
      stream.end();
      expect(() => _decode(stream), _damaged);
    });
  });

  group('groups', () {
    test('GROUP of two dots', () {
      // No style change ahead of the group, since its first figure already
      // has the current style; inside, the second dot is a REPEAT_SHORT.
      final expected = _Bits();
      _small.header(expected);
      _ext(expected, _extGroup);
      expected.compact(1);
      expected.write(_opDot, 4);
      _small.point(expected, 2, 2);
      expected.write(_opRepeatShort, 4);
      expected.write(0, 2);
      expected.zz(1, 3);
      expected.zz(0, 3);
      expected.end();
      _expectExact(
        _doc(_small, <MCOImageV4Figure>[
          MCOImageV4Group(figures: <MCOImageV4Figure>[_dot(2, 2), _dot(3, 2)]),
        ]),
        expected,
      );
    });

    test('a group takes the style of its first figure ahead of GROUP', () {
      final colored = MCOImageV4Style(strokeColor: _localA);
      final expected = _Bits();
      _small.header(expected);
      expected.write(_opSetStroke, 4);
      _small.color(expected, _colorA);
      _ext(expected, _extGroup);
      expected.compact(0);
      expected.write(_opDot, 4);
      _small.point(expected, 2, 2);
      // The figure after the group continues from the same style.
      expected.write(_opDot, 4);
      _small.point(expected, 12, 12);
      expected.end();
      _expectExact(
        _doc(_small, <MCOImageV4Figure>[
          MCOImageV4Group(figures: <MCOImageV4Figure>[_dot(2, 2, style: colored)]),
          _dot(12, 12, style: colored),
        ]),
        expected,
      );
    });

    test('nested style changes are discarded when the group ends', () {
      final stream = _Bits();
      _small.header(stream);
      stream.write(_opDot, 4);
      _small.point(stream, 2, 2);
      _ext(stream, _extGroup);
      stream.compact(0);
      stream.write(_opSetStroke, 4);
      _small.color(stream, _colorA);
      stream.write(_opDot, 4);
      _small.point(stream, 5, 5);
      stream.write(_opDot, 4);
      _small.point(stream, 9, 9);
      stream.end();
      expect(_documentText(_decode(stream)), <String>[
        'dot (2,2) fill=- stroke=$_black width=1',
        'group[dot (5,5) fill=- stroke=$_colorA width=1]',
        'dot (9,9) fill=- stroke=$_black width=1',
      ]);
    });

    test('groups nest, and a nested group counts as one figure', () {
      final stream = _Bits();
      _small.header(stream);
      _ext(stream, _extGroup);
      stream.compact(0); // one figure: the inner group
      _ext(stream, _extGroup);
      stream.compact(1); // two dots
      stream.write(_opDot, 4);
      _small.point(stream, 2, 2);
      stream.write(_opDot, 4);
      _small.point(stream, 9, 9);
      stream.end();
      expect(_documentText(_decode(stream)), <String>[
        'group[group[dot (2,2) fill=- stroke=$_black width=1; '
            'dot (9,9) fill=- stroke=$_black width=1]]',
      ]);
    });

    test('a nested history starts empty and a run counts every figure', () {
      final stream = _Bits();
      _small.header(stream);
      stream.write(_opDot, 4);
      _small.point(stream, 1, 1);
      _ext(stream, _extGroup);
      stream.compact(1); // two figures
      stream.write(_opDot, 4);
      _small.point(stream, 5, 5);
      stream.write(_opRepeatShort, 4); // repeats the nested dot, not (1,1)
      stream.write(0, 2);
      stream.zz(1, 3);
      stream.zz(1, 3);
      stream.end();
      expect(_documentText(_decode(stream)), <String>[
        'dot (1,1) fill=- stroke=$_black width=1',
        'group[dot (5,5) fill=- stroke=$_black width=1; '
            'dot (6,6) fill=- stroke=$_black width=1]',
      ]);
      _expectRoundTrip(
        _doc(_small, <MCOImageV4Figure>[
          MCOImageV4Group(figures: <MCOImageV4Figure>[
            MCOImageV4Group(figures: <MCOImageV4Figure>[_dot(2, 2), _dot(9, 9)]),
            _line(1, 1, 6, 4),
          ]),
          _dot(14, 14),
        ]),
      );
    });

    test('END inside a group is rejected', () {
      final stream = _Bits();
      _small.header(stream);
      _ext(stream, _extGroup);
      stream.compact(0);
      stream.end();
      stream.end();
      expect(() => _decode(stream), _damaged);
    });

    test('a group yielding more figures than declared is rejected', () {
      final stream = _Bits();
      _small.header(stream);
      _ext(stream, _extGroup);
      stream.compact(0); // one figure declared
      _ext(stream, _extDotRun); // two produced at once
      stream.bit(false);
      stream.compact(0);
      _small.point(stream, 2, 2);
      _small.point(stream, 5, 5);
      stream.end();
      expect(() => _decode(stream), _damaged);
    });

    test('the encoder refuses an empty group', () {
      expect(
        () => _codec.encode(
          _doc(_small, <MCOImageV4Figure>[
            MCOImageV4Group(figures: const <MCOImageV4Figure>[]),
          ]),
        ),
        _badInput,
      );
    });
  });

  group('raster layers', () {
    final image = MCOImage(
      width: 2,
      height: 2,
      paletteProfile: PaletteProfile.master8,
      pixels: const <int>[_white, _black, _black, _white],
      encodingVersion: MCOImageEncodingVersion.v3,
    );
    // The layer's v3 body without its packet nonce, as the encoder builds it.
    final v3Body = MCOImageV3Codec().encode(image, includePacketNonce: false).body;

    MCOImageV4RasterLayer layer() => MCOImageV4RasterLayer(
      x: 1,
      y: 1,
      width: 2,
      height: 2,
      pixels: const <int>[_white, _black, _black, _white],
    );

    test('RASTER_LAYER in a mixed document', () {
      final expected = _Bits();
      _small.header(expected, mode: 1);
      _ext(expected, _extRasterLayer);
      _small.point(expected, 1, 1);
      expected.write(v3Body[0] >> 4, 4);
      expected.compact(v3Body.length - 1);
      expected.bytes(v3Body.sublist(1));
      expected.write(_opDot, 4);
      _small.point(expected, 10, 10);
      expected.end();
      final document = _doc(_small, <MCOImageV4Figure>[layer(), _dot(10, 10)]);
      _expectExact(document, expected);
      expect(_codec.decodeBody(_codec.encode(document, nonce: 0).body).document.mode,
          MCOImageV4Mode.mixed);
    });

    test('a raster layer is not repeat history', () {
      // REPEAT_LAST right after the layer has no figure to repeat.
      final stream = _Bits();
      _small.header(stream, mode: 1);
      _ext(stream, _extRasterLayer);
      _small.point(stream, 1, 1);
      stream.write(v3Body[0] >> 4, 4);
      stream.compact(v3Body.length - 1);
      stream.bytes(v3Body.sublist(1));
      stream.write(_opRepeatLast, 4);
      stream.zz(1, _small.xBits + 1);
      stream.zz(1, _small.yBits + 1);
      stream.end();
      expect(() => _decode(stream), _damaged);
    });

    test('a raster layer in a vector document is rejected', () {
      final stream = _Bits();
      _small.header(stream);
      _ext(stream, _extRasterLayer);
      _small.point(stream, 1, 1);
      stream.write(v3Body[0] >> 4, 4);
      stream.compact(v3Body.length - 1);
      stream.bytes(v3Body.sublist(1));
      stream.end();
      expect(() => _decode(stream), _damaged);
    });

    test('a raster layer inside a group is rejected', () {
      final stream = _Bits();
      _small.header(stream, mode: 1);
      _ext(stream, _extGroup);
      stream.compact(0);
      _ext(stream, _extRasterLayer);
      _small.point(stream, 1, 1);
      stream.write(v3Body[0] >> 4, 4);
      stream.compact(v3Body.length - 1);
      stream.bytes(v3Body.sublist(1));
      stream.end();
      expect(() => _decode(stream), _damaged);
    });

    test('a raster payload shorter than two bytes is rejected', () {
      final stream = _Bits();
      _small.header(stream, mode: 1);
      _ext(stream, _extRasterLayer);
      _small.point(stream, 1, 1);
      stream.write(0, 4);
      stream.compact(1);
      stream.bytes(const <int>[0]);
      stream.end();
      expect(() => _decode(stream), _damaged);
    });

    test('the encoder refuses a raster layer inside a group', () {
      expect(
        () => _codec.encode(
          _doc(_small, <MCOImageV4Figure>[
            MCOImageV4Group(figures: <MCOImageV4Figure>[layer()]),
          ]),
        ),
        _badInput,
      );
    });

    test('the encoder refuses the reserved raster mode', () {
      expect(
        () => _codec.encode(
          _doc(_small, <MCOImageV4Figure>[layer()], mode: MCOImageV4Mode.raster),
        ),
        _badInput,
      );
    });
  });

  group('text', () {
    test('TEXT with every sticky field at its default', () {
      final encodedText = MCOtxtCodec.encode(
        'Hi',
        options: const MCOtxtEncodeOptions(collectStats: false),
      );
      final expected = _Bits();
      _large.header(expected);
      _ext(expected, _extEscape);
      expected.write(_ext2Text, 4);
      _large.point(expected, 8, 8);
      expected.write(0, 3); // default width, alignment and size
      expected.compact(encodedText.bitLength);
      expected.mcotxt(encodedText.data, encodedText.bitLength);
      expected.end();
      _expectExact(
        _doc(_large, <MCOImageV4Figure>[
          MCOImageV4Text(
            origin: const MCOImageV4Point(8, 8),
            fontSize: MCOImageV4Text.defaultFontSizeFor(128),
            align: MCOImageV4TextAlign.left,
            text: 'Hi',
            style: _ink,
          ),
        ]),
        expected,
      );
    });

    test('a reserved second-escape command is unsupported, not damage', () {
      final stream = _Bits();
      _small.header(stream);
      _ext(stream, _extEscape);
      stream.write(1, 4);
      stream.end();
      expect(() => _decode(stream), _unsupported);
    });

    test('an alignment of 3 is rejected', () {
      final encodedText = MCOtxtCodec.encode('a');
      final stream = _Bits();
      _large.header(stream);
      _ext(stream, _extEscape);
      stream.write(_ext2Text, 4);
      _large.point(stream, 8, 8);
      stream.write(0x02, 3);
      stream.write(3, 2);
      stream.compact(encodedText.bitLength);
      stream.mcotxt(encodedText.data, encodedText.bitLength);
      stream.end();
      expect(() => _decode(stream), _damaged);
    });

    test('an area width past the canvas and a font size past it are rejected', () {
      final encodedText = MCOtxtCodec.encode('a');
      const canvas = _Canvas(20, 10); // xBits 5 reaches 32, scalarBits 5 too
      void reject(void Function(_Bits b) fields, int mask) {
        final stream = _Bits();
        canvas.header(stream);
        _ext(stream, _extEscape);
        stream.write(_ext2Text, 4);
        canvas.point(stream, 1, 1);
        stream.write(mask, 3);
        fields(stream);
        stream.compact(encodedText.bitLength);
        stream.mcotxt(encodedText.data, encodedText.bitLength);
        stream.end();
        expect(() => _decode(stream), _damaged);
      }

      reject((b) => b.write(24, canvas.xBits), 0x01); // width 25 on 20 cells
      reject((b) => canvas.scalar(b, 25), 0x04); // font 25 on max 20
    });

    test('an MCOtxt stream of a version this build lacks is unsupported', () {
      // Header fields are 3 bits each, most significant bit first: version 2,
      // generation 0, language A 0, language B 7.
      final foreign = Uint8List.fromList(const <int>[0x40, 0x70]);
      final stream = _Bits();
      _large.header(stream);
      _ext(stream, _extEscape);
      stream.write(_ext2Text, 4);
      _large.point(stream, 8, 8);
      stream.write(0, 3);
      stream.compact(12);
      stream.mcotxt(foreign, 12);
      stream.end();
      expect(() => _decode(stream), _unsupported);
    });
  });

  group('coordinates, padding and truncation', () {
    test('a spare coordinate code is rejected', () {
      // 16 cells with a margin of 2 give 20 codes in a 5-bit field.
      final stream = _Bits();
      _small.header(stream);
      stream.write(_opDot, 4);
      stream.write(25, _small.xBits);
      stream.write(4, _small.yBits);
      stream.end();
      expect(() => _decode(stream), _damaged);
    });

    test('points may sit in the overscan margin', () {
      _expectRoundTrip(_doc(_small, <MCOImageV4Figure>[_line(-2, -2, 17, 17)]));
    });

    test('non-zero padding is rejected', () {
      final stream = _Bits();
      _small.header(stream);
      stream.end();
      // 19 bits so far; fill the byte's remaining five with ones.
      stream.write(0x1f, 5);
      expect(() => _decode(stream), _damaged);
    });

    test('a truncated stream is rejected', () {
      final stream = _Bits();
      _small.header(stream);
      stream.write(_opDot, 4);
      _small.point(stream, 3, 4);
      stream.end();
      final body = stream.body();
      expect(
        () => _codec.decodeBody(Uint8List.sublistView(body, 0, body.length - 1)),
        _damaged,
      );
      expect(() => _codec.decodeBody(Uint8List(0)), _damaged);
    });
  });

  group('transport tail and identity', () {
    final document = _doc(_small, <MCOImageV4Figure>[_dot(3, 4)]);

    test('the tail carries the target name and the reply timestamp', () {
      final encoded = _codec.encode(
        document,
        nonce: 7,
        targetName: ' Bob ',
        replyTimestamp: 0x01020304,
      );
      final canonical = encoded.canonicalDocument;
      expect(
        encoded.body,
        equals(Uint8List.fromList(<int>[
          7,
          ...canonical,
          0x03,
          3, 0x42, 0x6f, 0x62,
          0x04, 0x03, 0x02, 0x01,
        ])),
      );
      final decoded = _codec.decodeBody(encoded.body);
      expect(decoded.nonce, 7);
      expect(decoded.targetName, 'Bob');
      expect(decoded.replyTimestamp, 0x01020304);
      expect(decoded.canonicalDocument, equals(canonical));
    });

    test('either tail field may travel alone', () {
      final named = _codec.decodeBody(
        _codec.encode(document, nonce: 0, targetName: 'A').body,
      );
      expect(named.targetName, 'A');
      expect(named.replyTimestamp, isNull);
      final timed = _codec.decodeBody(
        _codec.encode(document, nonce: 0, replyTimestamp: 1).body,
      );
      expect(timed.targetName, isNull);
      expect(timed.replyTimestamp, 1);
    });

    test('unknown flags, an empty name and trailing bytes are rejected', () {
      final canonical = _codec.encode(document, nonce: 0).canonicalDocument;
      Uint8List body(List<int> tail) =>
          Uint8List.fromList(<int>[0, ...canonical, ...tail]);
      expect(() => _codec.decodeBody(body(const <int>[0x04])), _damaged);
      expect(() => _codec.decodeBody(body(const <int>[0x01, 0x00])), _damaged);
      expect(
        () => _codec.decodeBody(body(const <int>[0x02, 1, 0, 0, 0, 0x99])),
        _damaged,
      );
    });

    test('the encoder refuses an empty target name', () {
      expect(() => _codec.encode(document, targetName: '  '), _badInput);
    });

    test('identity and the stripped body exclude nonce and tail', () {
      final encoded = _codec.encode(
        document,
        nonce: 9,
        targetName: 'Bob',
        replyTimestamp: 5,
      );
      final canonical = encoded.canonicalDocument;
      expect(
        _codec.canonicalAppPayloadWithoutSender(encoded.body),
        equals(Uint8List.fromList(<int>[0x14, 0x00, ...canonical])),
      );
      expect(
        _codec.stripTransportTail(encoded.body, zeroNonce: true),
        equals(Uint8List.fromList(<int>[0, ...canonical])),
      );
      expect(
        _codec.stripTransportTail(encoded.body),
        equals(Uint8List.fromList(<int>[9, ...canonical])),
      );
      final refreshed = _codec.refreshPacketNonce(encoded.body);
      expect(refreshed.sublist(1), equals(encoded.body.sublist(1)));
    });

    test('the im4: text transport round-trips the whole body', () {
      final encoded = _codec.encode(document, nonce: 3, targetName: 'Bob');
      final text = _codec.textFromBody(encoded.body);
      expect(text, startsWith('im4:'));
      expect(MCOImageV4Codec.isTextPayload('  $text'), isTrue);
      expect(_codec.bodyFromText(text), equals(encoded.body));
      expect(_codec.decodeText(text).targetName, 'Bob');
      expect(() => _codec.bodyFromText('im3:AAAA'), _damaged);
    });
  });

  group('whole documents', () {
    test('a document with every figure kind round-trips', () {
      final document = _doc(_large, <MCOImageV4Figure>[
        _dot(2, 2),
        _line(1, 2, 7, 9),
        MCOImageV4Rect(
          first: const MCOImageV4Point(20, 20),
          second: const MCOImageV4Point(40, 30),
          third: const MCOImageV4Point(38, 24),
          style: const MCOImageV4Style(fillColor: _localA, strokeColor: _localBlack),
        ),
        MCOImageV4Ellipse(
          first: const MCOImageV4Point(50, 50),
          second: const MCOImageV4Point(80, 50),
          third: const MCOImageV4Point(65, 60),
          style: const MCOImageV4Style(strokeColor: _localB, strokeWidth: 3),
        ),
        _path(const <(int, int)>[(90, 10), (100, 12), (95, 30), (91, 22)], closed: true),
        MCOImageV4Wave(
          start: const MCOImageV4Point(10, 100),
          end: const MCOImageV4Point(60, 110),
          depth: -7,
          closed: false,
          style: _ink,
        ),
        MCOImageV4Group(figures: <MCOImageV4Figure>[
          _dot(100, 100, style: const MCOImageV4Style(strokeColor: _localC)),
          _dot(101, 101, style: const MCOImageV4Style(strokeColor: _localC)),
        ]),
        MCOImageV4Text(
          origin: const MCOImageV4Point(4, 120),
          fontSize: 6,
          align: MCOImageV4TextAlign.center,
          width: 100,
          text: 'Привет, mesh',
          style: _ink,
        ),
        _dot(120, 120),
      ]);
      final decoded = _expectRoundTrip(document);
      // Re-encoding the decoded document reproduces the canonical bytes.
      final again = _codec.encode(decoded.document, nonce: 0);
      expect(again.canonicalDocument, equals(decoded.canonicalDocument));
    });

    test('hidden figures are not serialized', () {
      final shown = _doc(_small, <MCOImageV4Figure>[_dot(3, 4)]);
      final withHidden = _doc(_small, <MCOImageV4Figure>[
        _dot(3, 4),
        _dot(9, 9).withVisibility(false),
      ]);
      expect(
        _codec.encode(withHidden, nonce: 0).canonicalDocument,
        equals(_codec.encode(shown, nonce: 0).canonicalDocument),
      );
    });
  });
}
