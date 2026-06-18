import 'package:flutter/foundation.dart';

import 'prefs_manager.dart';

class ConnectionTransportPreferenceStore {
  static const String bluetooth = 'bluetooth';
  static const String tcp = 'tcp';
  static const String usb = 'usb';
  static const String _key = 'last_connection_transport';
  static String? _lastSavedTransport;

  String get lastTransport =>
      _lastSavedTransport ??
      PrefsManager.instance.getString(_key) ??
      bluetooth;

  Future<void> save(String transport) async {
    if (transport != bluetooth && transport != tcp && transport != usb) {
      return;
    }
    _lastSavedTransport = transport;
    await PrefsManager.instance.setString(_key, transport);
  }

  @visibleForTesting
  static void resetCache() {
    _lastSavedTransport = null;
  }
}
