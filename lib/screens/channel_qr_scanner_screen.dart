import 'package:flutter/material.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/channel_qr_link.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../models/channel.dart';
import '../theme/mesh_theme.dart';
import '../widgets/adaptive_app_bar_title.dart';
import '../widgets/qr_scanner_widget.dart';

/// Scans a `meshcore://channel/add?...` QR code of an ordinary private or
/// hashtag channel and returns the parsed [ChannelQrLink].
///
/// Fork-only, see `helpers/channel_qr_link.dart` for how to remove it.
class ChannelQrScannerScreen extends StatelessWidget {
  const ChannelQrScannerScreen({super.key});

  /// Opens the scanner and puts the scanned channel into slot [index].
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

    // The secret is the channel: the same key under another name is the same
    // channel, so a second copy would only waste a slot.
    final pskHex = Channel.formatPskHex(link.psk);
    for (final channel in connector.channels) {
      if (channel.isEmpty || channel.pskHex != pskHex) continue;
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.channels_qrAlreadyAdded(channel.name)),
        backgroundColor: MeshPalette.warn,
      );
      return;
    }

    await connector.setChannel(index, link.name, link.psk);
    final region = link.regionScope;
    if (region != null) await connector.setChannelRegion(index, region);
    if (!context.mounted) return;
    showDismissibleSnackBar(
      context,
      content: Text(context.l10n.channels_channelAdded(link.name)),
    );
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
