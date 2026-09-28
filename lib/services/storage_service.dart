import 'dart:convert';
import '../models/delivery_observation.dart';
import '../models/path_history.dart';
import '../storage/message_history_storage.dart';
import '../storage/node_state.dart';
import '../storage/prefs_manager.dart';
import '../utils/app_logger.dart';

/// Path histories, delivery observations, repeater passwords and the other
/// app-wide maps. In the database where there is one (`contact_path_history`
/// and `delivery_observations`, the maps as `node_state` rows under the
/// empty node key); in preferences under the keys they always had on the
/// web and in a process that never opened the database.
class StorageService {
  static const String _pathHistoryPrefix = 'path_history_';
  static const String _pendingMessagesKey = 'pending_messages';
  static const String _repeaterPasswordsKey = 'repeater_passwords';
  static const String _repeaterAutoClockSyncAfterLoginKey =
      'repeater_auto_clock_sync_after_login';
  static const String _deliveryObservationsKey = 'delivery_observations';

  String _publicKeyHex = '';
  set setPublicKeyHex(String value) =>
      _publicKeyHex = value.length > 10 ? value.substring(0, 10) : '';

  MessageHistoryStorage get _storage => MessageHistoryStorage.instance;

  String _pathHistoryKey(String contactPubKeyHex) => _publicKeyHex.isEmpty
      ? '$_pathHistoryPrefix$contactPubKeyHex'
      : '$_pathHistoryPrefix${_publicKeyHex}_$contactPubKeyHex';

  Future<String?> _readAppValue(String key) =>
      NodeState.read(nodeKey: '', name: key, preferenceKey: key);

  Future<void> _writeAppValue(String key, String value) =>
      NodeState.write(nodeKey: '', name: key, preferenceKey: key, value: value);

  Future<void> _removeAppValue(String key) =>
      NodeState.remove(nodeKey: '', name: key, preferenceKey: key);

