import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'channel_app_data_helper.dart';
import 'mcoimg_palette.dart';
import 'mcoimg_types.dart';
import 'mcoimg_v4_model.dart';

class MCOImageV4Codec {
  static const String textPrefix = 'im4:';
  static const int version = 4;
  static const int subtypeId = ChannelAppDataHelper.mcoImageSubtype;
  static const int subtypeVersion = (subtypeId << 4) | version;

  static const int _opEnd = 0;
  static const int _opSetFill = 1;
  static const int _opSetStroke = 2;
  static const int _opSetStrokeWidth = 3;
  static const int _opDot = 4;
  static const int _opLine = 5;
  static const int _opRect = 6;
  static const int _opEllipse = 7;
  static const int _opPathAbsolute = 9;
  static const int _opPathDelta = 10;
  static const int _opWave = 11;
  static const int _opRepeatLast = 12;
  static const int _opBits = 4;

  static const List<int> _deltaWidths = <int>[3, 4, 5, 6];

  const MCOImageV4Codec();

  EncodedMCOImageV4 encode(
    MCOImageV4Document document, {
    int? nonce,
    String? targetName,
    int? replyTimestamp,
  }) {
    _validateDocument(document);
    final canonicalDocument = _encodeCanonicalDocument(document);
    final packetNonce = nonce ?? math.Random.secure().nextInt(256);
    if (packetNonce < 0 || packetNonce > 0xff) {
      throw const MCOImageInvalidInputException('Invalid v4 nonce');
    }
    final tail = _encodeTransportTail(
      targetName: targetName,
      replyTimestamp: replyTimestamp,
    );
    final body = Uint8List.fromList(<int>[
      packetNonce,
      ..._byteVarUint7(canonicalDocument.length),
      ...canonicalDocument,
      ...tail,
    ]);
    return EncodedMCOImageV4(
      body: body,
      canonicalDocument: canonicalDocument,
      document: document,
      nonce: packetNonce,
      targetName: targetName,
      replyTimestamp: replyTimestamp,
    );
  }

  DecodedMCOImageV4 decodeBody(Uint8List body) {
    try {
      final reader = _V4ByteReader(body);
      final nonce = reader.readByte();
      final documentLength = reader.readCanonicalVarUint7();
      if (documentLength <= 0 || documentLength > reader.remaining) {
        throw const MCOImageInvalidPayloadException(
          'Invalid v4 document length',
        );
      }
      final canonicalDocument = reader.readBytes(documentLength);
      final document = _decodeCanonicalDocument(canonicalDocument);

      String? targetName;
      int? replyTimestamp;
      if (reader.remaining > 0) {
        final flags = reader.readByte();
        if ((flags & ~0x03) != 0) {
          throw const MCOImageInvalidPayloadException(
            'Unknown v4 transport flags',
          );
        }
        if ((flags & 0x01) != 0) {
          final length = reader.readCanonicalVarUint7();
          if (length <= 0) {
            throw const MCOImageInvalidPayloadException(
              'Empty v4 target name',
            );
          }
          targetName = utf8.decode(reader.readBytes(length));
        }
        if ((flags & 0x02) != 0) {
          replyTimestamp = reader.readUint32Le();
        }
        if (reader.remaining != 0) {
          throw const MCOImageInvalidPayloadException(
            'Trailing v4 transport bytes',
          );
        }
      }

      return DecodedMCOImageV4(
        document: document,
        canonicalDocument: canonicalDocument,
        nonce: nonce,
        targetName: targetName,
        replyTimestamp: replyTimestamp,
      );
    } on MCOImageInvalidPayloadException {
      rethrow;
    } on MCOImageCodecException catch (error) {
      throw MCOImageInvalidPayloadException(error.message);
    } on Object catch (error) {
      throw MCOImageInvalidPayloadException('Invalid v4 payload: $error');
    }
  }

  Uint8List appPayloadWithoutSender(EncodedMCOImageV4 encoded) {
    return ChannelAppDataHelper.appPayloadWithoutSender(
      subtypeId: subtypeId,
      version: version,
      body: encoded.body,
    );
  }

  Uint8List canonicalAppPayloadWithoutSender(Uint8List body) {
    final decoded = decodeBody(body);
    return Uint8List.fromList(<int>[
      subtypeVersion,
      0,
      ..._byteVarUint7(decoded.canonicalDocument.length),
      ...decoded.canonicalDocument,
    ]);
  }

  Uint8List stripTransportTail(Uint8List body, {bool zeroNonce = false}) {
    final decoded = decodeBody(body);
    return Uint8List.fromList(<int>[
      zeroNonce ? 0 : decoded.nonce,
      ..._byteVarUint7(decoded.canonicalDocument.length),
      ...decoded.canonicalDocument,
    ]);
  }

