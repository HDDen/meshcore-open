import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/map_location_helper.dart';
import 'package:meshcore_open/services/wardrive_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Connector extends MeshCoreConnector {
  ({double latitude, double longitude})? position;
  int reads = 0;

  @override
  Future<({double latitude, double longitude})?> refreshSelfLocation({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    reads++;
    return position;
  }
}

// This helper only needs requestPhoneLocation; do not start the real
// service's asynchronous SQLite loading in a source-selection unit test.
class _Wardrive implements WardriveService {
  ({double latitude, double longitude})? position;
  int reads = 0;

  @override
  Future<({double latitude, double longitude})?> requestPhoneLocation() async {
    reads++;
    return position;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  for (final scenario in ['phone', 'node', 'none', 'disabled']) {
    test('U06b1 location priority: $scenario', () async {
      final connector = _Connector();
      final wardrive = _Wardrive();
      try {
        if (scenario != 'none') {
          connector.position = (latitude: 54.5, longitude: 36.5);
        }
        if (scenario == 'phone' || scenario == 'disabled') {
          wardrive.position = (latitude: 55.7, longitude: 37.6);
        }
        final phoneFixes = <LatLng>[];
        final result = await MapLocationHelper.resolve(
          enabled: scenario != 'disabled',
          wardrive: wardrive,
          connector: connector,
          onPhoneLocation: phoneFixes.add,
        );
        if (scenario == 'phone') {
          expect(result, const LatLng(55.7, 37.6));
          expect(phoneFixes, [const LatLng(55.7, 37.6)]);
          expect(connector.reads, 0);
        } else {
          expect(phoneFixes, isEmpty);
          expect(result, scenario == 'node' ? const LatLng(54.5, 36.5) : null);
          expect(connector.reads, scenario == 'disabled' ? 0 : 1);
        }
        expect(wardrive.reads, scenario == 'disabled' ? 0 : 1);
      } finally {
        connector.dispose();
      }
    });
  }
}
