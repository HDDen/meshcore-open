import 'package:flutter/material.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/companion_cli_protocol.dart';
import '../l10n/l10n.dart';
import '../screens/companion_cli_screen.dart';

/// Служебный чат не является Contact и не участвует в радио-синхронизации.
class CompanionCliTile extends StatelessWidget {
  const CompanionCliTile({super.key, required this.connector, this.dragIndex});
  final MeshCoreConnector connector;
  final int? dragIndex;

  @override
  Widget build(BuildContext context) => Card(
    key: const ValueKey(companionCliOrderKey),
    child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.terminal)),
      title: Text(context.l10n.companionCli_title),
      subtitle: Text(context.l10n.companionCli_description),
      trailing: dragIndex == null ? const Icon(Icons.chevron_right)
        : ReorderableDragStartListener(index: dragIndex!, child: const Padding(
          padding: EdgeInsets.all(12), child: Icon(Icons.drag_handle))),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CompanionCliScreen(connector: connector))),
    ),
  );
}
