import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/ble_power_options.dart';

/// Каждый новый сеанс получает свой запрос; ошибки не управляют транспортом.
Future<void> applyBleConnectionPriority({
  required BleConnectionPriorityMode mode,
  required bool isAndroid,
  required bool Function() isCurrentSession,
  required Future<void> Function(ConnectionPriority) request,
  void Function(String)? onInfo,
  void Function(String)? onWarning,
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (!isAndroid || mode == BleConnectionPriorityMode.original ||
      !isCurrentSession()) {
    return;
  }
  final priority = switch (mode) {
    BleConnectionPriorityMode.balanced => ConnectionPriority.balanced,
    BleConnectionPriorityMode.high => ConnectionPriority.high,
    BleConnectionPriorityMode.lowPower => ConnectionPriority.lowPower,
    BleConnectionPriorityMode.original => throw StateError('No priority override'),
  };
  try {
    await request(priority).timeout(timeout);
    if (isCurrentSession()) {
      onInfo?.call('BLE priority request sent: ${mode.name}; '
          'negotiated parameters are not reported by this API');
    }
  } catch (error) {
    if (isCurrentSession()) {
      onWarning?.call('BLE priority request ${mode.name} failed '
          '(${error.runtimeType}); keeping the connection');
    }
  }
}
