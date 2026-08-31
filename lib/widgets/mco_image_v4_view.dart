import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../helpers/mcoimg_palette.dart';
import '../helpers/mcoimg_types.dart';
import '../helpers/mcoimg_v4_model.dart';

class MCOImageV4View extends StatelessWidget {
  final MCOImageV4Document document;
  final double maxSize;

  const MCOImageV4View({
    super.key,
    required this.document,
    this.maxSize = 200,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxSize, maxHeight: maxSize),
      child: AspectRatio(
        aspectRatio: document.width / document.height,
        child: CustomPaint(painter: MCOImageV4Painter(document)),
      ),
    );
  }
}

class MCOImageV4Painter extends CustomPainter {
  static const Color _gridColor = Color(0xff00ff00);

  final MCOImageV4Document document;
  final MCOImageV4Figure? selectedFigure;
  final Color? selectionColor;
  final List<MCOImageV4Point> guidePoints;
  final MCOImageV4Style? guideStyle;
  final bool paintBackground;
  final bool showGrid;
  final Rect? logicalViewport;

  const MCOImageV4Painter(
    this.document, {
    this.selectedFigure,
    this.selectionColor,
    this.guidePoints = const [],
    this.guideStyle,
    this.paintBackground = true,
    this.showGrid = false,
    this.logicalViewport,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final viewport = logicalViewport ??
        Rect.fromLTWH(
          0,
          0,
          document.width.toDouble(),
          document.height.toDouble(),
        );
    final scale = math.min(
      size.width / viewport.width,
      size.height / viewport.height,
    );
    final offset = Offset(
      (size.width - viewport.width * scale) / 2,
      (size.height - viewport.height * scale) / 2,
    );

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale, scale);
    canvas.translate(-viewport.left, -viewport.top);
    canvas.clipRect(viewport);

    final background = document.backgroundColor;
    if (paintBackground && background != null) {
      canvas.drawRect(
        Rect.fromLTWH(
          0,
          0,
          document.width.toDouble(),
          document.height.toDouble(),
        ),
        Paint()
          ..style = PaintingStyle.fill
          ..color = _color(background),
      );
    }

    if (showGrid) _drawGrid(canvas, scale);

    for (final figure in document.figures) {
      if (!figure.visible) continue;
      _drawFigure(canvas, figure);
      if (identical(figure, selectedFigure)) {
        _drawSelection(canvas, figure, scale);
      }
    }
    _drawGuidePoints(canvas, scale);
    canvas.restore();
  }

  void _drawGrid(Canvas canvas, double scale) {
    final gridPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 0.6 / scale
      ..isAntiAlias = false;
    for (var x = 0; x <= document.width; x++) {
      final dx = x.toDouble();
      canvas.drawLine(
        Offset(dx, 0),
        Offset(dx, document.height.toDouble()),
        gridPaint,
      );
    }
    for (var y = 0; y <= document.height; y++) {
      final dy = y.toDouble();
      canvas.drawLine(
        Offset(0, dy),
        Offset(document.width.toDouble(), dy),
        gridPaint,
      );
    }
  }

  void _drawGuidePoints(Canvas canvas, double scale) {
    if (guidePoints.isEmpty) return;
    final color = selectionColor ?? const Color(0xff00aaff);
    final style = guideStyle;
    final linePaint = style == null
        ? (Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / scale
          ..strokeCap = StrokeCap.square
          ..strokeJoin = StrokeJoin.miter
          ..color = color)
        : (_strokePaint(style) ??
            (Paint()
              ..isAntiAlias = true
              ..style = PaintingStyle.stroke
              ..strokeWidth = style.strokeWidth.toDouble()
              ..strokeCap = StrokeCap.square
              ..strokeJoin = StrokeJoin.miter
              ..color = color));
    if (guidePoints.length >= 2) {
      final first = _point(guidePoints.first);
      final path = Path()..moveTo(first.dx, first.dy);
      for (var i = 1; i < guidePoints.length; i++) {
        final point = _point(guidePoints[i]);
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, linePaint);
    }
    final fillPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill
      ..color = color;
    final outlinePaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / scale
      ..color = const Color(0xffffffff);
    for (final point in guidePoints) {
      final center = _point(point);
      canvas
        ..drawCircle(center, 4 / scale, fillPaint)
        ..drawCircle(center, 4 / scale, outlinePaint);
    }
  }

