import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../helpers/mcoa_theme_options.dart';

/// Nullable color override with a palette swatch and an editable HEX value.
/// The fallback is drawn by the swatch, but is never written to the theme.
class McoaThemeColorControl extends StatefulWidget {
  const McoaThemeColorControl({
    super.key,
    required this.id,
    required this.label,
    required this.color,
    required this.fallback,
    required this.onChanged,
    required this.onPick,
  });

  final String id;
  final String label;
  final Color? color;
  final Color fallback;
  final ValueChanged<Color?> onChanged;
  final VoidCallback onPick;

  @override
  State<McoaThemeColorControl> createState() => _McoaThemeColorControlState();
}

class _McoaThemeColorControlState extends State<McoaThemeColorControl> {
  late final TextEditingController _hex;
  final _focus = FocusNode();

  static String _format(Color color) {
    final hex = McoaThemeOptions.hex(color);
    return color.a == 1 ? '#${hex.substring(3)}' : hex;
  }

  static Color? _parse(String text) {
    final hex = text.trim();
    return McoaThemeOptions.parseColor(hex.startsWith('#') ? hex : '#$hex');
  }

  @override
  void initState() {
    super.initState();
    _hex = TextEditingController(
      text: widget.color == null ? '' : _format(widget.color!),
    );
    _focus.addListener(_finishEditing);
  }

  @override
  void didUpdateWidget(covariant McoaThemeColorControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) {
      if (widget.color == null) {
        if (_hex.text.isNotEmpty) {
          _hex.clear();
        }
      } else if (_parse(_hex.text) != widget.color) {
        _hex.text = _format(widget.color!);
      }
    }
  }

  void _finishEditing() {
    if (!_focus.hasFocus && _hex.text.isNotEmpty && _parse(_hex.text) == null) {
      _hex.text = widget.color == null ? '' : _format(widget.color!);
    }
  }

  void _changed(String text) {
    if (text.trim().isEmpty) {
      widget.onChanged(null);
      return;
    }
    final color = _parse(text);
    if (color != null) {
      widget.onChanged(color);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_finishEditing);
    _focus.dispose();
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 104,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: widget.label,
          child: InkWell(
            onTap: widget.onPick,
            borderRadius: BorderRadius.circular(5),
            child: Container(
              key: ValueKey('mcoa-color-swatch-${widget.id}'),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: widget.color ?? widget.fallback,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Theme.of(context).colorScheme.outline),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          key: ValueKey('mcoa-color-hex-${widget.id}'),
          controller: _hex,
          focusNode: _focus,
          style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
          textAlign: TextAlign.center,
          maxLength: 9,
          maxLines: 1,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
          ],
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            hintText: _format(widget.fallback),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            border: const OutlineInputBorder(),
          ),
          onChanged: _changed,
        ),
      ],
    ),
  );
}
