import 'package:flutter/material.dart';

import '../helpers/settings_navigation_target.dart';

/// Opens a lazy settings list at an anchor once, without fighting later edits.
class TargetedSettingsList extends StatefulWidget {
  const TargetedSettingsList({super.key, required this.children,
    required this.padding, this.initialTarget});
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final SettingsNavigationTarget? initialTarget;

  @override
  State<TargetedSettingsList> createState() => _TargetedSettingsListState();
}

class _TargetedSettingsListState extends State<TargetedSettingsList> {
  final _controller = ScrollController();
  final _listKey = GlobalKey();
  bool _done = false;
  bool _rewind = true;
  bool _scheduled = false;
  int _steps = 0;
  int _stalled = 0;

  @override
  void didUpdateWidget(covariant TargetedSettingsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTarget != oldWidget.initialTarget) {
      _done = false;
      _rewind = true;
      _steps = 0;
      _stalled = 0;
    }
  }

  Element? _find(Element root, Key target) {
    if (root.widget.key == target) return root;
    Element? result;
    root.visitChildElements((child) {
      result ??= _find(child, target);
    });
    return result;
  }

  void _schedule() {
    if (_scheduled || _done || widget.initialTarget == null) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || _done || widget.initialTarget == null) return;
      final root = _listKey.currentContext;
      if (root is! Element || !_controller.hasClients) return;
      if (_rewind) {
        _rewind = false;
        _controller.jumpTo(_controller.position.minScrollExtent);
        _schedule();
        return;
      }
      final target = _find(root, widget.initialTarget!.key);
      if (target != null) {
        _done = true;
        Scrollable.ensureVisible(target, alignment: 0.1);
        return;
      }
      // A target further down a lazy list does not have an Element yet.
      // Walk by viewports, letting each frame build the next portion.
      final position = _controller.position;
      final next = (position.pixels + position.viewportDimension * 0.8)
          .clamp(position.minScrollExtent, position.maxScrollExtent).toDouble();
      _stalled = (next - position.pixels).abs() < 0.5 ? _stalled + 1 : 0;
      if (++_steps >= 160 || _stalled >= 3) {
        _done = true;
        return;
      }
      _controller.jumpTo(next);
      _schedule();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _schedule();
    return ListView(
      key: _listKey,
      controller: widget.initialTarget == null ? null : _controller,
      padding: widget.padding,
      children: widget.children,
    );
  }
}