  Uint8List refreshPacketNonce(Uint8List body) {
    final decoded = decodeBody(body);
    final refreshed = encode(
      decoded.document,
      targetName: decoded.targetName,
      replyTimestamp: decoded.replyTimestamp,
    );
    return refreshed.body;
  }

  String textFromBody(Uint8List body) {
    decodeBody(body);
    return '$textPrefix${_V4Base91.encode(body)}';
  }

  Uint8List bodyFromText(String text) {
    final trimmed = text.trimLeft();
    if (!trimmed.startsWith(textPrefix)) {
      throw const MCOImageInvalidPayloadException('Not an MCOimg v4 text');
    }
    final body = _V4Base91.decode(trimmed.substring(textPrefix.length));
    decodeBody(body);
    return body;
  }

  DecodedMCOImageV4 decodeText(String text) => decodeBody(bodyFromText(text));

  static bool isTextPayload(String text) => text.trimLeft().startsWith(
    textPrefix,
  );

  Uint8List _encodeCanonicalDocument(MCOImageV4Document document) {
    if (document.mode != MCOImageV4Mode.vector) {
      throw const MCOImageInvalidInputException(
        'MCOimg v4 raster encoding is not implemented yet',
      );
    }
    final writer = _V4BitWriter();
    final xBits = _coordinateBits(document.width);
    final yBits = _coordinateBits(document.height);
    final scalarBits = _scalarBits(document.width, document.height);
    final paletteBits = _paletteBits(document.palette.length);
    final profileColorBits = _profileColorBits(document.paletteProfile);

    writer
      ..writeBits(document.mode.index, 1)
      ..writeBits(document.width - 1, 8)
      ..writeBits(document.height - 1, 8)
      ..writeBits(document.paletteProfile.index, 4)
      ..writeBits(document.palette.length - 1, 6);
    for (final color in document.palette) {
      writer.writeBits(color, profileColorBits);
    }

    writer.writeBit(document.backgroundColor != null);
    if (document.backgroundColor case final background?) {
      writer.writeBits(background, paletteBits);
    }
    _writeOptionalColor(writer, document.initialStyle.fillColor, paletteBits);
    _writeOptionalColor(writer, document.initialStyle.strokeColor, paletteBits);
    writer.writeBits(document.initialStyle.strokeWidth - 1, scalarBits);

    var currentStyle = document.initialStyle;
    MCOImageV4Figure? lastFigure;
    for (final figure in document.figures.where((figure) => figure.visible)) {
      currentStyle = _writeStyleChanges(
        writer,
        currentStyle,
        figure.style,
        paletteBits,
        scalarBits,
      );
      final repeat = lastFigure == null
          ? null
          : _translationFrom(lastFigure, figure);
      final full = _encodeFigureCommand(
        figure,
        xBits: xBits,
        yBits: yBits,
        scalarBits: scalarBits,
      );
      final repeated = repeat == null
          ? null
          : _encodeRepeatCommand(
              repeat,
              width: document.width,
              height: document.height,
              xBits: xBits,
              yBits: yBits,
            );
      if (repeated != null && repeated.bitLength < full.bitLength) {
        writer.writeWriter(repeated);
      } else {
        writer.writeWriter(full);
      }
      lastFigure = figure;
    }
    writer.writeBits(_opEnd, _opBits);
    return writer.toBytes();
  }

