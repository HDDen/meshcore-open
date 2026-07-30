import 'package:flutter/material.dart';

import '../connector/meshcore_connector.dart';
import '../l10n/l10n.dart';
import 'snack_bar_builder.dart';

bool blockIfOffline(BuildContext context, MeshCoreConnector connector) {
  if (!connector.isOfflineMode) return false;
  showDismissibleSnackBar(
    context,
    content: Text(context.l10n.app_offline_unableToMessage),
    backgroundColor: Theme.of(context).colorScheme.error,
  );
  return true;
}
