import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../helpers/message_markup.dart';
import '../helpers/utf8_length_limiter.dart';
import '../l10n/l10n.dart';

/// A [TextField] that displays a live UTF-8 byte counter.
///
/// The counter appears below the field once the user starts typing and changes
/// colour as the limit is approached (orange at 70 %, error-red at 90 %).
///
/// All standard [TextField] behaviour (focus nodes, input actions, decoration
/// overrides, etc.) is forwarded so the widget can be dropped into any screen.
class ByteCountedTextField extends StatelessWidget {
  /// Maximum number of UTF-8 bytes allowed.
  final int maxBytes;

  /// Controller for the text field.
  final TextEditingController controller;

  /// Optional focus node forwarded to the inner [TextField].
  final FocusNode? focusNode;

  /// Hint text shown when the field is empty.
  final String? hintText;

  /// Keyboard action button. When null it resolves to
  /// [TextInputAction.newline] on phones — where the action button replaces the
  /// return key, so anything else costs the user line breaks — and to
  /// [TextInputAction.send] everywhere else.
  final TextInputAction? textInputAction;

  /// Called when the user submits via the keyboard action button.
  final ValueChanged<String>? onSubmitted;

  /// Additional [TextInputFormatter]s applied *before* the byte limiter.
  final List<TextInputFormatter> extraFormatters;

  /// Text capitalisation forwarded to the inner [TextField].
  final TextCapitalization textCapitalization;

  /// Optional full [InputDecoration] override.  When provided, [hintText] is
  /// ignored – set it inside the decoration instead.
  final InputDecoration? decoration;

  /// Ratio (0–1) at which the counter turns the warning colour (default 0.7).
  final double warningThreshold;

  /// Ratio (0–1) at which the counter turns the error colour (default 0.9).
  final double errorThreshold;

  /// Whether to hide the counter when the field is empty (default `true`).
  final bool hideCounterWhenEmpty;

  /// Optional encoder function to transform text before byte counting/limiting.
  /// If provided, byte limits and counters will use the encoded text length.
  final String Function(String)? encoder;

  /// Minimum number of visible lines before the field starts expanding.
  final int minLines;

  /// Optional maximum height for the input area before it becomes scrollable.
  final double? maxHeight;

  /// Whether the text field accepts input.
  final bool enabled;

  const ByteCountedTextField({
    super.key,
    required this.maxBytes,
    required this.controller,
    this.focusNode,
    this.hintText,
    this.textInputAction,
    this.onSubmitted,
    this.extraFormatters = const [],
    this.textCapitalization = TextCapitalization.sentences,
    this.decoration,
    this.warningThreshold = 0.7,
    this.errorThreshold = 0.9,
    this.hideCounterWhenEmpty = true,
    this.encoder,
    this.minLines = 1,
    this.maxHeight,
    this.enabled = true,
  });

