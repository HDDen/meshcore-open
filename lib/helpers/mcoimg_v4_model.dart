import 'dart:typed_data';

import 'mcoimg_types.dart';

enum MCOImageV4Mode { vector, raster }

class MCOImageV4Point {
  final int x;
  final int y;

  const MCOImageV4Point(this.x, this.y);

  MCOImageV4Point translated(int dx, int dy) =>
      MCOImageV4Point(x + dx, y + dy);

  @override
  bool operator ==(Object other) =>
      other is MCOImageV4Point && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

class MCOImageV4Style {
  final int? fillColor;
  final int? strokeColor;
  final int strokeWidth;

  const MCOImageV4Style({
    this.fillColor,
    this.strokeColor,
    this.strokeWidth = 1,
  });

  MCOImageV4Style copyWith({
    Object? fillColor = _unchanged,
    Object? strokeColor = _unchanged,
    int? strokeWidth,
  }) {
    return MCOImageV4Style(
      fillColor: identical(fillColor, _unchanged)
          ? this.fillColor
          : fillColor as int?,
      strokeColor: identical(strokeColor, _unchanged)
          ? this.strokeColor
          : strokeColor as int?,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }

  static const Object _unchanged = Object();

  @override
  bool operator ==(Object other) =>
      other is MCOImageV4Style &&
      other.fillColor == fillColor &&
      other.strokeColor == strokeColor &&
      other.strokeWidth == strokeWidth;

  @override
  int get hashCode => Object.hash(fillColor, strokeColor, strokeWidth);
}

sealed class MCOImageV4Figure {
  final MCOImageV4Style style;
  final bool visible;

  const MCOImageV4Figure({required this.style, this.visible = true});

  MCOImageV4Figure translated(int dx, int dy);

  MCOImageV4Figure withStyle(MCOImageV4Style style);

  MCOImageV4Figure withVisibility(bool visible);
}

class MCOImageV4Dot extends MCOImageV4Figure {
  final MCOImageV4Point point;

  const MCOImageV4Dot({
    required this.point,
    required super.style,
    super.visible,
  });

  @override
  MCOImageV4Dot translated(int dx, int dy) => MCOImageV4Dot(
    point: point.translated(dx, dy),
    style: style,
    visible: visible,
  );

  @override
  MCOImageV4Dot withStyle(MCOImageV4Style style) =>
      MCOImageV4Dot(point: point, style: style, visible: visible);

  @override
  MCOImageV4Dot withVisibility(bool visible) =>
      MCOImageV4Dot(point: point, style: style, visible: visible);
}

class MCOImageV4Line extends MCOImageV4Figure {
  final MCOImageV4Point start;
  final MCOImageV4Point end;

  const MCOImageV4Line({
    required this.start,
    required this.end,
    required super.style,
    super.visible,
  });

  @override
  MCOImageV4Line translated(int dx, int dy) => MCOImageV4Line(
    start: start.translated(dx, dy),
    end: end.translated(dx, dy),
    style: style,
    visible: visible,
  );

  @override
  MCOImageV4Line withStyle(MCOImageV4Style style) => MCOImageV4Line(
    start: start,
    end: end,
    style: style,
    visible: visible,
  );

  @override
  MCOImageV4Line withVisibility(bool visible) => MCOImageV4Line(
    start: start,
    end: end,
    style: style,
    visible: visible,
  );
}

sealed class MCOImageV4AreaFigure extends MCOImageV4Figure {
  final MCOImageV4Point first;
  final MCOImageV4Point second;
  final MCOImageV4Point third;

  const MCOImageV4AreaFigure({
    required this.first,
    required this.second,
    required this.third,
    required super.style,
    super.visible,
  });
}

class MCOImageV4Rect extends MCOImageV4AreaFigure {
  const MCOImageV4Rect({
    required super.first,
    required super.second,
    required super.third,
    required super.style,
    super.visible,
  });

  @override
  MCOImageV4Rect translated(int dx, int dy) => MCOImageV4Rect(
    first: first.translated(dx, dy),
    second: second.translated(dx, dy),
    third: third.translated(dx, dy),
    style: style,
    visible: visible,
  );

  @override
  MCOImageV4Rect withStyle(MCOImageV4Style style) => MCOImageV4Rect(
    first: first,
    second: second,
    third: third,
    style: style,
    visible: visible,
  );

  @override
  MCOImageV4Rect withVisibility(bool visible) => MCOImageV4Rect(
    first: first,
    second: second,
    third: third,
    style: style,
    visible: visible,
  );
}

class MCOImageV4Ellipse extends MCOImageV4AreaFigure {
  const MCOImageV4Ellipse({
    required super.first,
    required super.second,
    required super.third,
    required super.style,
    super.visible,
  });

  @override
  MCOImageV4Ellipse translated(int dx, int dy) => MCOImageV4Ellipse(
    first: first.translated(dx, dy),
    second: second.translated(dx, dy),
    third: third.translated(dx, dy),
    style: style,
    visible: visible,
  );

  @override
  MCOImageV4Ellipse withStyle(MCOImageV4Style style) => MCOImageV4Ellipse(
    first: first,
    second: second,
    third: third,
    style: style,
    visible: visible,
  );

  @override
  MCOImageV4Ellipse withVisibility(bool visible) => MCOImageV4Ellipse(
    first: first,
    second: second,
    third: third,
    style: style,
    visible: visible,
  );
}

class MCOImageV4Path extends MCOImageV4Figure {
  final List<MCOImageV4Point> points;
  final bool closed;

  MCOImageV4Path({
    required List<MCOImageV4Point> points,
    required this.closed,
    required super.style,
    super.visible,
  }) : points = List<MCOImageV4Point>.unmodifiable(points);