  MCOImageV4Document _decodeCanonicalDocument(Uint8List bytes) {
    final reader = _V4BitReader(bytes);
    final modeIndex = reader.readBits(1);
    if (modeIndex != MCOImageV4Mode.vector.index) {
      throw const MCOImageInvalidPayloadException(
        'Unsupported MCOimg v4 mode',
      );
    }
    final width = reader.readBits(8) + 1;
    final height = reader.readBits(8) + 1;
    final profileIndex = reader.readBits(4);
    if (profileIndex >= PaletteProfile.values.length) {
      throw const MCOImageInvalidPayloadException(
        'Invalid v4 palette profile',
      );
    }
    final paletteProfile = PaletteProfile.values[profileIndex];
    final profileColorBits = _profileColorBits(paletteProfile);
    final paletteLength = reader.readBits(6) + 1;
    final palette = <int>[];
    for (var i = 0; i < paletteLength; i++) {
      final color = reader.readBits(profileColorBits);
      final valid = paletteProfile.isDynamic
          ? MCOImageDynamicPalette.profileColorIdForGlobalIndex(
                  paletteProfile,
                  color,
                ) !=
                null
          : color >= 0 &&
                color < MCOImagePalette.colorsFor(paletteProfile).length;
      if (!valid) {
        throw const MCOImageInvalidPayloadException(
          'Invalid v4 palette color',
        );
      }
      if (palette.contains(color)) {
        throw const MCOImageInvalidPayloadException(
          'Duplicate v4 palette color',
        );
      }
      palette.add(color);
    }
    final paletteBits = _paletteBits(paletteLength);
    final xBits = _coordinateBits(width);
    final yBits = _coordinateBits(height);
    final scalarBits = _scalarBits(width, height);

    final backgroundColor = reader.readBit()
        ? _readPaletteRef(reader, paletteLength, paletteBits)
        : null;
    var currentStyle = MCOImageV4Style(
      fillColor: _readOptionalColor(reader, paletteLength, paletteBits),
      strokeColor: _readOptionalColor(reader, paletteLength, paletteBits),
      strokeWidth: reader.readBits(scalarBits) + 1,
    );
    final initialStyle = currentStyle;
    final figures = <MCOImageV4Figure>[];
    MCOImageV4Figure? lastFigure;

    while (true) {
      final opcode = reader.readBits(_opBits);
      if (opcode == _opEnd) break;
      switch (opcode) {
        case _opSetFill:
          currentStyle = currentStyle.copyWith(
            fillColor: _readOptionalColor(reader, paletteLength, paletteBits),
          );
        case _opSetStroke:
          currentStyle = currentStyle.copyWith(
            strokeColor: _readOptionalColor(
              reader,
              paletteLength,
              paletteBits,
            ),
          );
        case _opSetStrokeWidth:
          currentStyle = currentStyle.copyWith(
            strokeWidth: reader.readBits(scalarBits) + 1,
          );
        case _opRepeatLast:
          if (lastFigure == null) {
            throw const MCOImageInvalidPayloadException(
              'MCOimg v4 repeat has no previous figure',
            );
          }
          final dx = _zigZagDecode(reader.readBits(xBits + 1));
          final dy = _zigZagDecode(reader.readBits(yBits + 1));
          final repeated = lastFigure.translated(dx, dy).withStyle(currentStyle);
          _validateFigure(repeated, width, height, paletteLength);
          figures.add(repeated);
          lastFigure = repeated;
        default:
          final figure = _readFigure(
            opcode,
            reader,
            currentStyle,
            width: width,
            height: height,
            xBits: xBits,
            yBits: yBits,
            scalarBits: scalarBits,
          );
          _validateFigure(figure, width, height, paletteLength);
          figures.add(figure);
          lastFigure = figure;
      }
    }
    reader.finish();
    return MCOImageV4Document(
      width: width,
      height: height,
      paletteProfile: paletteProfile,
      palette: palette,
      backgroundColor: backgroundColor,
      initialStyle: initialStyle,
      figures: figures,
    );
  }

  MCOImageV4Style _writeStyleChanges(
    _V4BitWriter writer,
    MCOImageV4Style current,
    MCOImageV4Style next,
    int paletteBits,
    int scalarBits,
  ) {
    if (current.fillColor != next.fillColor) {
      writer.writeBits(_opSetFill, _opBits);
      _writeOptionalColor(writer, next.fillColor, paletteBits);
    }
    if (current.strokeColor != next.strokeColor) {
      writer.writeBits(_opSetStroke, _opBits);
      _writeOptionalColor(writer, next.strokeColor, paletteBits);
    }
    if (current.strokeWidth != next.strokeWidth) {
      writer
        ..writeBits(_opSetStrokeWidth, _opBits)
        ..writeBits(next.strokeWidth - 1, scalarBits);
    }
    return next;
  }

  _V4BitWriter _encodeFigureCommand(
    MCOImageV4Figure figure, {
    required int xBits,
    required int yBits,
    required int scalarBits,
  }) {
    if (figure is MCOImageV4Path) {
      return _encodeBestPath(figure, xBits: xBits, yBits: yBits);
    }
    final writer = _V4BitWriter();
    switch (figure) {
      case MCOImageV4Dot(:final point):
        writer.writeBits(_opDot, _opBits);
        _writePoint(writer, point, xBits, yBits);
      case MCOImageV4Line(:final start, :final end):
        writer.writeBits(_opLine, _opBits);
        _writePoint(writer, start, xBits, yBits);
        _writePoint(writer, end, xBits, yBits);
      case MCOImageV4Rect(
        :final first,
        :final second,
        :final third,
      ):
        writer.writeBits(_opRect, _opBits);
        _writePoint(writer, first, xBits, yBits);
        _writePoint(writer, second, xBits, yBits);
        _writePoint(writer, third, xBits, yBits);
      case MCOImageV4Ellipse(
        :final first,
        :final second,
        :final third,
      ):
        writer.writeBits(_opEllipse, _opBits);
        _writePoint(writer, first, xBits, yBits);
        _writePoint(writer, second, xBits, yBits);
        _writePoint(writer, third, xBits, yBits);
      case MCOImageV4Wave(
        :final start,
        :final end,
        :final depth,
        :final closed,
      ):
        writer
          ..writeBits(_opWave, _opBits)
          ..writeBit(closed);
        _writePoint(writer, start, xBits, yBits);
        _writePoint(writer, end, xBits, yBits);
        writer
          ..writeBit(depth < 0)
          ..writeBits(depth.abs() - 1, scalarBits);
      case MCOImageV4Path():
        throw const MCOImageInvalidInputException('Unexpected v4 path');
    }
    return writer;
  }

