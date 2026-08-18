import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Horizontal drag recognizer that only claims pointers starting inside the
/// back-swipe zone. Filtering in [isPointerAllowed] keeps the recognizer out of
/// the gesture arena entirely for pointers elsewhere on the screen, so content
/// outside the zone keeps its own horizontal gestures untouched.
class _ZoneHorizontalDragRecognizer extends HorizontalDragGestureRecognizer {
  _ZoneHorizontalDragRecognizer({required this.zoneWidth, required super.debugOwner});

  final double Function() zoneWidth;

  @override
  bool isPointerAllowed(PointerEvent event) {
    if (event.position.dx > zoneWidth()) return false;
    return super.isPointerAllowed(event);
  }
}

/// Count of screens currently asking for the app-level back-swipe to stay off.
/// A counter rather than a flag, so overlapping screens cannot re-enable it for
/// each other while one of them is still on top.
final ValueNotifier<int> _edgeSwipeSuppressions = ValueNotifier<int>(0);

/// Switches the app-level back-swipe off entirely while the screen is mounted.
///
/// Mix into the State of screens that own horizontal dragging end to end — the
/// drawing canvas, for example — where even the pull-and-spring-back preview
/// would be wrong. Screens that merely must not be popped should use PopScope
/// instead: that refuses the pop but still lets the gesture respond, so the
/// user can see the screen resist.
mixin EdgeSwipePopSuppression<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    _edgeSwipeSuppressions.value++;
  }

  @override
  void dispose() {
    _edgeSwipeSuppressions.value--;
    super.dispose();
  }
}

/// Drag-from-the-left-side gesture that pops the current route.
///
/// The screen follows the finger with resistance while dragging, so the pop is
/// previewed rather than fired blindly: releasing short of the threshold
/// springs the screen back and cancels. Because a real drag recognizer is used
/// (not a passive pointer listener), sliders, maps and horizontal lists win the
/// gesture arena over this widget and keep working normally.
class EdgeSwipePop extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;
  final bool enabled;

  /// Start zone as a fraction of the screen width, floored by [minEdgeWidth].
  /// Half the width by default: the recognizer competes in the gesture arena,
  /// so content that wants horizontal drags keeps them and a wide zone costs
  /// nothing but reach.
  final double edgeFraction;
  final double minEdgeWidth;

  /// Horizontal distance that commits the pop, as a fraction of the width and
  /// with an absolute floor.
  final double triggerFraction;
  final double minTriggerDistance;

  /// A quick flick commits even before [triggerFraction] is reached.
  final double commitVelocity;

  /// How far the screen may travel while following the finger.
  final double maxFollowFraction;

  /// Drag distance is multiplied by this before being applied, so the screen
  /// trails the finger instead of sticking to it.
  final double followResistance;

  const EdgeSwipePop({
    super.key,
    required this.child,
    this.navigatorKey,
    this.enabled = true,
    this.edgeFraction = 0.5,
    this.minEdgeWidth = 36,
    this.triggerFraction = 0.18,
    this.minTriggerDistance = 84,
    this.commitVelocity = 700,
    this.maxFollowFraction = 0.32,
    this.followResistance = 0.55,
  });

  @override
  State<EdgeSwipePop> createState() => _EdgeSwipePopState();
}

class _EdgeSwipePopState extends State<EdgeSwipePop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(_applySettleValue);
  final ValueNotifier<double> _offset = ValueNotifier<double>(0);
  double _settleFrom = 0;
  double _dragDistance = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _edgeSwipeSuppressions.addListener(_handleSuppressionChanged);
  }

  @override
  void dispose() {
    _edgeSwipeSuppressions.removeListener(_handleSuppressionChanged);
    _settle.dispose();
    _offset.dispose();
    super.dispose();
  }

  bool get _suppressed => _edgeSwipeSuppressions.value > 0;

  void _handleSuppressionChanged() {
    if (!mounted) return;
    // A screen may switch the gesture off mid-drag (it can be pushed by a
    // button while a drag is in flight), so drop any partial pull as well.
    if (_suppressed && (_dragging || _offset.value != 0)) {
      _dragging = false;
      _settle.stop();
      _offset.value = 0;
    }
    setState(() {});
  }

  void _applySettleValue() {
    final t = Curves.easeOutCubic.transform(_settle.value);
    _offset.value = _settleFrom * (1 - t);
  }

  double get _screenWidth => MediaQuery.sizeOf(context).width;

  double get _zoneWidth =>
      math.max(widget.minEdgeWidth, _screenWidth * widget.edgeFraction);

  double get _triggerDistance => math.max(
    widget.minTriggerDistance,
    _screenWidth * widget.triggerFraction,
  );

  double get _maxFollow => _screenWidth * widget.maxFollowFraction;

  NavigatorState? get _navigator =>
      widget.navigatorKey?.currentState ?? Navigator.maybeOf(context);

  void _handleDragStart(DragStartDetails details) {
    if (!widget.enabled || _suppressed) return;
    if (!(_navigator?.canPop() ?? false)) return;
    _settle.stop();
    _dragging = true;
    _dragDistance = 0;
    _offset.value = 0;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    _dragDistance = math.max(0, _dragDistance + details.delta.dx);
    // Resistance plus a hard cap: the screen hints at the pop instead of
    // sliding all the way off, which keeps the gap behind it small.
    final followed = _dragDistance * widget.followResistance;
    _offset.value = math.min(followed, _maxFollow);
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final shouldPop =
        _dragDistance >= _triggerDistance || velocity >= widget.commitVelocity;
    if (shouldPop) {
      // A route may refuse to pop (PopScope). The screen springs back either
      // way, so a blocked screen visibly resists instead of silently ignoring.
      _navigator?.maybePop();
    }
    _springBack();
  }

  void _handleDragCancel() {
    if (!_dragging) return;
    _dragging = false;
    _springBack();
  }

  void _springBack() {
    _settleFrom = _offset.value;
    if (_settleFrom == 0) return;
    _settle
      ..stop()
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _suppressed) return widget.child;

    final content = ValueListenableBuilder<double>(
      valueListenable: _offset,
      child: widget.child,
      builder: (context, offset, child) {
        if (offset == 0) return child!;
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
    );

    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        _ZoneHorizontalDragRecognizer:
            GestureRecognizerFactoryWithHandlers<
              _ZoneHorizontalDragRecognizer
            >(
              () => _ZoneHorizontalDragRecognizer(
                zoneWidth: () => _zoneWidth,
                debugOwner: this,
              ),
              (recognizer) {
                recognizer
                  ..onStart = _handleDragStart
                  ..onUpdate = _handleDragUpdate
                  ..onEnd = _handleDragEnd
                  ..onCancel = _handleDragCancel;
              },
            ),
      },
      child: content,
    );
  }
}
