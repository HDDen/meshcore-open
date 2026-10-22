import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/power_saving_settings.dart';
import '../screens/power_saving_screen.dart';
import '../services/app_settings_service.dart';

class PowerSavingSettingsTile extends StatelessWidget {
  const PowerSavingSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.select<AppSettingsService, PowerSavingProfile>(
      (service) => service.settings.powerSaving.profile,
    );
    return ListTile(
      leading: const Icon(Icons.energy_savings_leaf_outlined),
      title: Text(context.l10n.powerSaving_title),
      subtitle: Text(powerSavingProfileLabel(context.l10n, profile)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const PowerSavingScreen()),
      ),
    );
  }
}
