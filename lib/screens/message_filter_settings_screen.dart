import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/channel.dart';
import '../models/message_filter.dart';
import '../services/message_filter/message_filter_service.dart';
import '../widgets/channel_filter_rule_dialog.dart';

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
    final result = await showChannelFilterRuleDialog(context, rule: rule);
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
            if (settings.duplicates)
              ListTile(
                title: Text(l10n.messageFilter_repeatSends),
                subtitle: Text(
                  l10n.messageFilter_repeatSendsSubtitle(settings.repeatSends),
                ),
                trailing: DropdownButton<int>(
                  key: const ValueKey('messageFilter_repeatSends'),
                  value: settings.repeatSends,
                  onChanged: _saving || !settings.enabled
                      ? null
                      : (value) {
                          if (value == null) return;
                          _save(
                            () => service.updateSettings(
                              settings.copyWith(repeatSends: value),
                            ),
                          );
                        },
                  items: [
                    for (
                      var sends = MessageFilterSettings.minRepeatSends;
                      sends <= MessageFilterSettings.maxRepeatSends;
                      sends++
                    )
                      DropdownMenuItem(value: sends, child: Text('$sends')),
                  ],
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
                  '${filterRuleFieldLabel(context, rule.field)} · '
                  '${filterRuleMatchLabel(context, rule.match)}',
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
                      : (enabled) => _save(
                          () => service.setChannelExcluded(
                            entry.key,
                            excluded: enabled != true,
                          ),
                        ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
