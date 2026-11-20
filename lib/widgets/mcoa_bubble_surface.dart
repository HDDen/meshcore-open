import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Marks the end of the message area, including both spacing halves.
class McoaMetadataBoundary extends SingleChildRenderObjectWidget {
  const McoaMetadataBoundary({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _MetadataBoundary();
}

class _MetadataBoundary extends RenderProxyBox {}

/// Paints behind the existing content without adding intrinsic measurement,
/// layout passes, width constraints or hit-test layers.
class McoaBubbleSurface extends SingleChildRenderObjectWidget {
  const McoaBubbleSurface({
    super.key,
    required this.decoration,
    required this.metadataColor,
    required this.textDirection,
    required super.child,
  });

  final BoxDecoration decoration;
  final Color metadataColor;
  final TextDirection textDirection;

  @override
  RenderMcoaBubbleSurface createRenderObject(BuildContext context) =>
      RenderMcoaBubbleSurface(decoration, metadataColor, textDirection);

  @override
  void updateRenderObject(BuildContext context, RenderMcoaBubbleSurface renderObject) {
    renderObject.configure(decoration, metadataColor, textDirection);
  }
}

class RenderMcoaBubbleSurface extends RenderProxyBox {
  RenderMcoaBubbleSurface(this._decoration, this._metadataColor, this._textDirection);

  BoxDecoration _decoration;
  Color _metadataColor;
  TextDirection _textDirection;
  BoxPainter? _messagePainter;
  BoxPainter? _metadataPainter;
  _MetadataBoundary? _boundary;

  void configure(BoxDecoration decoration, Color metadataColor, TextDirection direction) {
    if (decoration == _decoration && metadataColor == _metadataColor &&
        direction == _textDirection) {
      return;
    }
    _decoration = decoration;
    _metadataColor = metadataColor;
    _textDirection = direction;
    _disposePainters();
    markNeedsPaint();
  }

  void _disposePainters() {
    _messagePainter?.dispose();
    _metadataPainter?.dispose();
    _messagePainter = null;
    _metadataPainter = null;
  }

  @override
  void dispose() {
    _disposePainters();
    super.dispose();
  }

  @override
  void performLayout() {
    super.performLayout();
    _boundary = null;
    void visit(RenderObject node) {
      if (_boundary != null) {
        return;
      }
      if (node is _MetadataBoundary) {
        _boundary = node;
      } else {
        node.visitChildren(visit);
      }
    }
    if (child != null) {
      visit(child!);
    }
  }

  /// Exposed for layout regressions; no persistent/global measurement state.
  Rect get messageRect {
    final boundary = _boundary;
    final bottom = boundary == null ? size.height : MatrixUtils.transformPoint(
      boundary.getTransformTo(this), Offset(0, boundary.size.height),
    ).dy.clamp(0.0, size.height).toDouble();
    return Rect.fromLTWH(0, 0, size.width, bottom);
  }

  Rect get metadataRect => Rect.fromLTRB(0, messageRect.bottom, size.width, size.height);

  // Match DecoratedBox: painted background and padding must participate in
  // hit testing, not just the text and badges. RenderBox tests children first,
  // preserving links/mentions before the enclosing message's menu gesture.
  @override
  bool hitTestSelf(Offset position) =>
      _decoration.hitTest(size, position, textDirection: _textDirection);

  @override
  void paint(PaintingContext context, Offset offset) {
    final metadata = metadataRect;
    if (!metadata.isEmpty) {
      // One continuous backing surface extends behind the rounded message.
      // Its top edge is hidden by the message rather than rounded again at
      // the metadata boundary. Layout and the logical metadata rect stay put.
      _metadataPainter ??= BoxDecoration(
        color: _metadataColor,
        borderRadius: _decoration.borderRadius,
      ).createBoxPainter(markNeedsPaint);
      _metadataPainter!.paint(context.canvas, offset, ImageConfiguration(
        size: size, textDirection: _textDirection,
      ));
    }
    _messagePainter ??= _decoration.createBoxPainter(markNeedsPaint);
    final message = messageRect;
    _messagePainter!.paint(context.canvas, offset, ImageConfiguration(
      size: message.size, textDirection: _textDirection,
    ));
    super.paint(context, offset);
  }
}
