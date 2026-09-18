import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../helpers/channel_qr_link.dart';
import '../helpers/image_clipboard.dart';
import '../helpers/mco_image_file_saver.dart';
import '../helpers/qr_bitmap.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../models/channel.dart';
import '../widgets/adaptive_app_bar_title.dart';
import '../widgets/qr_code_display.dart';

/// Shows a channel as a `meshcore://channel/add?...` QR code, with its secret
/// key, an optional region scope and a button that copies the link. A tap on
/// the QR code hands it over as a picture, ready for a messenger.
///
/// The region edited here only goes into the link: it starts as the channel's
/// own region and changing it does not touch the channel.
///
/// Fork-only, see `helpers/channel_qr_link.dart` for how to remove it.
class ChannelShareScreen extends StatefulWidget {
  const ChannelShareScreen({
    super.key,
    required this.channel,
    required this.displayName,
    this.initialRegion = '',
  });

  final Channel channel;

  /// What the channel is called in the lists; also the link name when the
  /// channel itself has none.
  final String displayName;
  final String initialRegion;

  static Future<void> open(
    BuildContext context, {
    required Channel channel,
    required String displayName,
    String initialRegion = '',
  }) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ChannelShareScreen(
          channel: channel,
          displayName: displayName,
          initialRegion: initialRegion,
        ),
      ),
    );
  }

  @override
  State<ChannelShareScreen> createState() => _ChannelShareScreenState();
}

class _ChannelShareScreenState extends State<ChannelShareScreen> {
  late final TextEditingController _regionController;
  late final TextEditingController _secretController;
  bool _sendingQrPicture = false;

  @override
  void initState() {
    super.initState();
    _regionController = TextEditingController(
      text: widget.initialRegion.trim(),
    );
    _secretController = TextEditingController(
      text: Channel.formatPskHex(widget.channel.psk).toLowerCase(),
    );
  }

  @override
  void dispose() {
    _regionController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  String get _linkName {
    final name = widget.channel.name.trim();
    return name.isEmpty ? widget.displayName : name;
  }

  String get _link => ChannelQrLink(
    name: _linkName,
    psk: widget.channel.psk,
    regionScope: _regionController.text,
  ).toLink();

  Future<void> _copy(String text, String confirmation) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showDismissibleSnackBar(context, content: Text(confirmation));
  }

  /// Onto the clipboard where the platform has one for pictures; through the
  /// save dialog or the share sheet everywhere else, which on a phone is the
  /// shorter way into a messenger anyway.
  Future<void> _sendQrPicture(String link) async {
    if (_sendingQrPicture) return;
    _sendingQrPicture = true;
    final l10n = context.l10n;
    String? notice;
    try {
      final bitmap = QrBitmap.render(link);
      final png = await bitmap.toPng();
      if (!ImageClipboard.isSupported) {
        await MCOImageFileSaver.savePngBytes(
          png,
          suggestedName: 'meshcore-channel-qr.png',
        );
      } else if (await ImageClipboard.write(
        width: bitmap.size,
        height: bitmap.size,
        rgba: bitmap.rgba,
        png: png,
      )) {
        notice = l10n.channels_shareQrImageCopied;
      } else {
        notice = l10n.channels_shareQrImageFailed;
      }
    } catch (error) {
      debugPrint('Channel QR picture failed: $error');
      notice = l10n.channels_shareQrImageFailed;
    } finally {
      _sendingQrPicture = false;
    }
    if (notice == null) return;
    if (!mounted) return;
    showDismissibleSnackBar(context, content: Text(notice));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final link = _link;
    final copiesQrPicture = ImageClipboard.isSupported;
    final tapHint = copiesQrPicture
        ? l10n.channels_shareQrTapToCopy
        : l10n.channels_shareQrTapToShare;
    return Scaffold(
      appBar: AppBar(
        title: AdaptiveAppBarTitle(l10n.common_share),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Tooltip(
                message: copiesQrPicture ? l10n.common_copy : l10n.common_share,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _sendQrPicture(link),
                  child: QrCodeDisplay(
                    data: link,
                    size: 240,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.displayName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '${l10n.channels_shareQrHint}\n$tapHint',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _secretController,
              readOnly: true,
              maxLines: null,
              decoration: InputDecoration(
                filled: true,
                labelText: l10n.channels_shareSecretKey,
                suffixIcon: IconButton(
                  tooltip: l10n.common_copy,
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: () => _copy(
                    _secretController.text,
                    l10n.channels_shareKeyCopied,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            TextField(
              controller: _regionController,
              autocorrect: false,
              enableSuggestions: false,
              // What the region screen lets a name be made of, so the link
              // is one the scanner on the other side accepts.
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[a-z0-9-]')),
                LengthLimitingTextInputFormatter(
                  ChannelQrLink.maxRegionLength,
                ),
              ],
              textInputAction: TextInputAction.done,
              // The QR code and the link follow the field as it is typed.
              onChanged: (_) => setState(() {}),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                filled: true,
                labelText: l10n.channels_shareRegionScope,
                suffixIcon: _regionController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l10n.common_clear,
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_regionController.clear),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _copy(link, l10n.channels_shareLinkCopied),
              icon: const Icon(Icons.link),
              label: Text(l10n.discoveredContacts_copyContact),
            ),
          ],
        ),
      ),
    );
  }
}
