import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/legacy_offline_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('legacy offline history is unavailable by default', () async {
    final access = LegacyOfflineAccess.instance;
    expect(access.enabled, isFalse);
    final connector = MeshCoreConnector();
    addTearDown(connector.dispose);
    expect(await connector.enterOfflineHistory(shared: true), isFalse);
    expect(connector.isLegacyOfflineSession, isFalse);
  });
}
