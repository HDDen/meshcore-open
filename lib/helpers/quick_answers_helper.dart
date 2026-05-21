import 'package:flutter/widgets.dart';

import '../models/app_settings.dart';

List<String> filterAvailableQuickAnswerTexts({
  required List<String> selectedAnswerIds,
  required List<QuickAnswer> globalAnswers,
}) {
  final answersById = {for (final answer in globalAnswers) answer.id: answer};
  return [
    for (final answerId in selectedAnswerIds)
      if (answersById.containsKey(answerId)) answersById[answerId]!.text,
  ];
}

void insertQuickAnswerIntoComposer({
  required TextEditingController controller,
  required FocusNode focusNode,
  required String text,
}) {
  final value = controller.value;
  final selection = value.selection;
  final textLength = value.text.length;
  final hasValidSelection =
      selection.isValid &&
      selection.start <= textLength &&
      selection.end <= textLength;
  final start = hasValidSelection ? selection.start : textLength;
  final end = hasValidSelection ? selection.end : textLength;
  final newText = value.text.replaceRange(start, end, text);

  // Keep quick replies useful as command templates by inserting them exactly.
  controller.value = TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(offset: start + text.length),
  );
  focusNode.requestFocus();
}
