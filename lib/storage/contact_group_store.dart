import 'dart:convert';
import '../models/contact_group.dart';
import '../utils/app_logger.dart';
import 'message_history_storage.dart';
import 'node_state.dart';
import 'prefs_manager.dart';

/// Contact groups per node: a `node_state` row named `contact_groups`, or
/// the preference key `contact_groups<node>` where there is no database.
class ContactGroupStore {
  static const String _keyPrefix = 'contact_groups';

  String publicKeyHex = '';
  set setPublicKeyHex(String value) =>
      publicKeyHex = value.length > 10 ? value.substring(0, 10) : '';

  String get keyFor => '$_keyPrefix$publicKeyHex';

  Future<List<ContactGroup>> loadGroups() async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot load contact groups.');
      return [];
    }
    String? jsonString = await NodeState.read(
      nodeKey: publicKeyHex,
      name: _keyPrefix,
      preferenceKey: keyFor,
    );
    if (jsonString == null || jsonString.isEmpty) {
      jsonString = await NodeState.takeOverLegacyPreference(
        legacyKey: _keyPrefix,
        preferenceKey: keyFor,
      );
    }
    return _decodeGroups(jsonString);
  }

  Future<({String? value, List<ContactGroup> groups})> snapshotForBackup() async {
    final value = await _readBackupValue();
    return (value: value, groups: _decodeGroups(value, strict: true));
  }

  Future<String?> _readBackupValue() {
    if (!NodeState.usesDatabase) return Future.value(_readBackupPreference());
    return NodeState.read(
      nodeKey: publicKeyHex,
      name: _keyPrefix,
      preferenceKey: keyFor,
    );
  }

  String? _readBackupPreference() {
    final prefs = PrefsManager.instance;
    final value = prefs.getString(keyFor);
    return value == null || value.isEmpty ? prefs.getString(_keyPrefix) : value;
  }

  Future<bool> restoreBackupGroups({
    required String? expected,
    required List<ContactGroup> groups,
    required bool Function() stillCurrent,
  }) async {
    final value = jsonEncode(groups.map((group) => group.toJson()).toList());
    if (NodeState.usesDatabase) {
      return MessageHistoryStorage.instance.replaceNodeStateIfUnchanged(
        nodeKey: publicKeyHex,
        name: _keyPrefix,
        expected: expected,
        value: value,
        stillCurrent: stillCurrent,
      );
    }
    if (_readBackupPreference() != expected || !stillCurrent()) return false;
    return PrefsManager.instance.setString(keyFor, value);
  }

  List<ContactGroup> _decodeGroups(String? jsonString, {bool strict = false}) {
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is List) {
        if (strict && decoded.any((row) => row is! Map<String, dynamic>)) {
          throw const FormatException('Invalid saved contact groups');
        }
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(ContactGroup.fromJson)
            .toList();
      }
    } catch (_) {
      if (strict) rethrow;
    }
    if (strict) throw const FormatException('Invalid saved contact groups');
    return [];
  }

  Future<void> saveGroups(List<ContactGroup> groups) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot save contact groups.');
      return;
    }
    final encoded = jsonEncode(groups.map((group) => group.toJson()).toList());
    await NodeState.write(
      nodeKey: publicKeyHex,
      name: _keyPrefix,
      preferenceKey: keyFor,
      value: encoded,
    );
  }
}
