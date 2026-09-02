import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'channel_app_data_helper.dart';
import 'mcoimg_palette.dart';
import 'mcoimg_types.dart';
import 'mcoimg_v3_codec.dart';
import 'mcoimg_v4_model.dart';

class MCOImageV4Codec {
  static const String textPrefix = 'im4:';
  static const int version = 4;
  static const int subtypeId = ChannelAppDataHelper.mcoImageSubtype;
  static const int subtypeVersion = (subtypeId << 4) | version;
  static const int _rasterLayerEncodeCacheLimit = 32;

  static const int _opEnd = 0;
  static const int _opSetFill = 1;
  static const int _opSetStroke = 2;
  static const int _opSetStrokeWidth = 3;
  static const int _opDot = 4;
  static const int _opLine = 5;
  static const int _opRect = 6;
  static const int _opEllipse = 7;
  static const int _opRectAxisAligned = 8;
  static const int _opPathAbsolute = 9;
  static const int _opPathDelta = 10;
  static const int _opWave = 11;
  static const int _opRepeatLast = 12;
  static const int _opEllipseAxisAligned = 13;
  static const int _opRepeatShort = 14;
  static const int _opExtended = 15;
  static const int _opBits = 4;
  static const int _modeBits = 2;

  static const List<int> _deltaWidths = <int>[3, 4, 5, 6];
  static final Map<
    _V4RasterLayerEncodeCacheKey,
    _V4RasterLayerEncodeCacheValue
  >
  _rasterLayerEncodeCache =
      <_V4RasterLayerEncodeCacheKey, _V4RasterLayerEncodeCacheValue>{};
  static const int _extLineDelta = 0;
  static const int _extLineAxisDelta = 1;
  static const int _extAreaDelta = 2;
  static const int _extWaveDelta = 3;
  static const int _extPathOrthogonal = 4;
  static const int _extPathBounds = 5;
  static const int _extPathBoundsDelta = 6;
  static const int _extLineAxisAbsolute = 7;
  static const int _extEllipseDepth = 8;
  static const int _extRepeatBack = 9;
  static const int _extDotRun = 10;
  static const int _extSetStyle = 11;
  static const int _extRepeatColorRun = 12;
  static const int _extGroup = 13;
  static const int _extRasterLayer = 14;
  static const int _extBits = 4;
  static const int _repeatBackWindow = 8;
  static const int _dimensionModeSquare64 = 0;
  static const int _dimensionModeSmall32 = 1;
  static const int _dimensionModeMedium64 = 2;
  static const int _dimensionModeExtended = 3;
  static const int _coordinateOverscanMax = 16;

  const MCOImageV4Codec();

  static void clearRasterLayerEncodeCache() {
    _rasterLayerEncodeCache.clear();
  }

  static int coordinateMarginForCanvasSize(int size) =>
      math.min(_coordinateOverscanMax, math.max(1, (size + 7) ~/ 8));