  void _drawFigure(Canvas canvas, MCOImageV4Figure figure) {
    switch (figure) {
      case MCOImageV4Dot(:final point, :final style):
        final stroke = style.strokeColor;
        if (stroke == null) return;
        canvas.drawCircle(
          _point(point),
          style.strokeWidth / 2,
          Paint()
            ..isAntiAlias = true
            ..style = PaintingStyle.fill
            ..color = _color(stroke),
        );
      case MCOImageV4Line(:final start, :final end, :final style):
        final paint = _strokePaint(style);
        if (paint == null) return;
        canvas.drawLine(_point(start), _point(end), paint);
      case MCOImageV4Rect(
        :final first,
        :final second,
        :final third,
        :final style,
      ):
        final corners = _rectCorners(first, second, third);
        final path = Path()
          ..moveTo(corners[0].dx, corners[0].dy)
          ..lineTo(corners[1].dx, corners[1].dy)
          ..lineTo(corners[2].dx, corners[2].dy)
          ..lineTo(corners[3].dx, corners[3].dy);
        _drawPath(canvas, path, style, closedStroke: true);
      case MCOImageV4Ellipse(
        :final first,
        :final second,
        :final third,
        :final style,
      ):
        final metrics = _ellipseMetrics(first, second, third);
        if (metrics == null) return;
        if (metrics.semiMinor < 0.5) {
          final path = Path()
            ..moveTo(_point(first).dx, _point(first).dy)
            ..lineTo(_point(second).dx, _point(second).dy);
          _drawPath(canvas, path, style, closedStroke: false);
          return;
        }
        final path = Path()
          ..addOval(
            Rect.fromLTWH(
              -metrics.semiMajor,
              -metrics.semiMinor,
              metrics.semiMajor * 2,
              metrics.semiMinor * 2,
            ),
          );
        canvas.save();
        canvas
          ..translate(metrics.center.dx, metrics.center.dy)
          ..rotate(metrics.angle);
        _drawPath(canvas, path, style, closedStroke: true);
        canvas.restore();
      case MCOImageV4Path(:final points, :final closed, :final style):
        final path = Path()..moveTo(points.first.x + 0.5, points.first.y + 0.5);
        for (final point in points.skip(1)) {
          path.lineTo(point.x + 0.5, point.y + 0.5);
        }
        _drawPath(canvas, path, style, closedStroke: closed);
      case MCOImageV4Wave(
        :final start,
        :final end,
        :final depth,
        :final closed,
        :final style,
      ):
        final startOffset = _point(start);
        final endOffset = _point(end);
        final dx = endOffset.dx - startOffset.dx;
        final dy = endOffset.dy - startOffset.dy;
        final length = math.sqrt(dx * dx + dy * dy);
        if (length == 0) return;
        final midpoint = Offset(
          (startOffset.dx + endOffset.dx) / 2,
          (startOffset.dy + endOffset.dy) / 2,
        );
        final normal = Offset(-dy / length, dx / length);
        // A quadratic curve reaches halfway between its control point and the
        // chord midpoint at t=0.5. Doubling depth makes the editor handle sit
        // on the visible midpoint of the wave.
        final control = midpoint + normal * (depth * 2);
        final path = Path()
          ..moveTo(startOffset.dx, startOffset.dy)
          ..quadraticBezierTo(
            control.dx,
            control.dy,
            endOffset.dx,
            endOffset.dy,
          );
        _drawPath(canvas, path, style, closedStroke: closed);
    }
  }

  void _drawPath(
    Canvas canvas,
    Path path,
    MCOImageV4Style style, {
    required bool closedStroke,
  }) {
    final fill = style.fillColor;
    if (fill != null) {
      final fillPath = Path.from(path)
        ..close()
        ..fillType = PathFillType.nonZero;
      canvas.drawPath(
        fillPath,
        Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.fill
          ..color = _color(fill),
      );
    }
    final strokePaint = _strokePaint(style);
    if (strokePaint != null) {
      final strokePath = closedStroke ? (Path.from(path)..close()) : path;
      canvas.drawPath(strokePath, strokePaint);
    }
  }

  Paint? _strokePaint(MCOImageV4Style style) {
    final stroke = style.strokeColor;
    if (stroke == null) return null;
    return Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.strokeWidth.toDouble()
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter
      ..color = _color(stroke);
  }

  void _drawSelection(Canvas canvas, MCOImageV4Figure figure, double scale) {
    final bounds = figureLogicalBounds(figure).inflate(2 / scale);
    canvas.drawRect(
      bounds,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / scale
        ..color = selectionColor ?? const Color(0xff00aaff),
    );
  }

  Color _color(int localIndex) {
    final color = document.palette[localIndex];
    return document.paletteProfile.isDynamic
        ? MCOImageDynamicPalette.global512[color]
        : MCOImagePalette.colorsFor(document.paletteProfile)[color];
  }

  static Offset _point(MCOImageV4Point point) =>
      Offset(point.x + 0.5, point.y + 0.5);

