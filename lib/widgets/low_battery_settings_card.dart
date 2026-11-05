import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/low_battery_alert_settings.dart';
import '../services/app_settings_service.dart';
import 'mesh_ui.dart';

class LowBatterySettingsCard extends StatefulWidget {
  const LowBatterySettingsCard({super.key});

  @override
  State<LowBatterySettingsCard> createState() => _LowBatterySettingsCardState();
}

class _LowBatterySettingsCardState extends State<LowBatterySettingsCard> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<AppSettingsService>();
    final options = service.settings.lowBatteryAlerts;
    return MeshCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.battery_alert_outlined),
            title: Text(context.l10n.settings_lowBatteryAlerts),
            value: options.enabled,
            onChanged: service.setLowBatteryAlertsEnabled,
          ),
          if (options.enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                scrollbarOrientation: ScrollbarOrientation.bottom,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      for (final threshold in LowBatteryAlertSettings.supportedThresholds)
                        MergeSemantics(
                          child: InkWell(
                            onTap: () => service.setLowBatteryAlertThreshold(
                              threshold, !options.thresholds.contains(threshold),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Checkbox(
                                  value: options.thresholds.contains(threshold),
                                  onChanged: (checked) => service.setLowBatteryAlertThreshold(
                                    threshold, checked ?? false,
                                  ),
                                ),
                                Text('$threshold%'),
                                const SizedBox(width: 12),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
