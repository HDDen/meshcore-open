import 'package:flutter/widgets.dart';

import 'message_markup.dart';

/// Text-editing operations behind the formatting toolbar, shortcuts and colour
/// palette. Pure transforms over a [TextEditingValue] so every entry point
/// behaves identically; callers apply their own byte limiter afterwards.
class MarkupEditing {
  MarkupEditing._();

  /// Wraps the selection in [opener] / [closer] and keeps the styled text
  /// selected. With nothing selected it drops an empty pair at the caret and
  /// puts the caret between them, the way editors do.
  static TextEditingValue wrap(
    TextEditingValue value,
    String opener,
    String closer,
  ) {
    final selection = value.selection;
    if (!selection.isValid) return value;
    final selected = value.text.substring(selection.start, selection.end);
    return TextEditingValue(
      text: value.text.replaceRange(
        selection.start,
        selection.end,
        '$opener$selected$closer',
      ),
      selection: TextSelection(
        baseOffset: selection.start + opener.length,
        extentOffset: selection.start + opener.length + selected.length,
      ),
    );
  }

  /// Undoes formatting over the selection: drops the markers it contains and,
  /// when it holds none, the pair immediately around it — which is the case
  /// when the user selected the styled words rather than the markers.
  static TextEditingValue stripFormatting(TextEditingValue value) {
    final selection = value.selection;
    if (!selection.isValid || selection.isCollapsed) return value;

    var before = value.text.substring(0, selection.start);
    var after = value.text.substring(selection.end);
    final selected = value.text.substring(selection.start, selection.end);

    final buffer = StringBuffer();
    for (final segment in MessageMarkup.parse(selected, keepMarkers: true)) {
      if (!segment.isMarker) buffer.write(segment.text);
    }
    final stripped = buffer.toString();

    if (stripped == selected) {
      for (final pair in _surroundingPairs) {
        if (before.endsWith(pair.opener) && after.startsWith(pair.closer)) {
          before = before.substring(0, before.length - pair.opener.length);
          after = after.substring(pair.closer.length);
          break;
        }
      }
    }

    return TextEditingValue(
      text: '$before$stripped$after',
      selection: TextSelection(
        baseOffset: before.length,
        extentOffset: before.length + stripped.length,
      ),
    );
  }

  /// Paired markers first, then colour tags — both can sit immediately around
  /// a selection that contains no markers of its own.
  static final List<({String opener, String closer})> _surroundingPairs = [
    for (final marker in MessageMarkup.markers)
      (opener: marker, closer: marker),
    for (final key in MessageMarkup.colorKeys)
      (opener: '[$key]', closer: '[/$key]'),
  ];
}
