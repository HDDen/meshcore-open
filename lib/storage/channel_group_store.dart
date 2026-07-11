import 'dart:convert';

import '../models/channel_group.dart';
import '../utils/app_logger.dart';
import 'prefs_manager.dart';

class ChannelGroupStore {
  static const String _keyPrefix = 'channel_groups';
  static const String _expandedKeyPrefix = 'channel_groups_expanded';
  static const String _screenOrderKeyPrefix = 'channel_screen_order';

  String publicKeyHex = '';
  set setPublicKeyHex(String value) =>
      publicKeyHex = value.length > 10 ? value.substring(0, 10) : '';

  String get keyFor => '$_keyPrefix$publicKeyHex';
  String get expandedKeyFor => '$_expandedKeyPrefix$publicKeyHex';
  String get screenOrderKeyFor => '$_screenOrderKeyPrefix$publicKeyHex';

  Future<List<ChannelGroup>> loadGroups() async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot load channel groups.');
      return [];
    }

    final prefs = PrefsManager.instance;
    final jsonString = prefs.getString(keyFor);
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(ChannelGroup.fromJson)
            .where((group) => group.name.trim().isNotEmpty)
            .toList();
      }
    } catch (_) {
      // Keep the channels screen usable even if old local group JSON is bad.
    }
    return [];
  }

  Future<void> saveGroups(List<ChannelGroup> groups) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot save channel groups.');
      return;
    }

    final prefs = PrefsManager.instance;
    final encoded = jsonEncode(groups.map((group) => group.toJson()).toList());
    await prefs.setString(keyFor, encoded);
  }

  Future<Set<String>> loadExpandedGroupNames() async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load expanded channel groups.',
      );
      return <String>{};
    }

    final prefs = PrefsManager.instance;
    final jsonString = prefs.getString(expandedKeyFor);
    if (jsonString == null || jsonString.isEmpty) {
      return <String>{};
    }

    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is List) {
        return decoded
            .map((value) => value.toString().trim())
            .where((name) => name.isNotEmpty)
            .toSet();
      }
    } catch (_) {
      // Bad UI state should not prevent groups from loading.
    }
    return <String>{};
  }

  Future<void> saveExpandedGroupNames(Set<String> names) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot save expanded channel groups.',
      );
      return;
    }

    final prefs = PrefsManager.instance;
    await prefs.setString(expandedKeyFor, jsonEncode(names.toList()));
  }

  Future<List<String>> loadScreenOrder() async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load channel screen order.',
      );
      return [];
    }

    final prefs = PrefsManager.instance;
    final jsonString = prefs.getString(screenOrderKeyFor);
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is List) {
        return decoded
            .map((value) => value.toString().trim())
            .where((name) => name.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // Bad UI order should not prevent the channels screen from loading.
    }
    return [];
  }

  Future<void> saveScreenOrder(List<String> order) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot save channel screen order.',
      );
      return;
    }

    final prefs = PrefsManager.instance;
    await prefs.setString(screenOrderKeyFor, jsonEncode(order));
  }
}
