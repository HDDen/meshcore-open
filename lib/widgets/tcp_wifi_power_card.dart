import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'mesh_ui.dart';

class TcpWifiPowerCard extends StatelessWidget {
  const TcpWifiPowerCard({super.key, required this.releaseAllowed, this.onChanged});

  final bool releaseAllowed;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MeshCard(
      padding: EdgeInsets.zero,
      child: SwitchListTile(
        key: const ValueKey('power-saving-tcp-wifi-lock'),
        title: Text(l10n.powerSaving_releaseTcpWifiLock),
        subtitle: Text(l10n.powerSaving_releaseTcpWifiLockDescription),
        value: releaseAllowed,
        onChanged: onChanged,
      ),
    );
  }
}
