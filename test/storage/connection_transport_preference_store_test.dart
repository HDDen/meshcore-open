import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/storage/connection_transport_preference_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'last_connection_transport':
          ConnectionTransportPreferenceStore.bluetooth,
    });
    PrefsManager.reset();
    ConnectionTransportPreferenceStore.resetCache();
    await PrefsManager.initialize();
  });

  tearDown(() {
    ConnectionTransportPreferenceStore.resetCache();
    PrefsManager.reset();
  });

  test('new transport is readable before its async save completes', () async {
    final store = ConnectionTransportPreferenceStore();

    final save = store.save(ConnectionTransportPreferenceStore.tcp);

    expect(store.lastTransport, ConnectionTransportPreferenceStore.tcp);
    await save;
  });
}