  EncodedMCOImageV4 encode(
    MCOImageV4Document document, {
    int? nonce,
    String? targetName,
    int? replyTimestamp,
    int compressionLevel = mcoImageDefaultCompressionLevel,
  }) {
    _validateDocument(document);
    final canonicalDocument = _encodeCanonicalDocument(
      document,
      compressionLevel: compressionLevel,
    );
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
      if (body.isEmpty) {
        throw const MCOImageInvalidPayloadException(
          'MCOimg v4 payload too short',
        );
      }
      final nonce = body[0];
      final decoded = _decodeCanonicalDocumentPrefix(
        Uint8List.sublistView(body, 1),
      );
      final document = decoded.document;
      final canonicalDocument = decoded.canonicalDocument;
      final reader = _V4ByteReader(
        Uint8List.sublistView(body, 1 + canonicalDocument.length),
      );

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
    } on MCOImageUnsupportedFormatException {
      rethrow;
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
      ...decoded.canonicalDocument,
    ]);
  }

  Uint8List stripTransportTail(Uint8List body, {bool zeroNonce = false}) {
    final decoded = decodeBody(body);
    return Uint8List.fromList(<int>[
      zeroNonce ? 0 : decoded.nonce,
      ...decoded.canonicalDocument,
    ]);
  }

  Uint8List refreshPacketNonce(Uint8List body) {
    decodeBody(body);
    final refreshed = Uint8List.fromList(body);
    refreshed[0] = math.Random.secure().nextInt(256);
    return refreshed;
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

  Uint8List _encodeCanonicalDocument(
    MCOImageV4Document document, {
    required int compressionLevel,
  }) {
    if (!_isObjectMode(document.mode)) {
      throw const MCOImageInvalidInputException(
        'MCOimg v4 raster encoding is not implemented yet',
      );
    }
    final writer = _V4BitWriter();
    final xBits = _coordinateBits(document.width);
    final yBits = _coordinateBits(document.height);
    final scalarBits = _scalarBits(document.width, document.height);
    final profileColorBits = _profileColorBits(document.paletteProfile);
    final mode = _effectiveObjectMode(document);

    writer
      ..writeBits(mode.index, _modeBits)
      ..writeBits(document.paletteProfile.index, 4);
    _writeDimensions(writer, document.width, document.height);

    final defaultBackgroundColor = _defaultBackgroundColorForDocument(document);
    final hasBackgroundOverride =
        defaultBackgroundColor == null ||
        document.backgroundColor != defaultBackgroundColor;
    writer.writeBit(hasBackgroundOverride);
    if (hasBackgroundOverride) {
      _writeOptionalColor(
        writer,
        document,
        document.backgroundColor,
        profileColorBits,
      );
    }
    var currentStyle = _defaultStyleForDocument(document);
    final history = <MCOImageV4Figure>[];
    final figures = document.figures.where((figure) => figure.visible).toList();
    for (var index = 0; index < figures.length;) {
      final figure = figures[index];
      if (figure is MCOImageV4RasterLayer) {
        writer.writeWriter(
          _encodeRasterLayerCommand(
            figure,
            document,
            xBits: xBits,
            yBits: yBits,
            compressionLevel: compressionLevel,
          ),
        );
        index++;
        continue;
      }
      currentStyle = _writeStyleChanges(
        writer,
        currentStyle,
        figure.style,
        document,
        profileColorBits,
        scalarBits,
      );

      ({
        List<MCOImageV4Figure> figures,
        _V4BitWriter writer,
      })?
      bestRepeatColorRun;
      void considerRepeatColorRun(bool strokeColorRun) {
        final run = _collectRepeatColorRun(
          figures,
          index,
          history,
          currentStyle,
          strokeColorRun: strokeColorRun,
        );
        if (run.length < 2) return;
        final encoded = _encodeBestRepeatColorRun(
          run,
          _translationFrom(history.last, run.first)!,
          currentStyle,
          document,
          profileColorBits,
          strokeColorRun: strokeColorRun,
          xBits: xBits,
          yBits: yBits,
        );
        final fallback = _encodeFigureSequence(
          run,
          history,
          currentStyle,
          document,
          profileColorBits,
          scalarBits,
          width: document.width,
          height: document.height,
          xBits: xBits,
          yBits: yBits,
        );
        if (encoded.bitLength >= fallback.bitLength) return;
        final previous = bestRepeatColorRun;
        if (previous == null || encoded.bitLength < previous.writer.bitLength) {
          bestRepeatColorRun = (
            figures: run,
            writer: encoded,
          );
        }
      }

      considerRepeatColorRun(false);
      considerRepeatColorRun(true);
      final repeatColorRun = bestRepeatColorRun;
      if (repeatColorRun != null) {
        writer.writeWriter(repeatColorRun.writer);
        history.addAll(repeatColorRun.figures);
        currentStyle = repeatColorRun.figures.last.style;
        index += repeatColorRun.figures.length;
        continue;
      }

      final dotRun = figure is MCOImageV4Dot
          ? _collectDotRun(figures, index)
          : const <MCOImageV4Dot>[];
      if (dotRun.length >= 2) {
        final dotRunEncoded = _encodeBestDotRun(
          dotRun,
          width: document.width,
          height: document.height,
          xBits: xBits,
          yBits: yBits,
        );
        final fallback = _encodeDotRunAsFigures(
          dotRun,
          history,
          currentStyle: currentStyle,
          document: document,
          profileColorBits: profileColorBits,
          width: document.width,
          height: document.height,
          xBits: xBits,
          yBits: yBits,
          scalarBits: scalarBits,
        );
        writer.writeWriter(
          dotRunEncoded.bitLength < fallback.bitLength
              ? dotRunEncoded
              : fallback,
        );
        history.addAll(dotRun);
        index += dotRun.length;
        continue;
      }

      writer.writeWriter(
        _encodeBestFigureCommand(
          figure,
          history,
          currentStyle: currentStyle,
          document: document,
          profileColorBits: profileColorBits,
          width: document.width,
          height: document.height,
          xBits: xBits,
          yBits: yBits,
          scalarBits: scalarBits,
        ),
      );
      history.add(figure);
      index++;
    }
    writer.writeBits(_opEnd, _opBits);
    return writer.toBytes();
  }

  _DecodedV4CanonicalDocument _decodeCanonicalDocumentPrefix(Uint8List bytes) {
    final reader = _V4BitReader(bytes);
    final document = _readCanonicalDocument(reader);
    reader.finishByte();
    return _DecodedV4CanonicalDocument(
      document: document,
      canonicalDocument: Uint8List.sublistView(bytes, 0, reader.byteOffset),
    );
  }

  MCOImageV4Document _readCanonicalDocument(_V4BitReader reader) {
    final modeIndex = reader.readBits(_modeBits);
    final mode = MCOImageV4Mode.values[modeIndex];
    if (!_isObjectMode(mode)) {
      throw const MCOImageUnsupportedFormatException(
        'Unsupported MCOimg v4 mode',
        receivedVersion: version,
        currentMaxSupportedVersion: version,
      );
    }
    final profileIndex = reader.readBits(4);
    if (profileIndex >= PaletteProfile.values.length) {
      throw const MCOImageInvalidPayloadException(
        'Invalid v4 palette profile',
      );
    }
    final paletteProfile = PaletteProfile.values[profileIndex];
    final dimensions = _readDimensions(reader);
    final width = dimensions.width;
    final height = dimensions.height;
    final profileColorBits = _profileColorBits(paletteProfile);
    final palette = <int>[];
    final paletteIndexByColor = <int, int>{};
    int localColorFromProfileColor(int color) {
      final existing = paletteIndexByColor[color];
      if (existing != null) return existing;
      final index = palette.length;
      palette.add(color);
      paletteIndexByColor[color] = index;
      return index;
    }

    int localColorFromProfileRef() {
      final ref = reader.readBits(profileColorBits);
      final color = _colorFromProfileRef(paletteProfile, ref, payload: true);
      return localColorFromProfileColor(color);
    }

    int? optionalLocalColorFromProfileRef() =>
        reader.readBit() ? localColorFromProfileRef() : null;

    final xBits = _coordinateBits(width);
    final yBits = _coordinateBits(height);
    final scalarBits = _scalarBits(width, height);

    final defaultBackgroundColor = localColorFromProfileColor(
      MCOImagePalette.whiteIndexFor(paletteProfile),
    );
    final backgroundColor = reader.readBit()
        ? optionalLocalColorFromProfileRef()
        : defaultBackgroundColor;
    var currentStyle = MCOImageV4Style(
      strokeColor: localColorFromProfileColor(
        MCOImagePalette.blackIndexFor(paletteProfile),
      ),
    );
    final initialStyle = currentStyle;
    final figures = <MCOImageV4Figure>[];
    final history = <MCOImageV4Figure>[];

    void addFigure(MCOImageV4Figure figure) {
      _validateFigure(
        figure,
        width,
        height,
        paletteProfile,
        palette.length,
      );
      figures.add(figure);
      if (figure is! MCOImageV4RasterLayer) {
        history.add(figure);
      }
    }

    while (true) {
      final opcode = reader.readBits(_opBits);
      if (opcode == _opEnd) break;
      switch (opcode) {
        case _opSetFill:
          currentStyle = currentStyle.copyWith(
            fillColor: optionalLocalColorFromProfileRef(),
          );
        case _opSetStroke:
          currentStyle = currentStyle.copyWith(
            strokeColor: optionalLocalColorFromProfileRef(),
          );
        case _opSetStrokeWidth:
          currentStyle = currentStyle.copyWith(
            strokeWidth: reader.readBits(scalarBits) + 1,
          );
        case _opRepeatLast:
          if (history.isEmpty) {
            throw const MCOImageInvalidPayloadException(
              'MCOimg v4 repeat has no previous figure',
            );
          }
          final dx = _zigZagDecode(reader.readBits(xBits + 1));
          final dy = _zigZagDecode(reader.readBits(yBits + 1));
          final repeated = history.last
              .translated(dx, dy)
              .withStyle(currentStyle);
          addFigure(repeated);
        case _opRepeatShort:
          if (history.isEmpty) {
            throw const MCOImageInvalidPayloadException(
              'MCOimg v4 repeat has no previous figure',
            );
          }
          final shortBits = _deltaWidths[reader.readBits(2)];
          final dx = _zigZagDecode(reader.readBits(shortBits));
          final dy = _zigZagDecode(reader.readBits(shortBits));
          final repeated = history.last
              .translated(dx, dy)
              .withStyle(currentStyle);
          addFigure(repeated);
        case _opExtended:
          final result = _readExtendedCommand(
            reader,
            currentStyle,
            history: history,
            width: width,
            height: height,
            xBits: xBits,
            yBits: yBits,
            scalarBits: scalarBits,
            paletteProfile: paletteProfile,
            allowRasterLayer: mode == MCOImageV4Mode.mixed,
            localColorFromProfileRef: optionalLocalColorFromProfileRef,
          );
          currentStyle = result.style;
          for (final figure in result.figures) {
            addFigure(figure);
          }
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
          addFigure(figure);
      }
    }
    if (mode == MCOImageV4Mode.mixed && !_containsRasterLayer(figures)) {
      throw const MCOImageInvalidPayloadException(
        'MCOimg v4 mixed document has no raster layers',
      );
    }
    return MCOImageV4Document(
      mode: mode,
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
    MCOImageV4Document document,
    int profileColorBits,
    int scalarBits,
  ) {
    if (current == next) return current;
    final candidates = <_V4BitWriter>[
      _encodeSeparateStyleChanges(
        current,
        next,
        document,
        profileColorBits,
        scalarBits,
      ),
      _encodeCombinedStyleChange(
        current,
        next,
        document,
        profileColorBits,
        scalarBits,
      ),
    ];
    candidates.sort((a, b) => a.bitLength.compareTo(b.bitLength));
    writer.writeWriter(candidates.first);
    return next;
  }

  _V4BitWriter _encodeSeparateStyleChanges(
    MCOImageV4Style current,
    MCOImageV4Style next,
    MCOImageV4Document document,
    int profileColorBits,
    int scalarBits,
  ) {
    final writer = _V4BitWriter();
    if (current.fillColor != next.fillColor) {
      writer.writeBits(_opSetFill, _opBits);
      _writeOptionalColor(writer, document, next.fillColor, profileColorBits);
    }
    if (current.strokeColor != next.strokeColor) {
      writer.writeBits(_opSetStroke, _opBits);
      _writeOptionalColor(writer, document, next.strokeColor, profileColorBits);
    }
    if (current.strokeWidth != next.strokeWidth) {
      writer
        ..writeBits(_opSetStrokeWidth, _opBits)
        ..writeBits(next.strokeWidth - 1, scalarBits);
    }
    return writer;
  }

  _V4BitWriter _encodeCombinedStyleChange(
    MCOImageV4Style current,
    MCOImageV4Style next,
    MCOImageV4Document document,
    int profileColorBits,
    int scalarBits,
  ) {
    final fillChanged = current.fillColor != next.fillColor;
    final strokeChanged = current.strokeColor != next.strokeColor;
    final widthChanged = current.strokeWidth != next.strokeWidth;
    final mask =
        (fillChanged ? 0x01 : 0) |
        (strokeChanged ? 0x02 : 0) |
        (widthChanged ? 0x04 : 0);
    final writer = _V4BitWriter()
      ..writeBits(_opExtended, _opBits)
      ..writeBits(_extSetStyle, _extBits)
      ..writeBits(mask, 3);
    if (fillChanged) {
      _writeOptionalColor(writer, document, next.fillColor, profileColorBits);
    }
    if (strokeChanged) {
      _writeOptionalColor(writer, document, next.strokeColor, profileColorBits);
    }
    if (widthChanged) {
      writer.writeBits(next.strokeWidth - 1, scalarBits);
    }
    return writer;
  }

  _V4BitWriter _encodeBestFigureCommand(
    MCOImageV4Figure figure,
    List<MCOImageV4Figure> history, {
    required MCOImageV4Style currentStyle,
    required MCOImageV4Document document,
    required int profileColorBits,
    required int width,
    required int height,
    required int xBits,
    required int yBits,
    required int scalarBits,
  }) {
    final candidates = <_V4BitWriter>[
      _encodeFigureCommand(
        figure,
        currentStyle: currentStyle,
        document: document,
        profileColorBits: profileColorBits,
        width: width,
        height: height,
        xBits: xBits,
        yBits: yBits,
        scalarBits: scalarBits,
      ),
    ];
    final maxDistance = math.min(history.length, _repeatBackWindow);
    for (var distance = 1; distance <= maxDistance; distance++) {
      final previous = history[history.length - distance];
      final repeat = _translationFrom(previous, figure);
      if (repeat == null) continue;
      final encoded = distance == 1
          ? _encodeBestRepeatCommand(
              repeat,
              width: width,
              height: height,
              xBits: xBits,
              yBits: yBits,
            )
          : _encodeBestRepeatBackCommand(
              distance,
              repeat,
              width: width,
              height: height,
              xBits: xBits,
              yBits: yBits,
            );
      if (encoded != null) candidates.add(encoded);
    }
    candidates.sort((a, b) => a.bitLength.compareTo(b.bitLength));
    return candidates.first;
  }

  List<MCOImageV4Dot> _collectDotRun(
    List<MCOImageV4Figure> figures,
    int start,
  ) {
    final first = figures[start];
    if (first is! MCOImageV4Dot) return const <MCOImageV4Dot>[];
    final result = <MCOImageV4Dot>[first];
    for (var index = start + 1; index < figures.length; index++) {
      final next = figures[index];
      if (next is! MCOImageV4Dot || next.style != first.style) break;
      result.add(next);
    }
    return result;
  }

  List<MCOImageV4Figure> _collectRepeatColorRun(
    List<MCOImageV4Figure> figures,
    int start,
    List<MCOImageV4Figure> history,
    MCOImageV4Style baseStyle, {
    required bool strokeColorRun,
  }) {
    if (history.isEmpty || start >= figures.length) {
      return const <MCOImageV4Figure>[];
    }
    final first = figures[start];
    if (!_canUseRepeatColorStyle(
      first.style,
      baseStyle,
      strokeColorRun: strokeColorRun,
    )) {
      return const <MCOImageV4Figure>[];
    }
    final delta = _translationFrom(history.last, first);
    if (delta == null) return const <MCOImageV4Figure>[];

    final result = <MCOImageV4Figure>[first];
    var previous = first;
    for (var index = start + 1; index < figures.length; index++) {
      final next = figures[index];
      if (!_canUseRepeatColorStyle(
        next.style,
        baseStyle,
        strokeColorRun: strokeColorRun,
      )) {
        break;
      }
      final nextDelta = _translationFrom(previous, next);
      if (nextDelta != delta) break;
      result.add(next);
      previous = next;
    }
    return result;
  }

  bool _canUseRepeatColorStyle(
    MCOImageV4Style style,
    MCOImageV4Style baseStyle, {
    required bool strokeColorRun,
  }) {
    if (style.strokeWidth != baseStyle.strokeWidth) return false;
    return strokeColorRun
        ? style.fillColor == baseStyle.fillColor
        : style.strokeColor == baseStyle.strokeColor;
  }

  _V4BitWriter _encodeFigureSequence(
    List<MCOImageV4Figure> figures,
    List<MCOImageV4Figure> history,
    MCOImageV4Style currentStyle,
    MCOImageV4Document document,
    int profileColorBits,
    int scalarBits, {
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    final writer = _V4BitWriter();
    final localHistory = <MCOImageV4Figure>[...history];
    var style = currentStyle;
    for (final figure in figures) {
      style = _writeStyleChanges(
        writer,
        style,
        figure.style,
        document,
        profileColorBits,
        scalarBits,
      );
      writer.writeWriter(
        _encodeBestFigureCommand(
          figure,
          localHistory,
          currentStyle: style,
          document: document,
          profileColorBits: profileColorBits,
          width: width,
          height: height,
          xBits: xBits,
          yBits: yBits,
          scalarBits: scalarBits,
        ),
      );
      localHistory.add(figure);
    }
    return writer;
  }

  _V4BitWriter _encodeFigureCommand(
    MCOImageV4Figure figure, {
    required MCOImageV4Style currentStyle,
    required MCOImageV4Document document,
    required int profileColorBits,
    required int width,
    required int height,
    required int xBits,
    required int yBits,
    required int scalarBits,
  }) {
    if (figure is MCOImageV4Path) {
      return _encodeBestPath(
        figure,
        width: width,
        height: height,
        xBits: xBits,
        yBits: yBits,
      );
    }
    if (figure is MCOImageV4Group) {
      return _encodeGroupCommand(
        figure,
        currentStyle: currentStyle,
        document: document,
        profileColorBits: profileColorBits,
        width: width,
        height: height,
        xBits: xBits,
        yBits: yBits,
        scalarBits: scalarBits,
      );
    }
    final candidates = <_V4BitWriter>[
      _encodeFullFigureCommand(
        figure,
        width: width,
        height: height,
        xBits: xBits,
        yBits: yBits,
        scalarBits: scalarBits,
      ),
    ];
    switch (figure) {
      case MCOImageV4Line(:final start, :final end):
        if (start.x == end.x || start.y == end.y) {
          candidates.addAll(
            _encodeAxisLineCandidates(
              figure,
              width: width,
              height: height,
              xBits: xBits,
              yBits: yBits,
            ),
          );
        }
        candidates.addAll(
          _encodePointDeltaFigureCandidates(
            _extLineDelta,
            <MCOImageV4Point>[start, end],
            width: width,
            height: height,
            xBits: xBits,
            yBits: yBits,
          ),
        );
      case MCOImageV4AreaFigure(
        :final first,
        :final second,
        :final third,
      ):
        candidates.addAll(
          _encodePointDeltaFigureCandidates(
            _extAreaDelta,
            <MCOImageV4Point>[first, second, third],
            width: width,
            height: height,
            xBits: xBits,
            yBits: yBits,
            extraHeader: figure is MCOImageV4Ellipse ? 1 : 0,
            extraHeaderBits: 1,
          ),
        );
        if (figure is MCOImageV4Ellipse) {
          final depth = _ellipseDepthEncoding(figure);
          if (depth != null) {
            candidates.add(
              _encodeEllipseDepth(
                figure,
                negative: depth.negative,
                magnitude: depth.magnitude,
                width: width,
                height: height,
                xBits: xBits,
                yBits: yBits,
                scalarBits: scalarBits,
              ),
            );
          }
        }
      case MCOImageV4Wave(:final start, :final end, :final depth, :final closed):
        candidates.addAll(
          _encodePointDeltaFigureCandidates(
            _extWaveDelta,
            <MCOImageV4Point>[start, end],
            width: width,
            height: height,
            xBits: xBits,
            yBits: yBits,
            extraHeader:
                (closed ? 1 : 0) |
                ((depth < 0 ? 1 : 0) << 1) |
                ((depth.abs() - 1) << 2),
            extraHeaderBits: 2 + scalarBits,
          ),
        );
      case MCOImageV4Dot():
        break;
      case MCOImageV4Path():
        throw const MCOImageInvalidInputException('Unexpected v4 path');
      case MCOImageV4Group():
        throw const MCOImageInvalidInputException('Unexpected v4 group');
      case MCOImageV4RasterLayer():
        throw const MCOImageInvalidInputException('Unexpected v4 raster layer');
    }
    candidates.sort((a, b) => a.bitLength.compareTo(b.bitLength));
    return candidates.first;
  }

  _V4BitWriter _encodeGroupCommand(
    MCOImageV4Group group, {
    required MCOImageV4Style currentStyle,
    required MCOImageV4Document document,
    required int profileColorBits,
    required int width,
    required int height,
    required int xBits,
    required int yBits,
    required int scalarBits,
  }) {
    final figures = group.figures.where((figure) => figure.visible).toList();
    if (figures.isEmpty) {
      throw const MCOImageInvalidInputException('MCOimg v4 group is empty');
    }
    return _V4BitWriter()
      ..writeBits(_opExtended, _opBits)
      ..writeBits(_extGroup, _extBits)
      ..writeCompactUint(figures.length - 1)
      ..writeWriter(
        _encodeFigureSequence(
          figures,
          const <MCOImageV4Figure>[],
          currentStyle,
          document,
          profileColorBits,
          scalarBits,
          width: width,
          height: height,
          xBits: xBits,
          yBits: yBits,
        ),
      );
  }

  _V4BitWriter _encodeRasterLayerCommand(
    MCOImageV4RasterLayer layer,
    MCOImageV4Document document, {
    required int xBits,
    required int yBits,
    required int compressionLevel,
  }) {
    final cacheKey = _V4RasterLayerEncodeCacheKey(
      paletteProfile: document.paletteProfile,
      compressionLevel: compressionLevel,
      width: layer.width,
      height: layer.height,
      transparentColor: layer.transparentColor,
      pixels: layer.pixels,
    );
    final cached = _rasterLayerEncodeCache[cacheKey] ??
        _encodeRasterLayerPayload(layer, document, compressionLevel, cacheKey);
    final writer = _V4BitWriter()
      ..writeBits(_opExtended, _opBits)
      ..writeBits(_extRasterLayer, _extBits);
    _writePoint(
      writer,
      MCOImageV4Point(layer.x, layer.y),
      xBits,
      yBits,
      width: document.width,
      height: document.height,
    );
    writer
      ..writeBits(cached.v3HeaderHigh, 4)
      ..writeCompactUint(cached.payload.length)
      ..writeBytes(cached.payload);
    return writer;
  }

  _V4RasterLayerEncodeCacheValue _encodeRasterLayerPayload(
    MCOImageV4RasterLayer layer,
    MCOImageV4Document document,
    int compressionLevel,
    _V4RasterLayerEncodeCacheKey cacheKey,
  ) {
    final image = MCOImage(
      width: layer.width,
      height: layer.height,
      paletteProfile: document.paletteProfile,
      pixels: layer.pixels,
      transparentColor: layer.transparentColor,
      encodingVersion: MCOImageEncodingVersion.v3,
    );
    final encoded = MCOImageV3Codec().encode(
      image,
      compressionLevel: compressionLevel,
      includePacketNonce: false,
    );
    final value = _V4RasterLayerEncodeCacheValue(
      v3HeaderHigh: encoded.body[0] >> 4,
      payload: Uint8List.sublistView(encoded.body, 1),
    );
    _rememberRasterLayerEncoding(cacheKey, value);
    return value;
  }

  static void _rememberRasterLayerEncoding(
    _V4RasterLayerEncodeCacheKey key,
    _V4RasterLayerEncodeCacheValue value,
  ) {
    _rasterLayerEncodeCache[key] = value;
    while (_rasterLayerEncodeCache.length > _rasterLayerEncodeCacheLimit) {
      _rasterLayerEncodeCache.remove(_rasterLayerEncodeCache.keys.first);
    }
  }

  _V4BitWriter _encodeFullFigureCommand(
    MCOImageV4Figure figure, {
    required int width,
    required int height,
    required int xBits,
    required int yBits,
    required int scalarBits,
  }) {
    final writer = _V4BitWriter();
    switch (figure) {
      case MCOImageV4Dot(:final point):
        writer.writeBits(_opDot, _opBits);
        _writePoint(writer, point, xBits, yBits, width: width, height: height);
      case MCOImageV4Line(:final start, :final end):
        writer.writeBits(_opLine, _opBits);
        _writePoint(writer, start, xBits, yBits, width: width, height: height);
        _writePoint(writer, end, xBits, yBits, width: width, height: height);
      case MCOImageV4Rect(
        :final first,
        :final second,
        :final third,
      ):
        final compact = _axisAlignedArea(figure);
        if (compact == null) {
          writer.writeBits(_opRect, _opBits);
          _writePoint(writer, first, xBits, yBits, width: width, height: height);
          _writePoint(writer, second, xBits, yBits, width: width, height: height);
          _writePoint(writer, third, xBits, yBits, width: width, height: height);
        } else {
          writer
            ..writeBits(_opRectAxisAligned, _opBits)
            ..writeBit(compact.swapped);
          _writePoint(
            writer,
            compact.first,
            xBits,
            yBits,
            width: width,
            height: height,
          );
          _writePoint(
            writer,
            compact.second,
            xBits,
            yBits,
            width: width,
            height: height,
          );
        }
      case MCOImageV4Ellipse(
        :final first,
        :final second,
        :final third,
      ):
        final compact = _axisAlignedArea(figure);
        if (compact == null) {
          writer.writeBits(_opEllipse, _opBits);
          _writePoint(writer, first, xBits, yBits, width: width, height: height);
          _writePoint(writer, second, xBits, yBits, width: width, height: height);
          _writePoint(writer, third, xBits, yBits, width: width, height: height);
        } else {
          writer
            ..writeBits(_opEllipseAxisAligned, _opBits)
            ..writeBit(compact.swapped);
          _writePoint(
            writer,
            compact.first,
            xBits,
            yBits,
            width: width,
            height: height,
          );
          _writePoint(
            writer,
            compact.second,
            xBits,
            yBits,
            width: width,
            height: height,
          );
        }
      case MCOImageV4Wave(
        :final start,
        :final end,
        :final depth,
        :final closed,
      ):
        writer
          ..writeBits(_opWave, _opBits)
          ..writeBit(closed);
        _writePoint(writer, start, xBits, yBits, width: width, height: height);
        _writePoint(writer, end, xBits, yBits, width: width, height: height);
        writer
          ..writeBit(depth < 0)
          ..writeBits(depth.abs() - 1, scalarBits);
      case MCOImageV4Path():
        throw const MCOImageInvalidInputException('Unexpected v4 path');
      case MCOImageV4Group():
        throw const MCOImageInvalidInputException('Unexpected v4 group');
      case MCOImageV4RasterLayer():
        throw const MCOImageInvalidInputException('Unexpected v4 raster layer');
    }
    return writer;
  }

  List<_V4BitWriter> _encodeAxisLineCandidates(
    MCOImageV4Line line, {
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    final vertical = line.start.x == line.end.x;
    final delta = vertical
        ? line.end.y - line.start.y
        : line.end.x - line.start.x;
    final result = <_V4BitWriter>[
      _encodeAxisLineAbsolute(
        line,
        vertical: vertical,
        width: width,
        height: height,
        xBits: xBits,
        yBits: yBits,
      ),
    ];
    for (var selector = 0; selector < _deltaWidths.length; selector++) {
      final shortBits = _deltaWidths[selector];
      if (!_canEncodeSignedShort(delta, shortBits)) continue;
      final writer = _V4BitWriter()
        ..writeBits(_opExtended, _opBits)
        ..writeBits(_extLineAxisDelta, _extBits)
        ..writeBit(vertical)
        ..writeBits(selector, 2);
      _writePoint(
        writer,
        line.start,
        xBits,
        yBits,
        width: width,
        height: height,
      );
      writer.writeBits(_zigZagEncode(delta), shortBits);
      result.add(writer);
    }
    return result;
  }

  _V4BitWriter _encodeAxisLineAbsolute(
    MCOImageV4Line line, {
    required bool vertical,
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    final writer = _V4BitWriter()
      ..writeBits(_opExtended, _opBits)
      ..writeBits(_extLineAxisAbsolute, _extBits)
      ..writeBit(vertical);
    if (vertical) {
      writer
        ..writeBits(_encodeCoordinate(line.start.x, width), xBits)
        ..writeBits(_encodeCoordinate(line.start.y, height), yBits)
        ..writeBits(_encodeCoordinate(line.end.y, height), yBits);
    } else {
      writer
        ..writeBits(_encodeCoordinate(line.start.y, height), yBits)
        ..writeBits(_encodeCoordinate(line.start.x, width), xBits)
        ..writeBits(_encodeCoordinate(line.end.x, width), xBits);
    }
    return writer;
  }

  _V4BitWriter _encodeEllipseDepth(
    MCOImageV4Ellipse ellipse, {
    required bool negative,
    required int magnitude,
    required int width,
    required int height,
    required int xBits,
    required int yBits,
    required int scalarBits,
  }) {
    final writer = _V4BitWriter()
      ..writeBits(_opExtended, _opBits)
      ..writeBits(_extEllipseDepth, _extBits);
    _writePoint(
      writer,
      ellipse.first,
      xBits,
      yBits,
      width: width,
      height: height,
    );
    _writePoint(
      writer,
      ellipse.second,
      xBits,
      yBits,
      width: width,
      height: height,
    );
    writer
      ..writeBit(negative)
      ..writeBits(magnitude - 1, scalarBits);
    return writer;
  }

  _V4BitWriter _encodeBestDotRun(
    List<MCOImageV4Dot> dots, {
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    final points = dots.map((dot) => dot.point).toList();
    final candidates = <_V4BitWriter>[
      _encodeAbsoluteDotRun(
        points,
        width: width,
        height: height,
        xBits: xBits,
        yBits: yBits,
      ),
      for (var selector = 0; selector < _deltaWidths.length; selector++)
        if (_canEncodePointDeltas(points, _deltaWidths[selector]))
          _encodeDeltaDotRun(
            points,
            selector: selector,
            shortBits: _deltaWidths[selector],
            width: width,
            height: height,
            xBits: xBits,
            yBits: yBits,
          ),
    ];
    candidates.sort((a, b) => a.bitLength.compareTo(b.bitLength));
    return candidates.first;
  }

  _V4BitWriter _encodeDotRunAsFigures(
    List<MCOImageV4Dot> dots,
    List<MCOImageV4Figure> history, {
    required MCOImageV4Style currentStyle,
    required MCOImageV4Document document,
    required int profileColorBits,
    required int width,
    required int height,
    required int xBits,
    required int yBits,
    required int scalarBits,
  }) {
    final writer = _V4BitWriter();
    final localHistory = <MCOImageV4Figure>[...history];
    for (final dot in dots) {
      writer.writeWriter(
        _encodeBestFigureCommand(
          dot,
          localHistory,
          currentStyle: currentStyle,
          document: document,
          profileColorBits: profileColorBits,
          width: width,
          height: height,
          xBits: xBits,
          yBits: yBits,
          scalarBits: scalarBits,
        ),
      );
      localHistory.add(dot);
    }
    return writer;
  }

  _V4BitWriter _encodeAbsoluteDotRun(
    List<MCOImageV4Point> points, {
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    final writer = _V4BitWriter()
      ..writeBits(_opExtended, _opBits)
      ..writeBits(_extDotRun, _extBits)
      ..writeBit(false)
      ..writeCompactUint(points.length - 2);
    for (final point in points) {
      _writePoint(writer, point, xBits, yBits, width: width, height: height);
    }
    return writer;
  }

  _V4BitWriter _encodeDeltaDotRun(
    List<MCOImageV4Point> points, {
    required int selector,
    required int shortBits,
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    final writer = _V4BitWriter()
      ..writeBits(_opExtended, _opBits)
      ..writeBits(_extDotRun, _extBits)
      ..writeBit(true)
      ..writeBits(selector, 2)
      ..writeCompactUint(points.length - 2);
    _writePoint(
      writer,
      points.first,
      xBits,
      yBits,
      width: width,
      height: height,
    );
    for (var i = 1; i < points.length; i++) {
      writer
        ..writeBits(_zigZagEncode(points[i].x - points[i - 1].x), shortBits)
        ..writeBits(_zigZagEncode(points[i].y - points[i - 1].y), shortBits);
    }
    return writer;
  }

  List<_V4BitWriter> _encodePointDeltaFigureCandidates(
    int subop,
    List<MCOImageV4Point> points, {
    required int width,
    required int height,
    required int xBits,
    required int yBits,
    int extraHeader = 0,
    int extraHeaderBits = 0,
  }) {
    final result = <_V4BitWriter>[];
    for (var selector = 0; selector < _deltaWidths.length; selector++) {
      final shortBits = _deltaWidths[selector];
      if (!_canEncodePointDeltas(points, shortBits)) continue;
      final writer = _V4BitWriter()
        ..writeBits(_opExtended, _opBits)
        ..writeBits(subop, _extBits);
      if (extraHeaderBits > 0) {
        writer.writeBits(extraHeader, extraHeaderBits);
      }
      writer.writeBits(selector, 2);
      _writePoint(
        writer,
        points.first,
        xBits,
        yBits,
        width: width,
        height: height,
      );
      for (var i = 1; i < points.length; i++) {
        writer
          ..writeBits(_zigZagEncode(points[i].x - points[i - 1].x), shortBits)
          ..writeBits(_zigZagEncode(points[i].y - points[i - 1].y), shortBits);
      }
      result.add(writer);
    }
    return result;
  }

  _V4BitWriter _encodeBestPath(
    MCOImageV4Path path, {
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    final candidates = <_V4BitWriter>[
      _encodeAbsolutePath(
        path,
        width: width,
        height: height,
        xBits: xBits,
        yBits: yBits,
      ),
      ..._encodeOrthogonalPathCandidates(
        path,
        width: width,
        height: height,
        xBits: xBits,
        yBits: yBits,
      ),
      _encodeBoundsPath(
        path,
        width: width,
        height: height,
        xBits: xBits,
        yBits: yBits,
      ),
      ..._encodeBoundsDeltaPathCandidates(
        path,
        width: width,
        height: height,
        xBits: xBits,
        yBits: yBits,
      ),
      for (var selector = 0; selector < _deltaWidths.length; selector++)
        _encodeDeltaPath(
          path,
          selector: selector,
          shortBits: _deltaWidths[selector],
          width: width,
          height: height,
          xBits: xBits,
          yBits: yBits,
        ),
    ];
    candidates.sort((a, b) => a.bitLength.compareTo(b.bitLength));
    return candidates.first;
  }

  _V4BitWriter _encodeAbsolutePath(
    MCOImageV4Path path, {
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    final minimum = path.closed ? 3 : 2;
    final writer = _V4BitWriter()
      ..writeBits(_opPathAbsolute, _opBits)
      ..writeBit(path.closed)
      ..writeCompactUint(path.points.length - minimum);
    for (final point in path.points) {
      _writePoint(writer, point, xBits, yBits, width: width, height: height);
    }
    return writer;
  }

  _V4BitWriter _encodeDeltaPath(
    MCOImageV4Path path, {
    required int selector,
    required int shortBits,
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    final minimum = path.closed ? 3 : 2;
    final writer = _V4BitWriter()
      ..writeBits(_opPathDelta, _opBits)
      ..writeBit(path.closed)
      ..writeBits(selector, 2)
      ..writeCompactUint(path.points.length - minimum);
    _writePoint(
      writer,
      path.points.first,
      xBits,
      yBits,
      width: width,
      height: height,
    );
    for (var i = 1; i < path.points.length; i++) {
      final previous = path.points[i - 1];
      final current = path.points[i];
      _writePathComponent(
        writer,
        current.x,
        previous.x,
        shortBits,
        xBits,
        width,
      );
      _writePathComponent(
        writer,
        current.y,
        previous.y,
        shortBits,
        yBits,
        height,
      );
    }
    return writer;
  }

  List<_V4BitWriter> _encodeOrthogonalPathCandidates(
    MCOImageV4Path path, {
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    if (path.points.length < 2) return const <_V4BitWriter>[];
    final deltas = <int>[];
    final vertical = <bool>[];
    for (var i = 1; i < path.points.length; i++) {
      final previous = path.points[i - 1];
      final current = path.points[i];
      final dx = current.x - previous.x;
      final dy = current.y - previous.y;
      if (dx != 0 && dy != 0) return const <_V4BitWriter>[];
      vertical.add(dx == 0);
      deltas.add(dx == 0 ? dy : dx);
    }

    final minimum = path.closed ? 3 : 2;
    final result = <_V4BitWriter>[];
    for (var selector = 0; selector < _deltaWidths.length; selector++) {
      final shortBits = _deltaWidths[selector];
      if (deltas.any((delta) => !_canEncodeSignedShort(delta, shortBits))) {
        continue;
      }
      final writer = _V4BitWriter()
        ..writeBits(_opExtended, _opBits)
        ..writeBits(_extPathOrthogonal, _extBits)
        ..writeBit(path.closed)
        ..writeBits(selector, 2)
        ..writeCompactUint(path.points.length - minimum);
      _writePoint(
        writer,
        path.points.first,
        xBits,
        yBits,
        width: width,
        height: height,
      );
      for (var i = 0; i < deltas.length; i++) {
        writer
          ..writeBit(vertical[i])
          ..writeBits(_zigZagEncode(deltas[i]), shortBits);
      }
      result.add(writer);
    }
    return result;
  }

  _V4BitWriter _encodeBoundsPath(
    MCOImageV4Path path, {
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    final bounds = _pathBounds(path.points);
    final boundsWidth = bounds.width;
    final boundsHeight = bounds.height;
    final localXBits = _localCoordinateBits(boundsWidth);
    final localYBits = _localCoordinateBits(boundsHeight);
    final minimum = path.closed ? 3 : 2;
    final writer = _V4BitWriter()
      ..writeBits(_opExtended, _opBits)
      ..writeBits(_extPathBounds, _extBits)
      ..writeBit(path.closed)
      ..writeCompactUint(path.points.length - minimum);
    _writePoint(
      writer,
      MCOImageV4Point(bounds.x, bounds.y),
      xBits,
      yBits,
      width: width,
      height: height,
    );
    writer
      ..writeBits(boundsWidth - 1, xBits)
      ..writeBits(boundsHeight - 1, yBits);
    for (final point in path.points) {
      writer
        ..writeBits(point.x - bounds.x, localXBits)
        ..writeBits(point.y - bounds.y, localYBits);
    }
    return writer;
  }

  List<_V4BitWriter> _encodeBoundsDeltaPathCandidates(
    MCOImageV4Path path, {
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    final bounds = _pathBounds(path.points);
    final localPoints = path.points
        .map((point) => MCOImageV4Point(point.x - bounds.x, point.y - bounds.y))
        .toList();
    final localXBits = _localCoordinateBits(bounds.width);
    final localYBits = _localCoordinateBits(bounds.height);
    final minimum = path.closed ? 3 : 2;
    final result = <_V4BitWriter>[];
    for (var selector = 0; selector < _deltaWidths.length; selector++) {
      final shortBits = _deltaWidths[selector];
      if (!_canEncodePointDeltas(localPoints, shortBits)) continue;
      final writer = _V4BitWriter()
        ..writeBits(_opExtended, _opBits)
        ..writeBits(_extPathBoundsDelta, _extBits)
        ..writeBit(path.closed)
        ..writeBits(selector, 2)
        ..writeCompactUint(path.points.length - minimum);
      _writePoint(
        writer,
        MCOImageV4Point(bounds.x, bounds.y),
        xBits,
        yBits,
        width: width,
        height: height,
      );
      writer
        ..writeBits(bounds.width - 1, xBits)
        ..writeBits(bounds.height - 1, yBits)
        ..writeBits(localPoints.first.x, localXBits)
        ..writeBits(localPoints.first.y, localYBits);
      for (var i = 1; i < localPoints.length; i++) {
        writer
          ..writeBits(
            _zigZagEncode(localPoints[i].x - localPoints[i - 1].x),
            shortBits,
          )
          ..writeBits(
            _zigZagEncode(localPoints[i].y - localPoints[i - 1].y),
            shortBits,
          );
      }
      result.add(writer);
    }
    return result;
  }

  void _writePathComponent(
    _V4BitWriter writer,
    int current,
    int previous,
    int shortBits,
    int absoluteBits,
    int axisSize,
  ) {
    final code = _zigZagEncode(current - previous);
    if (code < (1 << shortBits)) {
      writer
        ..writeBit(false)
        ..writeBits(code, shortBits);
    } else {
      writer
        ..writeBit(true)
        ..writeBits(_encodeCoordinate(current, axisSize), absoluteBits);
    }
  }

  _V4BitWriter? _encodeBestRepeatCommand(
    MCOImageV4Point delta, {
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    if (delta.x.abs() > _coordinateValueCount(width) - 1 ||
        delta.y.abs() > _coordinateValueCount(height) - 1) {
      return null;
    }
    final candidates = <_V4BitWriter>[
      _encodeFullRepeatCommand(delta, xBits: xBits, yBits: yBits),
      for (var selector = 0; selector < _deltaWidths.length; selector++)
        if (_canEncodeShortRepeat(delta, _deltaWidths[selector]))
          _encodeShortRepeatCommand(
            delta,
            selector: selector,
            shortBits: _deltaWidths[selector],
          ),
    ];
    candidates.sort((a, b) => a.bitLength.compareTo(b.bitLength));
    return candidates.first;
  }

  _V4BitWriter _encodeFullRepeatCommand(
    MCOImageV4Point delta, {
    required int xBits,
    required int yBits,
  }) {
    return _V4BitWriter()
      ..writeBits(_opRepeatLast, _opBits)
      ..writeBits(_zigZagEncode(delta.x), xBits + 1)
      ..writeBits(_zigZagEncode(delta.y), yBits + 1);
  }

  _V4BitWriter? _encodeBestRepeatBackCommand(
    int distance,
    MCOImageV4Point delta, {
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    if (distance < 2 || distance > _repeatBackWindow) return null;
    if (delta.x.abs() > _coordinateValueCount(width) - 1 ||
        delta.y.abs() > _coordinateValueCount(height) - 1) {
      return null;
    }
    final candidates = <_V4BitWriter>[
      _encodeFullRepeatBackCommand(distance, delta, xBits: xBits, yBits: yBits),
      for (var selector = 0; selector < _deltaWidths.length; selector++)
        if (_canEncodeShortRepeat(delta, _deltaWidths[selector]))
          _encodeShortRepeatBackCommand(
            distance,
            delta,
            selector: selector,
            shortBits: _deltaWidths[selector],
          ),
    ];
    candidates.sort((a, b) => a.bitLength.compareTo(b.bitLength));
    return candidates.first;
  }

  _V4BitWriter _encodeFullRepeatBackCommand(
    int distance,
    MCOImageV4Point delta, {
    required int xBits,
    required int yBits,
  }) {
    return _V4BitWriter()
      ..writeBits(_opExtended, _opBits)
      ..writeBits(_extRepeatBack, _extBits)
      ..writeBits(distance - 1, 3)
      ..writeBit(false)
      ..writeBits(_zigZagEncode(delta.x), xBits + 1)
      ..writeBits(_zigZagEncode(delta.y), yBits + 1);
  }

  _V4BitWriter _encodeShortRepeatBackCommand(
    int distance,
    MCOImageV4Point delta, {
    required int selector,
    required int shortBits,
  }) {
    return _V4BitWriter()
      ..writeBits(_opExtended, _opBits)
      ..writeBits(_extRepeatBack, _extBits)
      ..writeBits(distance - 1, 3)
      ..writeBit(true)
      ..writeBits(selector, 2)
      ..writeBits(_zigZagEncode(delta.x), shortBits)
      ..writeBits(_zigZagEncode(delta.y), shortBits);
  }

  bool _canEncodeShortRepeat(MCOImageV4Point delta, int shortBits) =>
      _zigZagEncode(delta.x) < (1 << shortBits) &&
      _zigZagEncode(delta.y) < (1 << shortBits);

  bool _canEncodePointDeltas(List<MCOImageV4Point> points, int shortBits) {
    for (var i = 1; i < points.length; i++) {
      if (!_canEncodeSignedShort(points[i].x - points[i - 1].x, shortBits) ||
          !_canEncodeSignedShort(points[i].y - points[i - 1].y, shortBits)) {
        return false;
      }
    }
    return true;
  }

  bool _canEncodeSignedShort(int value, int shortBits) =>
      _zigZagEncode(value) < (1 << shortBits);

  _V4BitWriter _encodeBestRepeatColorRun(
    List<MCOImageV4Figure> figures,
    MCOImageV4Point delta,
    MCOImageV4Style baseStyle,
    MCOImageV4Document document,
    int profileColorBits, {
    required bool strokeColorRun,
    required int xBits,
    required int yBits,
  }) {
    final candidates = <_V4BitWriter>[
      _encodeRepeatColorRun(
        figures,
        delta,
        baseStyle,
        document,
        profileColorBits,
        strokeColorRun: strokeColorRun,
        shortSelector: null,
        xBits: xBits,
        yBits: yBits,
      ),
      for (var selector = 0; selector < _deltaWidths.length; selector++)
        if (_canEncodeShortRepeat(delta, _deltaWidths[selector]))
          _encodeRepeatColorRun(
            figures,
            delta,
            baseStyle,
            document,
            profileColorBits,
            strokeColorRun: strokeColorRun,
            shortSelector: selector,
            xBits: xBits,
            yBits: yBits,
          ),
    ];
    candidates.sort((a, b) => a.bitLength.compareTo(b.bitLength));
    return candidates.first;
  }

  _V4BitWriter _encodeRepeatColorRun(
    List<MCOImageV4Figure> figures,
    MCOImageV4Point delta,
    MCOImageV4Style baseStyle,
    MCOImageV4Document document,
    int profileColorBits, {
    required bool strokeColorRun,
    required int? shortSelector,
    required int xBits,
    required int yBits,
  }) {
    int? color(MCOImageV4Style style) =>
        strokeColorRun ? style.strokeColor : style.fillColor;
    final baseColor = color(baseStyle);
    final hasColorChanges = figures
        .skip(1)
        .any((figure) => color(figure.style) != baseColor);
    final writer = _V4BitWriter()
      ..writeBits(_opExtended, _opBits)
      ..writeBits(_extRepeatColorRun, _extBits)
      ..writeBit(strokeColorRun)
      ..writeBit(shortSelector != null);
    if (shortSelector == null) {
      writer
        ..writeBits(_zigZagEncode(delta.x), xBits + 1)
        ..writeBits(_zigZagEncode(delta.y), yBits + 1);
    } else {
      final shortBits = _deltaWidths[shortSelector];
      writer
        ..writeBits(shortSelector, 2)
        ..writeBits(_zigZagEncode(delta.x), shortBits)
        ..writeBits(_zigZagEncode(delta.y), shortBits);
    }
    writer
      ..writeCompactUint(figures.length - 2)
      ..writeBit(hasColorChanges);
    if (hasColorChanges) {
      for (final figure in figures.skip(1)) {
        _writeOptionalColor(
          writer,
          document,
          color(figure.style),
          profileColorBits,
        );
      }
    }
    return writer;
  }

  _V4BitWriter _encodeShortRepeatCommand(
    MCOImageV4Point delta, {
    required int selector,
    required int shortBits,
  }) {
    return _V4BitWriter()
      ..writeBits(_opRepeatShort, _opBits)
      ..writeBits(selector, 2)
      ..writeBits(_zigZagEncode(delta.x), shortBits)
      ..writeBits(_zigZagEncode(delta.y), shortBits);
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
      case _opRectAxisAligned:
      case _opEllipseAxisAligned:
        final swapped = reader.readBit();
        final first = _readPoint(reader, width, height, xBits, yBits);
        final second = _readPoint(reader, width, height, xBits, yBits);
        final third = swapped
            ? MCOImageV4Point(second.x, first.y)
            : MCOImageV4Point(first.x, second.y);
        return opcode == _opRectAxisAligned
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

  _V4ExtendedReadResult _readExtendedCommand(
    _V4BitReader reader,
    MCOImageV4Style style, {
    required List<MCOImageV4Figure> history,
    required int width,
    required int height,
    required int xBits,
    required int yBits,
    required int scalarBits,
    required PaletteProfile paletteProfile,
    required bool allowRasterLayer,
    required int? Function() localColorFromProfileRef,
  }) {
    _V4ExtendedReadResult one(MCOImageV4Figure figure) =>
        _V4ExtendedReadResult(
          style: style,
          figures: <MCOImageV4Figure>[figure],
        );

    final subop = reader.readBits(_extBits);
    switch (subop) {
      case _extSetStyle:
        final mask = reader.readBits(3);
        if (mask == 0) {
          throw const MCOImageInvalidPayloadException(
            'Empty MCOimg v4 style change',
          );
        }
        var next = style;
        if ((mask & 0x01) != 0) {
          next = next.copyWith(fillColor: localColorFromProfileRef());
        }
        if ((mask & 0x02) != 0) {
          next = next.copyWith(strokeColor: localColorFromProfileRef());
        }
        if ((mask & 0x04) != 0) {
          next = next.copyWith(strokeWidth: reader.readBits(scalarBits) + 1);
        }
        return _V4ExtendedReadResult(
          style: next,
          figures: const <MCOImageV4Figure>[],
        );
      case _extLineDelta:
        final points = _readPointDeltaSequence(
          reader,
          count: 2,
          width: width,
          height: height,
          xBits: xBits,
          yBits: yBits,
        );
        return one(
          MCOImageV4Line(
            start: points[0],
            end: points[1],
            style: style,
          ),
        );
      case _extLineAxisDelta:
        final vertical = reader.readBit();
        final shortBits = _deltaWidths[reader.readBits(2)];
        final start = _readPoint(reader, width, height, xBits, yBits);
        final delta = _zigZagDecode(reader.readBits(shortBits));
        final end = vertical
            ? MCOImageV4Point(start.x, start.y + delta)
            : MCOImageV4Point(start.x + delta, start.y);
        _validatePointInPayload(end, width, height);
        return one(MCOImageV4Line(start: start, end: end, style: style));
      case _extLineAxisAbsolute:
        final vertical = reader.readBit();
        if (vertical) {
          final x = _readCoordinate(reader, xBits, width);
          final startY = _readCoordinate(reader, yBits, height);
          final endY = _readCoordinate(reader, yBits, height);
          return one(
            MCOImageV4Line(
              start: MCOImageV4Point(x, startY),
              end: MCOImageV4Point(x, endY),
              style: style,
            ),
          );
        }
        final y = _readCoordinate(reader, yBits, height);
        final startX = _readCoordinate(reader, xBits, width);
        final endX = _readCoordinate(reader, xBits, width);
        return one(
          MCOImageV4Line(
            start: MCOImageV4Point(startX, y),
            end: MCOImageV4Point(endX, y),
            style: style,
          ),
        );
      case _extAreaDelta:
        final isEllipse = reader.readBit();
        final points = _readPointDeltaSequence(
          reader,
          count: 3,
          width: width,
          height: height,
          xBits: xBits,
          yBits: yBits,
        );
        return one(
          isEllipse
              ? MCOImageV4Ellipse(
                first: points[0],
                second: points[1],
                third: points[2],
                style: style,
              )
              : MCOImageV4Rect(
                first: points[0],
                second: points[1],
                third: points[2],
                style: style,
              ),
        );
      case _extWaveDelta:
        final closed = reader.readBit();
        final negative = reader.readBit();
        final magnitude = reader.readBits(scalarBits) + 1;
        final points = _readPointDeltaSequence(
          reader,
          count: 2,
          width: width,
          height: height,
          xBits: xBits,
          yBits: yBits,
        );
        return one(
          MCOImageV4Wave(
            start: points[0],
            end: points[1],
            depth: negative ? -magnitude : magnitude,
            closed: closed,
            style: style,
          ),
        );
      case _extEllipseDepth:
        final first = _readPoint(reader, width, height, xBits, yBits);
        final second = _readPoint(reader, width, height, xBits, yBits);
        final negative = reader.readBit();
        final magnitude = reader.readBits(scalarBits) + 1;
        final third = _ellipseThirdFromDepth(
          first,
          second,
          negative ? -magnitude : magnitude,
        );
        if (third == null) {
          throw const MCOImageInvalidPayloadException(
            'Invalid MCOimg v4 ellipse depth',
          );
        }
        return one(
          MCOImageV4Ellipse(
            first: first,
            second: second,
            third: third,
            style: style,
          ),
        );
      case _extRepeatBack:
        final distance = reader.readBits(3) + 1;
        if (distance < 2 || distance > history.length) {
          throw const MCOImageInvalidPayloadException(
            'MCOimg v4 repeat back has no matching figure',
          );
        }
        final short = reader.readBit();
        late final int dx;
        late final int dy;
        if (short) {
          final shortBits = _deltaWidths[reader.readBits(2)];
          dx = _zigZagDecode(reader.readBits(shortBits));
          dy = _zigZagDecode(reader.readBits(shortBits));
        } else {
          dx = _zigZagDecode(reader.readBits(xBits + 1));
          dy = _zigZagDecode(reader.readBits(yBits + 1));
        }
        return one(
          history[history.length - distance]
              .translated(dx, dy)
              .withStyle(style),
        );
      case _extRepeatColorRun:
        if (history.isEmpty) {
          throw const MCOImageInvalidPayloadException(
            'MCOimg v4 repeat color run has no previous figure',
          );
        }
        final strokeColorRun = reader.readBit();
        final short = reader.readBit();
        late final int dx;
        late final int dy;
        if (short) {
          final shortBits = _deltaWidths[reader.readBits(2)];
          dx = _zigZagDecode(reader.readBits(shortBits));
          dy = _zigZagDecode(reader.readBits(shortBits));
        } else {
          dx = _zigZagDecode(reader.readBits(xBits + 1));
          dy = _zigZagDecode(reader.readBits(yBits + 1));
        }
        final count = reader.readCompactUint() + 2;
        final hasColorChanges = reader.readBit();
        final figures = <MCOImageV4Figure>[];
        var previous = history.last;
        var currentRunStyle = style;
        for (var index = 0; index < count; index++) {
          if (index > 0 && hasColorChanges) {
            final color = localColorFromProfileRef();
            currentRunStyle = strokeColorRun
                ? style.copyWith(strokeColor: color)
                : style.copyWith(fillColor: color);
          }
          final figure = previous.translated(dx, dy).withStyle(currentRunStyle);
          figures.add(figure);
          previous = figure;
        }
        return _V4ExtendedReadResult(
          style: currentRunStyle,
          figures: figures,
        );
      case _extDotRun:
        return _V4ExtendedReadResult(
          style: style,
          figures: _readDotRun(
            reader,
            style,
            width: width,
            height: height,
            xBits: xBits,
            yBits: yBits,
          ),
        );
      case _extPathOrthogonal:
        return one(
          _readOrthogonalPath(
            reader,
            style,
            width: width,
            height: height,
            xBits: xBits,
            yBits: yBits,
          ),
        );
      case _extPathBounds:
        return one(
          _readBoundsPath(
            reader,
            style,
            width: width,
            height: height,
            xBits: xBits,
            yBits: yBits,
          ),
        );
      case _extPathBoundsDelta:
        return one(
          _readBoundsDeltaPath(
            reader,
            style,
            width: width,
            height: height,
            xBits: xBits,
            yBits: yBits,
          ),
        );
      case _extRasterLayer:
        if (!allowRasterLayer) {
          throw const MCOImageInvalidPayloadException(
            'MCOimg v4 raster layer is only valid in mixed mode',
          );
        }
        return one(
          _readRasterLayer(
            reader,
            paletteProfile: paletteProfile,
            width: width,
            height: height,
            xBits: xBits,
            yBits: yBits,
          ),
        );
      case _extGroup:
        final count = reader.readCompactUint() + 1;
        var nestedStyle = style;
        final nestedHistory = <MCOImageV4Figure>[];
        final figures = <MCOImageV4Figure>[];

        void addNestedFigures(List<MCOImageV4Figure> nextFigures) {
          if (figures.length + nextFigures.length > count) {
            throw const MCOImageInvalidPayloadException(
              'MCOimg v4 group contains too many figures',
            );
          }
          figures.addAll(nextFigures);
          nestedHistory.addAll(nextFigures);
        }

        while (figures.length < count) {
          final nestedOpcode = reader.readBits(_opBits);
          switch (nestedOpcode) {
            case _opEnd:
              throw const MCOImageInvalidPayloadException(
                'Unexpected MCOimg v4 end inside group',
              );
            case _opSetFill:
              nestedStyle = nestedStyle.copyWith(
                fillColor: localColorFromProfileRef(),
              );
            case _opSetStroke:
              nestedStyle = nestedStyle.copyWith(
                strokeColor: localColorFromProfileRef(),
              );
            case _opSetStrokeWidth:
              nestedStyle = nestedStyle.copyWith(
                strokeWidth: reader.readBits(scalarBits) + 1,
              );
            case _opRepeatLast:
              if (nestedHistory.isEmpty) {
                throw const MCOImageInvalidPayloadException(
                  'MCOimg v4 group repeat has no previous figure',
                );
              }
              final dx = _zigZagDecode(reader.readBits(xBits + 1));
              final dy = _zigZagDecode(reader.readBits(yBits + 1));
              addNestedFigures(
                <MCOImageV4Figure>[
                  nestedHistory.last.translated(dx, dy).withStyle(nestedStyle),
                ],
              );
            case _opRepeatShort:
              if (nestedHistory.isEmpty) {
                throw const MCOImageInvalidPayloadException(
                  'MCOimg v4 group repeat has no previous figure',
                );
              }
              final shortBits = _deltaWidths[reader.readBits(2)];
              final dx = _zigZagDecode(reader.readBits(shortBits));
              final dy = _zigZagDecode(reader.readBits(shortBits));
              addNestedFigures(
                <MCOImageV4Figure>[
                  nestedHistory.last.translated(dx, dy).withStyle(nestedStyle),
                ],
              );
            case _opExtended:
              final result = _readExtendedCommand(
                reader,
                nestedStyle,
                history: nestedHistory,
                width: width,
                height: height,
                xBits: xBits,
                yBits: yBits,
                scalarBits: scalarBits,
                paletteProfile: paletteProfile,
                allowRasterLayer: false,
                localColorFromProfileRef: localColorFromProfileRef,
              );
              nestedStyle = result.style;
              addNestedFigures(result.figures);
            default:
              addNestedFigures(
                <MCOImageV4Figure>[
                  _readFigure(
                    nestedOpcode,
                    reader,
                    nestedStyle,
                    width: width,
                    height: height,
                    xBits: xBits,
                    yBits: yBits,
                    scalarBits: scalarBits,
                  ),
                ],
              );
          }
        }
        return _V4ExtendedReadResult(
          style: style,
          figures: <MCOImageV4Figure>[
            MCOImageV4Group(figures: figures, style: style),
          ],
        );
      default:
        throw MCOImageUnsupportedFormatException(
          'Unknown MCOimg v4 extended opcode: $subop',
          receivedVersion: version,
          currentMaxSupportedVersion: version,
        );
    }
  }

  MCOImageV4RasterLayer _readRasterLayer(
    _V4BitReader reader, {
    required PaletteProfile paletteProfile,
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    final origin = _readPoint(reader, width, height, xBits, yBits);
    final v3HeaderHigh = reader.readBits(4);
    final payloadLength = reader.readCompactUint();
    if (payloadLength < 2) {
      throw const MCOImageInvalidPayloadException(
        'MCOimg v4 raster layer payload too short',
      );
    }
    final payload = reader.readBytes(payloadLength);
    final body = Uint8List(payload.length + 1)
      ..[0] = (v3HeaderHigh << 4) | paletteProfile.index
      ..setRange(
        1,
        1 + payload.length,
        payload,
      );
    final image = MCOImageV3Codec().decodeBodyWithoutPacketNonce(body);
    if (image.paletteProfile != paletteProfile) {
      throw const MCOImageInvalidPayloadException(
        'MCOimg v4 raster layer palette profile mismatch',
      );
    }
    return MCOImageV4RasterLayer(
      x: origin.x,
      y: origin.y,
      width: image.width,
      height: image.height,
      pixels: image.pixels,
      transparentColor: image.transparentColor,
    );
  }

  MCOImageV4Path _readOrthogonalPath(
    _V4BitReader reader,
    MCOImageV4Style style, {
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    final closed = reader.readBit();
    final shortBits = _deltaWidths[reader.readBits(2)];
    final minimum = closed ? 3 : 2;
    final pointCount = reader.readCompactUint() + minimum;
    final points = <MCOImageV4Point>[
      _readPoint(reader, width, height, xBits, yBits),
    ];
    while (points.length < pointCount) {
      final previous = points.last;
      final vertical = reader.readBit();
      final delta = _zigZagDecode(reader.readBits(shortBits));
      final point = vertical
          ? MCOImageV4Point(previous.x, previous.y + delta)
          : MCOImageV4Point(previous.x + delta, previous.y);
      _validatePointInPayload(point, width, height);
      points.add(point);
    }
    return MCOImageV4Path(points: points, closed: closed, style: style);
  }

  List<MCOImageV4Dot> _readDotRun(
    _V4BitReader reader,
    MCOImageV4Style style, {
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    final deltaEncoded = reader.readBit();
    final shortBits = deltaEncoded ? _deltaWidths[reader.readBits(2)] : null;
    final pointCount = reader.readCompactUint() + 2;
    final points = <MCOImageV4Point>[
      _readPoint(reader, width, height, xBits, yBits),
    ];
    while (points.length < pointCount) {
      if (shortBits == null) {
        points.add(_readPoint(reader, width, height, xBits, yBits));
        continue;
      }
      final previous = points.last;
      final point = MCOImageV4Point(
        previous.x + _zigZagDecode(reader.readBits(shortBits)),
        previous.y + _zigZagDecode(reader.readBits(shortBits)),
      );
      _validatePointInPayload(point, width, height);
      points.add(point);
    }
    return points
        .map((point) => MCOImageV4Dot(point: point, style: style))
        .toList();
  }

  MCOImageV4Path _readBoundsPath(
    _V4BitReader reader,
    MCOImageV4Style style, {
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    final closed = reader.readBit();
    final minimum = closed ? 3 : 2;
    final pointCount = reader.readCompactUint() + minimum;
    final origin = _readPoint(reader, width, height, xBits, yBits);
    final boundsWidth = reader.readBits(xBits) + 1;
    final boundsHeight = reader.readBits(yBits) + 1;
    if (!_isCoordinateInRange(origin.x + boundsWidth - 1, width) ||
        !_isCoordinateInRange(origin.y + boundsHeight - 1, height)) {
      throw const MCOImageInvalidPayloadException(
        'MCOimg v4 path bounds are outside the coordinate range',
      );
    }
    final localXBits = _localCoordinateBits(boundsWidth);
    final localYBits = _localCoordinateBits(boundsHeight);
    final points = <MCOImageV4Point>[];
    while (points.length < pointCount) {
      final point = MCOImageV4Point(
        origin.x + _readLocalCoordinate(reader, localXBits, boundsWidth),
        origin.y + _readLocalCoordinate(reader, localYBits, boundsHeight),
      );
      points.add(point);
    }
    return MCOImageV4Path(points: points, closed: closed, style: style);
  }

  MCOImageV4Path _readBoundsDeltaPath(
    _V4BitReader reader,
    MCOImageV4Style style, {
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    final closed = reader.readBit();
    final shortBits = _deltaWidths[reader.readBits(2)];
    final minimum = closed ? 3 : 2;
    final pointCount = reader.readCompactUint() + minimum;
    final origin = _readPoint(reader, width, height, xBits, yBits);
    final boundsWidth = reader.readBits(xBits) + 1;
    final boundsHeight = reader.readBits(yBits) + 1;
    if (!_isCoordinateInRange(origin.x + boundsWidth - 1, width) ||
        !_isCoordinateInRange(origin.y + boundsHeight - 1, height)) {
      throw const MCOImageInvalidPayloadException(
        'MCOimg v4 path bounds are outside the coordinate range',
      );
    }
    final localXBits = _localCoordinateBits(boundsWidth);
    final localYBits = _localCoordinateBits(boundsHeight);
    final first = MCOImageV4Point(
      _readLocalCoordinate(reader, localXBits, boundsWidth),
      _readLocalCoordinate(reader, localYBits, boundsHeight),
    );
    final localPoints = <MCOImageV4Point>[first];
    while (localPoints.length < pointCount) {
      final previous = localPoints.last;
      final point = MCOImageV4Point(
        previous.x + _zigZagDecode(reader.readBits(shortBits)),
        previous.y + _zigZagDecode(reader.readBits(shortBits)),
      );
      _validateLocalPointInPayload(point, boundsWidth, boundsHeight);
      localPoints.add(point);
    }
    final points = localPoints
        .map((point) => MCOImageV4Point(origin.x + point.x, origin.y + point.y))
        .toList();
    return MCOImageV4Path(points: points, closed: closed, style: style);
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

  List<MCOImageV4Point> _readPointDeltaSequence(
    _V4BitReader reader, {
    required int count,
    required int width,
    required int height,
    required int xBits,
    required int yBits,
  }) {
    final shortBits = _deltaWidths[reader.readBits(2)];
    final points = <MCOImageV4Point>[
      _readPoint(reader, width, height, xBits, yBits),
    ];
    while (points.length < count) {
      final previous = points.last;
      final point = MCOImageV4Point(
        previous.x + _zigZagDecode(reader.readBits(shortBits)),
        previous.y + _zigZagDecode(reader.readBits(shortBits)),
      );
      _validatePointInPayload(point, width, height);
      points.add(point);
    }
    return points;
  }

  int _readPathComponent(
    _V4BitReader reader,
    int previous,
    int shortBits,
    int absoluteBits,
    int axisSize,
  ) {
    final value = reader.readBit()
        ? _readCoordinate(reader, absoluteBits, axisSize)
        : previous + _zigZagDecode(reader.readBits(shortBits));
    if (!_isCoordinateInRange(value, axisSize)) {
      throw const MCOImageInvalidPayloadException(
        'MCOimg v4 path coordinate is out of range',
      );
    }
    return value;
  }

  void _validateDocument(MCOImageV4Document document) {
    if (!_isObjectMode(document.mode)) {
      throw const MCOImageInvalidInputException('Unsupported MCOimg v4 mode');
    }
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
                color <
                    MCOImagePalette.colorsFor(
                      document.paletteProfile,
                    ).length;
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
        document.paletteProfile,
        document.palette.length,
      );
    }
  }

  static bool _isObjectMode(MCOImageV4Mode mode) =>
      mode == MCOImageV4Mode.vector || mode == MCOImageV4Mode.mixed;

  static MCOImageV4Mode _effectiveObjectMode(MCOImageV4Document document) =>
      _containsRasterLayer(document.figures)
          ? MCOImageV4Mode.mixed
          : MCOImageV4Mode.vector;

  static bool _containsRasterLayer(Iterable<MCOImageV4Figure> figures) {
    for (final figure in figures) {
      if (!figure.visible) continue;
      if (figure is MCOImageV4RasterLayer) return true;
      if (figure is MCOImageV4Group && _containsRasterLayer(figure.figures)) {
        return true;
      }
    }
    return false;
  }

  static void _validateFigure(
    MCOImageV4Figure figure,
    int canvasWidth,
    int canvasHeight,
    PaletteProfile paletteProfile,
    int paletteLength,
  ) {
    _validateStyle(
      figure.style,
      paletteLength,
      math.max(canvasWidth, canvasHeight),
    );
    void point(MCOImageV4Point value) {
      if (!_isCoordinateInRange(value.x, canvasWidth) ||
          !_isCoordinateInRange(value.y, canvasHeight)) {
        throw const MCOImageInvalidInputException(
          'MCOimg v4 point is outside the coordinate range',
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
        if (depth == 0 || depth.abs() > math.max(canvasWidth, canvasHeight)) {
          throw const MCOImageInvalidInputException(
            'Invalid MCOimg v4 wave depth',
          );
        }
      case MCOImageV4RasterLayer(
        :final x,
        :final y,
        :final width,
        :final height,
        :final pixels,
        :final transparentColor,
      ):
        point(MCOImageV4Point(x, y));
        if (width < 1 || width > 256 || height < 1 || height > 256) {
          throw const MCOImageInvalidInputException(
            'Invalid MCOimg v4 raster layer size',
          );
        }
        if (pixels.length != width * height) {
          throw const MCOImageInvalidInputException(
            'Invalid MCOimg v4 raster layer pixels',
          );
        }
        if (transparentColor != null) {
          _colorRefForProfile(paletteProfile, transparentColor);
        }
        for (final color in pixels) {
          _colorRefForProfile(paletteProfile, color);
        }
      case MCOImageV4Group(:final figures):
        if (figures.isEmpty) {
          throw const MCOImageInvalidInputException('MCOimg v4 group is empty');
        }
        for (final child in figures.where((figure) => figure.visible)) {
          if (child is MCOImageV4RasterLayer) {
            throw const MCOImageInvalidInputException(
              'MCOimg v4 raster layer cannot be nested in a group',
            );
          }
          _validateFigure(
            child,
            canvasWidth,
            canvasHeight,
            paletteProfile,
            paletteLength,
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

  static MCOImageV4Style _defaultStyleForDocument(
    MCOImageV4Document document,
  ) {
    final black = MCOImagePalette.blackIndexFor(document.paletteProfile);
    final localBlack = document.palette.indexOf(black);
    return MCOImageV4Style(strokeColor: localBlack);
  }

  static int? _defaultBackgroundColorForDocument(
    MCOImageV4Document document,
  ) {
    final white = MCOImagePalette.whiteIndexFor(document.paletteProfile);
    final localWhite = document.palette.indexOf(white);
    return localWhite < 0 ? null : localWhite;
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
      case (MCOImageV4Group() && final a, MCOImageV4Group() && final b):
        final aFigures = a.figures.where((figure) => figure.visible).toList();
        final bFigures = b.figures.where((figure) => figure.visible).toList();
        if (aFigures.length != bFigures.length) return null;
        MCOImageV4Point? groupDelta;
        for (var i = 0; i < aFigures.length; i++) {
          if (aFigures[i].style != bFigures[i].style) return null;
          final childDelta = _translationFrom(aFigures[i], bFigures[i]);
          if (childDelta == null) return null;
          groupDelta ??= childDelta;
          if (groupDelta != childDelta) return null;
        }
        return groupDelta;
      default:
        return null;
    }
  }

  static ({
    MCOImageV4Point first,
    MCOImageV4Point second,
    bool swapped,
  })? _axisAlignedArea(MCOImageV4AreaFigure figure) {
    final thirdA = MCOImageV4Point(figure.first.x, figure.second.y);
    if (figure.third == thirdA) {
      return (
        first: figure.first,
        second: figure.second,
        swapped: false,
      );
    }
    final thirdB = MCOImageV4Point(figure.second.x, figure.first.y);
    if (figure.third == thirdB) {
      return (
        first: figure.first,
        second: figure.second,
        swapped: true,
      );
    }
    return null;
  }

  static ({bool negative, int magnitude})? _ellipseDepthEncoding(
    MCOImageV4Ellipse ellipse,
  ) {
    final dx = ellipse.second.x - ellipse.first.x;
    final dy = ellipse.second.y - ellipse.first.y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) return null;
    final centerX = (ellipse.first.x + ellipse.second.x) / 2;
    final centerY = (ellipse.first.y + ellipse.second.y) / 2;
    final relX = ellipse.third.x - centerX;
    final relY = ellipse.third.y - centerY;
    final projection = (relX * -dy + relY * dx) / length;
    final magnitude = projection.abs().round();
    if (magnitude <= 0) return null;
    if ((projection.abs() - magnitude).abs() > 1e-9) return null;
    final reconstructed = _ellipseThirdFromDepth(
      ellipse.first,
      ellipse.second,
      projection < 0 ? -magnitude : magnitude,
    );
    if (reconstructed == null) return null;
    if (reconstructed != ellipse.third) return null;
    if ((_ellipseProjectedDepth(ellipse.first, ellipse.second, reconstructed) -
                projection.abs())
            .abs() >
        1e-9) {
      return null;
    }
    return (negative: projection < 0, magnitude: magnitude);
  }

  static MCOImageV4Point? _ellipseThirdFromDepth(
    MCOImageV4Point first,
    MCOImageV4Point second,
    int depth,
  ) {
    final dx = second.x - first.x;
    final dy = second.y - first.y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) return null;
    final centerX = (first.x + second.x) / 2;
    final centerY = (first.y + second.y) / 2;
    final x = centerX + (-dy / length) * depth;
    final y = centerY + (dx / length) * depth;
    final roundedX = x.round();
    final roundedY = y.round();
    if ((x - roundedX).abs() > 1e-9 || (y - roundedY).abs() > 1e-9) {
      return null;
    }
    return MCOImageV4Point(roundedX, roundedY);
  }

  static double _ellipseProjectedDepth(
    MCOImageV4Point first,
    MCOImageV4Point second,
    MCOImageV4Point third,
  ) {
    final dx = second.x - first.x;
    final dy = second.y - first.y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) return 0;
    final centerX = (first.x + second.x) / 2;
    final centerY = (first.y + second.y) / 2;
    final relX = third.x - centerX;
    final relY = third.y - centerY;
    return ((relX * -dy + relY * dx) / length).abs();
  }

  static ({int x, int y, int width, int height}) _pathBounds(
    List<MCOImageV4Point> points,
  ) {
    var minX = points.first.x;
    var maxX = minX;
    var minY = points.first.y;
    var maxY = minY;
    for (final point in points.skip(1)) {
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
      minY = math.min(minY, point.y);
      maxY = math.max(maxY, point.y);
    }
    return (
      x: minX,
      y: minY,
      width: maxX - minX + 1,
      height: maxY - minY + 1,
    );
  }

  static void _writePoint(
    _V4BitWriter writer,
    MCOImageV4Point point,
    int xBits,
    int yBits, {
    required int width,
    required int height,
  }) {
    writer
      ..writeBits(_encodeCoordinate(point.x, width), xBits)
      ..writeBits(_encodeCoordinate(point.y, height), yBits);
  }

  static void _writeDimensions(_V4BitWriter writer, int width, int height) {
    if (width == height && width <= 64) {
      writer
        ..writeBits(_dimensionModeSquare64, 2)
        ..writeBits(width - 1, 6);
      return;
    }

    if (width <= 32 && height <= 32) {
      writer
        ..writeBits(_dimensionModeSmall32, 2)
        ..writeBits(width - 1, 5)
        ..writeBits(height - 1, 5);
      return;
    }

    if (width <= 64 && height <= 64) {
      writer
        ..writeBits(_dimensionModeMedium64, 2)
        ..writeBits(width - 1, 6)
        ..writeBits(height - 1, 6);
      return;
    }

    writer.writeBits(_dimensionModeExtended, 2);
    if (width == height) {
      writer
        ..writeBit(false)
        ..writeBits(width - 1, 8);
      return;
    }

    writer
      ..writeBit(true)
      ..writeBits(width - 1, 8)
      ..writeBits(height - 1, 8);
  }

  static ({int width, int height}) _readDimensions(_V4BitReader reader) {
    final mode = reader.readBits(2);
    late final int width;
    late final int height;
    switch (mode) {
      case _dimensionModeSquare64:
        width = reader.readBits(6) + 1;
        height = width;
      case _dimensionModeSmall32:
        width = reader.readBits(5) + 1;
        height = reader.readBits(5) + 1;
        if (width == height) {
          throw const MCOImageInvalidPayloadException(
            'Non-canonical v4 small square dimensions',
          );
        }
      case _dimensionModeMedium64:
        width = reader.readBits(6) + 1;
        height = reader.readBits(6) + 1;
        if (width == height || width <= 32 && height <= 32) {
          throw const MCOImageInvalidPayloadException(
            'Non-canonical v4 medium dimensions',
          );
        }
      case _dimensionModeExtended:
        final generalRectangle = reader.readBit();
        if (!generalRectangle) {
          width = reader.readBits(8) + 1;
          height = width;
          if (width <= 64) {
            throw const MCOImageInvalidPayloadException(
              'Non-canonical v4 extended square dimensions',
            );
          }
        } else {
          width = reader.readBits(8) + 1;
          height = reader.readBits(8) + 1;
          if (width == height || width <= 64 && height <= 64) {
            throw const MCOImageInvalidPayloadException(
              'Non-canonical v4 extended dimensions',
            );
          }
        }
    }
    return (width: width, height: height);
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
    if (value >= _coordinateValueCount(size)) {
      throw const MCOImageInvalidPayloadException(
        'MCOimg v4 coordinate is out of range',
      );
    }
    return value - _coordinateMargin(size);
  }

  static int _readLocalCoordinate(_V4BitReader reader, int bits, int size) {
    final value = reader.readBits(bits);
    if (value >= size) {
      throw const MCOImageInvalidPayloadException(
        'MCOimg v4 coordinate is out of range',
      );
    }
    return value;
  }

  static void _validatePointInPayload(
    MCOImageV4Point point,
    int width,
    int height,
  ) {
    if (!_isCoordinateInRange(point.x, width) ||
        !_isCoordinateInRange(point.y, height)) {
      throw const MCOImageInvalidPayloadException(
        'MCOimg v4 coordinate is out of range',
      );
    }
  }

  static void _validateLocalPointInPayload(
    MCOImageV4Point point,
    int width,
    int height,
  ) {
    if (point.x < 0 || point.x >= width || point.y < 0 || point.y >= height) {
      throw const MCOImageInvalidPayloadException(
        'MCOimg v4 coordinate is out of range',
      );
    }
  }

  static void _writeOptionalColor(
    _V4BitWriter writer,
    MCOImageV4Document document,
    int? color,
    int profileColorBits,
  ) {
    writer.writeBit(color != null);
    if (color != null) {
      writer.writeBits(
        _profileColorRefForDocumentColor(document, color),
        profileColorBits,
      );
    }
  }

  static int _profileColorRefForDocumentColor(
    MCOImageV4Document document,
    int color,
  ) {
    if (color < 0 || color >= document.palette.length) {
      throw const MCOImageInvalidInputException(
        'MCOimg v4 palette reference is out of range',
      );
    }
    return _colorRefForProfile(
      document.paletteProfile,
      document.palette[color],
    );
  }

  static int _coordinateBits(int size) =>
      math.max(1, (_coordinateValueCount(size) - 1).bitLength);

  static int _localCoordinateBits(int size) =>
      math.max(1, (size - 1).bitLength);

  static int _coordinateMargin(int size) =>
      coordinateMarginForCanvasSize(size);

  static int _coordinateValueCount(int size) =>
      size + _coordinateMargin(size) * 2;

  static bool _isCoordinateInRange(int value, int size) {
    final margin = _coordinateMargin(size);
    return value >= -margin && value < size + margin;
  }

  static int _encodeCoordinate(int value, int size) {
    if (!_isCoordinateInRange(value, size)) {
      throw const MCOImageInvalidInputException(
        'MCOimg v4 point is outside the coordinate range',
      );
    }
    return value + _coordinateMargin(size);
  }

  static int _scalarBits(int width, int height) =>
      math.max(1, (math.max(width, height) - 1).bitLength);

  static int _profileColorBits(PaletteProfile profile) =>
      math.max(1, (_profilePaletteSize(profile) - 1).bitLength);

  static int _profilePaletteSize(PaletteProfile profile) => profile.isDynamic
      ? MCOImageDynamicPalette.indicesFor(profile).length
      : MCOImagePalette.colorsFor(profile).length;

  static int _colorRefForProfile(PaletteProfile profile, int color) {
    if (!profile.isDynamic) {
      if (color < 0 || color >= MCOImagePalette.colorsFor(profile).length) {
        throw MCOImageInvalidInputException(
          'Color $color is outside fixed profile $profile',
        );
      }
      return color;
    }
    final ref = MCOImageDynamicPalette.profileColorIdForGlobalIndex(
      profile,
      color,
    );
    if (ref == null) {
      throw MCOImageInvalidInputException(
        'Color $color is outside dynamic profile $profile',
      );
    }
    return ref;
  }

  static int _colorFromProfileRef(
    PaletteProfile profile,
    int ref, {
    required bool payload,
  }) {
    final size = _profilePaletteSize(profile);
    if (ref < 0 || ref >= size) {
      final message = 'Color reference $ref is outside ${profile.name}';
      if (payload) throw MCOImageInvalidPayloadException(message);
      throw MCOImageInvalidInputException(message);
    }
    return profile.isDynamic
        ? MCOImageDynamicPalette.globalIndexForProfileColorId(profile, ref)
        : ref;
  }

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

class _DecodedV4CanonicalDocument {
  final MCOImageV4Document document;
  final Uint8List canonicalDocument;

  const _DecodedV4CanonicalDocument({
    required this.document,
    required this.canonicalDocument,
  });
}

class _V4ExtendedReadResult {
  final MCOImageV4Style style;
  final List<MCOImageV4Figure> figures;

  const _V4ExtendedReadResult({
    required this.style,
    required this.figures,
  });
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

  void writeBytes(Uint8List bytes) {
    for (final byte in bytes) {
      writeBits(byte, 8);
    }
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

  int get byteOffset => (_bitIndex + 7) >> 3;

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

  Uint8List readBytes(int length) {
    if (length < 0 || length > remainingBits ~/ 8) {
      throw const MCOImageInvalidPayloadException('Unexpected end of v4 bits');
    }
    return Uint8List.fromList(
      List<int>.generate(length, (_) => readBits(8), growable: false),
    );
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

  void finishByte() {
    final padding = _bitIndex & 7;
    if (padding == 0) return;
    final remaining = 8 - padding;
    if (readBits(remaining) != 0) {
      throw const MCOImageInvalidPayloadException(
        'Non-zero MCOimg v4 padding',
      );
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

class _V4RasterLayerEncodeCacheKey {
  final PaletteProfile paletteProfile;
  final int compressionLevel;
  final int width;
  final int height;
  final int? transparentColor;
  final List<int> pixels;
  final int _hash;

  _V4RasterLayerEncodeCacheKey({
    required this.paletteProfile,
    required this.compressionLevel,
    required this.width,
    required this.height,
    required this.transparentColor,
    required this.pixels,
  }) : _hash = _hashValues(
         paletteProfile,
         compressionLevel,
         width,
         height,
         transparentColor,
         pixels,
       );

  static int _hashValues(
    PaletteProfile paletteProfile,
    int compressionLevel,
    int width,
    int height,
    int? transparentColor,
    List<int> pixels,
  ) {
    var hash = Object.hash(
      paletteProfile,
      compressionLevel,
      width,
      height,
      transparentColor,
      pixels.length,
    );
    for (final pixel in pixels) {
      hash = 0x1fffffff & (hash + pixel);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= hash >> 11;
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _V4RasterLayerEncodeCacheKey ||
        other._hash != _hash ||
        other.paletteProfile != paletteProfile ||
        other.compressionLevel != compressionLevel ||
        other.width != width ||
        other.height != height ||
        other.transparentColor != transparentColor ||
        other.pixels.length != pixels.length) {
      return false;
    }
    for (var i = 0; i < pixels.length; i++) {
      if (other.pixels[i] != pixels[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => _hash;
}

class _V4RasterLayerEncodeCacheValue {
  final int v3HeaderHigh;
  final Uint8List payload;

  _V4RasterLayerEncodeCacheValue({
    required this.v3HeaderHigh,
    required Uint8List payload,
  }) : payload = Uint8List.fromList(payload);
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
