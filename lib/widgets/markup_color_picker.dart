import 'package:flutter/material.dart';

import '../helpers/message_markup.dart';
import '../l10n/l10n.dart';
import '../theme/mesh_theme.dart';

/// Colour picker behind the "text colour" action in the selection toolbar.
///
/// Ten colours are too many for the toolbar itself, so they live in their own
/// swatch grid. Returns the chosen key from `MessageMarkup.colorKeys`, or null
/// when dismissed.
Future<String?> showMarkupColorPicker(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.l10n.chat_formatColor),
      content: SizedBox(
        width: 260,
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final colorKey in MessageMarkup.colorKeys)
              _Swatch(
                colorKey: colorKey,
                onTap: () => Navigator.pop(dialogContext, colorKey),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(dialogContext.l10n.common_cancel),
        ),
      ],
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.colorKey, required this.onTap});

  final String colorKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MeshRadii.pill),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: MarkupPalette.colors[colorKey],
          shape: BoxShape.circle,
          // White and black swatches would vanish into the dialog surface
          // without an outline.
          border: Border.all(color: scheme.outlineVariant, width: 1),
        ),
      ),
    );
  }
}
