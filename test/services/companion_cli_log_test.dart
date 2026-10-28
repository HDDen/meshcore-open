import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/ble_debug_log_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('CLI raw requests and replies retain metadata but never export console payload', () {
    final log = BleDebugLogService();
    log.logFrame(Uint8List.fromList([66, ...'set wifi.pwd SYNTHETIC_ONLY'.codeUnits]), outgoing: true);
    log.logFrame(Uint8List.fromList([29, ...'SYNTHETIC_REPLY'.codeUnits]), outgoing: false);
    expect(log.entries.map((entry) => entry.payload.toList()), [[66], [29]]);
    log.dispose();
  });
}