  Future<Map<String, bool>> _loadRepeaterAutoClockSyncAfterLogin() async {
    final jsonStr = await _readAppValue(_repeaterAutoClockSyncAfterLoginKey);
    if (jsonStr == null) return {};

    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return json.map((key, value) => MapEntry(key, value == true));
    } catch (e) {
      return {};
    }
  }

  Future<bool> getRepeaterAutoClockSyncAfterLoginEnabled(
    String repeaterPubKeyHex,
  ) async {
    final settings = await _loadRepeaterAutoClockSyncAfterLogin();
    return settings[repeaterPubKeyHex] ?? false;
  }

  Future<void> setRepeaterAutoClockSyncAfterLoginEnabled(
    String repeaterPubKeyHex,
    bool enabled,
  ) async {
    final settings = await _loadRepeaterAutoClockSyncAfterLogin();
    settings[repeaterPubKeyHex] = enabled;
    await _writeAppValue(
      _repeaterAutoClockSyncAfterLoginKey,
      jsonEncode(settings),
    );
  }

  /// Stores the history under this node, or as the shared history of the
  /// contact when no node is set, which every node reads until it has one
  /// of its own.
  Future<void> savePathHistory(
    String contactPubKeyHex,
    ContactPathHistory history,
  ) async {
    final jsonStr = jsonEncode(history.toJson());
    if (_storage.hasDatabase) {
      await _storage.savePathHistoryJson(
        nodeKey: _publicKeyHex,
        contactKey: contactPubKeyHex,
        historyJson: jsonStr,
      );
      return;
    }
    final prefs = PrefsManager.instance;
    await prefs.setString(_pathHistoryKey(contactPubKeyHex), jsonStr);
  }

  Future<ContactPathHistory?> loadPathHistory(String contactPubKeyHex) async {
    final String? jsonStr;
    if (_storage.hasDatabase) {
      jsonStr = await _storage.loadPathHistoryJson(
        _publicKeyHex,
        contactPubKeyHex,
      );
    } else {
      final prefs = PrefsManager.instance;
      // Fall back to the pre-scoping key so learned routes survive the
      // upgrade.
      jsonStr =
          prefs.getString(_pathHistoryKey(contactPubKeyHex)) ??
          prefs.getString('$_pathHistoryPrefix$contactPubKeyHex');
    }

    if (jsonStr == null) return null;

    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return ContactPathHistory.fromJson(contactPubKeyHex, json);
    } catch (e) {
      return null;
    }
  }

  Future<void> clearPathHistory(String contactPubKeyHex) async {
    if (_storage.hasDatabase) {
      await _storage.deletePathHistory(_publicKeyHex, contactPubKeyHex);
      return;
    }
    final prefs = PrefsManager.instance;
    for (final key in {
      _pathHistoryKey(contactPubKeyHex),
      '$_pathHistoryPrefix$contactPubKeyHex',
    }) {
      if (prefs.containsKey(key)) await prefs.remove(key);
    }
  }

  /// Removes every node's histories, the shared ones included.
  Future<void> clearAllPathHistories() async {
    if (_storage.hasDatabase) {
      await _storage.clearPathHistories();
      return;
    }
    final prefs = PrefsManager.instance;
    final keys = prefs.getKeys();
    final pathHistoryKeys = keys.where(
      (key) => key.startsWith(_pathHistoryPrefix),
    );

    for (final key in pathHistoryKeys) {
      await prefs.remove(key);
    }
  }

  Future<Map<String, String>> loadPendingMessages() async {
    final jsonStr = await _readAppValue(_pendingMessagesKey);
    if (jsonStr == null) return {};

    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return json.map((key, value) => MapEntry(key, value as String));
    } catch (e) {
      return {};
    }
  }

  Future<void> savePendingMessages(Map<String, String> pending) async {
    await _writeAppValue(_pendingMessagesKey, jsonEncode(pending));
  }

  Future<void> clearPendingMessages() async {
    await _removeAppValue(_pendingMessagesKey);
  }

  /// Save a repeater password by public key hex
  Future<void> saveRepeaterPassword(
    String repeaterPubKeyHex,
    String password,
  ) async {
    final passwords = await loadRepeaterPasswords();
    passwords[repeaterPubKeyHex] = password;
    await _writeAppValue(_repeaterPasswordsKey, jsonEncode(passwords));
  }

  /// Load all saved repeater passwords (map of pubKeyHex -> password)
  Future<Map<String, String>> loadRepeaterPasswords() async {
    final jsonStr = await _readAppValue(_repeaterPasswordsKey);
    if (jsonStr == null) return {};

    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return json.map((key, value) => MapEntry(key, value as String));
    } catch (e) {
      return {};
    }
  }

  /// Get a specific repeater's saved password
  Future<String?> getRepeaterPassword(String repeaterPubKeyHex) async {
    final passwords = await loadRepeaterPasswords();
    return passwords[repeaterPubKeyHex];
  }

  /// Remove a saved repeater password
  Future<void> removeRepeaterPassword(String repeaterPubKeyHex) async {
    final passwords = await loadRepeaterPasswords();
    passwords.remove(repeaterPubKeyHex);
    await _writeAppValue(_repeaterPasswordsKey, jsonEncode(passwords));
  }

  /// Clear all saved repeater passwords
  Future<void> clearAllRepeaterPasswords() async {
    await _removeAppValue(_repeaterPasswordsKey);
  }

  /// Stores the whole list; the service hands over its capped list after
  /// each change, two seconds apart at most.
  Future<void> saveDeliveryObservations(
    List<DeliveryObservation> observations,
  ) async {
    if (_storage.hasDatabase) {
      await _storage.replaceDeliveryObservations([
        for (final observation in observations) jsonEncode(observation.toJson()),
      ]);
      return;
    }
    final prefs = PrefsManager.instance;
    final jsonStr = jsonEncode(observations.map((o) => o.toJson()).toList());
    await prefs.setString(_deliveryObservationsKey, jsonStr);
  }

  Future<List<DeliveryObservation>> loadDeliveryObservations() async {
    final List<dynamic> list;
    if (_storage.hasDatabase) {
      list = await _storage.loadDeliveryObservations();
    } else {
      final jsonStr = PrefsManager.instance.getString(_deliveryObservationsKey);
      if (jsonStr == null) return [];
      try {
        list = jsonDecode(jsonStr) as List<dynamic>;
      } catch (e) {
        appLogger.warn('Stored delivery observations are unreadable: $e');
        return [];
      }
    }
    final observations = <DeliveryObservation>[];
    for (final e in list) {
      try {
        final json = e is String ? jsonDecode(e) : e;
        observations.add(
          DeliveryObservation.fromJson(json as Map<String, dynamic>),
        );
      } catch (err) {
        appLogger.warn('Skipping malformed delivery observation: $err');
      }
    }
    return observations;
  }

  Future<void> clearDeliveryObservations() async {
    if (_storage.hasDatabase) {
      await _storage.replaceDeliveryObservations(const []);
      return;
    }
    final prefs = PrefsManager.instance;
    if (prefs.containsKey(_deliveryObservationsKey)) {
      await prefs.remove(_deliveryObservationsKey);
    }
  }
}
