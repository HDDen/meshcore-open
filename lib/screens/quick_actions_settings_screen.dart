import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../helpers/companion_cli_protocol.dart';
import '../l10n/l10n.dart';
import '../models/quick_actions_settings.dart';
import '../models/quick_actions_header_settings.dart';
import '../services/app_settings_service.dart';
import '../widgets/adaptive_app_bar_title.dart';
import '../widgets/mesh_ui.dart';
import '../widgets/quick_action_presentation.dart';

class QuickActionsSettingsScreen extends StatelessWidget {
  const QuickActionsSettingsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const QuickActionsSettingsScreen()),
  );

  Future<void> _edit(
    BuildContext context,
    AppSettingsService service,
    QuickActionItem item,
  ) async {
    final next = await showDialog<QuickActionItem>(
      context: context,
      builder: (_) => _QuickActionEditor(item: item),
    );
    if (!context.mounted || next == null) return;
    final settings = service.settings;
    final current = settings.quickActions.items.firstWhere(
      (entry) => entry.action == next.action,
    );
    await service.updateSettings(settings.copyWith(
      quickActions: settings.quickActions.update(
        next.copyWith(visible: current.visible),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<AppSettingsService>();
    final items = service.settings.quickActions.items;
    final l10n = context.l10n;
    final header = service.settings.quickActionsHeader;
    final display = header.display;
    final intervals = QuickActionsHeaderSettings.allowedIntervalsMs;
    final intervalIndex = intervals.indexOf(header.intervalMsFor(display));
    String intervalText(int milliseconds) => l10n.quickActions_intervalSeconds(
      NumberFormat('0.#', Localizations.localeOf(context).toLanguageTag()).format(milliseconds / 1000),
    );
    return Scaffold(
      appBar: AppBar(title: AdaptiveAppBarTitle(l10n.quickActions_settings)),
      body: SafeArea(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
          buildDefaultDragHandles: false,
          itemCount: items.length,
          header: SectionHeader(l10n.quickActions_title),
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(l10n.quickActions_buttonDisplay),
              SwitchListTile(
                title: Text(l10n.quickActions_showInMainHeader),
                value: service.settings.showQuickActionsInMainHeader,
                onChanged: (value) => service.updateSettings(
                  service.settings.copyWith(showQuickActionsInMainHeader: value),
                ),
              ),
              SwitchListTile(
                title: Text(l10n.quickActions_showInChannelHeader),
                value: service.settings.showQuickActionsInChannelHeader,
                onChanged: (value) => service.updateSettings(
                  service.settings.copyWith(showQuickActionsInChannelHeader: value),
                ),
              ),
              SwitchListTile(
                title: Text(l10n.quickActions_showInContactHeader),
                value: service.settings.showQuickActionsInContactHeader,
                onChanged: (value) => service.updateSettings(
                  service.settings.copyWith(showQuickActionsInContactHeader: value),
                ),
              ),
              MeshCard(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButton<QuickActionsHeaderDisplay>(
                  key: const ValueKey('quick-actions-header-display'),
                  value: display,
                  isExpanded: true,
                  items: [
                    for (final mode in QuickActionsHeaderDisplay.values)
                      DropdownMenuItem(
                        value: mode, enabled: mode.selectable,
                        child: Text(mode.label(l10n)),
                      ),
                  ],
                  onChanged: (mode) {
                    if (mode == null || !mode.selectable) return;
                    final settings = service.settings;
                    service.updateSettings(settings.copyWith(
                      quickActionsHeader: settings.quickActionsHeader.copyWith(display: mode),
                    ));
                  },
                ),
              ),
              if (display.hasPolling)
                MeshCard(
                  key: const ValueKey('quick-actions-header-interval'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l10n.quickActions_updateInterval),
                      Text(intervalText(intervals[intervalIndex])),
                      Slider(
                        value: intervalIndex.toDouble(), min: 0,
                        max: (intervals.length - 1).toDouble(),
                        divisions: intervals.length - 1,
                        label: intervalText(intervals[intervalIndex]),
                        semanticFormatterCallback: (value) => intervalText(intervals[value.round()]),
                        onChanged: (value) {
                          final settings = service.settings;
                          service.updateSettings(settings.copyWith(
                            quickActionsHeader: settings.quickActionsHeader.withInterval(
                              display, intervals[value.round()],
                            ),
                          ));
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
          onReorderItem: (oldIndex, newIndex) {
            final settings = service.settings;
            service.updateSettings(settings.copyWith(
              quickActions: settings.quickActions.reorder(oldIndex, newIndex),
            ));
          },
          itemBuilder: (_, index) {
            final item = items[index];
            final label = item.label(l10n);
            return MeshCard(
              key: ValueKey(item.action),
              padding: EdgeInsets.zero,
              onTap: item.action.isCustom
                  ? () => _edit(context, service, item)
                  : null,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 8),
                child: Row(
                  children: [
                    Icon(item.action.icon),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: Theme.of(context).textTheme.bodyMedium),
                          if (item.action.isCustom && item.text.isNotEmpty)
                            Text(
                              item.text,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    Semantics(
                      label: label,
                      child: Switch(
                        value: item.visible,
                        onChanged: (visible) {
                          final settings = service.settings;
                          service.updateSettings(settings.copyWith(
                            quickActions: settings.quickActions.update(
                              item.copyWith(visible: visible),
                            ),
                          ));
                        },
                      ),
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _QuickActionEditor extends StatefulWidget {
  const _QuickActionEditor({required this.item});

  final QuickActionItem item;

  @override
  State<_QuickActionEditor> createState() => _QuickActionEditorState();
}

class _QuickActionEditorState extends State<_QuickActionEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item.name);
  late final _text = TextEditingController(text: widget.item.text);
  late final _channel = TextEditingController(text: widget.item.channelName);

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, widget.item.copyWith(
      name: _name.text.trim(),
      text: _text.text,
      channelName: _channel.text.trim(),
    ));
  }

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    _channel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final action = widget.item.action;
    return AlertDialog(
      scrollable: true,
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              decoration: InputDecoration(labelText: l10n.quickActions_name),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _text,
              decoration: InputDecoration(labelText: l10n.quickActions_text),
              maxLines: action.isCliCommand ? 1 : 4,
              minLines: 1,
              validator: (value) {
                final text = value ?? '';
                if (text.trim().isEmpty || text.contains('\u0000')) {
                  return l10n.quickActions_required;
                }
                if (action.isCliCommand) {
                  try {
                    buildCompanionCliFrame(text, 'AA');
                  } on CompanionCliException catch (error) {
                    return error.code == 'tooLong'
                        ? l10n.companionCli_tooLong
                        : l10n.companionCli_invalidCommand;
                  }
                }
                return null;
              },
            ),
            if (action.isChannelMessage) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _channel,
                decoration: InputDecoration(labelText: l10n.channels_channelName),
                validator: (value) => (value?.trim().isEmpty ?? true)
                    ? l10n.quickActions_required
                    : null,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.common_cancel),
        ),
        FilledButton(onPressed: _save, child: Text(l10n.common_save)),
      ],
    );
  }
}