  @override
  MCOImageV4Path translated(int dx, int dy) => MCOImageV4Path(
    points: points.map((point) => point.translated(dx, dy)).toList(),
    closed: closed,
    style: style,
    visible: visible,
  );

  @override
  MCOImageV4Path withStyle(MCOImageV4Style style) => MCOImageV4Path(
    points: points,
    closed: closed,
    style: style,
    visible: visible,
  );

  @override
  MCOImageV4Path withVisibility(bool visible) => MCOImageV4Path(
    points: points,
    closed: closed,
    style: style,
    visible: visible,
  );
}

class MCOImageV4Wave extends MCOImageV4Figure {
  final MCOImageV4Point start;
  final MCOImageV4Point end;
  final int depth;
  final bool closed;

  const MCOImageV4Wave({
    required this.start,
    required this.end,
    required this.depth,
    required this.closed,
    required super.style,
    super.visible,
  });

  @override
  MCOImageV4Wave translated(int dx, int dy) => MCOImageV4Wave(
    start: start.translated(dx, dy),
    end: end.translated(dx, dy),
    depth: depth,
    closed: closed,
    style: style,
    visible: visible,
  );

  @override
  MCOImageV4Wave withStyle(MCOImageV4Style style) => MCOImageV4Wave(
    start: start,
    end: end,
    depth: depth,
    closed: closed,
    style: style,
    visible: visible,
  );

  @override
  MCOImageV4Wave withVisibility(bool visible) => MCOImageV4Wave(
    start: start,
    end: end,
    depth: depth,
    closed: closed,
    style: style,
    visible: visible,
  );
}

class MCOImageV4Group extends MCOImageV4Figure {
  final List<MCOImageV4Figure> figures;

  MCOImageV4Group({
    required List<MCOImageV4Figure> figures,
    MCOImageV4Style? style,
    super.visible,
  }) : figures = List<MCOImageV4Figure>.unmodifiable(figures),
       super(style: style ?? _styleForFigures(figures));

  static MCOImageV4Style _styleForFigures(List<MCOImageV4Figure> figures) {
    if (figures.isEmpty) return const MCOImageV4Style(strokeColor: 0);
    for (final figure in figures) {
      if (figure.visible) return figure.style;
    }
    return figures.first.style;
  }

  @override
  MCOImageV4Group translated(int dx, int dy) => MCOImageV4Group(
    figures: figures.map((figure) => figure.translated(dx, dy)).toList(),
    style: style,
    visible: visible,
  );

  @override
  MCOImageV4Group withStyle(MCOImageV4Style style) {
    if (style == this.style) {
      return MCOImageV4Group(
        figures: figures,
        style: style,
        visible: visible,
      );
    }
    return MCOImageV4Group(
      figures: figures.map((figure) => figure.withStyle(style)).toList(),
      style: style,
      visible: visible,
    );
  }

  @override
  MCOImageV4Group withVisibility(bool visible) => MCOImageV4Group(
    figures: figures,
    style: style,
    visible: visible,
  );
}

class MCOImageV4Document {
  final MCOImageV4Mode mode;
  final int width;
  final int height;

  /// Fixed-profile color ids or dynamic-profile global512 indices.
  final List<int> palette;
  final PaletteProfile paletteProfile;
  final int? backgroundColor;
  final MCOImageV4Style initialStyle;
  final List<MCOImageV4Figure> figures;

  MCOImageV4Document({
    this.mode = MCOImageV4Mode.vector,
    required this.width,
    required this.height,
    required this.paletteProfile,
    required List<int> palette,
    this.backgroundColor,
    this.initialStyle = const MCOImageV4Style(strokeColor: 0),
    required List<MCOImageV4Figure> figures,
  }) : palette = List<int>.unmodifiable(palette),
       figures = List<MCOImageV4Figure>.unmodifiable(figures);

  MCOImageV4Document copyWith({
    MCOImageV4Mode? mode,
    int? width,
    int? height,
    PaletteProfile? paletteProfile,
    List<int>? palette,
    Object? backgroundColor = MCOImageV4Style._unchanged,
    MCOImageV4Style? initialStyle,
    List<MCOImageV4Figure>? figures,
  }) {
    return MCOImageV4Document(
      mode: mode ?? this.mode,
      width: width ?? this.width,
      height: height ?? this.height,
      paletteProfile: paletteProfile ?? this.paletteProfile,
      palette: palette ?? this.palette,
      backgroundColor: identical(
        backgroundColor,
        MCOImageV4Style._unchanged,
      )
          ? this.backgroundColor
          : backgroundColor as int?,
      initialStyle: initialStyle ?? this.initialStyle,
      figures: figures ?? this.figures,
    );
  }
}

class EncodedMCOImageV4 {
  final Uint8List body;
  final Uint8List canonicalDocument;
  final MCOImageV4Document document;
  final int nonce;
  final String? targetName;
  final int? replyTimestamp;

  const EncodedMCOImageV4({
    required this.body,
    required this.canonicalDocument,
    required this.document,
    required this.nonce,
    this.targetName,
    this.replyTimestamp,
  });

  int get byteLength => body.length;
}

class DecodedMCOImageV4 {
  final MCOImageV4Document document;
  final Uint8List canonicalDocument;
  final int nonce;
  final String? targetName;
  final int? replyTimestamp;

  const DecodedMCOImageV4({
    required this.document,
    required this.canonicalDocument,
    required this.nonce,
    this.targetName,
    this.replyTimestamp,
  });
}

class MCOImageV4Preview extends MCOImage {
  final MCOImageV4Document document;

  MCOImageV4Preview({
    required this.document,
    required super.paletteProfile,
    required super.pixels,
    super.transparentColor,
  }) : super(
         width: document.width,
         height: document.height,
         encodingVersion: MCOImageEncodingVersion.v4,
       );
}