  bool get _usesDesktopEnterHandling {
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  /// Phone keyboards have no separate return key: the action button takes its
  /// place. Asking for [TextInputAction.send] there would make line breaks
  /// impossible to type, so the action becomes a newline and sending stays on
  /// the composer's own button.
  TextInputAction get _effectiveTextInputAction {
    if (textInputAction != null) return textInputAction!;
    final isPhone =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return isPhone ? TextInputAction.newline : TextInputAction.send;
  }

  /// Wraps the selection in [marker], the toolbar and shortcut counterpart of
  /// typing the markers by hand. With nothing selected it drops an empty pair
  /// at the caret and puts the caret between them, the way editors do.
  void _wrapSelection(String marker) {
    final value = controller.value;
    final selection = value.selection;
    if (!selection.isValid) return;
    final selected = value.text.substring(selection.start, selection.end);
    final wrapped = '$marker$selected$marker';
    var next = TextEditingValue(
      text: value.text.replaceRange(selection.start, selection.end, wrapped),
      selection: TextSelection(
        baseOffset: selection.start + marker.length,
        extentOffset: selection.start + marker.length + selected.length,
      ),
    );
    next = Utf8LengthLimitingTextInputFormatter(
      maxBytes,
      encoder: encoder,
    ).formatEditUpdate(value, next);
    controller.value = next;
  }

  List<ContextMenuButtonItem> _formattingButtons(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return const [];
    final l10n = context.l10n;
    final labels = <String, String>{
      MessageMarkup.bold: l10n.chat_formatBold,
      MessageMarkup.italic: l10n.chat_formatItalic,
      MessageMarkup.underline: l10n.chat_formatUnderline,
      MessageMarkup.strikethrough: l10n.chat_formatStrikethrough,
      MessageMarkup.mono: l10n.chat_formatMono,
    };
    return [
      for (final entry in labels.entries)
        ContextMenuButtonItem(
          label: entry.value,
          onPressed: () {
            editableTextState.hideToolbar();
            _wrapSelection(entry.key);
          },
        ),
    ];
  }

  /// Undoes formatting over the selection: drops the markers it contains and,
  /// when it holds none, the pair immediately around it — which is the case
  /// when the user selected the styled words rather than the markers.
  void _clearFormatting() {
    final value = controller.value;
    final selection = value.selection;
    if (!selection.isValid || selection.isCollapsed) return;

    var before = value.text.substring(0, selection.start);
    var after = value.text.substring(selection.end);
    final selected = value.text.substring(selection.start, selection.end);

    final buffer = StringBuffer();
    for (final segment in MessageMarkup.parse(selected, keepMarkers: true)) {
      if (!segment.isMarker) buffer.write(segment.text);
    }
    final stripped = buffer.toString();

    if (stripped == selected) {
      for (final marker in MessageMarkup.markers) {
        if (before.endsWith(marker) && after.startsWith(marker)) {
          before = before.substring(0, before.length - marker.length);
          after = after.substring(marker.length);
          break;
        }
      }
    }

    controller.value = TextEditingValue(
      text: '$before$stripped$after',
      selection: TextSelection(
        baseOffset: before.length,
        extentOffset: before.length + stripped.length,
      ),
    );
  }

  /// Enter sends and Shift+Enter breaks the line where a hardware keyboard
  /// is the norm; the formatting combos ride alongside them.
  Map<ShortcutActivator, VoidCallback> get _shortcutBindings {
    if (!enabled) return const {};
    return {
      if (_usesDesktopEnterHandling && onSubmitted != null) ...{
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            onSubmitted!(controller.text),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
            onSubmitted!(controller.text),
        const SingleActivator(LogicalKeyboardKey.enter, shift: true): () =>
            _insertText('\n'),
        const SingleActivator(
          LogicalKeyboardKey.numpadEnter,
          shift: true,
        ): () =>
            _insertText('\n'),
      },
      ..._formattingShortcuts,
    };
  }

  bool get _isMacOS => defaultTargetPlatform == TargetPlatform.macOS;

  bool get _isDesktop => _usesDesktopEnterHandling || _isMacOS;

  /// Formatting shortcuts, keyboard-only so they exist on desktop alone.
  /// macOS follows its own conventions for underline and monospace.
  Map<ShortcutActivator, VoidCallback> get _formattingShortcuts {
    if (!_isDesktop) return const {};
    final mac = _isMacOS;
    SingleActivator combo(LogicalKeyboardKey key, {bool shift = false}) =>
        SingleActivator(key, control: !mac, meta: mac, shift: shift);
    return {
      combo(LogicalKeyboardKey.keyB): () =>
          _wrapSelection(MessageMarkup.bold),
      combo(LogicalKeyboardKey.keyI): () =>
          _wrapSelection(MessageMarkup.italic),
      combo(LogicalKeyboardKey.keyU, shift: mac): () =>
          _wrapSelection(MessageMarkup.underline),
      combo(LogicalKeyboardKey.keyX, shift: true): () =>
          _wrapSelection(MessageMarkup.strikethrough),
      if (mac)
        combo(LogicalKeyboardKey.keyK, shift: true): () =>
            _wrapSelection(MessageMarkup.mono)
      else ...{
        combo(LogicalKeyboardKey.keyM, shift: true): () =>
            _wrapSelection(MessageMarkup.mono),
        combo(LogicalKeyboardKey.keyN, shift: true): _clearFormatting,
      },
    };
  }

  void _insertText(String text) {
    final oldValue = controller.value;
    final selection = oldValue.selection;
    final start = selection.isValid
        ? selection.start.clamp(0, oldValue.text.length).toInt()
        : oldValue.text.length;
    final end = selection.isValid
        ? selection.end.clamp(0, oldValue.text.length).toInt()
        : oldValue.text.length;
    final normalizedStart = start < end ? start : end;
    final normalizedEnd = start < end ? end : start;
    final newText = oldValue.text.replaceRange(
      normalizedStart,
      normalizedEnd,
      text,
    );
    var newValue = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: normalizedStart + text.length),
    );

    newValue = Utf8LengthLimitingTextInputFormatter(
      maxBytes,
      encoder: encoder,
    ).formatEditUpdate(oldValue, newValue);
    controller.value = newValue;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final effectiveText = encoder != null
            ? encoder!(value.text)
            : value.text;
        final usedBytes = utf8.encode(effectiveText).length;
        final ratio = maxBytes > 0 ? usedBytes / maxBytes : 0.0;
        final showCounter = !(hideCounterWhenEmpty && value.text.isEmpty);

        final counterColor = ratio > errorThreshold
            ? Theme.of(context).colorScheme.error
            : ratio > warningThreshold
            ? Theme.of(context).colorScheme.tertiary
            : Theme.of(context).colorScheme.onSurfaceVariant;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: maxHeight ?? double.infinity,
              ),
              child: CallbackShortcuts(
                bindings: _shortcutBindings,
                child: TextField(
                  minLines: minLines,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  scrollPhysics: const BouncingScrollPhysics(),
                  textAlignVertical: TextAlignVertical.top,
                  controller: controller,
                  focusNode: focusNode,
                  enabled: enabled,
                  inputFormatters: [
                    ...extraFormatters,
                    Utf8LengthLimitingTextInputFormatter(
                      maxBytes,
                      encoder: encoder,
                    ),
                  ],
                  textCapitalization: textCapitalization,
                  decoration:
                      decoration ??
                      InputDecoration(
                        hintText: hintText,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                  textInputAction: _effectiveTextInputAction,
                  onSubmitted: onSubmitted,
                  contextMenuBuilder: (context, editableTextState) =>
                      AdaptiveTextSelectionToolbar.buttonItems(
                        anchors: editableTextState.contextMenuAnchors,
                        buttonItems: [
                          ...editableTextState.contextMenuButtonItems,
                          ..._formattingButtons(context, editableTextState),
                        ],
                      ),
                ),
              ),
            ),
            Opacity(
              opacity: showCounter ? 1 : 0,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, right: 4),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '$usedBytes / $maxBytes',
                    style: TextStyle(fontSize: 11, color: counterColor),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
