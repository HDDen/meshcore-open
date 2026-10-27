import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'mesh_ui.dart';

class DeliveryObservationPowerCard extends StatelessWidget {
  const DeliveryObservationPowerCard({super.key, required this.enabled, this.onChanged});

  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MeshCard(
      padding: EdgeInsets.zero,
      child: SwitchListTile(
        key: const ValueKey('power-saving-delivery-observation-writes'),
        title: Text(l10n.powerSaving_reduceDeliveryObservationWrites),
        subtitle: Text(l10n.powerSaving_reduceDeliveryObservationWritesDescription),
        value: enabled,
        onChanged: onChanged,
      ),
    );
  }
}
