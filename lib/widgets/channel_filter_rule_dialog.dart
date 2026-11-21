import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/message_filter.dart';
import '../helpers/sender_filter_identity.dart';

Future<({FilterRule? rule})?> showChannelFilterRuleDialog(
  BuildContext context, {
  FilterRule? rule,
  String initialPattern = '',
}) => showDialog<({FilterRule? rule})>(
  context: context,
  builder: (_) => _RuleDialog(rule: rule, initialPattern: initialPattern),
);

String filterRuleFieldLabel(BuildContext context, FilterRuleField field) =>
    switch (field) {
      FilterRuleField.text => context.l10n.messageFilter_ruleFieldText,
      FilterRuleField.sender => context.l10n.messageFilter_ruleFieldSender,
      FilterRuleField.both => context.l10n.messageFilter_ruleFieldBoth,
      FilterRuleField.mcmpKey => context.l10n.messageFilter_ruleFieldMcmpKey,
    };

String filterRuleMatchLabel(BuildContext context, FilterRuleMatch match) =>
    switch (match) {
      FilterRuleMatch.contains => context.l10n.messageFilter_ruleMatchContains,
      FilterRuleMatch.wholeWord => context.l10n.messageFilter_ruleMatchWholeWord,
      FilterRuleMatch.exact => context.l10n.messageFilter_ruleMatchExact,
    };

class _RuleDialog extends StatefulWidget {
  const _RuleDialog({required this.rule, required this.initialPattern});

  final FilterRule? rule;
  final String initialPattern;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final _pattern = TextEditingController(
    text: widget.rule?.senderKeyHex ?? widget.rule?.pattern ?? widget.initialPattern,
  );
  late var _field = widget.rule?.senderKeyHex != null
      ? FilterRuleField.mcmpKey : widget.rule?.field ?? FilterRuleField.text;
  late var _match = widget.rule?.senderKeyHex != null
      ? FilterRuleMatch.exact : widget.rule?.match ?? FilterRuleMatch.contains;

  @override
  void dispose() {
    _pattern.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rule = widget.rule;
    final small = Theme.of(context).textTheme.bodySmall;
    final isKey = _field == FilterRuleField.mcmpKey;
    final key = SenderFilterIdentity.normalizeKey(_pattern.text);
    final labelRoom = MediaQuery.textScalerOf(context).scale(16);
    return AlertDialog(
      scrollable: true,
      constraints: const BoxConstraints(maxWidth: 560),
      title: Text(
        rule == null ? l10n.messageFilter_addRule : l10n.messageFilter_editRule,
      ),
      // The floating label needs room above the field inside the viewport.
      contentPadding: EdgeInsets.fromLTRB(24, labelRoom + 8, 24, 24),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _pattern,
              style: small,
              scrollPadding: EdgeInsets.fromLTRB(20, 20 + labelRoom, 20, 20),
              minLines: 1,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.messageFilter_rulePattern,
                labelStyle: small, hintStyle: small,
                errorText: isKey && _pattern.text.isNotEmpty && key == null
                    ? l10n.messageFilter_invalidMcmpKey : null,
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<FilterRuleField>(
              initialValue: _field,
              style: small,
              isExpanded: true,
              decoration: InputDecoration(labelText: l10n.messageFilter_ruleWhere, labelStyle: small),
              items: [
                for (final field in FilterRuleField.values)
                  DropdownMenuItem(
                    value: field,
                    child: Text(filterRuleFieldLabel(context, field)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _field = value;
                    if (value == FilterRuleField.mcmpKey) {
                      _match = FilterRuleMatch.exact;
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<FilterRuleMatch>(
              key: ValueKey(isKey),
              style: small,
              initialValue: _match,
              isExpanded: true,
              decoration: InputDecoration(labelText: l10n.messageFilter_ruleMatch, labelStyle: small),
              items: [
                for (final match in FilterRuleMatch.values)
                  DropdownMenuItem(
                    value: match,
                    child: Text(filterRuleMatchLabel(context, match)),
                  ),
              ],
              onChanged: isKey ? null : (value) {
                if (value != null) _match = value;
              },
            ),
          ],
        ),
      ),
      actions: [
        if (rule != null)
          TextButton(
            onPressed: () => Navigator.pop(context, (rule: null)),
            child: Text(l10n.common_delete),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.common_cancel),
        ),
        FilledButton(
          onPressed: _pattern.text.trim().isEmpty || (isKey && key == null)
              ? null
              : () => Navigator.pop(
                  context,
                  (rule: FilterRule(
                    id: rule?.id ??
                        DateTime.now().microsecondsSinceEpoch.toString(),
                    pattern: isKey ? key! : _pattern.text.trim(),
                    field: _field,
                    match: _match,
                    enabled: rule?.enabled ?? true,
                    senderKeyHex: isKey ? key : null,
                  )),
                ),
          child: Text(l10n.common_save),
        ),
      ],
    );
  }
}
