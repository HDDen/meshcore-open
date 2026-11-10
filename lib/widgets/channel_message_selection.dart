import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/channel_post_identity.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../models/channel.dart';
import '../models/channel_message.dart';
import '../utils/platform_info.dart';

class ChannelMessageSelection {
  final _keys = <ChannelPostIdentity>{};
  (MeshCoreConnector, String)? _scope;
  bool busy = false;

  bool isActive(MeshCoreConnector connector, String nodeKey) =>
      _keys.isNotEmpty && _scope == (connector, nodeKey);

  bool contains(ChannelMessage message) =>
      _keys.contains(channelPostIdentity(message));

  void toggle(MeshCoreConnector connector, ChannelMessage message) {
    if (busy) return;
    final scope = (connector, connector.selfPublicKeyHex);
    if (_scope != scope) {
      _keys.clear();
      _scope = scope;
    }
    final key = channelPostIdentity(message);
    if (!_keys.remove(key)) _keys.add(key);
  }

  void selectAll(Iterable<ChannelMessage> messages) {
    _keys.addAll(messages.map(channelPostIdentity));
  }

  void clear() => _keys.clear();

  Future<void> run(
    BuildContext context,
    StateSetter setState,
    Future<bool> Function() action,
  ) async {
    if (busy) return;
    setState(() => busy = true);
    var done = false;
    try {
      done = await action();
    } finally {
      if (context.mounted) {
        setState(() {
          busy = false;
          if (done) clear();
        });
      }
    }
  }
}

class ChannelSelectionRow extends StatelessWidget {
  const ChannelSelectionRow({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                ),
              ),
              Expanded(child: IgnorePointer(child: child)),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SelectionMenu { selectAll, copy }

AppBar buildChannelSelectionAppBar(
  BuildContext context, {
  required int count,
  required bool busy,
  required VoidCallback onClose,
  required VoidCallback onSelectAll,
  required VoidCallback onCopy,
  VoidCallback? onDelete,
  VoidCallback? onSpam,
  VoidCallback? onNotSpam,
}) {
  final l10n = context.l10n;
  return AppBar(
    leading: IconButton(
      tooltip: l10n.chat_clearSelection,
      onPressed: busy ? null : onClose,
      icon: const Icon(Icons.close),
    ),
    title: Text(l10n.chat_selectedCount(count), overflow: TextOverflow.ellipsis),
    actions: [
      if (onSpam != null)
        IconButton(
          tooltip: l10n.messageFilter_markSpam,
          onPressed: busy ? null : onSpam,
          icon: const Icon(Icons.flag_outlined),
        ),
      if (onNotSpam != null)
        IconButton(
          tooltip: l10n.messageFilter_notSpam,
          onPressed: busy ? null : onNotSpam,
          icon: const Icon(Icons.undo),
        ),
      if (onDelete != null)
        IconButton(
          tooltip: l10n.common_delete,
          onPressed: busy ? null : onDelete,
          icon: const Icon(Icons.delete_outline),
        ),
      PopupMenuButton<_SelectionMenu>(
        enabled: !busy,
        onSelected: (action) {
          switch (action) {
            case _SelectionMenu.selectAll:
              onSelectAll();
            case _SelectionMenu.copy:
              onCopy();
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: _SelectionMenu.selectAll,
            child: Text(l10n.chat_selectAll),
          ),
          PopupMenuItem(
            value: _SelectionMenu.copy,
            enabled: count > 0,
            child: Text(l10n.common_copy),
          ),
        ],
      ),
    ],
  );
}

void copySelectedChannelMessages(
  BuildContext context,
  List<ChannelMessage> messages,
) {
  final text = messages.map((message) {
    if (message.isOutgoing || message.senderName.isEmpty) return message.text;
    return '${message.senderName}: ${message.text}';
  }).join('\n');
  Clipboard.setData(ClipboardData(text: text));
  if (PlatformInfo.isAndroid) return;
  showDismissibleSnackBar(
    context,
    content: Text(context.l10n.chat_messageCopied),
  );
}

Future<bool> deleteSelectedChannelMessages(
  BuildContext context,
  MeshCoreConnector connector,
  Channel channel,
  List<ChannelMessage> messages,
) async {
  final nodeKey = connector.selfPublicKeyHex;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final l10n = context.l10n;
      return AlertDialog(
        scrollable: true,
        content: Text(l10n.chat_confirmDeleteSelected(messages.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.common_delete),
          ),
        ],
      );
    },
  );
  if (confirmed != true ||
      !context.mounted ||
      connector.selfPublicKeyHex != nodeKey) {
    return false;
  }
  final deleted = await connector.deleteSelectedChannelMessages(channel, messages);
  if (!deleted && context.mounted) {
    showDismissibleSnackBar(
      context,
      content: Text(context.l10n.chat_deleteSelectedFailed),
    );
  }
  return deleted;
}
