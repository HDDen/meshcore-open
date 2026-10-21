import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/app_settings.dart';

/// Fork-specific nearby-repeater controls, separate from the route hop target.
class ChannelResendRepeaterSettings extends StatelessWidget {
  final AppSettings settings;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<int> onCountChanged;

  const ChannelResendRepeaterSettings({
    super.key,
    required this.settings,
    required this.onEnabledChanged,
    required this.onCountChanged,
  });

  @override
  Widget build(BuildContext context) {
    final count = settings.channelMinHopsRepeaterCount.clamp(2, 10).toInt();
    return Column(
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          secondary: const Icon(Icons.hub_outlined, size: 20),
          title: Text(context.l10n.appSettings_channelMinHopsCountRepeaters),
          subtitle: Text(
            context.l10n.appSettings_channelMinHopsCountRepeatersSubtitle(count),
          ),
          value: settings.channelMinHopsCountRepeaters,
          onChanged: onEnabledChanged,
        ),
        if (settings.channelMinHopsCountRepeaters)
          ListTile(
            title: Text(
              context.l10n.appSettings_channelMinHopsRepeaterCount(count),
            ),
            subtitle: Slider(
              value: count.toDouble(),
              min: 2,
              max: 10,
              divisions: 8,
              label: count.toString(),
              onChanged: (value) => onCountChanged(value.round()),
            ),
          ),
      ],
    );
  }
}
