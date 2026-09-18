import 'package:flutter/material.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/channel_qr_link.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../models/channel.dart';
import '../storage/channel_region_store.dart';
import '../storage/region_store.dart';
import '../theme/mesh_theme.dart';
import '../widgets/adaptive_app_bar_title.dart';
import '../widgets/qr_scanner_widget.dart';

/// Scans a `meshcore://channel/add?...` QR code of an ordinary private or
/// hashtag channel and returns the parsed [ChannelQrLink].
///
/// Fork-only, see `helpers/channel_qr_link.dart` for how to remove it.
class ChannelQrScannerScreen extends StatelessWidget {
  const ChannelQrScannerScreen({super.key});

  /// Opens the scanner and puts the scanned channel into slot [index], or,
  /// when the node already has a channel of that name, offers to update it.
  static Future<void> scanAndAdd(
    BuildContext context, {
    required MeshCoreConnector connector,
    required int index,
  }) async {
    final link = await Navigator.push<ChannelQrLink>(
      context,
      MaterialPageRoute(builder: (_) => const ChannelQrScannerScreen()),
    );
    if (link == null || !context.mounted) return;

    final plan = link.importInto(
      connector.channels,
      regionOf: connector.getChannelRegion,
    );
    final existing = plan.existing;
    switch (plan.action) {
      case ChannelQrImportAction.alreadyAdded:
        showDismissibleSnackBar(
          context,
          content: Text(
            context.l10n.channels_qrAlreadyAdded(existing!.name),
          ),
          backgroundColor: MeshPalette.warn,
        );
      case ChannelQrImportAction.update:
        if (!await _confirmUpdate(context, existing!.name)) return;
        // The channel keeps its own name: history and settings hang on it.
        await _write(connector, existing.index, existing.name, link);
        if (!context.mounted) return;
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.channels_channelUpdated(existing.name)),
        );
      case ChannelQrImportAction.add:
        await _write(connector, index, link.name, link);
        if (!context.mounted) return;
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.channels_channelAdded(link.name)),
        );
    }
  }

  static Future<bool> _confirmUpdate(BuildContext context, String name) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(
          l10n.channels_qrUpdateExisting(name),
          style: Theme.of(dialogContext).textTheme.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.common_ok),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// The link is the whole description of the channel: its key, and its
  /// region or the lack of one, so a channel that had a region loses it when
  /// the link names none. A region the app has not met is added to the list
  /// the region picker shows, or the channel would hold a region nobody can
  /// see selected.
  static Future<void> _write(
    MeshCoreConnector connector,
    int index,
    String name,
    ChannelQrLink link,
  ) async {
    final region = link.regionScope ?? '';
    if (region.isNotEmpty) {
      final regions = RegionStore();
      if (!regions.loadRegions().contains(region)) regions.addRegion(region);
    }
    // A channel's region is stored under the channel's name, and the connector
    // learns which name a slot holds only when the node reports it back, some
    // time after setChannel has returned. For a new channel that is too late
    // for setChannelRegion: it finds no name for the slot and stores nothing.
    // So the region is written first, under the name the slot is about to
    // get, and the sync setChannel starts reads it from there.
    final store = ChannelRegionStore()
      ..setPublicKeyHex = connector.selfPublicKeyHex
      ..registerChannel(Channel(index: index, name: name, psk: link.psk));
    await store.saveRegion(index, region);
    await connector.setChannel(index, name, link.psk);
    // A slot the connector already knows, an updated channel, takes the
    // region at once instead of at the end of that sync.
    await connector.setChannelRegion(index, region);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AdaptiveAppBarTitle(context.l10n.channels_scanQrCode),
        centerTitle: true,
      ),
      body: QrScannerWidget(
        onScanned: (data) =>
            Navigator.of(context).pop(ChannelQrLink.tryParse(data)),
        validator: ChannelQrLink.isValid,
        onValidationFailed: (_) => showDismissibleSnackBar(
          context,
          content: Text(context.l10n.channels_invalidQrCode),
          backgroundColor: MeshPalette.warn,
        ),
        instructions: context.l10n.channels_scanQrInstructions,
      ),
    );
  }
}
