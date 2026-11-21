import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/message_filter.dart';
import '../helpers/sender_filter_identity.dart';
import '../services/message_filter/message_filter_service.dart';
import 'channel_filter_rule_dialog.dart';

Future<void> addChannelSenderFilter(
  BuildContext context,
  MessageFilterService service, {
  required String channelId,
  required String sender,
  String? verifiedSenderKey,
}) async {
  final name = sender.trim();
  final key = SenderFilterIdentity.normalizeKey(verifiedSenderKey);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Text(context.l10n.messageFilter_filterSender),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(key == null
              ? context.l10n.messageFilter_filterSenderConfirm(name)
              : context.l10n.messageFilter_filterSenderKeyConfirm(name)),
          if (key != null) ...[
            const SizedBox(height: 12),
            Text(context.l10n.messageFilter_senderByKey),
            SelectableText(key),
          ],
        ],
      ),
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
      senderKeyHex: key,
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
