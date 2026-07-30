import 'package:flutter/widgets.dart';

class EdgeSwipePop extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;
  final bool enabled;
  final double edgeWidth;
  final double triggerDistance;
  final double maxVerticalDrift;

  const EdgeSwipePop({
    super.key,
    required this.child,
    this.navigatorKey,
    this.enabled = true,
    this.edgeWidth = 36,
    this.triggerDistance = 84,
    this.maxVerticalDrift = 72,
  });

  @override
  State<EdgeSwipePop> createState() => _EdgeSwipePopState();
}

class _EdgeSwipePopState extends State<EdgeSwipePop> {
  int? _pointerId;
  Offset? _startPosition;
  bool _triggered = false;

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    final navigator =
        widget.navigatorKey?.currentState ?? Navigator.of(context);
    if (!navigator.canPop()) return;
    if (event.position.dx > widget.edgeWidth) return;
    _pointerId = event.pointer;
    _startPosition = event.position;
    _triggered = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_pointerId != event.pointer || _startPosition == null || _triggered) {
      return;
    }

    final delta = event.position - _startPosition!;
    if (delta.dx < widget.triggerDistance) return;
    if (delta.dy.abs() > widget.maxVerticalDrift) {
      _reset();
      return;
    }

    _triggered = true;
    final navigator =
        widget.navigatorKey?.currentState ?? Navigator.of(context);
    navigator.maybePop();
  }

  void _reset() {
    _pointerId = null;
    _startPosition = null;
    _triggered = false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: (_) => _reset(),
      onPointerCancel: (_) => _reset(),
      child: widget.child,
    );
  }
}
