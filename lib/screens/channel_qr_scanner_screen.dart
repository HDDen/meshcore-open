import 'package:flutter/material.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/channel_qr_link.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../theme/mesh_theme.dart';
import '../widgets/adaptive_app_bar_title.dart';
import '../widgets/channel_link_import.dart';
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
    await ChannelLinkImport.addScanned(
      context,
      connector: connector,
      link: link,
      index: index,
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
