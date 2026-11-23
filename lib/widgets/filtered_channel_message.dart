import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/blocked_senders.dart';
import '../helpers/channel_post_identity.dart';
import '../l10n/l10n.dart';
import '../models/channel.dart';
import '../models/channel_message.dart';
import '../models/message_filter.dart';
import '../services/message_filter/message_filter_service.dart';
import 'channel_message_selection.dart';

class FilteredChannelMessage extends StatelessWidget {
  const FilteredChannelMessage({
    super.key,
    required this.message,
    required this.channel,
    required this.connector,
    this.initiallyExpanded = false,
    this.review = false,
    this.inline = false,
    this.onSelect,
  });

  final ChannelMessage message;
  final Channel channel;
  final MeshCoreConnector connector;
  final bool initiallyExpanded;
  final bool review;
  final bool inline;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final verdict = message.filterVerdict!;
    final reason = switch (verdict.reason) {
      FilterReason.senderRule => l10n.messageFilter_ruleFieldSender,
      FilterReason.textRule => l10n.messageFilter_ruleFieldText,
      FilterReason.manual => l10n.messageFilter_reasonManual,
      FilterReason.repeatedCharacters =>
        l10n.messageFilter_reasonRepeatedCharacters,
      FilterReason.duplicate => l10n.messageFilter_reasonDuplicate,
      FilterReason.crossSenderDuplicate =>
        l10n.messageFilter_reasonCrossSenderDuplicate,
      FilterReason.learned => l10n.messageFilter_reasonLearned,
    };
    final detail = verdict.detail;
    final compactStyle = Theme.of(context).textTheme.bodySmall;
    final service = connector.messageFilterService;
    final senderKey = BlockedSenders.verifiedKeyOf(message);
    final editable = !connector.isOfflineSharedMode && message.sharedHistorySourceName == null;
    final content = <Widget>[
      if (!review && verdict.reason != FilterReason.senderRule) ...[
        Text(reason, style: compactStyle),
        if (detail != null) Text(detail, style: compactStyle),
        const SizedBox(height: 8),
      ],
      SelectableText(
        '${message.senderName}: ${message.text}',
        key: const PageStorageKey('filtered-message-text'),
        style: review ? null : compactStyle,
      ),
      if (editable)
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => saveChannelMessageVerdict(context, connector, channel, message, null),
              child: Text(l10n.messageFilter_notSpam),
            ),
            if (service != null && service.hasSenderRule(message.senderName, senderKey))
              TextButton(
                onPressed: () async {
                  try {
                    await service.disableSenderRules(message.senderName, senderKey);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.messageFilter_saveError)),
                      );
                    }
                  }
                },
                child: Text(l10n.messageFilter_unblockSender),
              ),
          ],
        ),
    ];
    final Widget tile = review || inline
        ? SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: content,
              ),
            ),
          )
        : ExpansionTile(
            key: PageStorageKey(channelPostIdentity(message)),
            initiallyExpanded: initiallyExpanded,
            leading: const Icon(Icons.filter_alt_outlined),
            title: Text(l10n.messageFilter_ghostSingle, style: compactStyle),
            subtitle: Text(message.senderName, style: compactStyle),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            expandedAlignment: Alignment.centerLeft,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                key: const ValueKey('filtered-message-expanded-content'),
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: content,
                ),
              ),
            ],
          );
    return onSelect == null
        ? tile
        : GestureDetector(behavior: HitTestBehavior.opaque, onLongPress: onSelect, child: tile);
  }
}

Future<void> saveChannelMessageVerdict(
  BuildContext context,
  MeshCoreConnector connector,
  Channel channel,
  ChannelMessage message,
  FilterVerdict? verdict,
) async {
  await saveChannelMessageVerdicts(
    context,
    connector,
    channel,
    [message],
    verdict,
  );
}

bool canSelectChannelVerdict(
  MeshCoreConnector connector,
  Channel channel,
  ChannelMessage message,
) =>
    !connector.isOfflineSharedMode &&
    !message.isOutgoing &&
    !message.isLegacyBlocked &&
    message.sharedHistorySourceName == null &&
    !BlockedSenders.instance.isSenderBlocked(
      message,
      connector.channelDisplayName(channel.index),
    );

Future<bool> saveChannelMessageVerdicts(
  BuildContext context,
  MeshCoreConnector connector,
  Channel channel,
  List<ChannelMessage> messages,
  FilterVerdict? verdict,
) async {
  final nodeKey = connector.selfPublicKeyHex;
  try {
    final service = connector.messageFilterService;
    final learningAvailable = MessageFilterService.learningAvailable;
    final markingSpam = verdict?.reason == FilterReason.manual;
    if (markingSpam && (!learningAvailable || service == null)) return false;
    if (learningAvailable &&
        service != null &&
        !service.learningEnabled &&
        (markingSpam || verdict == null)) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          final l10n = dialogContext.l10n;
          return AlertDialog(
            scrollable: true,
            content: Text(
              l10n.messageFilter_enableLearningPrompt,
              style: Theme.of(dialogContext)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.common_cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.common_ok),
              ),
            ],
          );
        },
      );
      if (accepted != true ||
          !context.mounted ||
          connector.selfPublicKeyHex != nodeKey) {
        return false;
      }
      await service.updateSettings(service.settings.copyWith(learning: true));
      if (!context.mounted || !service.learningEnabled) return false;
    }

    var saved = true;
    for (final message in messages) {
      if (!context.mounted || connector.selfPublicKeyHex != nodeKey) return false;
      if (!await connector.setChannelMessageFilterVerdict(channel, message, verdict)) {
        saved = false;
      }
    }
    if (saved) return true;
  } catch (_) {
    // Report a failed settings write in the same place as a failed verdict.
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.messageFilter_saveError)),
    );
  }
  return false;
}

