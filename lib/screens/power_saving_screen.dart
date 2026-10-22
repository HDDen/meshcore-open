import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n.dart';
import '../models/power_saving_settings.dart';
import '../helpers/device_polling_intervals.dart';
import '../services/app_settings_service.dart';
import '../widgets/mesh_ui.dart';
import '../widgets/power_saving_interval_card.dart';

String powerSavingProfileLabel(
  AppLocalizations l10n,
  PowerSavingProfile profile,
) => switch (profile) {
  PowerSavingProfile.disabled => l10n.powerSaving_disabled,
  PowerSavingProfile.balanced => l10n.powerSaving_balanced,
  PowerSavingProfile.economical => l10n.powerSaving_economical,
  PowerSavingProfile.maximum => l10n.powerSaving_maximum,
  PowerSavingProfile.custom => l10n.powerSaving_custom,
};

class PowerSavingScreen extends StatelessWidget {
  const PowerSavingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<AppSettingsService>();
    final settings = service.settings.powerSaving;
    final custom = settings.profile == PowerSavingProfile.custom;
    final effective = settings.effective;
    final deviceIntervals = DevicePollingIntervals.fromOptions(effective);
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.powerSaving_title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          InputDecorator(
            decoration: InputDecoration(labelText: l10n.powerSaving_profile),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<PowerSavingProfile>(
                value: settings.profile,
                isExpanded: true,
                items: [
                  for (final profile in PowerSavingProfile.values)
                    DropdownMenuItem<PowerSavingProfile>(
                      value: profile,
                      child: Text(powerSavingProfileLabel(l10n, profile)),
                    ),
                ],
                onChanged: (profile) {
                  if (profile == null) return;
                  unawaited(service.setPowerSavingProfile(profile));
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          PowerSavingIntervalCard(
            key: const ValueKey('power-saving-radio-stats'),
            title: l10n.powerSaving_hiddenRadioStatsInterval,
            description: l10n.powerSaving_radioStatsDescription,
            value: effective.hiddenRadioStatsIntervalSeconds,
            minimum: PowerSavingOptions.minRadioStatsInterval,
            maximum: PowerSavingOptions.maxRadioStatsInterval,
            onSaved: custom ? service.setHiddenRadioStatsIntervalSeconds : null,
          ),
          const SizedBox(height: 12),
          MeshCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              key: const ValueKey('power-saving-radio-indicator'),
              title: Text(l10n.powerSaving_pauseHiddenRadioIndicator),
              subtitle: Text(l10n.powerSaving_pauseHiddenRadioIndicatorDescription),
              value: settings.effective.pauseHiddenRadioIndicator,
              onChanged: custom
                  ? (value) => unawaited(
                      service.setPauseHiddenRadioIndicator(value),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          PowerSavingIntervalCard(
            key: const ValueKey('power-saving-battery'),
            title: l10n.powerSaving_batteryInterval,
            description: l10n.powerSaving_batteryDescription(
              deviceIntervals.watchdogSilence.inMinutes,
            ),
            value: effective.batteryIntervalSeconds,
            minimum: PowerSavingOptions.minBatteryInterval,
            maximum: PowerSavingOptions.maxBatteryInterval,
            step: PowerSavingOptions.deviceIntervalStep,
            onSaved: custom ? service.setBatteryPollingIntervalSeconds : null,
          ),
          const SizedBox(height: 12),
          PowerSavingIntervalCard(
            key: const ValueKey('power-saving-gps'),
            title: l10n.powerSaving_gpsInterval,
            description: l10n.powerSaving_gpsDescription,
            value: effective.gpsIntervalSeconds,
            minimum: PowerSavingOptions.minGpsInterval,
            maximum: PowerSavingOptions.maxGpsInterval,
            step: PowerSavingOptions.deviceIntervalStep,
            onSaved: custom ? service.setGpsPollingIntervalSeconds : null,
          ),
          const SizedBox(height: 12),
          MeshCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              key: const ValueKey('power-saving-image-cleanup'),
              title: Text(l10n.powerSaving_pauseIdleImageCleanup),
              subtitle: Text(l10n.powerSaving_pauseIdleImageCleanupDescription),
              value: effective.pauseIdleImageCleanup,
              onChanged: custom
                  ? (value) => unawaited(service.setPauseIdleImageCleanup(value))
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          MeshCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              key: const ValueKey('power-saving-gifs'),
              title: Text(l10n.powerSaving_pauseHiddenGifs),
              subtitle: Text(l10n.powerSaving_pauseHiddenGifsDescription),
              value: effective.pauseHiddenGifs,
              onChanged: custom
                  ? (value) => unawaited(service.setPauseHiddenGifs(value))
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          PowerSavingIntervalCard(
            key: const ValueKey('power-saving-ui-notifications'),
            title: l10n.powerSaving_uiNotificationInterval,
            description: l10n.powerSaving_uiNotificationDescription,
            value: effective.uiNotificationIntervalMilliseconds,
            milliseconds: true,
            minimum: PowerSavingOptions.minUiNotificationInterval,
            maximum: PowerSavingOptions.maxUiNotificationInterval,
            step: PowerSavingOptions.uiNotificationIntervalStep,
            onSaved: custom ? service.setUiNotificationIntervalMilliseconds : null,
          ),
          const SizedBox(height: 12),
          MeshCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              key: const ValueKey('power-saving-log-descriptions'),
              title: Text(l10n.powerSaving_deferBleLogDescriptions),
              subtitle: Text(l10n.powerSaving_deferBleLogDescriptionsDescription),
              value: effective.deferBleLogDescriptions,
              onChanged: custom
                  ? (value) => unawaited(service.setDeferBleLogDescriptions(value))
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          MeshCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              key: const ValueKey('power-saving-ble-plugin-logs'),
              title: Text(l10n.powerSaving_reduceBlePluginLogs),
              subtitle: Text(l10n.powerSaving_reduceBlePluginLogsDescription),
              value: effective.reduceBlePluginLogs,
              onChanged: custom
                  ? (value) => unawaited(service.setReduceBlePluginLogs(value))
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          Text(custom
              ? l10n.powerSaving_customDescription
              : l10n.powerSaving_presetDescription),
        ],
      ),
    );
  }
}
