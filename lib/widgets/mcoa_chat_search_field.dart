import 'package:flutter/material.dart';

import 'mcoa_chat_list_style.dart';

/// The production search field and inert preview share palette resolution.
/// Unset colors preserve the effective InputDecorationTheme and field style.
class McoaChatSearchField extends StatelessWidget {
  const McoaChatSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.decoration,
    this.onChanged,
    this.autofocus = false,
    this.readOnly = false,
    this.contacts = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final InputDecoration decoration;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool readOnly;
  final bool contacts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effective = decoration.applyDefaults(theme.inputDecorationTheme);
    final borderColor = McoaChatListStyle.override(context, 'search_border');
    final background = McoaChatListStyle.searchBackground(context, contacts: contacts);
    final ink = McoaChatListStyle.override(context, 'search_text');
    final hint = McoaChatListStyle.override(context, 'search_hint_icons');
    InputBorder? border(InputBorder? original) => borderColor == null ? original
        : (original ?? effective.border ?? const OutlineInputBorder()).copyWith(
            borderSide: (original?.borderSide ?? effective.border?.borderSide ?? const BorderSide())
                .copyWith(color: borderColor),
          );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      autofocus: autofocus,
      readOnly: readOnly,
      style: ink == null ? null : (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(color: ink),
      decoration: effective.copyWith(
        filled: background == null ? effective.filled : true,
        fillColor: background ?? effective.fillColor,
        hintStyle: hint == null ? effective.hintStyle
            : (effective.hintStyle ?? const TextStyle()).copyWith(color: hint),
        prefixIconColor: hint ?? effective.prefixIconColor,
        suffixIconColor: hint ?? effective.suffixIconColor,
        border: border(effective.border),
        enabledBorder: border(effective.enabledBorder),
        focusedBorder: border(effective.focusedBorder),
        disabledBorder: border(effective.disabledBorder),
        errorBorder: border(effective.errorBorder),
        focusedErrorBorder: border(effective.focusedErrorBorder),
      ),
    );
  }
}