class FilteredChannelGroup extends StatelessWidget {
  const FilteredChannelGroup({
    super.key,
    required this.messages,
    required this.channel,
  });

  final List<ChannelMessage> messages;
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final connector = context.watch<MeshCoreConnector>();
    return ExpansionTile(
      key: PageStorageKey(('filtered-group', channel.storageId,
        messages.isEmpty ? null : channelPostIdentity(messages.first))),
      leading: const Icon(Icons.filter_alt_outlined),
      title: Text(context.l10n.messageFilter_ghostMany(messages.length),
        style: Theme.of(context).textTheme.bodySmall),
      expandedAlignment: Alignment.centerLeft,
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final message in messages)
          FilteredChannelMessage(
            key: ValueKey(channelPostIdentity(message)),
            message: message,
            channel: channel,
            connector: connector,
            inline: true,
          ),
      ],
    );
  }
}

Future<void> showFilteredChannelMessages(
  BuildContext context,
  Channel channel, {
  List<ChannelMessage>? group,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (context) => _FilteredChannelReview(
        channel: channel,
        group: group?.map(channelPostIdentity).toSet(),
      ),
    ),
  );
}

class _FilteredChannelReview extends StatefulWidget {
  const _FilteredChannelReview({required this.channel, required this.group});

  final Channel channel;
  final Set<ChannelPostIdentity>? group;

  @override
  State<_FilteredChannelReview> createState() => _FilteredChannelReviewState();
}

class _FilteredChannelReviewState extends State<_FilteredChannelReview> {
  final _selection = ChannelMessageSelection();

  @override
  Widget build(BuildContext context) {
    final connector = context.watch<MeshCoreConnector>();
    final channel = widget.channel;
    final group = widget.group;
    final name = connector.channelDisplayName(channel.index);
    final Iterable<ChannelMessage> candidates;
    if (group == null) {
      candidates = connector.getLoadedFilteredChannelMessages(channel);
    } else if (connector.isChannelFilterEnabled(channel)) {
      candidates = connector
          .getChannelMergedMessages(channel)
          .reversed
          .where((message) =>
              message.isFiltered && group.contains(channelPostIdentity(message)));
    } else {
      candidates = const [];
    }
    final messages = candidates.where((message) =>
        !message.isLegacyBlocked &&
        !BlockedSenders.instance.hidesStoredMessage(message, name)).toList();
    final selecting = _selection.isActive(connector, connector.selfPublicKeyHex);
    final selected = selecting
        ? messages.reversed.where(_selection.contains).toList()
        : const <ChannelMessage>[];
    final editable = selected.where((message) =>
        canSelectChannelVerdict(connector, channel, message)).toList();
    final deletable = connector.isOfflineMode
        ? const <ChannelMessage>[]
        : selected
            .where((message) => message.sharedHistorySourceName == null)
            .toList();
    void clear() => setState(_selection.clear);

    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selecting && !_selection.busy) clear();
      },
      child: Scaffold(
        appBar: selecting
            ? buildChannelSelectionAppBar(
                context,
                count: selected.length,
                busy: _selection.busy,
                onClose: clear,
                onSelectAll: () =>
                    setState(() => _selection.selectAll(messages)),
                onCopy: () {
                  copySelectedChannelMessages(context, selected);
                  clear();
                },
                onDelete: deletable.isEmpty
                    ? null
                    : () => _selection.run(
                        context,
                        setState,
                        () => deleteSelectedChannelMessages(
                          context, connector, channel, deletable,
                        ),
                      ),
                onNotSpam: editable.isEmpty
                    ? null
                    : () => _selection.run(
                        context,
                        setState,
                        () => saveChannelMessageVerdicts(
                          context, connector, channel, editable, null,
                        ),
                      ),
              )
            : AppBar(title: Text(context.l10n.messageFilter_displayTitle)),
        body: SafeArea(
          child: messages.isEmpty
              ? Center(child: Text(context.l10n.messageFilter_filteredMessagesEmpty))
              : ListView.builder(
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    void toggle() =>
                        setState(() => _selection.toggle(connector, message));
                    final tile = FilteredChannelMessage(
                      channel: channel,
                      message: message,
                      connector: connector,
                      review: true,
                      onSelect: toggle,
                    );
                    final key = ValueKey(channelPostIdentity(message));
                    return selecting
                        ? ChannelSelectionRow(
                            key: key,
                            selected: _selection.contains(message),
                            onTap: toggle,
                            child: tile,
                          )
                        : KeyedSubtree(key: key, child: tile);
                  },
                ),
        ),
      ),
    );
  }
}
