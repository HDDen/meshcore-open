import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/app_settings.dart';
import '../services/app_settings_service.dart';
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
        child: Consumer<AppSettingsService>(
          builder: (context, settingsService, child) {
            final settings = settingsService.settings;
            return ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
              children: [
                SectionHeader(context.l10n.settings_modSettingsVisual),
                MeshCard(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    secondary: const Icon(Icons.tag_outlined, size: 20),
                    title: Text(context.l10n.settings_modSettingsHideChInd),
                    value: settings.hideChannelIndexIndicator,
                    onChanged: settingsService.setHideChannelIndexIndicator,
                  ),
                ),
                MeshCard(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    secondary: const Icon(Icons.zoom_out_map, size: 20),
                    title: Text(
                      context
                          .l10n
                          .settings_modSettingsVisualHideMapZoomControls,
                    ),
                    value: settings.hideMapZoomControls,
                    onChanged: settingsService.setHideMapZoomControls,
                  ),
                ),
                MeshCard(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    secondary: const Icon(Icons.aspect_ratio, size: 20),
                    title: Text(
                      context
                          .l10n
                          .settings_modSettingsVisualShowMCOimgResolution,
                    ),
                    value: settings.showMcoImageResolution,
                    onChanged: settingsService.setShowMcoImageResolution,
                  ),
                ),
                MeshCard(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    secondary: const Icon(Icons.numbers, size: 20),
                    title: Text(
                      context.l10n.settings_modSettingsVisualShowMCOimgFormat,
                    ),
                    value: settings.showMcoImageFormat,
                    onChanged: settingsService.setShowMcoImageFormat,
                  ),
                ),
                MeshCard(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    secondary: const Icon(Icons.account_tree_outlined, size: 20),
                    title: Text(
                      context.l10n.settings_modSettingsVisualShowMCOimgAlgo,
                    ),
                    value: settings.showMcoImageAlgorithm,
                    onChanged: settingsService.setShowMcoImageAlgorithm,
                  ),
                ),
                MeshCard(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    secondary: const Icon(Icons.data_usage_outlined, size: 20),
                    title: Text(
                      context.l10n.settings_modSettingsVisualShowMCOimgBytes,
                    ),
                    value: settings.showMcoImageBytes,
                    onChanged: settingsService.setShowMcoImageBytes,
                  ),
                ),
                MeshCard(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    secondary: const Icon(Icons.compress, size: 20),
                    title: Text(
                      context
                          .l10n
                          .settings_modSettingsMessagingShowCompressionRatio,
                    ),
                    value: settings.showCompressionRatio,
                    onChanged: settingsService.setShowCompressionRatio,
                  ),
                ),
                MeshCard(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    secondary: const Icon(Icons.person_outline, size: 20),
                    title: Text(
                      context
                          .l10n
                          .settings_modSettingsMessagingCompressionRatioWithSendername,
                    ),
                    value: settings.compressionRatioWithSenderName,
                    onChanged:
                        settingsService.setCompressionRatioWithSenderName,
                  ),
                ),
                MeshCard(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    secondary: const Icon(Icons.public, size: 20),
                    title: Text(
                      context.l10n.settings_modSettingsVisualShowMsgRegion,
                    ),
                    value: settings.showMessageRegion,
                    onChanged: settingsService.setShowMessageRegion,
                  ),
                ),
                SectionHeader(context.l10n.settings_modSettingsMessaging),
                MeshCard(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    secondary: const Icon(Icons.alternate_email, size: 20),
                    title: Text(
                      context.l10n.settings_modSettingsIncomingQuoteAsMentions,
                    ),
                    value: settings.incomingQuoteAsMentions,
                    onChanged: settingsService.setIncomingQuoteAsMentions,
                  ),
                ),
                MeshCard(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    secondary: const Icon(Icons.text_fields, size: 20),
                    title: Text(
                      context.l10n.settings_modSettingsSimplifiedMentions,
                    ),
                    value: settings.simplifiedMentions,
                    onChanged: settingsService.setSimplifiedMentions,
                  ),
                ),
                MeshCard(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<SharedMessageHistoryMode>(
                        initialValue: settings.sharedMessageHistoryMode,
                        decoration: InputDecoration(
                          labelText:
                              context.l10n.settings_modSettingsSharedMsgHistory,
                          prefixIcon: const Icon(Icons.history, size: 20),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: SharedMessageHistoryMode.disabled,
                            child: Text(
                              context
                                  .l10n
                                  .settings_modSettingsSharedMsgHistoryDisabled,
                            ),
                          ),
                          DropdownMenuItem(
                            value: SharedMessageHistoryMode.channels,
                            child: Text(
                              context
                                  .l10n
                                  .settings_modSettingsSharedMsgHistoryChannels,
                            ),
                          ),
                          DropdownMenuItem(
                            value: SharedMessageHistoryMode.contacts,
                            child: Text(
                              context
                                  .l10n
                                  .settings_modSettingsSharedMsgHistoryContacts,
                            ),
                          ),
                          DropdownMenuItem(
                            value: SharedMessageHistoryMode.all,
                            child: Text(
                              context
                                  .l10n
                                  .settings_modSettingsSharedMsgHistoryAll,
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          settingsService.setSharedMessageHistoryMode(value);
                        },
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          context.l10n.settings_modSettingsSharedMsgHistoryDscr,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
