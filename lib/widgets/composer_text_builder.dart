import 'package:flutter/material.dart';

/// Rebuilds only when the controller's **text** changes.
///
/// A `TextEditingController` notifies on every value change, selection
/// included — and dragging an Android selection handle changes the selection
/// continuously. Rebuilding the composer through all of that rebuilds the text
/// field underneath the gesture, which is enough to make the handle stutter.
/// Everything in the composer that reacts to the controller only ever reads
/// the text, so it belongs here rather than on a raw `ValueListenableBuilder`.
class ComposerTextBuilder extends StatefulWidget {
  const ComposerTextBuilder({
    super.key,
    required this.controller,
    required this.builder,
  });

  final TextEditingController controller;
  final Widget Function(BuildContext context, String text) builder;

  @override
  State<ComposerTextBuilder> createState() => _ComposerTextBuilderState();
}

class _ComposerTextBuilderState extends State<ComposerTextBuilder> {
  late String _text = widget.controller.text;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(ComposerTextBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
      _text = widget.controller.text;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (widget.controller.text == _text) return;
    setState(() => _text = widget.controller.text);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _text);
}
