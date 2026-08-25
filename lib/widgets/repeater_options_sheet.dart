import 'package:flutter/material.dart';

import '../l10n/contact_localization.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../theme/mesh_theme.dart';
import 'mesh_ui.dart';

typedef RepeaterExtraTilesBuilder =
    List<Widget> Function(BuildContext sheetContext);

void showRepeaterOptionsSheet({
  required BuildContext context,
  required Contact repeater,
  required VoidCallback onPing,
  required VoidCallback onManage,
  required VoidCallback onToggleFavorite,
  required RepeaterExtraTilesBuilder extraTilesBuilder,
  required bool ignoredInWardrive,
  required ValueChanged<bool> onWardriveIgnoredChanged,
  required VoidCallback onShare,
  required VoidCallback onShareZeroHop,
  required VoidCallback onDelete,
}) {
  showMeshSheet(
    context,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BottomSheetHeader(
                title: repeater.name,
                subtitle: repeater.typeLabel(context.l10n),
              ),
              ListTile(
                leading: Icon(Icons.radar, color: MeshPalette.signal),
                title: Text(context.l10n.contacts_ping),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onPing();
                },
              ),
              ListTile(
                leading: Icon(Icons.cell_tower, color: MeshPalette.warn),
                title: Text(context.l10n.contacts_manageRepeater),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onManage();
                },
              ),
              ListTile(
                leading: Icon(
                  repeater.isFavorite ? Icons.star : Icons.star_border,
                  color: MeshPalette.warn,
                ),
                title: Text(
                  repeater.isFavorite
                      ? context.l10n.listFilter_removeFromFavorites
                      : context.l10n.listFilter_addToFavorites,
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onToggleFavorite();
                },
              ),
              ...extraTilesBuilder(sheetContext),
              ListTile(
                leading: Icon(
                  ignoredInWardrive ? Icons.visibility : Icons.visibility_off,
                  color: ignoredInWardrive
                      ? MeshPalette.signal
                      : Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  ignoredInWardrive
                      ? context.l10n.listFilter_returnToWardrive
                      : context.l10n.listFilter_removeFromWardrive,
                ),
                onTap: () {
                  final nextIgnored = !ignoredInWardrive;
                  setSheetState(() => ignoredInWardrive = nextIgnored);
                  onWardriveIgnoredChanged(nextIgnored);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: Text(context.l10n.contacts_ShareContact),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onShare();
                },
              ),
              ListTile(
                leading: const Icon(Icons.connect_without_contact),
                title: Text(context.l10n.contacts_ShareContactZeroHop),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onShareZeroHop();
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  context.l10n.contacts_deleteContact,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onDelete();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    ),
  );
}
