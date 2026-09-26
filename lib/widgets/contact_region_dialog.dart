import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../screens/region_management_screen.dart';
import '../storage/contact_region_store.dart';
import '../storage/region_store.dart';

/// Picks the region a contact's flood sends go out under: no region at all
/// first (`ContactRegionStore.unscoped`), then every region the app knows.
/// The clear action in the bar drops the contact's own choice, handing the
/// scope back to the node's default. Pops with the chosen value, an empty
/// string for that clearing, or null when dismissed.
class ContactRegionDialog extends StatefulWidget {
  const ContactRegionDialog({super.key, required this.selectedRegion});

  /// The contact's current choice: a region, the unscoped marker, or empty
  /// for the node's default.
  final String selectedRegion;

  static Future<String?> show(
    BuildContext context, {
    required String selectedRegion,
  }) => showDialog<String>(
    context: context,
    builder: (_) => ContactRegionDialog(selectedRegion: selectedRegion),
  );

  @override
  State<ContactRegionDialog> createState() => _ContactRegionDialogState();
}

class _ContactRegionDialogState extends State<ContactRegionDialog> {
  final RegionStore _regionStore = RegionStore();
  List<Region> _regions = const [];

  @override
  void initState() {
    super.initState();
    _regions = _regionStore.loadRegions();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected = widget.selectedRegion.trim();
    final selectedColor = Colors.blue.withValues(alpha: 0.2);
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              backgroundColor: Colors.transparent,
              title: Text(l10n.channels_regionSelect_Title),
              centerTitle: true,
              actions: [
                IconButton(
                  tooltip: l10n.channels_clearRegion,
                  icon: const Icon(Icons.backspace_outlined),
                  onPressed: () => Navigator.pop(context, ''),
                ),
                IconButton(
                  tooltip: l10n.settings_regionSettingsSubtitle,
                  icon: const Icon(Icons.settings),
                  onPressed: () async {
                    await pushRegionManagementScreen(context);
                    if (!mounted) return;
                    setState(() => _regions = _regionStore.loadRegions());
                  },
                ),
              ],
            ),
            const SizedBox(height: 15),
            // A tile's colour is ink, painted on the nearest Material rather
            // than by the tile, so a scrolled-away tile kept its colour under
            // the bar. A Material of the list's own inside a clip keeps that
            // paint within the list.
            Flexible(
              child: ClipRect(
                child: Material(
                  type: MaterialType.transparency,
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        title: Text(l10n.chat_floodRegionNone),
                        tileColor: ContactRegionStore.isUnscoped(selected)
                            ? selectedColor
                            : null,
                        onTap: () =>
                            Navigator.pop(context, ContactRegionStore.unscoped),
                      ),
                      for (final region in _regions)
                        ListTile(
                          title: Text(region),
                          tileColor: region == selected ? selectedColor : null,
                          onTap: () => Navigator.pop(context, region),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
