import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../helpers/companion_cli_protocol.dart';
import '../l10n/l10n.dart';
import '../models/quick_actions_settings.dart';
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
              MeshCard(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButton<int>(
                  value: 0,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(value: 0, child: Text(l10n.quickActions_icon)),
                    DropdownMenuItem(
                      value: 1,
                      enabled: false,
                      child: Text(l10n.quickActions_noise),
                    ),
                    DropdownMenuItem(
                      value: 2,
                      enabled: false,
                      child: Text(l10n.quickActions_extraHops),
                    ),
                  ],
                  onChanged: (_) {},
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
