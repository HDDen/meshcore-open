import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/channel_qr_link.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../models/channel.dart';
import '../storage/channel_region_store.dart';
import '../storage/region_store.dart';
import '../theme/mesh_theme.dart';

/// Adds the channel a `meshcore://channel/add?...` link describes, whether it
/// was scanned from a QR code, tapped in a message or pasted from the
/// clipboard.
///
/// Fork-only, see `helpers/channel_qr_link.dart` for how to remove it.
class ChannelLinkImport {
  ChannelLinkImport._();

  /// A link tapped in a message or pasted from the clipboard. It needs a live
  /// session with the node, and a new channel is asked about before it takes
  /// the first free slot, since the link is somebody else's suggestion.
  static Future<void> confirmAndAdd(
    BuildContext context,
    ChannelQrLink link,
  ) async {
    final connector = context.read<MeshCoreConnector>();
    if (connector.isOfflineMode) {
      _warn(context, context.l10n.app_offline_unableToMessage);
      return;
    }
    if (!connector.isConnected) {
      _warn(context, context.l10n.scanner_notConnected);
      return;
    }
    await _import(context, connector, link, confirmNew: true);
  }

  /// A scanned QR code: a new channel goes into [index] at once, the scan
  /// itself being the request.
  static Future<void> addScanned(
    BuildContext context, {
    required MeshCoreConnector connector,
    required ChannelQrLink link,
    required int index,
  }) => _import(context, connector, link, index: index);

  static Future<void> _import(
    BuildContext context,
    MeshCoreConnector connector,
    ChannelQrLink link, {
    int? index,
    bool confirmNew = false,
  }) async {
    final plan = link.importInto(
      connector.channels,
      regionOf: connector.getChannelRegion,
    );
    final existing = plan.existing;
    switch (plan.action) {
      case ChannelQrImportAction.alreadyAdded:
        _warn(context, context.l10n.channels_qrAlreadyAdded(existing!.name));
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
        final slot = index ?? _freeSlot(connector);
        if (slot == null) {
          _warn(context, context.l10n.channels_noFreeSlots);
          return;
        }
        if (confirmNew && !await _confirmAdd(context, link)) return;
        await _write(connector, slot, link.name, link);
        if (!context.mounted) return;
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.channels_channelAdded(link.name)),
        );
    }
  }

  /// The first slot no channel holds, as the channels screen picks one.
  static int? _freeSlot(MeshCoreConnector connector) {
    final used = {for (final channel in connector.channels) channel.index};
    for (var index = 0; index < connector.maxChannels; index++) {
      if (!used.contains(index)) return index;
    }
    return null;
  }

  static void _warn(BuildContext context, String message) {
    showDismissibleSnackBar(
      context,
      content: Text(message),
      backgroundColor: MeshPalette.warn,
    );
  }

  static Future<bool> _confirmAdd(
    BuildContext context,
    ChannelQrLink link,
  ) async {
    final l10n = context.l10n;
    final region = link.regionScope ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.channels_addChannel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              link.name,
              style: Theme.of(dialogContext).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              region.isEmpty
                  ? l10n.channels_regionNotSet
                  : l10n.channels_regionSetTo(region),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.common_add),
          ),
        ],
      ),
    );
    return confirmed == true;
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
}
