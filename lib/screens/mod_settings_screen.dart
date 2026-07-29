import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/app_settings.dart';
import '../services/app_settings_service.dart';
import 'package:mco_service/mco_service.dart';
import '../utils/platform_info.dart';
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
                    secondary: const Icon(Icons.insights_outlined, size: 20),
                    title: Text(
                      context.l10n.settings_modSettingsHideRadioStats,
                    ),
                    value: settings.hideRadioStatsButton,
                    onChanged: settingsService.setHideRadioStatsButton,
                  ),
                ),
                MeshCard(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    secondary: const Icon(Icons.cell_tower, size: 20),
                    title: Text(
                      context
                          .l10n
                          .settings_modSettingsSNRindicatorAllRepActivity,
                    ),
                    value: settings.snrIndicatorAllRepActivity,
                    onChanged: settingsService.setSnrIndicatorAllRepActivity,
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
                MeshCard(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    secondary: const Icon(Icons.mark_email_unread, size: 20),
                    title: Text(
                      context
                          .l10n
                          .settings_modSettingsVisualChannelsUnreadSorting,
                    ),
                    value: settings.channelsUnreadSorting,
                    onChanged: settingsService.setChannelsUnreadSorting,
                  ),
                ),
                MeshCard(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.format_size, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              context.l10n.settings_modSettingsDPIchange,
                            ),
                          ),
                          Text(
                            '${(settings.uiScale * 100).round()}%',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.image_outlined, size: 20),
                        title: Text(
                          context.l10n.settings_modSettingsDPIchangeToIcons,
                        ),
                        value: settings.uiScaleApplyToIcons,
                        onChanged: settingsService.setUiScaleApplyToIcons,
                      ),
                      Slider(
                        value: settings.uiScale.clamp(0.5, 2.0).toDouble(),
                        min: 0.5,
                        max: 2.0,
                        divisions: 30,
                        label: '${(settings.uiScale * 100).round()}%',
                        onChanged: (value) {
                          settingsService.setUiScale((value * 20).round() / 20);
                        },
                      ),
                    ],
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
                MeshCard(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.cell_tower, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              context.l10n.settings_modSettingsNoRetraHeading,
                            ),
                          ),
                          Text(
                            settings.noRetransmissionWarningSeconds <= 0
                                ? 'Off'
                                : '${settings.noRetransmissionWarningSeconds}s',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(left: 32),
                        child: Text(
                          context.l10n.settings_modSettingsNoRetraDscr,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      Slider(
                        value: settings.noRetransmissionWarningSeconds <= 0
                            ? 4.0
                            : settings.noRetransmissionWarningSeconds
                                  .toDouble(),
                        min: 4,
                        max: AppSettings.maxNoRetransmissionWarningSeconds
                            .toDouble(),
                        divisions:
                            AppSettings.maxNoRetransmissionWarningSeconds - 4,
                        label: settings.noRetransmissionWarningSeconds <= 0
                            ? 'Off'
                            : '${settings.noRetransmissionWarningSeconds}s',
                        onChanged: (value) {
                          final rounded = value.round();
                          settingsService.setNoRetransmissionWarningSeconds(
                            rounded <
                                    AppSettings
                                        .minNoRetransmissionWarningSeconds
                                ? 0
                                : rounded,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                if (PlatformInfo.isAndroid)
                  MeshCard(
                    padding: EdgeInsets.zero,
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      secondary: const Icon(
                        Icons.cloud_sync_outlined,
                        size: 20,
                      ),
                      title: Text(
                        context.l10n.settings_modSettingsMessagingBackgroundTCP,
                      ),
                      value: settings.backgroundTcpEnabled,
                      onChanged: settingsService.setBackgroundTcpEnabled,
                    ),
                  ),
                SectionHeader(context.l10n.settings_modSettingsMCOimg),
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
                    secondary: const Icon(
                      Icons.account_tree_outlined,
                      size: 20,
                    ),
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
                    secondary: const Icon(Icons.image_outlined, size: 20),
                    title: Text(
                      context.l10n.settings_modSettingsMCOimg_showReplacements,
                    ),
                    value: settings.showMcoImagePackReplacements,
                    onChanged: settingsService.setShowMcoImagePackReplacements,
                  ),
                ),
                MeshCard(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.zoom_in, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              context
                                  .l10n
                                  .settings_modSettingsMCOimg_replacementsScale,
                            ),
                          ),
                          Text(
                            '${settings.mcoImageReplacementsScale.toStringAsFixed(1)}x',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                      Slider(
                        value: settings.mcoImageReplacementsScale
                            .clamp(1.0, 5.0)
                            .toDouble(),
                        min: 1.0,
                        max: 5.0,
                        divisions: 40,
                        label:
                            '${settings.mcoImageReplacementsScale.toStringAsFixed(1)}x',
                        onChanged: (value) {
                          settingsService.setMcoImageReplacementsScale(
                            (value * 10).round() / 10,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                MeshCard(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.animation, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              context
                                  .l10n
                                  .settings_modSettingsMCOimg_replacementsLottieScale,
                            ),
                          ),
                          Text(
                            '${settings.mcoImageReplacementsLottieScalePercent}%',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                      Slider(
                        value: settings.mcoImageReplacementsLottieScalePercent
                            .clamp(10, 100)
                            .toDouble(),
                        min: 10,
                        max: 100,
                        divisions: 9,
                        label:
                            '${settings.mcoImageReplacementsLottieScalePercent}%',
                        onChanged: (value) {
                          settingsService
                              .setMcoImageReplacementsLottieScalePercent(
                                value.round(),
                              );
                        },
                      ),
                    ],
                  ),
                ),
                MeshCard(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    secondary: const Icon(Icons.grid_on, size: 20),
                    title: Text(
                      context
                          .l10n
                          .settings_modSettingsMCOimg_scaleNearestNeighbor,
                    ),
                    value: settings.mcoImageScaleNearestNeighbor,
                    onChanged: settingsService.setMcoImageScaleNearestNeighbor,
                  ),
                ),
                MeshCard(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.deblur, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              context
                                  .l10n
                                  .settings_modSettingsMCOimg_replacementsSharp,
                            ),
                          ),
                          Text(
                            '${settings.mcoImageReplacementsSharpness}',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(left: 32),
                        child: Text(
                          context
                              .l10n
                              .settings_modSettingsMCOimg_replacementsSharpDscr,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      Slider(
                        value: settings.mcoImageReplacementsSharpness
                            .clamp(0, 10)
                            .toDouble(),
                        min: 0,
                        max: 10,
                        divisions: 10,
                        label: '${settings.mcoImageReplacementsSharpness}',
                        onChanged: (value) {
                          settingsService.setMcoImageReplacementsSharpness(
                            value.round(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                SectionHeader(context.l10n.settings_modSettingsRoomServer),
                MeshCard(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    value: settings.roomServerShowNotemptyOnChatscreen,
                    onChanged:
                        settingsService.setRoomServerShowNotemptyOnChatscreen,
                    secondary: const Icon(Icons.meeting_room_outlined),
                    title: Text(
                      context
                          .l10n
                          .settings_modSettingsRoomServerShowNotemptyOnChatscreen,
                    ),
                  ),
                ),
                MeshCard(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    value: settings.roomServerShowNotemptyContactsOnChatscreen,
                    onChanged: settingsService
                        .setRoomServerShowNotemptyContactsOnChatscreen,
                    secondary: const Icon(Icons.person_outline),
                    title: Text(
                      context
                          .l10n
                          .settings_modSettingsRoomServerShowNotemptyContactsOnChatscreen,
                    ),
                  ),
                ),
                MeshCard(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    value: settings.roomServerDisableRoomAndContactsSorting,
                    onChanged: settingsService
                        .setRoomServerDisableRoomAndContactsSorting,
                    secondary: const Icon(Icons.low_priority_outlined),
                    title: Text(
                      context
                          .l10n
                          .settings_modSettingsRoomServerDisableRoomAndContactsSorting,
                    ),
                  ),
                ),
                ...context.watch<SettingsSectionsService>().modSettingsSections(
                  context,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
