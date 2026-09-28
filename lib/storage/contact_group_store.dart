import 'dart:convert';
import '../models/contact_group.dart';
import '../utils/app_logger.dart';
import 'node_state.dart';

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
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(ContactGroup.fromJson)
            .toList();
      }
    } catch (_) {
      // Return empty list on parse errors.
    }
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
