import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/channel.dart';
import '../models/message_filter.dart';
import '../services/message_filter/message_filter_service.dart';

class MessageFilterSettingsScreen extends StatefulWidget {
  const MessageFilterSettingsScreen({
    super.key,
    required this.service,
    required this.channels,
  });

  final MessageFilterService service;
  final List<Channel> channels;

  @override
  State<MessageFilterSettingsScreen> createState() =>
      _MessageFilterSettingsScreenState();
}

class _MessageFilterSettingsScreenState
    extends State<MessageFilterSettingsScreen> {
  bool _saving = false;

  Future<void> _save(Future<void> Function() write) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await write();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.messageFilter_saveError)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editRule(FilterRule? rule) async {
    final result = await showDialog<({FilterRule? rule})>(
      context: context,
      builder: (_) => _RuleDialog(rule: rule),
    );
    if (result == null || !mounted) return;
    final replacement = result.rule;
    final rules = widget.service.rules;
    await _save(() => widget.service.replaceRules([
      for (final current in rules)
        if (current.id != rule?.id)
          current
        else
          ?replacement,
      if (rule == null) ?replacement,
    ]));
  }

  Future<void> _resetLearning() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.messageFilter_resetLearning),
        content: Text(l10n.messageFilter_resetLearningConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.messageFilter_resetLearning),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _save(widget.service.resetLearning);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final service = widget.service;
    final settings = service.settings;
    final channelsByKey = <String, Channel>{
      for (final channel in widget.channels)
        ?channel.storageId: channel,
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.messageFilter_title)),
      body: SafeArea(
        child: ListView(
          children: [
            SwitchListTile(
              title: Text(l10n.messageFilter_enabled),
              subtitle: Text(l10n.messageFilter_enabledSubtitle),
              value: settings.enabled,
              onChanged: _saving
                  ? null
                  : (enabled) => _save(
                      () => service.updateSettings(
                        settings.copyWith(enabled: enabled),
                      ),
                    ),
            ),
            SwitchListTile(
              title: Text(l10n.messageFilter_displayHide),
              subtitle: Text(l10n.messageFilter_displayHideHelp),
              value: settings.hideFiltered,
              onChanged: _saving
                  ? null
                  : (hide) => _save(
                      () => service.updateSettings(
                        settings.copyWith(hideFiltered: hide),
                      ),
                    ),
            ),
            const Divider(),
            ListTile(title: Text(l10n.messageFilter_automaticSection)),
            SwitchListTile(
              title: Text(l10n.messageFilter_duplicates),
              subtitle: Text(l10n.messageFilter_duplicatesSubtitle),
              value: settings.duplicates,
              onChanged: _saving
                  ? null
                  : (enabled) => _save(
                      () => service.updateSettings(
                        settings.copyWith(duplicates: enabled),
                      ),
                    ),
            ),
            SwitchListTile(
              title: Text(l10n.messageFilter_repeatedCharacters),
              subtitle: Text(l10n.messageFilter_repeatedCharactersSubtitle),
              value: settings.repeatedCharacters,
              onChanged: _saving
                  ? null
                  : (enabled) => _save(
                      () => service.updateSettings(
                        settings.copyWith(repeatedCharacters: enabled),
                      ),
                    ),
            ),
            if (MessageFilterService.learningAvailable) ...[
              SwitchListTile(
                title: Text(l10n.messageFilter_learning),
                subtitle: Text(
                  service.learningEnabled
                      ? l10n.messageFilter_learningSubtitle(
                          service.spamExampleCount,
                          service.notSpamExampleCount,
                        )
                      : l10n.messageFilter_learningSqlHelp,
                ),
                value: settings.learning,
                onChanged: _saving || !settings.enabled
                    ? null
                    : (enabled) => _save(
                        () => service.updateSettings(
                          settings.copyWith(learning: enabled),
                        ),
                      ),
              ),
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: Text(l10n.messageFilter_resetLearning),
                onTap: _saving ? null : _resetLearning,
              ),
            ],
            const Divider(),
            ListTile(
              title: Text(l10n.messageFilter_rulesSection),
              subtitle: Text(l10n.messageFilter_rulesScope),
            ),
            for (final rule in service.rules)
              ListTile(
                title: Text(rule.pattern),
                subtitle: Text(
                  '${_fieldLabel(context, rule.field)} · '
                  '${_matchLabel(context, rule.match)}',
                ),
                onTap: _saving ? null : () => _editRule(rule),
                trailing: Switch(
                  value: rule.enabled,
                  onChanged: _saving
                      ? null
                      : (enabled) => _save(
                          () => service.replaceRules([
                            for (final current in service.rules)
                              if (current.id == rule.id)
                                FilterRule(
                                  id: current.id,
                                  pattern: current.pattern,
                                  field: current.field,
                                  match: current.match,
                                  enabled: enabled,
                                )
                              else
                                current,
                          ]),
                        ),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(l10n.messageFilter_addRule),
              onTap: _saving ? null : () => _editRule(null),
            ),
            if (channelsByKey.isNotEmpty) ...[
              const Divider(),
              ListTile(title: Text(l10n.messageFilter_channelToggle)),
              for (final entry in channelsByKey.entries)
                CheckboxListTile(
                  title: Text(entry.value.name),
                  value: !settings.excludedChannelIds.contains(entry.key),
                  onChanged: _saving
                      ? null
                      : (enabled) {
                          final excluded = {...settings.excludedChannelIds};
                          if (enabled == true) {
                            excluded.remove(entry.key);
                          } else {
                            excluded.add(entry.key);
                          }
                          _save(
                            () => service.updateSettings(
                              settings.copyWith(excludedChannelIds: excluded),
                            ),
                          );
                        },
                ),
            ],
          ],
        ),
      ),
    );
  }
}

String _fieldLabel(BuildContext context, FilterRuleField field) =>
    switch (field) {
      FilterRuleField.text => context.l10n.messageFilter_ruleFieldText,
      FilterRuleField.sender => context.l10n.messageFilter_ruleFieldSender,
      FilterRuleField.both => context.l10n.messageFilter_ruleFieldBoth,
    };

String _matchLabel(BuildContext context, FilterRuleMatch match) =>
    switch (match) {
      FilterRuleMatch.contains => context.l10n.messageFilter_ruleMatchContains,
      FilterRuleMatch.wholeWord => context.l10n.messageFilter_ruleMatchWholeWord,
      FilterRuleMatch.exact => context.l10n.messageFilter_ruleMatchExact,
    };

class _RuleDialog extends StatefulWidget {
  const _RuleDialog({required this.rule});

  final FilterRule? rule;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final _pattern = TextEditingController(text: widget.rule?.pattern);
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
    return AlertDialog(
      scrollable: true,
      title: Text(
        rule == null ? l10n.messageFilter_addRule : l10n.messageFilter_editRule,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pattern,
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
                  child: Text(_fieldLabel(context, field)),
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
                  child: Text(_matchLabel(context, match)),
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
