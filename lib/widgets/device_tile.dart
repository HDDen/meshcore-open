import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../l10n/l10n.dart';
import 'signal_ui.dart';

/// A reusable tile widget for displaying a MeshCore device in a list
class DeviceTile extends StatelessWidget {
  final ScanResult scanResult;
  final VoidCallback? onTap;
  final bool isConnecting;

  const DeviceTile({
    super.key,
    required this.scanResult,
    required this.onTap,
    this.isConnecting = false,
  });

  @override
  Widget build(BuildContext context) {
    final device = scanResult.device;
    final rssi = scanResult.rssi;
    final name = device.platformName.isNotEmpty
        ? device.platformName
        : scanResult.advertisementData.advName;

    return ListTile(
      enabled: onTap != null || isConnecting,
      leading: _buildSignalIcon(rssi),
      title: Text(
        name.isNotEmpty ? name : context.l10n.common_unknownDevice,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(device.remoteId.toString()),
      trailing: isConnecting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: onTap,
    );
  }

  Widget _buildSignalIcon(int rssi) {
    final tier = rssi >= -60
        ? 0
        : rssi >= -70
        ? 1
        : rssi >= -80
        ? 2
        : rssi >= -90
        ? 3
        : 4;
    final signalUi = signalUiForStrengthTier(tier);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(signalUi.icon, color: signalUi.color),
        Text(
          '$rssi dBm',
          style: TextStyle(fontSize: 10, color: signalUi.color),
        ),
      ],
    );
  }
}
