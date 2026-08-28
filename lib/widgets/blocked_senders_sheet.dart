import 'dart:async';

import 'package:flutter/material.dart';

import '../helpers/blocked_senders.dart';
import '../l10n/l10n.dart';
import '../storage/blocked_sender_store.dart';

/// The block list: every muted sender, with the key its rule is pinned to and
/// the channels that rule covers.
///
/// Reads and writes `BlockedSenders.instance` directly — the table is app-wide
/// and synchronous, so there is nothing to pass in and nothing to hand back.
/// The caller only has to rebuild itself once the sheet closes.
class BlockedSendersSheet extends StatefulWidget {
  const BlockedSendersSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const BlockedSendersSheet(),
    );
  }

  @override
  State<BlockedSendersSheet> createState() => _BlockedSendersSheetState();
}

class _BlockedSendersSheetState extends State<BlockedSendersSheet> {
  final TextEditingController _searchController = TextEditingController();

  /// Kept here rather than created per dialog: `showDialog` completes on pop,
  /// while the dialog is still animating out and its field still reads the
  /// controller, so disposing it right after the await is too early.
  final TextEditingController _addController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _addController.dispose();
    super.dispose();
  }

  List<MapEntry<String, BlockedSenderRule>> get _entries {
    final query = _searchController.text.trim().toLowerCase();
    return BlockedSenders.instance.rules.entries
        .where((e) => query.isEmpty || e.key.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
  }

  Future<void> _remove(String name) async {
    await BlockedSenders.instance.unblock(name);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _toggleMessageWidgets(
    String name,
    BlockedSenderRule rule,
  ) async {
    await BlockedSenders.instance.setMessageWidgetsHidden(
      name,
      !rule.hideMessageWidgets,
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _promptAdd() async {
    _addController.clear();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.chat_blockSender),
        content: TextField(
          controller: _addController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: dialogContext.l10n.chat_blockSenderName,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        // One Row instead of the default OverflowBar, which stacks the buttons
        // vertically as soon as a translation stops fitting.
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: _actionLabel(dialogContext.l10n.common_cancel),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, _addController.text),
                  child: _actionLabel(dialogContext.l10n.common_add),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    await BlockedSenders.instance.blockName(trimmed);
    if (!mounted) return;
    setState(() {});
  }

  /// Dialog action labels are clipped rather than wrapped, so both stay on one
  /// line however long the translation is.
  Widget _actionLabel(String text) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: TextAlign.center,
  );

  Widget _buildRow(String name, BlockedSenderRule rule) {
    final theme = Theme.of(context);
    final faded = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
    );
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text.rich(
        TextSpan(
          text: name,
          children: rule.keyHex.isEmpty
              ? null
              : [TextSpan(text: '  (${rule.keyHex})', style: faded)],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelLarge,
      ),
      subtitle: Text(
        rule.channels.contains(BlockedSenderRule.everyChannel)
            ? context.l10n.chat_blockedSendersAllChannels
            : rule.channels.join(', '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: faded,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: rule.hideMessageWidgets
                ? context.l10n.chat_showBlockedSenderMessages
                : context.l10n.chat_hideBlockedSenderMessages,
            icon: Icon(
              rule.hideMessageWidgets
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            color: rule.hideMessageWidgets
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
            onPressed: () => unawaited(_toggleMessageWidgets(name, rule)),
          ),
          IconButton(
            tooltip: context.l10n.common_delete,
            icon: const Icon(Icons.delete_outline),
            color: theme.colorScheme.error,
            onPressed: () => unawaited(_remove(name)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _entries;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Padding(
          padding: EdgeInsets.only(
            top: 16,
            bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.chat_blockedSenders,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: context.l10n.chat_blockSenderName,
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: entries.isEmpty
                    ? Center(child: Text(context.l10n.chat_blockedSendersEmpty))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: entries.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 4, endIndent: 4),
                        itemBuilder: (context, index) =>
                            _buildRow(entries[index].key, entries[index].value),
                      ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: FilledButton.tonalIcon(
                    onPressed: () => unawaited(_promptAdd()),
                    icon: const Icon(Icons.add),
                    label: Text(
                      context.l10n.common_add,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
