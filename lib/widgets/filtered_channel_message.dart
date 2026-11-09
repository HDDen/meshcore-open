import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/blocked_senders.dart';
import '../l10n/l10n.dart';
import '../models/channel.dart';
import '../models/channel_message.dart';
import '../models/message_filter.dart';
import '../services/message_filter/message_filter_service.dart';

class FilteredChannelMessage extends StatelessWidget {
  const FilteredChannelMessage({
    super.key,
    required this.message,
    required this.channel,
    required this.connector,
  });

  final ChannelMessage message;
  final Channel channel;
  final MeshCoreConnector connector;

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
    return ExpansionTile(
      key: PageStorageKey('filter:${message.messageId}'),
      leading: const Icon(Icons.filter_alt_outlined),
      title: Text(l10n.messageFilter_ghostSingle),
      subtitle: Text(reason),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (detail != null) ...[
          Text(detail),
          const SizedBox(height: 8),
        ],
        SelectableText(
          '${message.senderName}: ${message.text}',
          // Separate the text's scroll offset from the tile's expansion state.
          key: const PageStorageKey('filtered-message-text'),
        ),
        if (!connector.isOfflineSharedMode &&
            message.sharedHistorySourceName == null)
          TextButton(
            onPressed: () => saveChannelMessageVerdict(
              context,
              connector,
              channel,
              message,
              null,
            ),
            child: Text(l10n.messageFilter_notSpam),
          ),
      ],
    );
  }
}

Future<void> saveChannelMessageVerdict(
  BuildContext context,
  MeshCoreConnector connector,
  Channel channel,
  ChannelMessage message,
  FilterVerdict? verdict,
) async {
  try {
    final service = connector.messageFilterService;
    final learningAvailable = MessageFilterService.learningAvailable;
    final markingSpam = verdict?.reason == FilterReason.manual;
    if (markingSpam && (!learningAvailable || service == null)) return;
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
      if (accepted != true || !context.mounted) return;
      await service.updateSettings(service.settings.copyWith(learning: true));
      if (!context.mounted || !service.learningEnabled) return;
    }

    if (await connector.setChannelMessageFilterVerdict(
      channel,
      message,
      verdict,
    )) {
      return;
    }
  } catch (_) {
    // Report a failed settings write in the same place as a failed verdict.
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.messageFilter_saveError)),
    );
  }
}

Future<void> showFilteredChannelMessages(BuildContext context, Channel channel) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.messageFilter_displayTitle)),
        body: SafeArea(
          child: Consumer<MeshCoreConnector>(
            builder: (context, connector, _) {
              final name = connector.channelDisplayName(channel.index);
              final messages = connector
                  .getLoadedFilteredChannelMessages(channel)
                  .where(
                    (message) =>
                        !message.wasBlocked &&
                        !BlockedSenders.instance.hidesStoredMessage(message, name),
                  )
                  .toList(growable: false);
              if (messages.isEmpty) {
                return Center(
                  child: Text(context.l10n.messageFilter_filteredMessagesEmpty),
                );
              }
              return ListView.builder(
                itemCount: messages.length,
                itemBuilder: (context, index) => FilteredChannelMessage(
                  key: ValueKey(messages[index].messageId),
                  channel: channel,
                  message: messages[index],
                  connector: connector,
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
