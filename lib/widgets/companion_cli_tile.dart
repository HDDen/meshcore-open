import 'package:flutter/material.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/companion_cli_protocol.dart';
import '../l10n/l10n.dart';
import '../screens/companion_cli_screen.dart';
import 'mesh_ui.dart';

/// Служебный чат не является Contact и не участвует в радио-синхронизации.
class CompanionCliTile extends StatelessWidget {
  const CompanionCliTile({super.key, required this.connector, this.dragIndex, this.compact = false,
    this.margin = const EdgeInsets.symmetric(vertical: 4)});
  final MeshCoreConnector connector;
  final int? dragIndex;
  final bool compact;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MeshCard(
      key: const ValueKey(companionCliOrderKey),
      margin: margin,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 8 : 10),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CompanionCliScreen(connector: connector))),
      child: Row(children: [
        CircleAvatar(radius: compact ? 16 : 21,
          child: Icon(Icons.terminal, size: compact ? 18 : 24)),
        const SizedBox(width: 12),
        Expanded(child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.l10n.companionCli_title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          if (!compact)
            Text(context.l10n.companionCli_description, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ])),
        const SizedBox(width: 4),
        if (dragIndex case final index?)
          ReorderableDragStartListener(index: index, child: const Padding(
            padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle)))
        else
          Padding(padding: EdgeInsets.all(compact ? 6 : 8),
            child: Icon(Icons.chevron_right, size: compact ? 20 : 24)),
      ]),
    );
  }
}
