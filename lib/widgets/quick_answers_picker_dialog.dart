import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

Future<String?> showQuickAnswersPickerDialog(
  BuildContext context, {
  required List<String> answerTexts,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.l10n.settings_quickAnswersTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.6,
          ),
          child: answerTexts.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(dialogContext.l10n.settings_quickAnswersNotAdded),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: answerTexts.length,
                  itemBuilder: (context, index) {
                    final answer = answerTexts[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(answer),
                      onTap: () => Navigator.pop(dialogContext, answer),
                    );
                  },
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(dialogContext.l10n.common_close),
        ),
      ],
    ),
  );
}
