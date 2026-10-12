import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/network_map/network_map_upload_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  test('off by default and never listens without a connected radio', () async {
    final connector = MeshCoreConnector();
    final settings = AppSettingsService();
    await settings.loadSettings();
    var requests = 0;
    final service = NetworkMapUploadService(
      connector: connector,
      settings: settings,
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 202);
      }),
    );
    addTearDown(() {
      service.dispose();
      connector.dispose();
    });

    expect(service.enabled, isFalse);
    expect(service.isActive, isFalse);

    await service.setEnabled(true);
    expect(service.enabled, isTrue);
    expect(settings.settings.networkMapUploadEnabled, isTrue);
    expect(service.isActive, isFalse);
    expect(service.lastUploadAt, isNull);
    expect(service.packetsSentToday, 0);
    expect(requests, 0);
  });
}
