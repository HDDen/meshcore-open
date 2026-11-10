import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FlutterView;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../helpers/chat_scroll_controller.dart';
import '../utils/platform_info.dart';

/// Handles the Android scrolling-screenshot session in Flutter view pixels.
class ScrollCaptureService {
  static const _channel = MethodChannel('mco_advanced/scroll_capture');
  static const _idleLimit = Duration(seconds: 5);
  static const _frameLimit = Duration(milliseconds: 250);

  static void initialize() {
    if (!PlatformInfo.isAndroid) return;
    _channel.setMethodCallHandler(ScrollCaptureService().handle);
  }

  int? _id;
  _Target? _target;
  _Capture? _capture;
  Timer? _watchdog;

  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments;
    if (args is! Map || args['id'] is! int) return null;
    final id = args['id'] as int;
    if (call.method == 'search') return _search(id);
    if (id != _id) return null;
    switch (call.method) {
      case 'start':
        return _start();
      case 'scroll':
        final top = args['top'];
        final bottom = args['bottom'];
        if (top is! int || bottom is! int || bottom <= top) return null;
        return _scroll(id, top, bottom);
      case 'end':
        if (_end(id)) {
          await WidgetsBinding.instance.endOfFrame.timeout(
            _frameLimit,
            onTimeout: () {},
          );
        }
    }
    return null;
  }

  Map<String, int>? _search(int id) {
    if (_capture != null) return null;
    final binding = WidgetsBinding.instance;
    final view = binding.platformDispatcher.implicitView;
    final root = binding.rootElement;
    if (view == null || root == null) return null;
    _Target? best;
    var bestArea = 0.0;

    void visit(Element element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final state = element.state as ScrollableState;
        final bounds = _visibleBounds(state, view);
        if (bounds != null) {
          final area = bounds.width * bounds.height;
          if (area > bestArea) {
            best = _Target(state, state.position, view, bounds);
            bestArea = area;
          }
        }
      }
      element.visitChildren(visit);
    }

    root.visitChildren(visit);
    final target = best;
    if (target == null) return null;
    _id = id;
    _target = target;
    _armWatchdog(id);
    return {
      'left': target.bounds.left.ceil(),
      'top': target.bounds.top.ceil(),
      'right': target.bounds.right.floor(),
      'bottom': target.bounds.bottom.floor(),
    };
  }

  bool _start() {
    final target = _target;
    if (target == null || _capture != null || !target.isCurrent ||
        target.position.isScrollingNotifier.value) {
      return false;
    }
    final controller = target.controller;
    final chat = controller is ChatScrollController ? controller : null;
    chat?.beginScrollCapture();
    _capture = _Capture(target, chat);
    _armWatchdog(_id!);
    return true;
  }

  Future<int?> _scroll(int id, int top, int bottom) async {
    final capture = _capture;
    if (capture == null) return null;
    final target = capture.target;
    if (!target.isCurrent) {
      _end(id);
      return null;
    }
    _armWatchdog(id);
    final position = target.position;
    final ratio = target.devicePixelRatio;
    final direction = target.axisDirection == AxisDirection.up ? -1 : 1;
    final offset = direction * (position.pixels - capture.startPixels) * ratio;
    final viewportHeight = target.bounds.bottom.floor() - target.bounds.top.ceil();
    final desired = top < offset
        ? top.toDouble()
        : math.max(offset, (bottom - viewportHeight).toDouble());
    final wanted = capture.startPixels + direction * desired / ratio;
    position.jumpTo(wanted.clamp(position.minScrollExtent, position.maxScrollExtent));
    try {
      await WidgetsBinding.instance.endOfFrame.timeout(_frameLimit);
      if (_capture != capture) return null;
      await WidgetsBinding.instance.endOfFrame.timeout(_frameLimit);
    } on TimeoutException {
      _end(id);
      return null;
    }
    if (_capture != capture) return null;
    if (!target.isCurrent) {
      _end(id);
      return null;
    }
    return (direction * (position.pixels - capture.startPixels) * ratio).round();
  }

  void _armWatchdog(int id) {
    _watchdog?.cancel();
    _watchdog = Timer(_idleLimit, () => _end(id));
  }

  bool _end(int id) {
    if (_id != id) return false;
    _watchdog?.cancel();
    _watchdog = null;
    final capture = _capture;
    _capture = null;
    _target = null;
    _id = null;
    if (capture == null) return false;
    try {
      final position = capture.target.positionForRestore;
      if (position == null) return false;
      position.jumpTo(capture.startPixels.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ));
      return true;
    } finally {
      capture.chat?.endScrollCapture();
    }
  }
}

class _Target {
  _Target(this.scrollable, this.position, this.view, this.bounds)
      : devicePixelRatio = view.devicePixelRatio,
        controller = scrollable.widget.controller,
        axisDirection = scrollable.axisDirection;

  final ScrollableState scrollable;
  final ScrollPosition position;
  final FlutterView view;
  final Rect bounds;
  final double devicePixelRatio;
  final ScrollController? controller;
  final AxisDirection axisDirection;

  ScrollPosition? get positionForRestore {
    if (!scrollable.mounted ||
        !identical(scrollable.widget.controller, controller) ||
        scrollable.axisDirection != axisDirection) {
      return null;
    }
    // Covering the route can recreate the position while retaining its offset.
    final current = scrollable.position;
    return current.hasContentDimensions ? current : null;
  }

  bool get isCurrent =>
      identical(positionForRestore, position) &&
      view.devicePixelRatio == devicePixelRatio &&
      _visibleBounds(scrollable, view) == bounds;
}

class _Capture {
  _Capture(this.target, this.chat) : startPixels = target.position.pixels;

  final _Target target;
  final ChatScrollController? chat;
  final double startPixels;
}

Rect? _visibleBounds(ScrollableState state, FlutterView view) {
  if (axisDirectionToAxis(state.axisDirection) != Axis.vertical) return null;
  final box = state.context.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  if (ModalRoute.isCurrentOf(state.context) == false) return null;
  final position = state.position;
  if (!position.hasContentDimensions ||
      !position.maxScrollExtent.isFinite ||
      position.maxScrollExtent <= position.minScrollExtent) {
    return null;
  }
  final translation = MatrixUtils.getAsTranslation(box.getTransformTo(null));
  if (translation == null) return null;
  var bounds = translation & box.size;
  RenderObject child = box;
  while (true) {
    final parent = child.parent;
    if (parent == null) break;
    final clip = parent.describeApproximatePaintClip(child);
    if (clip != null) {
      bounds = bounds.intersect(MatrixUtils.transformRect(parent.getTransformTo(null), clip));
    }
    child = parent;
  }
  final safe = view.viewPadding;
  final insets = view.viewInsets;
  final ratio = view.devicePixelRatio;
  final visible = Rect.fromLTRB(
    math.max(safe.left, insets.left),
    math.max(safe.top, insets.top),
    view.physicalSize.width - math.max(safe.right, insets.right),
    view.physicalSize.height - math.max(safe.bottom, insets.bottom),
  );
  final pixels = Rect.fromLTRB(
    bounds.left * ratio,
    bounds.top * ratio,
    bounds.right * ratio,
    bounds.bottom * ratio,
  ).intersect(visible);
  if (pixels.isEmpty || pixels.height < 100 * ratio) return null;

  final hit = HitTestResult();
  WidgetsBinding.instance.hitTestInView(hit, pixels.center / ratio, view.viewId);
  return hit.path.any((entry) => identical(entry.target, box)) ? pixels : null;
}
