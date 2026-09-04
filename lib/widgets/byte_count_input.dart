import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../helpers/markup_editing.dart';
import '../helpers/message_markup.dart';
import '../helpers/utf8_length_limiter.dart';
import '../l10n/l10n.dart';
import 'markup_color_picker.dart';

/// A [TextField] that displays a live UTF-8 byte counter.
///
/// The counter appears below the field once the user starts typing and changes
/// colour as the limit is approached (orange at 70 %, error-red at 90 %).
///
/// All standard [TextField] behaviour (focus nodes, input actions, decoration
/// overrides, etc.) is forwarded so the widget can be dropped into any screen.
class ByteCountedTextField extends StatefulWidget {
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

  /// Optional second budget: how many bytes the text is over it, shown as
  /// `(-N)` between the count and the limit, or null to show nothing.
  /// Evaluated together with [encoder], on text changes only.
  final int? Function(String text)? excessBytes;

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
    this.excessBytes,
    this.minLines = 1,
    this.maxHeight,
    this.enabled = true,
  });

  @override
  State<ByteCountedTextField> createState() => _ByteCountedTextFieldState();
}

class _ByteCountedTextFieldState extends State<ByteCountedTextField> {
  /// Cached counter input. Dragging an Android selection handle fires the
  /// controller on every pixel of travel, and recomputing the encoded length
  /// there means running MCMP or cyr2lat over the whole message dozens of
  /// times a second — enough dropped frames to make the handle stutter. Only a
  /// text change can move the byte count, so selection-only updates are
  /// ignored.
  late String _text = widget.controller.text;
  String? _encodedFor;
  int _usedBytes = 0;
  int? _excessBytes;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(ByteCountedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _text = widget.controller.text;
      _encodedFor = null;
    }
    if (oldWidget.encoder != widget.encoder ||
        oldWidget.excessBytes != widget.excessBytes) {
      _encodedFor = null;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (widget.controller.text == _text) return;
    setState(() => _text = widget.controller.text);
  }

  int get _byteCount {
    if (_encodedFor == _text) return _usedBytes;
    final encoder = widget.encoder;
    final effective = encoder != null ? encoder(_text) : _text;
    _usedBytes = utf8.encode(effective).length;
    _excessBytes = widget.excessBytes?.call(_text);
    _encodedFor = _text;
    return _usedBytes;
  }

  bool get _usesDesktopEnterHandling {
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  /// Phone keyboards have no separate return key: the action button takes its
  /// place. Asking for [TextInputAction.send] there would make line breaks
  /// impossible to type, so the action becomes a newline and sending stays on
  /// the composer's own button.
  TextInputAction get _effectiveTextInputAction {
    if (widget.textInputAction != null) return widget.textInputAction!;
    final isPhone =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return isPhone ? TextInputAction.newline : TextInputAction.send;
  }

  /// Wraps the selection, the toolbar and shortcut counterpart of typing the
  /// markers by hand. Paired markers pass the same string twice; colour tags
  /// pass `[key]` and `[/key]`.
  void _wrapSelection(String opener, [String? closer]) {
    final value = widget.controller.value;
    widget.controller.value = Utf8LengthLimitingTextInputFormatter(
      widget.maxBytes,
      encoder: widget.encoder,
    ).formatEditUpdate(
      value,
      MarkupEditing.wrap(value, opener, closer ?? opener),
    );
  }

  Future<void> _pickColor(BuildContext context) async {
    final key = await showMarkupColorPicker(context);
    if (key == null) return;
    _wrapSelection('[$key]', '[/$key]');
  }

  List<ContextMenuButtonItem> _formattingButtons(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final selection = widget.controller.selection;
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
      ContextMenuButtonItem(
        label: l10n.chat_formatColor,
        onPressed: () {
          editableTextState.hideToolbar();
          unawaited(_pickColor(context));
        },
      ),
    ];
  }

  void _clearFormatting() {
    widget.controller.value = MarkupEditing.stripFormatting(
      widget.controller.value,
    );
  }

  /// Enter sends and Shift+Enter breaks the line where a hardware keyboard
  /// is the norm; the formatting combos ride alongside them.
  Map<ShortcutActivator, VoidCallback> get _shortcutBindings {
    if (!widget.enabled) return const {};
    return {
      if (_usesDesktopEnterHandling && widget.onSubmitted != null) ...{
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            widget.onSubmitted!(widget.controller.text),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
            widget.onSubmitted!(widget.controller.text),
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
    final oldValue = widget.controller.value;
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
      widget.maxBytes,
      encoder: widget.encoder,
    ).formatEditUpdate(oldValue, newValue);
    widget.controller.value = newValue;
  }

  @override
  Widget build(BuildContext context) {
    final usedBytes = _byteCount;
    final excessBytes = _excessBytes;
    final ratio = widget.maxBytes > 0 ? usedBytes / widget.maxBytes : 0.0;
    final showCounter = !(widget.hideCounterWhenEmpty && _text.isEmpty);

    final counterColor = ratio > widget.errorThreshold
        ? Theme.of(context).colorScheme.error
        : ratio > widget.warningThreshold
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: widget.maxHeight ?? double.infinity,
          ),
          child: CallbackShortcuts(
            bindings: _shortcutBindings,
            child: TextField(
              minLines: widget.minLines,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              scrollPhysics: const BouncingScrollPhysics(),
              textAlignVertical: TextAlignVertical.top,
              controller: widget.controller,
              focusNode: widget.focusNode,
              enabled: widget.enabled,
              inputFormatters: [
                ...widget.extraFormatters,
                Utf8LengthLimitingTextInputFormatter(
                  widget.maxBytes,
                  encoder: widget.encoder,
                ),
              ],
              textCapitalization: widget.textCapitalization,
              decoration:
                  widget.decoration ??
                  InputDecoration(
                    hintText: widget.hintText,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
              textInputAction: _effectiveTextInputAction,
              onSubmitted: widget.onSubmitted,
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
                excessBytes == null
                    ? '$usedBytes / ${widget.maxBytes}'
                    : '$usedBytes (-$excessBytes) / ${widget.maxBytes}',
                style: TextStyle(fontSize: 11, color: counterColor),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
