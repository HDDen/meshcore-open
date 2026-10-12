import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/l10n.dart';
import '../utils/platform_info.dart';
import '../helpers/channel_qr_link.dart'; // channel-qr-chat
import '../helpers/contact_link.dart';
import '../helpers/mesh_link_linkifier.dart';
import '../helpers/snack_bar_builder.dart';
import '../widgets/channel_link_import.dart'; // channel-qr-chat
import '../widgets/contact_link_import.dart';

class LinkHandler {
  static TextStyle defaultLinkStyle(BuildContext context, TextStyle base) {
    final brightness = Theme.of(context).brightness;
    final orange = brightness == Brightness.dark
        ? const Color(0xFFFFB74D)
        : const Color(0xFFE65100);
    return base.copyWith(color: orange, decoration: TextDecoration.underline);
  }

  /// The system text scale as a linear factor for [style]'s size.
  ///
  /// flutter_linkify only takes a `textScaleFactor` (default 1.0, which
  /// ignores the system font size), so the ambient [TextScaler] is sampled
  /// at the style's font size to keep Android's nonlinear scaling. The
  /// in-app chat text scale is already part of `style.fontSize`.
  static double systemTextScaleFactor(BuildContext context, TextStyle style) {
    final fontSize =
        style.fontSize ?? DefaultTextStyle.of(context).style.fontSize ?? 14;
    if (fontSize <= 0) return 1.0;
    return MediaQuery.textScalerOf(context).scale(fontSize) / fontSize;
  }

  /// Returns a [SelectableLinkify] on desktop or a [Linkify] on mobile.
  ///
  /// [textScaler] lets callers scale linkified text explicitly, which the chat
  /// screens do to combine their zoom with the global UI scale (see the DPI
  /// setting). flutter_linkify does not inherit MediaQuery's textScaler, so
  /// without one the system text scale is applied here.
  static Widget buildLinkifyText({
    required BuildContext context,
    required String text,
    required TextStyle style,
    TextStyle? linkStyle,
    TextScaler? textScaler,
    VoidCallback? onSecondaryTap,
  }) {
    final effectiveLinkStyle = linkStyle ?? defaultLinkStyle(context, style);
    const options = LinkifyOptions(humanize: false, defaultToHttps: false);
    const linkifiers = [
      MeshLinkLinkifier(),
      UrlLinkifier(),
      EmailLinkifier(),
    ];
    void onOpen(LinkableElement link) => handleLinkTap(context, link.url);
    // flutter_linkify 6.0.0 exposes textScaleFactor (double), not textScaler.
    final effectiveTextScaleFactor = textScaler != null
        ? textScaler.scale(1.0)
        : systemTextScaleFactor(context, style);

    if (PlatformInfo.isDesktop) {
      final linkify = SelectableLinkify(
        text: text,
        style: style,
        linkStyle: effectiveLinkStyle,
        options: options,
        linkifiers: linkifiers,
        onOpen: onOpen,
        textScaleFactor: effectiveTextScaleFactor,
      );
      if (onSecondaryTap == null) return linkify;
      return Listener(
        onPointerDown: (event) {
          if (event.buttons & kSecondaryMouseButton != 0) onSecondaryTap();
        },
        behavior: HitTestBehavior.translucent,
        child: linkify,
      );
    }
    return Linkify(
      text: text,
      style: style,
      linkStyle: effectiveLinkStyle,
      options: options,
      linkifiers: linkifiers,
      onOpen: onOpen,
      textScaleFactor: effectiveTextScaleFactor,
    );
  }

  static Future<void> handleLinkTap(BuildContext context, String url) async {
    // channel-qr-chat: a channel shared into a chat is added, not browsed.
    final channelLink = ChannelQrLink.tryParse(url);
    if (channelLink != null) {
      return ChannelLinkImport.confirmAndAdd(context, channelLink);
    }
    // A contact shared into a chat is added as from its card.
    final contactLink = ContactLink.tryParse(url);
    if (contactLink != null) {
      return ContactLinkImport.confirmAndAdd(context, contactLink);
    }

    // Show confirmation dialog
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.chat_openLink),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.chat_openLinkConfirmation,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                url,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.chat_open),
          ),
        ],
      ),
    );

    if (shouldOpen != true) return;

    // Launch URL
    try {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (context.mounted) {
          showDismissibleSnackBar(
            context,
            content: Text(context.l10n.chat_couldNotOpenLink(url)),
            backgroundColor: Colors.red,
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.chat_invalidLink),
          backgroundColor: Colors.red,
        );
      }
    }
  }
}
