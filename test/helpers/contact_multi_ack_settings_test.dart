import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/contact_multi_ack_settings.dart';

class _Connector extends MeshCoreConnector {
  int base = 0;
  int location = 0;
  int environment = 0;
  int advert = 0;
  int refreshes = 0;
  final saved = <List<int>>[];
  @override
  int get telemetryModeBase => base;
  @override
  int get telemetryModeLoc => location;
  @override
  int get telemetryModeEnv => environment;
  @override
  int get advertLocationPolicy => advert;
  @override
  Future<void> setTelemetryModeBase(int base, int location, int env, int advert, int multiAcks) async {
    saved.add([base, location, env, advert, multiAcks]);
  }
  @override
  Future<void> refreshDeviceInfo() async { refreshes++; }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('saving changed Multi ACK retains current privacy values', () async {
    final connector = _Connector();
    addTearDown(connector.dispose);
    // Privacy may have changed since the contacts dialog was opened.
    connector.base = 2;
    connector.location = 1;
    connector.environment = 2;
    connector.advert = 1;
    await saveContactMultiAcks(connector, initialValue: 0, selectedValue: 1);
    expect(connector.saved, [[2, 1, 2, 1, 1]]);
    expect(connector.refreshes, 1);
    await saveContactMultiAcks(connector, initialValue: 1, selectedValue: 0);
    expect(connector.saved.last, [2, 1, 2, 1, 0]);
  });

  test('unchanged values, including firmware mode 2, send no shared-parameter command', () async {
    final connector = _Connector();
    addTearDown(connector.dispose);
    for (final value in [0, 1, 2]) {
      await saveContactMultiAcks(connector, initialValue: value, selectedValue: value);
    }
    expect(connector.saved, isEmpty);
    expect(connector.refreshes, 0);
  });
}
