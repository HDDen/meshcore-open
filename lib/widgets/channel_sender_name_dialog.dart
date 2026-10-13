import 'dart:convert';

import 'package:flutter/material.dart';

import '../helpers/utf8_length_limiter.dart';
import '../l10n/l10n.dart';

/// The dialog behind the channel header's *Sender* line: the name the channel
/// sends under, emptied for the node's own, limited to the bytes a node name
/// may have. The node's name is the hint, since that is what *default* means.
/// [onSave] gets the trimmed name, or null to clear it; Save is enabled only
/// by a change.
Future<void> showChannelSenderNameDialog(
  BuildContext context, {
  required String? currentName,
  required String? nodeName,
  required void Function(String? name) onSave,
}) {
  final current = currentName ?? '';
  final controller = TextEditingController(text: current);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final l10n = dialogContext.l10n;
      return AlertDialog(
        title: Text(l10n.channels_senderNameTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.channels_senderNameBody),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: nodeName,
                border: const OutlineInputBorder(),
              ),
              inputFormatters: const [
                Utf8LengthLimitingTextInputFormatter(maxRadioNameBytes),
              ],
            ),
            const SizedBox(height: 4),
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) => Text(
                l10n.channels_senderNameBytes(
                  utf8.encode(controller.text).length,
                  maxRadioNameBytes,
                ),
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.common_cancel),
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final name = controller.text.trim();
              return TextButton(
                onPressed: name == current
                    ? null
                    : () {
                        Navigator.pop(dialogContext);
                        onSave(name.isEmpty ? null : name);
                      },
                child: Text(l10n.common_save),
              );
            },
          ),
        ],
      );
    },
  );
}
