import 'prefs_manager.dart';

class ConnectionTransportPreferenceStore {
  static const String bluetooth = 'bluetooth';
  static const String tcp = 'tcp';
  static const String usb = 'usb';
  static const String _key = 'last_connection_transport';

  String get lastTransport =>
      PrefsManager.instance.getString(_key) ?? bluetooth;

  Future<void> save(String transport) async {
    if (transport != bluetooth && transport != tcp && transport != usb) {
      return;
    }
    await PrefsManager.instance.setString(_key, transport);
  }
}
