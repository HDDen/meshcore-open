import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../widgets/adaptive_app_bar_title.dart';
import '../widgets/mesh_ui.dart';
import '../widgets/sync_progress_overlay.dart';

class ModSettingsScreen extends StatelessWidget {
  const ModSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AdaptiveAppBarTitle(context.l10n.settings_modSettings),
        centerTitle: true,
        bottom: const SyncProgressAppBarBottom(),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
          children: [
            SectionHeader(context.l10n.settings_modSettingsVisual),
            SectionHeader(context.l10n.settings_modSettingsMessaging),
          ],
        ),
      ),
    );
  }
}
