import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../helpers/link_handler.dart';
import '../l10n/l10n.dart';

class DonateScreen extends StatelessWidget {
  const DonateScreen({super.key});

  static const String tipUrl = 'https://pay.cloudtips.ru/p/b6dc28c1';
  static const String upstreamUrl = 'https://meshcoreopen.org/about/#donations';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.settings_supportDevelopment,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                l10n.donate_intro,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Text(
                l10n.donate_tipLinkLabel,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              _DonateLink(url: tipUrl),
              const SizedBox(height: 24),
              SvgPicture.asset(
                'assets/images/donate-mcoa.svg',
                width: 220,
                height: 220,
              ),
              const SizedBox(height: 24),
              Text(
                l10n.donate_upstreamAuthor,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              _DonateLink(url: upstreamUrl),
            ],
          ),
        ),
      ),
    );
  }
}

/// A centered tappable URL. Linkify aligns its text to the left and cannot be
/// centered, so the link is drawn as plain text and routed through the same
/// confirmation dialog that chat links use.
class _DonateLink extends StatelessWidget {
  const _DonateLink({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    return InkWell(
      onTap: () => LinkHandler.handleLinkTap(context, url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          url,
          textAlign: TextAlign.center,
          style: LinkHandler.defaultLinkStyle(context, base),
        ),
      ),
    );
  }
}
