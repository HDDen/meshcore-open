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
    await _import(context, connector, link, confirmNew: true);
  }

  /// A scanned QR code: prefer [index] if it is still free. The scan itself
  /// is the request, but its node and slot must be checked again on return.
  static Future<void> addScanned(
    BuildContext context, {
    required MeshCoreConnector connector,
    required ChannelQrLink link,
    required int index,
    String? expectedNodeKey,
  }) => _import(
    context,
    connector,
    link,
    index: index,
    expectedNodeKey: expectedNodeKey,
  );

  static Future<void> _import(
    BuildContext context,
    MeshCoreConnector connector,
    ChannelQrLink link, {
    int? index,
    bool confirmNew = false,
    String? expectedNodeKey,
  }) async {
    final nodeKey = expectedNodeKey ?? connector.selfPublicKeyHex;
    if (!_ready(context, connector, nodeKey)) {
      return;
    }
    final plan = link.importInto(
      connector.channels,
      regionOf: connector.getChannelRegion,
    );
    final existing = plan.existing;
    switch (plan.action) {
      case ChannelQrImportAction.alreadyAdded:
        _warn(context, context.l10n.channels_qrAlreadyAdded(existing!.name));
        return;
      case ChannelQrImportAction.update:
        if (!await _confirmUpdate(context, existing!.name)) {
          return;
        }
        if (!context.mounted) {
          return;
        }
        if (!_ready(context, connector, nodeKey)) {
          return;
        }
        final updatePlan = link.importInto(
          connector.channels,
          regionOf: connector.getChannelRegion,
        );
        if (updatePlan.action == ChannelQrImportAction.alreadyAdded) {
          _warn(
            context,
            context.l10n.channels_qrAlreadyAdded(updatePlan.existing!.name),
          );
          return;
        }
        if (updatePlan.action != ChannelQrImportAction.update ||
            !_sameChannel(existing, updatePlan.existing) ||
            connector.unconfirmedChannelSlots.contains(existing.index)) {
          _warn(context, context.l10n.channels_qrImportChanged);
          return;
        }
        // The channel keeps its own name: history and settings hang on it.
        final updated = await _write(
          context,
          connector,
          existing.index,
          existing.name,
          link,
          nodeKey: nodeKey,
          canWrite: () {
            if (!_ready(context, connector, nodeKey)) {
              return false;
            }
            final latest = link.importInto(
              connector.channels,
              regionOf: connector.getChannelRegion,
            );
            if (latest.action != ChannelQrImportAction.update ||
                !_sameChannel(existing, latest.existing) ||
                connector.unconfirmedChannelSlots.contains(existing.index)) {
              _warn(context, context.l10n.channels_qrImportChanged);
              return false;
            }
            return true;
          },
        );
        if (!updated) {
          return;
        }
        if (!context.mounted) {
          return;
        }
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.channels_channelUpdated(existing.name)),
        );
        return;
      case ChannelQrImportAction.add:
        if (_freeSlot(connector, preferred: index) == null) {
          _warn(context, context.l10n.channels_noFreeSlots);
          return;
        }
        if (confirmNew && !await _confirmAdd(context, link)) {
          return;
        }
        if (!context.mounted) {
          return;
        }
        if (!_ready(context, connector, nodeKey)) {
          return;
        }
        final addPlan = link.importInto(
          connector.channels,
          regionOf: connector.getChannelRegion,
        );
        if (addPlan.action == ChannelQrImportAction.alreadyAdded) {
          _warn(
            context,
            context.l10n.channels_qrAlreadyAdded(addPlan.existing!.name),
          );
          return;
        }
        // Confirmation to add a new channel is not permission to replace
        // another one that acquired its name while the dialog was open.
        if (addPlan.action != ChannelQrImportAction.add) {
          _warn(context, context.l10n.channels_qrImportChanged);
          return;
        }
        final slot = _freeSlot(connector, preferred: index);
        if (slot == null) {
          _warn(context, context.l10n.channels_noFreeSlots);
          return;
        }
        final added = await _write(
          context,
          connector,
          slot,
          link.name,
          link,
          nodeKey: nodeKey,
          canWrite: () {
            if (!_ready(context, connector, nodeKey)) {
              return false;
            }
            final latest = link.importInto(
              connector.channels,
              regionOf: connector.getChannelRegion,
            );
            if (latest.action != ChannelQrImportAction.add ||
                _freeSlot(connector, preferred: slot) != slot) {
              _warn(context, context.l10n.channels_qrImportChanged);
              return false;
            }
            return true;
          },
        );
        if (!added) {
          return;
        }
        if (!context.mounted) {
          return;
        }
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.channels_channelAdded(link.name)),
        );
    }
  }

  /// A scanner/dialog can outlive the connection or its channel sync. Read
  /// current in-memory state; never start another request or wait by polling.
  static bool _ready(
    BuildContext context,
    MeshCoreConnector connector,
    String nodeKey,
  ) {
    if (!context.mounted) {
      return false;
    }
    if (connector.isOfflineMode) {
      _warn(context, context.l10n.app_offline_unableToMessage);
      return false;
    }
    if (!connector.isConnected) {
      _warn(context, context.l10n.scanner_notConnected);
      return false;
    }
    if (nodeKey.isEmpty || connector.selfPublicKeyHex != nodeKey) {
      _warn(context, context.l10n.channels_qrImportChanged);
      return false;
    }
    if (!connector.hasLoadedChannels || connector.isSyncingChannels) {
      _warn(context, context.l10n.channels_waitForSync);
      return false;
    }
    return true;
  }

  static bool _sameChannel(Channel a, Channel? b) =>
      b != null && a.index == b.index && a.name == b.name && a.pskHex == b.pskHex;

  /// The first slot no channel holds, as the channels screen picks one.
  /// A pre-scan slot is only a preference; it may have been occupied meanwhile.
  static int? _freeSlot(MeshCoreConnector connector, {int? preferred}) {
    final used = {
      for (final channel in connector.channels) channel.index,
      ...connector.unconfirmedChannelSlots,
    };
    if (preferred != null &&
        preferred >= 0 &&
        preferred < connector.maxChannels &&
        !used.contains(preferred)) {
      return preferred;
    }
    for (var index = 0; index < connector.maxChannels; index++) {
      if (!used.contains(index)) {
        return index;
      }
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
        // The full channel name and region remain readable with large text.
        scrollable: true,
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
  static Future<bool> _write(
    BuildContext context,
    MeshCoreConnector connector,
    int index,
    String name,
    ChannelQrLink link, {
    required String nodeKey,
    required bool Function() canWrite,
  }) async {
    if (!canWrite()) {
      return false;
    }
    final region = link.regionScope ?? '';
    if (region.isNotEmpty) {
      final regions = RegionStore();
      if (!regions.loadRegions().contains(region)) {
        regions.addRegion(region);
      }
    }
    // A channel's region is stored under the channel's name, and the connector
    // learns which name a slot holds only when the node reports it back, some
    // time after setChannel has returned. For a new channel that is too late
    // for setChannelRegion: it finds no name for the slot and stores nothing.
    // So the region is written first, under the name the slot is about to
    // get, and the sync setChannel starts reads it from there.
    final store = ChannelRegionStore()
      ..setPublicKeyHex = nodeKey
      ..registerChannel(Channel(index: index, name: name, psk: link.psk));
    await store.saveRegion(index, region);
    // Preferences can complete asynchronously. Recheck before a radio command
    // so a context change cannot redirect that command to a different node.
    if (!canWrite()) {
      return false;
    }
    await connector.setChannel(index, name, link.psk);
    if (!context.mounted) {
      return false;
    }
    if (!connector.isConnected ||
        connector.isOfflineMode ||
        connector.selfPublicKeyHex != nodeKey) {
      _warn(context, context.l10n.channels_qrImportChanged);
      return false;
    }
    // A slot the connector already knows, an updated channel, takes the
    // region at once instead of at the end of that sync.
    await connector.setChannelRegion(index, region);
    return true;
  }
}
