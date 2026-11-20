import 'package:flutter/material.dart';

import '../helpers/mcoa_theme_options.dart';
import '../l10n/l10n.dart';
import 'channel_widget_color_picker.dart';

/// The channel widget's continuous HSV palette with a synchronized HEX input.
class McoaThemePalette extends StatefulWidget {
  const McoaThemePalette({super.key, required this.color, required this.onChanged});

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  State<McoaThemePalette> createState() => _McoaThemePaletteState();
}

class _McoaThemePaletteState extends State<McoaThemePalette> {
  late final TextEditingController _hex;

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
    _hex = TextEditingController(text: _format(widget.color));
  }

  @override
  void didUpdateWidget(covariant McoaThemePalette oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color && _parse(_hex.text) != widget.color) {
      _hex.text = _format(widget.color);
    }
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ChannelColorPalette(color: widget.color, onChanged: widget.onChanged),
      const SizedBox(height: 16),
      TextField(
        controller: _hex,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: context.l10n.themes_hexColor,
          hintText: '#RRGGBB / #AARRGGBB',
        ),
        onChanged: (text) {
          final color = _parse(text);
          if (color != null) {
            widget.onChanged(color);
          }
        },
      ),
    ],
  );
}
