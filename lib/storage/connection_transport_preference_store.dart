import 'package:flutter/foundation.dart';

import 'prefs_manager.dart';

class ConnectionTransportPreferenceStore {
  static const String bluetooth = 'bluetooth';
  static const String tcp = 'tcp';
  static const String usb = 'usb';
  static const String _key = 'last_connection_transport';
  static const String _autoconnectKeyPrefix = 'connection_autoconnect_';
  static String? _lastSavedTransport;
  static final Map<String, bool> _autoconnectCache = {};

  String get lastTransport =>
      _lastSavedTransport ?? PrefsManager.instance.getString(_key) ?? bluetooth;

  Future<void> save(String transport) async {
    if (transport != bluetooth && transport != tcp && transport != usb) {
      return;
    }
    _lastSavedTransport = transport;
    await PrefsManager.instance.setString(_key, transport);
  }

  bool isAutoconnectEnabled(String transport) {
    if (transport != bluetooth && transport != tcp && transport != usb) {
      return false;
    }
    return _autoconnectCache[transport] ??
        PrefsManager.instance.getBool('$_autoconnectKeyPrefix$transport') ??
        false;
  }

  Future<void> setAutoconnectEnabled(String transport, bool enabled) async {
    if (transport != bluetooth && transport != tcp && transport != usb) {
      return;
    }
    _autoconnectCache[transport] = enabled;
    await PrefsManager.instance.setBool(
      '$_autoconnectKeyPrefix$transport',
      enabled,
    );
  }

  @visibleForTesting
  static void resetCache() {
    _lastSavedTransport = null;
    _autoconnectCache.clear();
  }
}