  _V4BitWriter _encodeBestPath(
    MCOImageV4Path path, {
    required int xBits,
    required int yBits,
  }) {
    final candidates = <_V4BitWriter>[
      _encodeAbsolutePath(path, xBits: xBits, yBits: yBits),
      for (var selector = 0; selector < _deltaWidths.length; selector++)
        _encodeDeltaPath(
          path,
          selector: selector,
          shortBits: _deltaWidths[selector],
          xBits: xBits,
          yBits: yBits,
        ),
    ];
    candidates.sort((a, b) => a.bitLength.compareTo(b.bitLength));
    return candidates.first;
  }

  _V4BitWriter _encodeAbsolutePath(
    MCOImageV4Path path, {
    required int xBits,
    required int yBits,
  }) {
    final minimum = path.closed ? 3 : 2;
    final writer = _V4BitWriter()
      ..writeBits(_opPathAbsolute, _opBits)
      ..writeBit(path.closed)
      ..writeCompactUint(path.points.length - minimum);
    for (final point in path.points) {
      _writePoint(writer, point, xBits, yBits);
    }
    return writer;
  }

  _V4BitWriter _encodeDeltaPath(
    MCOImageV4Path path, {
    required int selector,
    required int shortBits,
    required int xBits,
    required int yBits,
  }) {
    final minimum = path.closed ? 3 : 2;
    final writer = _V4BitWriter()
      ..writeBits(_opPathDelta, _opBits)
      ..writeBit(path.closed)
      ..writeBits(selector, 2)
      ..writeCompactUint(path.points.length - minimum);
    _writePoint(writer, path.points.first, xBits, yBits);
    for (var i = 1; i < path.points.length; i++) {
      final previous = path.points[i - 1];
      final current = path.points[i];
      _writePathComponent(writer, current.x, previous.x, shortBits, xBits);
      _writePathComponent(writer, current.y, previous.y, shortBits, yBits);
    }
    return writer;
  }

  void _writePathComponent(
    _V4BitWriter writer,
    int current,
    int previous,
    int shortBits,
    int absoluteBits,
  ) {
    final code = _zigZagEncode(current - previous);
    if (code < (1 << shortBits)) {
      writer
        ..writeBit(false)
        ..writeBits(code, shortBits);
    } else {
      writer
        ..writeBit(true)
        ..writeBits(current, absoluteBits);
    }
  }