  static Rect figureLogicalBounds(MCOImageV4Figure figure) {
    switch (figure) {
      case MCOImageV4Dot(:final point, :final style):
        return Rect.fromCircle(
          center: _point(point),
          radius: style.strokeWidth / 2,
        );
      case MCOImageV4Line(:final start, :final end, :final style):
        return Rect.fromPoints(_point(start), _point(end)).inflate(
          style.strokeWidth / 2,
        );
      case MCOImageV4Rect(
        :final first,
        :final second,
        :final third,
        :final style,
      ):
        return _offsetBounds(
          _rectCorners(first, second, third),
        ).inflate(style.strokeWidth / 2);
      case MCOImageV4Ellipse(
        :final first,
        :final second,
        :final third,
        :final style,
      ):
        final metrics = _ellipseMetrics(first, second, third);
        if (metrics == null) {
          return Rect.fromPoints(_point(first), _point(second));
        }
        final radiusX = math.sqrt(
          math.pow(metrics.cos * metrics.semiMajor, 2) +
              math.pow(metrics.sin * metrics.semiMinor, 2),
        );
        final radiusY = math.sqrt(
          math.pow(metrics.sin * metrics.semiMajor, 2) +
              math.pow(metrics.cos * metrics.semiMinor, 2),
        );
        return Rect.fromLTRB(
          metrics.center.dx - radiusX,
          metrics.center.dy - radiusY,
          metrics.center.dx + radiusX,
          metrics.center.dy + radiusY,
        ).inflate(style.strokeWidth / 2);
      case MCOImageV4Path(:final points, :final style):
        return _pointBounds(points).inflate(style.strokeWidth / 2);
      case MCOImageV4Wave(
        :final start,
        :final end,
        :final depth,
        :final style,
      ):
        return Rect.fromPoints(_point(start), _point(end)).inflate(
          depth.abs() + style.strokeWidth / 2,
        );
    }
  }

  static Rect _pointBounds(List<MCOImageV4Point> points) {
    var minX = points.first.x + 0.5;
    var maxX = minX;
    var minY = points.first.y + 0.5;
    var maxY = minY;
    for (final point in points.skip(1)) {
      minX = math.min(minX, point.x + 0.5);
      maxX = math.max(maxX, point.x + 0.5);
      minY = math.min(minY, point.y + 0.5);
      maxY = math.max(maxY, point.y + 0.5);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static List<Offset> _rectCorners(
    MCOImageV4Point first,
    MCOImageV4Point second,
    MCOImageV4Point third,
  ) {
    final a = _point(first);
    final b = _point(third);
    final c = _point(second);
    final d = Offset(a.dx + c.dx - b.dx, a.dy + c.dy - b.dy);
    return <Offset>[a, b, c, d];
  }

  static _EllipseMetrics? _ellipseMetrics(
    MCOImageV4Point first,
    MCOImageV4Point second,
    MCOImageV4Point third,
  ) {
    final a = _point(first);
    final b = _point(second);
    final c = _point(third);
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) return null;
    final center = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final ux = dx / length;
    final uy = dy / length;
    final vx = -uy;
    final vy = ux;
    final relX = c.dx - center.dx;
    final relY = c.dy - center.dy;
    return _EllipseMetrics(
      center: center,
      semiMajor: length / 2,
      semiMinor: (relX * vx + relY * vy).abs(),
      angle: math.atan2(dy, dx),
      cos: ux,
      sin: uy,
    );
  }

  static Rect _offsetBounds(List<Offset> offsets) {
    var minX = offsets.first.dx;
    var maxX = minX;
    var minY = offsets.first.dy;
    var maxY = minY;
    for (final offset in offsets.skip(1)) {
      minX = math.min(minX, offset.dx);
      maxX = math.max(maxX, offset.dx);
      minY = math.min(minY, offset.dy);
      maxY = math.max(maxY, offset.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  @override
  bool shouldRepaint(covariant MCOImageV4Painter oldDelegate) {
    return oldDelegate.document != document ||
        oldDelegate.selectedFigure != selectedFigure ||
        oldDelegate.selectionColor != selectionColor ||
        oldDelegate.guidePoints != guidePoints ||
        oldDelegate.guideStyle != guideStyle ||
        oldDelegate.paintBackground != paintBackground ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.logicalViewport != logicalViewport;
  }
}

class _EllipseMetrics {
  final Offset center;
  final double semiMajor;
  final double semiMinor;
  final double angle;
  final double cos;
  final double sin;

  const _EllipseMetrics({
    required this.center,
    required this.semiMajor,
    required this.semiMinor,
    required this.angle,
    required this.cos,
    required this.sin,
  });
}

Future<Uint8List> renderMCOImageV4Png(
  MCOImageV4Document document, {
  int scale = 4,
}) async {
  final width = document.width * scale;
  final height = document.height * scale;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  MCOImageV4Painter(document).paint(
    canvas,
    Size(width.toDouble(), height.toDouble()),
  );
  final image = await recorder.endRecording().toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Cannot render MCOimg v4 PNG');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}
