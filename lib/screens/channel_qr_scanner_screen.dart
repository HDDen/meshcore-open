import 'package:flutter/material.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/channel_qr_link.dart';
import '../helpers/qr_gallery_scan.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../theme/mesh_theme.dart';
import '../widgets/adaptive_app_bar_title.dart';
import '../widgets/channel_link_import.dart';
import '../widgets/qr_scanner_widget.dart';

/// Scans a `meshcore://channel/add?...` QR code of an ordinary private or
/// hashtag channel, with the camera or from a picture in the gallery, and
/// returns the parsed [ChannelQrLink].
///
/// Fork-only, see `helpers/channel_qr_link.dart` for how to remove it.
class ChannelQrScannerScreen extends StatefulWidget {
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
  State<ChannelQrScannerScreen> createState() => _ChannelQrScannerScreenState();
}

class _ChannelQrScannerScreenState extends State<ChannelQrScannerScreen> {
  /// Set while the gallery is open, so that the camera cannot pop the route
  /// with a second code meanwhile, and kept once a code was taken, so that
  /// the camera does not restart on the closing route.
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AdaptiveAppBarTitle(context.l10n.channels_scanQrCode),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: context.l10n.contacts_qrFromGallery,
            icon: const Icon(Icons.photo_library),
            onPressed: _isProcessing ? null : _pickFromGallery,
          ),
        ],
      ),
      body: _isProcessing
          ? const QrScannerProcessingBody()
          : QrScannerWidget(
              onScanned: _finish,
              validator: ChannelQrLink.isValid,
              onValidationFailed: (_) => _showInvalidQr(),
              instructions: context.l10n.channels_scanQrInstructions,
              // Without a camera (Windows, Linux) a picture is the way in,
              // so the widget offers the gallery under its camera message.
              onPickPicture: _pickFromGallery,
            ),
    );
  }

  void _finish(String data) {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    Navigator.of(context).pop(ChannelQrLink.tryParse(data));
  }

  Future<void> _pickFromGallery() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    final scan = await scanQrFromGallery(accepts: ChannelQrLink.isValid);
    if (!mounted) return;
    switch (scan.status) {
      case QrGalleryScanStatus.found:
        Navigator.of(context).pop(ChannelQrLink.tryParse(scan.value!));
        return;
      case QrGalleryScanStatus.cancelled:
        break;
      case QrGalleryScanStatus.pickerFailed:
        _warn(context.l10n.contacts_qrGalleryFailed);
      case QrGalleryScanStatus.noBarcode:
        _warn(context.l10n.contacts_noQrCodeFound);
      case QrGalleryScanStatus.noMatch:
        _showInvalidQr();
    }
    setState(() => _isProcessing = false);
  }

  void _showInvalidQr() =>
      showInvalidQrSnackBar(context, context.l10n.channels_invalidQrCode);

  void _warn(String text) => showDismissibleSnackBar(
    context,
    content: Text(text),
    backgroundColor: MeshPalette.warn,
    duration: const Duration(seconds: 2),
  );
}
