import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/message_filter.dart';

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
    text: widget.rule?.pattern ?? widget.initialPattern,
  );
  late var _field = widget.rule?.field ?? FilterRuleField.text;
  late var _match = widget.rule?.match ?? FilterRuleMatch.contains;

  @override
  void dispose() {
    _pattern.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rule = widget.rule;
    final labelRoom = MediaQuery.textScalerOf(context).scale(16);
    return AlertDialog(
      scrollable: true,
      title: Text(
        rule == null ? l10n.messageFilter_addRule : l10n.messageFilter_editRule,
      ),
      // The floating label needs room above the field inside the viewport.
      contentPadding: EdgeInsets.fromLTRB(24, labelRoom + 8, 24, 24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pattern,
            scrollPadding: EdgeInsets.fromLTRB(20, 20 + labelRoom, 20, 20),
            minLines: 1,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: l10n.messageFilter_rulePattern),
          ),
          DropdownButtonFormField<FilterRuleField>(
            initialValue: _field,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.messageFilter_ruleWhere),
            items: [
              for (final field in FilterRuleField.values)
                DropdownMenuItem(
                  value: field,
                  child: Text(filterRuleFieldLabel(context, field)),
                ),
            ],
            onChanged: (value) {
              if (value != null) _field = value;
            },
          ),
          DropdownButtonFormField<FilterRuleMatch>(
            initialValue: _match,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.messageFilter_ruleMatch),
            items: [
              for (final match in FilterRuleMatch.values)
                DropdownMenuItem(
                  value: match,
                  child: Text(filterRuleMatchLabel(context, match)),
                ),
            ],
            onChanged: (value) {
              if (value != null) _match = value;
            },
          ),
        ],
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
          onPressed: _pattern.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  (rule: FilterRule(
                    id: rule?.id ??
                        DateTime.now().microsecondsSinceEpoch.toString(),
                    pattern: _pattern.text.trim(),
                    field: _field,
                    match: _match,
                    enabled: rule?.enabled ?? true,
                  )),
                ),
          child: Text(l10n.common_save),
        ),
      ],
    );
  }
}
