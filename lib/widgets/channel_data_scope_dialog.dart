import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// How far a manual deletion or clearing of a channel reaches.
enum ChannelDataScope {
  /// This node's scope only.
  thisNode,

  /// Every node's scope in the app's merged history.
  allNodes,
}

/// Asks whether the channel's data goes for this node or for every node, when
/// the shared channel history is on and the merged history is what the user
/// sees. Resolves to null when the user cancels.
Future<ChannelDataScope?> showChannelDataScopeDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  final l10n = context.l10n;
  return showDialog<ChannelDataScope>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text('$message\n\n${l10n.channels_dataScopeQuestion}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, ChannelDataScope.thisNode),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: Text(l10n.channels_dataScopeThisNode),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, ChannelDataScope.allNodes),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            child: Text(l10n.channels_dataScopeAllNodes),
          ),
        ],
      );
    },
  );
}