  _V4BitWriter? _encodeRepeatCommand(
    MCOImageV4Point delta, {
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    if (delta.x.abs() > width - 1 || delta.y.abs() > height - 1) {
      return null;
    }
    return _V4BitWriter()
      ..writeBits(_opRepeatLast, _opBits)
      ..writeBits(_zigZagEncode(delta.x), xBits + 1)
      ..writeBits(_zigZagEncode(delta.y), yBits + 1);
  }

  MCOImageV4Figure _readFigure(
    int opcode,
    _V4BitReader reader,
    MCOImageV4Style style, {
    required int width,
    required int height,
    required int xBits,
    required int yBits,
    required int scalarBits,
  }) {
    switch (opcode) {
      case _opDot:
        return MCOImageV4Dot(
          point: _readPoint(reader, width, height, xBits, yBits),
          style: style,
        );
      case _opLine:
        return MCOImageV4Line(
          start: _readPoint(reader, width, height, xBits, yBits),
          end: _readPoint(reader, width, height, xBits, yBits),
          style: style,
        );
      case _opRect:
      case _opEllipse:
        final first = _readPoint(reader, width, height, xBits, yBits);
        final second = _readPoint(reader, width, height, xBits, yBits);
        final third = _readPoint(reader, width, height, xBits, yBits);
        return opcode == _opRect
            ? MCOImageV4Rect(
                first: first,
                second: second,
                third: third,
                style: style,
              )
            : MCOImageV4Ellipse(
                first: first,
                second: second,
                third: third,
                style: style,
              );
      case _opPathAbsolute:
      case _opPathDelta:
        return _readPath(
          opcode,
          reader,
          style,
          width: width,
          height: height,
          xBits: xBits,
          yBits: yBits,
        );
      case _opWave:
        final closed = reader.readBit();
        final start = _readPoint(reader, width, height, xBits, yBits);
        final end = _readPoint(reader, width, height, xBits, yBits);
        final negative = reader.readBit();
        final magnitude = reader.readBits(scalarBits) + 1;
        return MCOImageV4Wave(
          start: start,
          end: end,
          depth: negative ? -magnitude : magnitude,
          closed: closed,
          style: style,
        );
      default:
        throw MCOImageInvalidPayloadException(
          'Unknown MCOimg v4 opcode: $opcode',
        );
    }
  }

  MCOImageV4Path _readPath(
    int opcode,
    _V4BitReader reader,
    MCOImageV4Style style, {
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    final closed = reader.readBit();
    final shortBits = opcode == _opPathDelta
        ? _deltaWidths[reader.readBits(2)]
        : null;
    final minimum = closed ? 3 : 2;
    final pointCount = reader.readCompactUint() + minimum;
    final minimumBitsPerPoint = shortBits == null
        ? xBits + yBits
        : 2 * (shortBits + 1);
    if (pointCount - 1 >
        reader.remainingBits ~/ math.max(1, minimumBitsPerPoint)) {
      throw const MCOImageInvalidPayloadException(
        'MCOimg v4 path point count exceeds payload',
      );
    }
    final points = <MCOImageV4Point>[
      _readPoint(reader, width, height, xBits, yBits),
    ];
    while (points.length < pointCount) {
      final previous = points.last;
      if (shortBits == null) {
        points.add(_readPoint(reader, width, height, xBits, yBits));
      } else {
        final x = _readPathComponent(
          reader,
          previous.x,
          shortBits,
          xBits,
          width,
        );
        final y = _readPathComponent(
          reader,
          previous.y,
          shortBits,
          yBits,
          height,
        );
        points.add(MCOImageV4Point(x, y));
      }
    }
    return MCOImageV4Path(points: points, closed: closed, style: style);
  }

  int _readPathComponent(
    _V4BitReader reader,
    int previous,
    int shortBits,
    int absoluteBits,
    int axisSize,
  ) {
    final value = reader.readBit()
        ? reader.readBits(absoluteBits)
        : previous + _zigZagDecode(reader.readBits(shortBits));
    if (value < 0 || value >= axisSize) {
      throw const MCOImageInvalidPayloadException(
        'MCOimg v4 path coordinate is out of range',
      );
    }
    return value;
  }

  void _validateDocument(MCOImageV4Document document) {
    if (document.width < 1 || document.width > 256) {
      throw const MCOImageInvalidInputException('Invalid v4 canvas width');
    }
    if (document.height < 1 || document.height > 256) {
      throw const MCOImageInvalidInputException('Invalid v4 canvas height');
    }
    if (document.palette.isEmpty || document.palette.length > 64) {
      throw const MCOImageInvalidInputException('Invalid v4 palette size');
    }
    final seen = <int>{};
    for (final color in document.palette) {
      final valid = document.paletteProfile.isDynamic
          ? MCOImageDynamicPalette.profileColorIdForGlobalIndex(
                  document.paletteProfile,
                  color,
                ) !=
                null
          : color >= 0 &&
                color < MCOImagePalette.colorsFor(document.paletteProfile).length;
      if (!valid || !seen.add(color)) {
        throw const MCOImageInvalidInputException('Invalid v4 palette color');
      }
    }
    _validatePaletteRef(
      document.backgroundColor,
      document.palette.length,
      'background',
    );
    _validateStyle(
      document.initialStyle,
      document.palette.length,
      math.max(document.width, document.height),
    );
    for (final figure in document.figures.where((figure) => figure.visible)) {
      _validateFigure(
        figure,
        document.width,
        document.height,
        document.palette.length,
      );
    }
  }

  static void _validateFigure(
    MCOImageV4Figure figure,
    int width,
    int height,
    int paletteLength,
  ) {
    _validateStyle(figure.style, paletteLength, math.max(width, height));
    void point(MCOImageV4Point value) {
      if (value.x < 0 ||
          value.x >= width ||
          value.y < 0 ||
          value.y >= height) {
        throw const MCOImageInvalidInputException(
          'MCOimg v4 point is outside the canvas',
        );
      }
    }

    switch (figure) {
      case MCOImageV4Dot(point: final asPoint):
        point(asPoint);
        if (figure.style.strokeColor == null) {
          throw const MCOImageInvalidInputException(
            'MCOimg v4 dot requires a stroke color',
          );
        }
      case MCOImageV4Line(:final start, :final end):
        point(start);
        point(end);
      case MCOImageV4AreaFigure(
        :final first,
        :final second,
        :final third,
      ):
        point(first);
        point(second);
        point(third);
        if (first == second || first == third || second == third) {
          throw const MCOImageInvalidInputException(
            'MCOimg v4 area figure has duplicate control points',
          );
        }
      case MCOImageV4Path(:final points, :final closed):
        if (points.length < (closed ? 3 : 2)) {
          throw const MCOImageInvalidInputException(
            'MCOimg v4 path has too few points',
          );
        }
        for (final value in points) {
          point(value);
        }
      case MCOImageV4Wave(:final start, :final end, :final depth):
        point(start);
        point(end);
        if (depth == 0 || depth.abs() > math.max(width, height)) {
          throw const MCOImageInvalidInputException(
            'Invalid MCOimg v4 wave depth',
          );
        }
    }
  }

  static void _validateStyle(
    MCOImageV4Style style,
    int paletteLength,
    int scalarSize,
  ) {
    _validatePaletteRef(style.fillColor, paletteLength, 'fill');
    _validatePaletteRef(style.strokeColor, paletteLength, 'stroke');
    if (style.strokeWidth < 1 || style.strokeWidth > scalarSize) {
      throw const MCOImageInvalidInputException(
        'Invalid MCOimg v4 stroke width',
      );
    }
  }

  static void _validatePaletteRef(
    int? value,
    int paletteLength,
    String label,
  ) {
    if (value != null && (value < 0 || value >= paletteLength)) {
      throw MCOImageInvalidInputException('Invalid v4 $label palette index');
    }
  }

  static MCOImageV4Point? _translationFrom(
    MCOImageV4Figure previous,
    MCOImageV4Figure current,
  ) {
    MCOImageV4Point delta(MCOImageV4Point a, MCOImageV4Point b) =>
        MCOImageV4Point(b.x - a.x, b.y - a.y);

    switch ((previous, current)) {
      case (MCOImageV4Dot(point: final a), MCOImageV4Dot(point: final b)):
        return delta(a, b);
      case (
        MCOImageV4Line(start: final a1, end: final a2),
        MCOImageV4Line(start: final b1, end: final b2),
      ):
        final d = delta(a1, b1);
        return a2.translated(d.x, d.y) == b2 ? d : null;
      case (MCOImageV4Rect() && final a, MCOImageV4Rect() && final b):
        final d = delta(a.first, b.first);
        return a.second.translated(d.x, d.y) == b.second &&
                a.third.translated(d.x, d.y) == b.third
            ? d
            : null;
      case (MCOImageV4Ellipse() && final a, MCOImageV4Ellipse() && final b):
        final d = delta(a.first, b.first);
        return a.second.translated(d.x, d.y) == b.second &&
                a.third.translated(d.x, d.y) == b.third
            ? d
            : null;
      case (MCOImageV4Path() && final a, MCOImageV4Path() && final b):
        if (a.closed != b.closed || a.points.length != b.points.length) {
          return null;
        }
        final d = delta(a.points.first, b.points.first);
        for (var i = 1; i < a.points.length; i++) {
          if (a.points[i].translated(d.x, d.y) != b.points[i]) return null;
        }
        return d;
      case (MCOImageV4Wave() && final a, MCOImageV4Wave() && final b):
        if (a.depth != b.depth || a.closed != b.closed) return null;
        final d = delta(a.start, b.start);
        return a.end.translated(d.x, d.y) == b.end ? d : null;
      default:
        return null;
    }
  }

  static void _writePoint(
    _V4BitWriter writer,
    MCOImageV4Point point,
    int xBits,
    int yBits,
  ) {
    writer
      ..writeBits(point.x, xBits)
      ..writeBits(point.y, yBits);
  }

  static MCOImageV4Point _readPoint(
    _V4BitReader reader,
    int width,
    int height,
    int xBits,
    int yBits,
  ) {
    return MCOImageV4Point(
      _readCoordinate(reader, xBits, width),
      _readCoordinate(reader, yBits, height),
    );
  }

  static int _readCoordinate(_V4BitReader reader, int bits, int size) {
    final value = reader.readBits(bits);
    if (value >= size) {
      throw const MCOImageInvalidPayloadException(
        'MCOimg v4 coordinate is out of range',
      );
    }
    return value;
  }

  static void _writeOptionalColor(
    _V4BitWriter writer,
    int? color,
    int paletteBits,
  ) {
    writer.writeBit(color != null);
    if (color != null) writer.writeBits(color, paletteBits);
  }

  static int? _readOptionalColor(
    _V4BitReader reader,
    int paletteLength,
    int paletteBits,
  ) {
    return reader.readBit()
        ? _readPaletteRef(reader, paletteLength, paletteBits)
        : null;
  }

  static int _readPaletteRef(
    _V4BitReader reader,
    int paletteLength,
    int paletteBits,
  ) {
    final value = reader.readBits(paletteBits);
    if (value >= paletteLength) {
      throw const MCOImageInvalidPayloadException(
        'MCOimg v4 palette reference is out of range',
      );
    }
    return value;
  }

  static int _coordinateBits(int size) => math.max(1, (size - 1).bitLength);

  static int _scalarBits(int width, int height) =>
      math.max(1, (math.max(width, height) - 1).bitLength);

  static int _paletteBits(int length) => math.max(1, (length - 1).bitLength);

  static int _profileColorBits(PaletteProfile profile) => profile.isDynamic
      ? 9
      : math.max(1, (MCOImagePalette.colorsFor(profile).length - 1).bitLength);

  static int _zigZagEncode(int value) =>
      value >= 0 ? value << 1 : ((-value) << 1) - 1;

  static int _zigZagDecode(int value) =>
      (value & 1) == 0 ? value >> 1 : -((value + 1) >> 1);

  static Uint8List _encodeTransportTail({
    String? targetName,
    int? replyTimestamp,
  }) {
    final normalizedName = targetName?.trim();
    if (normalizedName != null && normalizedName.isEmpty) {
      throw const MCOImageInvalidInputException('Empty v4 target name');
    }
    if (replyTimestamp != null &&
        (replyTimestamp < 0 || replyTimestamp > 0xffffffff)) {
      throw const MCOImageInvalidInputException('Invalid v4 reply timestamp');
    }
    if (normalizedName == null && replyTimestamp == null) return Uint8List(0);
    final nameBytes = normalizedName == null
        ? null
        : Uint8List.fromList(utf8.encode(normalizedName));
    final flags = (nameBytes != null ? 0x01 : 0) |
        (replyTimestamp != null ? 0x02 : 0);
    return Uint8List.fromList(<int>[
      flags,
      if (nameBytes != null) ...<int>[
        ..._byteVarUint7(nameBytes.length),
        ...nameBytes,
      ],
      if (replyTimestamp != null) ...<int>[
        replyTimestamp & 0xff,
        (replyTimestamp >> 8) & 0xff,
        (replyTimestamp >> 16) & 0xff,
        (replyTimestamp >> 24) & 0xff,
      ],
    ]);
  }

  static List<int> _byteVarUint7(int value) {
    if (value < 0) {
      throw const MCOImageInvalidInputException('Negative v4 varuint');
    }
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

class _V4BitWriter {
  final List<int> _bytes = <int>[];
  int _current = 0;
  int _bitOffset = 0;
  int bitLength = 0;

  void writeBit(bool value) => writeBits(value ? 1 : 0, 1);

  void writeBits(int value, int bits) {
    if (bits < 0 || bits > 32 || value < 0) {
      throw const MCOImageInvalidInputException('Invalid v4 bit field');
    }
    if (bits < 32 && value >= (1 << bits)) {
      throw const MCOImageInvalidInputException('V4 bit field overflow');
    }
    var remaining = bits;
    var source = value;
    while (remaining > 0) {
      final available = 8 - _bitOffset;
      final take = math.min(available, remaining);
      final mask = (1 << take) - 1;
      _current |= (source & mask) << _bitOffset;
      source >>= take;
      _bitOffset += take;
      bitLength += take;
      remaining -= take;
      if (_bitOffset == 8) {
        _bytes.add(_current);
        _current = 0;
        _bitOffset = 0;
      }
    }
  }

  void writeCompactUint(int value) {
    if (value < 0) {
      throw const MCOImageInvalidInputException('Negative v4 compact uint');
    }
    if (value <= 3) {
      writeBits(0, 1);
      writeBits(value, 2);
    } else if (value <= 19) {
      writeBits(1, 2);
      writeBits(value - 4, 4);
    } else if (value <= 275) {
      writeBits(3, 3);
      writeBits(value - 20, 8);
    } else {
      writeBits(7, 3);
      writeBitVarUint(value);
    }
  }

  void writeBitVarUint(int value) {
    var remaining = value;
    do {
      var byte = remaining & 0x7f;
      remaining >>= 7;
      if (remaining != 0) byte |= 0x80;
      writeBits(byte, 8);
    } while (remaining != 0);
  }

  void writeWriter(_V4BitWriter other) {
    final reader = _V4BitReader(other.toBytes(), bitLimit: other.bitLength);
    while (reader.remainingBits > 0) {
      final take = math.min(32, reader.remainingBits);
      writeBits(reader.readBits(take), take);
    }
  }

  Uint8List toBytes() {
    final result = <int>[..._bytes];
    if (_bitOffset != 0) result.add(_current);
    return Uint8List.fromList(result);
  }
}

class _V4BitReader {
  final Uint8List _bytes;
  final int _bitLimit;
  int _bitIndex = 0;

  _V4BitReader(Uint8List bytes, {int? bitLimit})
      : _bytes = bytes,
        _bitLimit = bitLimit ?? bytes.length * 8;

  int get remainingBits => _bitLimit - _bitIndex;

  bool readBit() => readBits(1) != 0;

  int readBits(int bits) {
    if (bits < 0 || bits > 32 || _bitIndex + bits > _bitLimit) {
      throw const MCOImageInvalidPayloadException('Unexpected end of v4 bits');
    }
    var value = 0;
    for (var shift = 0; shift < bits; shift++) {
      final byte = _bytes[_bitIndex >> 3];
      value |= ((byte >> (_bitIndex & 7)) & 1) << shift;
      _bitIndex++;
    }
    return value;
  }

  int readCompactUint() {
    if (readBits(1) == 0) return readBits(2);
    if (readBits(1) == 0) return readBits(4) + 4;
    if (readBits(1) == 0) return readBits(8) + 20;
    final value = readCanonicalBitVarUint();
    if (value <= 275) {
      throw const MCOImageInvalidPayloadException(
        'Non-canonical v4 compact uint',
      );
    }
    return value;
  }

  int readCanonicalBitVarUint() {
    var result = 0;
    var shift = 0;
    for (var i = 0; i < 5; i++) {
      final byte = readBits(8);
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        if (i > 0 && (byte & 0x7f) == 0) {
          throw const MCOImageInvalidPayloadException(
            'Non-canonical v4 bit varuint',
          );
        }
        return result;
      }
      shift += 7;
    }
    throw const MCOImageInvalidPayloadException('V4 bit varuint is too long');
  }

  void finish() {
    while (_bitIndex < _bitLimit) {
      if (readBits(1) != 0) {
        throw const MCOImageInvalidPayloadException(
          'Non-zero MCOimg v4 padding',
        );
      }
    }
  }
}

class _V4ByteReader {
  final Uint8List _bytes;
  int _offset = 0;

  _V4ByteReader(this._bytes);

  int get remaining => _bytes.length - _offset;

  int readByte() {
    if (_offset >= _bytes.length) {
      throw const MCOImageInvalidPayloadException('Unexpected end of v4 bytes');
    }
    return _bytes[_offset++];
  }

  int readCanonicalVarUint7() {
    var result = 0;
    var shift = 0;
    for (var i = 0; i < 5; i++) {
      final byte = readByte();
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        if (i > 0 && (byte & 0x7f) == 0) {
          throw const MCOImageInvalidPayloadException(
            'Non-canonical v4 byte varuint',
          );
        }
        return result;
      }
      shift += 7;
    }
    throw const MCOImageInvalidPayloadException('V4 byte varuint is too long');
  }

  Uint8List readBytes(int length) {
    if (length < 0 || length > remaining) {
      throw const MCOImageInvalidPayloadException('Unexpected end of v4 bytes');
    }
    final result = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return Uint8List.fromList(result);
  }

  int readUint32Le() {
    final b0 = readByte();
    final b1 = readByte();
    final b2 = readByte();
    final b3 = readByte();
    return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
  }
}

class _V4Base91 {
  static const String _alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
      '!#\$%&()*+,./:;<=>?@[]^_`{|}~"';
  static final Map<int, int> _decode = <int, int>{
    for (var i = 0; i < _alphabet.length; i++) _alphabet.codeUnitAt(i): i,
  };

  static String encode(Uint8List data) {
    var b = 0;
    var n = 0;
    final result = StringBuffer();
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
          ..writeCharCode(_alphabet.codeUnitAt(value % 91))
          ..writeCharCode(_alphabet.codeUnitAt(value ~/ 91));
      }
    }
    if (n > 0) {
      result.writeCharCode(_alphabet.codeUnitAt(b % 91));
      if (n > 7 || b > 90) {
        result.writeCharCode(_alphabet.codeUnitAt(b ~/ 91));
      }
    }
    return result.toString();
  }

  static Uint8List decode(String text) {
    var b = 0;
    var n = 0;
    var value = -1;
    final output = <int>[];
    for (final codeUnit in text.codeUnits) {
      final decoded = _decode[codeUnit];
      if (decoded == null) {
        throw const MCOImageInvalidPayloadException(
          'Invalid MCOimg v4 Base91 character',
        );
      }
      if (value < 0) {
        value = decoded;
      } else {
        value += decoded * 91;
        b |= value << n;
        n += (value & 8191) > 88 ? 13 : 14;
        while (n >= 8) {
          output.add(b & 0xff);
          b >>= 8;
          n -= 8;
        }
        value = -1;
      }
    }
    if (value >= 0) output.add((b | (value << n)) & 0xff);
    return Uint8List.fromList(output);
  }
}
