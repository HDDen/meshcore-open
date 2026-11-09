import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/message_filter.dart';
import '../services/message_filter/message_filter_service.dart';
import 'channel_filter_rule_dialog.dart';

Future<void> addChannelSenderFilter(
  BuildContext context,
  MessageFilterService service, {
  required String channelId,
  required String sender,
}) async {
  final name = sender.trim();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Text(context.l10n.messageFilter_filterSender),
      content: Text(context.l10n.messageFilter_filterSenderConfirm(name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.l10n.common_cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(context.l10n.common_save),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted || !service.appliesTo(channelId)) {
    return;
  }
  await _saveFilterChange(
    context,
    () => service.addRule(FilterRule(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      pattern: name,
      field: FilterRuleField.sender,
      match: FilterRuleMatch.exact,
    )),
    showRuleSaved: true,
  );
}

Future<void> addChannelTextFilter(
  BuildContext context,
  MessageFilterService service, {
  required String channelId,
  required String text,
}) async {
  final result = await showChannelFilterRuleDialog(context, initialPattern: text);
  final rule = result?.rule;
  if (rule == null || !context.mounted || !service.appliesTo(channelId)) return;
  await _saveFilterChange(
    context,
    () => service.addRule(rule),
    showRuleSaved: true,
  );
}

Future<void> toggleChannelMessageFilter(
  BuildContext context,
  MessageFilterService service,
  String channelId,
) => _saveFilterChange(
  context,
  () => service.setChannelExcluded(
    channelId,
    excluded: service.appliesTo(channelId),
  ),
);

Future<void> _saveFilterChange(
  BuildContext context,
  Future<void> Function() save, {
  bool showRuleSaved = false,
}) async {
  try {
    await save();
    if (showRuleSaved && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.messageFilter_ruleSaved)),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.messageFilter_saveError)),
      );
    }
  }
}
