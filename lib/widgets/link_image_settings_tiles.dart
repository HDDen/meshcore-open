import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../services/app_settings_service.dart';

/// Global policy and the fallback for chats without a saved URL-image choice.
/// Neither switch rewrites individual chat settings or starts a file upload.
class LinkImageSettingsTiles extends StatelessWidget {
  const LinkImageSettingsTiles({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppSettingsService>(
      builder: (context, service, child) {
        final settings = service.settings;
        return Column(
          children: [
            SwitchListTile(
              key: const ValueKey('load-link-images'),
              secondary: const Icon(Icons.image_search_outlined),
              title: Text(context.l10n.appSettings_loadLinkImages),
              subtitle: Text(context.l10n.appSettings_loadLinkImagesSubtitle),
              value: settings.loadLinkImages,
              onChanged: service.setLoadLinkImages,
            ),
            SwitchListTile(
              key: const ValueKey('show-link-images-by-default'),
              secondary: const Icon(Icons.collections_outlined),
              title: Text(context.l10n.appSettings_showLinkImagesByDefault),
              subtitle: Text(context.l10n.appSettings_showLinkImagesByDefaultSubtitle),
              value: settings.showLinkImagesByDefault,
              onChanged: settings.loadLinkImages
                  ? service.setShowLinkImagesByDefault
                  : null,
            ),
          ],
        );
      },
    );
  }
}
