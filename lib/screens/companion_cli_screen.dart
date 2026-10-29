import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/companion_cli_protocol.dart';
import '../helpers/companion_cli_commands.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../models/app_settings.dart';
import '../models/companion_cli_entry.dart';
import '../services/app_settings_service.dart';
import '../services/companion_cli_session.dart';
import '../services/ui_view_state_service.dart';
import '../theme/mesh_theme.dart';
import '../utils/platform_info.dart';
import '../widgets/confirm_clear_dialog.dart';
import '../widgets/companion_cli_command_help_sheet.dart';
import '../widgets/popup_menu_row.dart';

class CompanionCliScreen extends StatefulWidget {
  const CompanionCliScreen({super.key, required this.connector});
  final MeshCoreConnector connector;
  @override
  State<CompanionCliScreen> createState() => _CompanionCliScreenState();
}

class _CompanionCliScreenState extends State<CompanionCliScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _quickScroll = ScrollController();
  late final CompanionCliSession _session = widget.connector.companionCli;
  late final Listenable _changes = Listenable.merge([widget.connector, _session]);
  bool _loaded = false;
  bool _loadFailed = false;
  bool _clearing = false;
  int _historyIndex = -1;

  void _applyCommand(String command) {
    final example = companionCliCommandExample(command);
    _historyIndex = -1;
    _input.value = TextEditingValue(text: example,
      selection: TextSelection.collapsed(offset: example.length));
    _focus.requestFocus();
  }

  Future<void> _showCommandHelp() async {
    _focus.unfocus();
    final command = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true, useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => CompanionCliCommandHelpSheet(
        sections: companionCliHelpSections(context.l10n),
        onSelect: (command) => Navigator.pop(sheetContext, command)),
    );
    if (mounted && command != null) { _applyCommand(command); }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      await _session.ensureLoaded();
      if (mounted) {
        setState(() { _loaded = true; _loadFailed = false; });
      }
    } catch (_) {
      if (mounted) {
        setState(() { _loaded = true; _loadFailed = true; });
      }
    }
  }

  String _error(String? code) {
    final l10n = context.l10n;
    return switch (code) {
      'unavailable' => l10n.companionCli_unavailable,
      'busy' => l10n.companionCli_busy,
      'invalidCommand' => l10n.companionCli_invalidCommand,
      'tooLong' => l10n.companionCli_tooLong,
      'tagExhausted' => l10n.companionCli_tagExhausted,
      'timeout' => l10n.companionCli_timeout,
      'protocol' => l10n.companionCli_protocolError,
      'disconnected' => l10n.companionCli_disconnected,
      'sendFailed' => l10n.companionCli_sendFailed,
      _ => l10n.companionCli_historyError,
    };
  }

  Future<void> _send() async {
    final text = _input.text;
    try {
      await _session.sendCommand(text);
      if (mounted) {
        if (_input.text == text) { _input.clear(); }
        _historyIndex = -1;
        _focus.requestFocus();
        if (_scroll.hasClients) { _scroll.jumpTo(0); }
      }
    } catch (error) {
      if (mounted) {
        showDismissibleSnackBar(context,
          content: Text(_error(error is CompanionCliException ? error.code : null)));
      }
    }
  }

  void _recall(bool up) {
    final commands = _session.entries(shared: false).reversed.toList();
    if (commands.isEmpty) { return; }
    _historyIndex = _historyIndex.clamp(-1, commands.length - 1).toInt();
    if (up) {
      if (_historyIndex < commands.length - 1) { _historyIndex++; }
    } else if (_historyIndex > 0) {
      _historyIndex--;
    } else {
      _historyIndex = -1;
      _input.clear();
      return;
    }
    _input.text = commands[_historyIndex].command;
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
  }

  Future<void> _clear() async {
    final nodeKey = widget.connector.selfPublicKeyHex;
    final confirmed = await showConfirmClearDialog(context,
      title: context.l10n.repeater_clearHistory, message: context.l10n.cliHistory_clearCurrentNodeConfirm);
    if (!confirmed || !mounted) { return; }
    setState(() => _clearing = true);
    try {
      await _session.clearHistory(nodeKey);
      _historyIndex = -1;
    } catch (_) {
      if (mounted) { showDismissibleSnackBar(context, content: Text(context.l10n.companionCli_historyError)); }
    } finally {
      if (mounted) { setState(() => _clearing = false); }
    }
  }

  String _transcript(List<CompanionCliEntry> entries) => entries.map((entry) =>
    '[${entry.nodeName} · ${entry.nodeKey}]\n> ${entry.command}\n${entry.response ?? ''}').join('\n');

  Future<void> _copy(List<CompanionCliEntry> entries) async {
    await Clipboard.setData(ClipboardData(text: _transcript(entries)));
    if (mounted) { showDismissibleSnackBar(context, content: Text(context.l10n.repeater_cliTranscriptCopied)); }
  }

  Future<void> _share(List<CompanionCliEntry> entries) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(text: _transcript(entries),
      subject: context.l10n.companionCli_title,
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size));
  }

  @override
  void dispose() {
    _input.dispose(); _focus.dispose(); _scroll.dispose(); _quickScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<AppSettingsService?>()?.settings.sharedMessageHistoryMode;
    final viewState = context.watch<UiViewStateService>();
    return AnimatedBuilder(animation: _changes, builder: (context, _) {
      final connector = widget.connector;
      final scheme = Theme.of(context).colorScheme;
      final l10n = context.l10n;
      final shared = viewState.companionCliSharedHistory ??
        (mode == SharedMessageHistoryMode.contacts ||
          mode == SharedMessageHistoryMode.all || connector.isOfflineSharedMode);
      final entries = _session.entries(shared: shared);
      final canClear = _session.entries(shared: false).isNotEmpty && !_clearing;
      final canSend = _loaded && !_loadFailed && !_session.busy && !_clearing &&
        connector.isConnected && connector.selfPublicKeyHex.isNotEmpty &&
        !connector.isOfflineMode && connector.supportsCompanionCli;
      return Scaffold(
        backgroundColor: scheme.surfaceContainerLowest,
        appBar: AppBar(backgroundColor: scheme.surfaceContainer, foregroundColor: scheme.onSurface,
          title: Text(l10n.companionCli_title), centerTitle: true, actions: [
            IconButton(key: const ValueKey('companion-cli-shared'),
              tooltip: l10n.companionCli_sharedHistory, isSelected: shared,
              icon: const Icon(Icons.hub_outlined), selectedIcon: const Icon(Icons.hub),
              onPressed: () => unawaited(viewState.setCompanionCliSharedHistory(!shared))),
            IconButton(key: const ValueKey('companion-cli-help'),
              tooltip: l10n.repeater_commandHelp, icon: const Icon(Icons.help_outline),
              onPressed: () => unawaited(_showCommandHelp())),
            PopupMenuButton<String>(onSelected: (value) {
              switch (value) {
                case 'copy': unawaited(_copy(entries));
                case 'share': unawaited(_share(entries));
                case 'clear': unawaited(_clear());
              }
            }, itemBuilder: (_) => [
              PopupMenuItem(value: 'copy', enabled: entries.isNotEmpty,
                child: PopupMenuRow(icon: Icons.copy, text: l10n.repeater_cliCopyTranscript)),
              PopupMenuItem(value: 'share', enabled: entries.isNotEmpty,
                child: PopupMenuRow(icon: Icons.share, text: l10n.repeater_cliShareTranscript)),
              PopupMenuItem(value: 'clear', enabled: canClear,
                child: PopupMenuRow(icon: Icons.clear_all, text: l10n.repeater_clearHistory)),
            ]),
          ]),
        body: Column(children: [
          SizedBox(width: double.infinity, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(l10n.companionCli_nodeTitle(connector.selfName ?? l10n.companionCli_noNode),
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium))),
          if (!connector.isConnected || connector.isOfflineMode || !connector.supportsCompanionCli)
            Padding(padding: const EdgeInsets.all(8), child: Text(l10n.companionCli_unavailable)),
          if (PlatformInfo.isWeb) Padding(padding: const EdgeInsets.all(8), child: Text(l10n.cliHistory_temporary)),
          if (_loadFailed) ListTile(title: Text(l10n.companionCli_historyError),
            trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: () => unawaited(_load()))),
          if (!_loaded || _session.busy) const LinearProgressIndicator(),
          Container(key: const ValueKey('companion-cli-quick-commands'),
            width: double.infinity, color: scheme.surfaceContainer,
            padding: EdgeInsets.fromLTRB(8, 6, 8, PlatformInfo.isDesktop ? 0 : 6),
            // This local strip is not at the screen bottom. CupertinoScrollbar
            // would subtract the home-indicator inset and paint over the chips.
            child: MediaQuery.removePadding(context: context,
              removeTop: true, removeBottom: true,
              child: Scrollbar(controller: _quickScroll, thumbVisibility: PlatformInfo.isDesktop,
              child: SingleChildScrollView(controller: _quickScroll, scrollDirection: Axis.horizontal,
                // Logical pixels scale with DPI together with the scrollbar.
                // Reserve a lane on Android too, even while its thumb fades.
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(children: [for (final command in companionCliQuickCommands) Padding(
                  padding: const EdgeInsets.only(right: 6), child: ActionChip(
                    key: ValueKey('companion-cli-quick:$command'),
                    label: Text(command, style: MeshTheme.mono(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.primary)),
                    backgroundColor: scheme.primary.withValues(alpha: 0.12),
                    side: BorderSide(color: scheme.primary.withValues(alpha: 0.5)),
                    onPressed: () => _applyCommand(command),
                  ))])),
            ))),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(child: entries.isEmpty
            ? Center(child: Text(l10n.companionCli_empty, style: MeshTheme.mono(fontSize: 15, color: scheme.onSurface)))
            : ListView.builder(controller: _scroll, reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), itemCount: entries.length,
              itemBuilder: (context, index) => _entry(entries[entries.length - 1 - index]))),
          Divider(height: 1, color: scheme.outlineVariant),
          Container(color: scheme.surfaceContainer, padding: const EdgeInsets.all(8),
            child: SafeArea(top: false, child: Row(children: [
              IconButton(tooltip: l10n.repeater_previousCommand, icon: const Icon(Icons.arrow_upward, size: 22), onPressed: () => _recall(true)),
              IconButton(tooltip: l10n.repeater_nextCommand, icon: const Icon(Icons.arrow_downward, size: 22), onPressed: () => _recall(false)),
              Expanded(child: TextField(controller: _input, focusNode: _focus, minLines: 1, maxLines: 4,
                key: const ValueKey('companion-cli-input'), autocorrect: false, enableSuggestions: false,
                style: MeshTheme.mono(fontSize: 15, color: scheme.onSurface),
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(hintText: 'ver', prefixText: '> ',
                  prefixStyle: MeshTheme.mono(fontSize: 15, color: scheme.primary, fontWeight: FontWeight.w700),
                  filled: true, fillColor: scheme.surfaceContainerHigh,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(MeshRadii.pill))),
                onSubmitted: (_) { if (canSend) { unawaited(_send()); } })),
              const SizedBox(width: 6),
              SizedBox(width: 48, height: 48, child: IconButton.filledTonal(
                key: const ValueKey('companion-cli-send'), tooltip: l10n.companionCli_send,
                icon: const Icon(Icons.send, size: 24), onPressed: canSend ? () => unawaited(_send()) : null)),
            ]))),
        ]),
      );
    });
  }

  Widget _line(String text, {bool command = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 20, child: Text(command ? '>' : ' ', style: MeshTheme.mono(
          fontSize: 14, fontWeight: FontWeight.w700, color: scheme.primary))),
        const SizedBox(width: 6),
        Expanded(child: SelectableText(text, style: MeshTheme.mono(
          fontSize: 14, color: command ? scheme.primary : scheme.onSurface))),
      ]));
  }

  Widget _entry(CompanionCliEntry entry) => Padding(
    key: ValueKey('${entry.nodeKey}:${entry.id}'), padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${entry.nodeName} · ${entry.nodeKey.length > 10 ? entry.nodeKey.substring(0, 10) : entry.nodeKey} · '
        '${entry.createdAt.toLocal().toString().split('.').first}', style: Theme.of(context).textTheme.labelSmall),
      const SizedBox(height: 4), _line(entry.command, command: true),
      if (entry.response != null) _line(entry.response!.isEmpty ? context.l10n.companionCli_emptyReply : entry.response!),
      if (entry.status == CompanionCliStatus.failed || entry.status == CompanionCliStatus.disconnected)
        Text(_error(entry.status == CompanionCliStatus.disconnected ? 'disconnected' : entry.failure),
          style: MeshTheme.mono(fontSize: 14, color: Theme.of(context).colorScheme.error)),
    ]),
  );
}
