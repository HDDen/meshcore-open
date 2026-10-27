import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/ble_power_options.dart';
import 'mesh_ui.dart';

class BleConnectionPriorityCard extends StatelessWidget {
  const BleConnectionPriorityCard({
    super.key,
    required this.mode,
    this.onChanged,
  });

  final BleConnectionPriorityMode mode;
  final ValueChanged<BleConnectionPriorityMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MeshCard(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.powerSaving_blePriorityTitle),
        DropdownButton<BleConnectionPriorityMode>(
          key: const ValueKey('power-saving-ble-priority'),
          value: mode,
          isExpanded: true,
          onChanged: onChanged == null ? null : (value) {
            if (value != null) onChanged!(value);
          },
          items: [
            for (final value in BleConnectionPriorityMode.values)
              DropdownMenuItem(value: value, child: Text(switch (value) {
                BleConnectionPriorityMode.original => l10n.powerSaving_bleOriginal,
                BleConnectionPriorityMode.balanced => l10n.powerSaving_bleBalanced,
                BleConnectionPriorityMode.high => l10n.powerSaving_bleHigh,
                BleConnectionPriorityMode.lowPower => l10n.powerSaving_bleLowPower,
              })),
          ],
        ),
        Text(l10n.powerSaving_blePriorityDescription),
      ],
    ));
  }
}
