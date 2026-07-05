import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/app_settings_service.dart';

Future<List<String>?> showQuickAnswersSelectionDialog(
  BuildContext context, {
  required AppSettingsService settingsService,
  required List<String> selectedAnswerIds,
}) {
  final allAnswers = settingsService.settings.quickAnswers;
  final selectedSet = selectedAnswerIds.toSet();
  final orderedAnswers = [
    // Keep already enabled answers at the top so existing selections are easy to review.
    for (final answerId in selectedAnswerIds)
      for (final answer in allAnswers)
        if (answer.id == answerId) answer,
    for (final answer in allAnswers)
      if (!selectedSet.contains(answer.id)) answer,
  ];
  final draftSelection = selectedSet.intersection(
    allAnswers.map((answer) => answer.id).toSet(),
  );

  return showDialog<List<String>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(dialogContext.l10n.settings_quickAnswersSelect),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.6,
            ),
            child: orderedAnswers.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(dialogContext.l10n.common_notAvailable),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: orderedAnswers.length,
                    itemBuilder: (context, index) {
                      final answer = orderedAnswers[index];
                      final iconColor = Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant;
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: draftSelection.contains(answer.id),
                        title: Row(
                          children: [
                            Flexible(child: Text(answer.text)),
                            if (answer.sendAtSelect) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.flash_on_outlined,
                                size: 16,
                                color: iconColor,
                              ),
                            ],
                          ],
                        ),
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              draftSelection.add(answer.id);
                            } else {
                              draftSelection.remove(answer.id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, [
                for (final answer in orderedAnswers)
                  if (draftSelection.contains(answer.id)) answer.id,
              ]);
            },
            child: Text(dialogContext.l10n.common_save),
          ),
        ],
      ),
    ),
  );
}
