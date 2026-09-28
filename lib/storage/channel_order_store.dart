import 'dart:convert';
import '../utils/app_logger.dart';
import 'node_state.dart';

/// The user's channel order per node: a `node_state` row named
/// `channel_order`, or the preference key `channel_order_<node>` where there
/// is no database.
class ChannelOrderStore {
  static const String _keyPrefix = 'channel_order_';
  static const String _stateName = 'channel_order';

  String publicKeyHex = '';
  set setPublicKeyHex(String value) =>
      publicKeyHex = value.length > 10 ? value.substring(0, 10) : '';

  String get keyFor => '$_keyPrefix$publicKeyHex';

  Future<void> saveChannelOrder(List<int> order) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot save channel order.');
      return;
    }
    await NodeState.write(
      nodeKey: publicKeyHex,
      name: _stateName,
      preferenceKey: keyFor,
      value: jsonEncode(order),
    );
  }

  Future<List<int>> loadChannelOrder({bool allowLegacyMigration = true}) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot load channel order.');
      return [];
    }
    String? jsonString = await NodeState.read(
      nodeKey: publicKeyHex,
      name: _stateName,
      preferenceKey: keyFor,
    );
    if ((jsonString == null || jsonString.isEmpty) && allowLegacyMigration) {
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
            .map((value) => value is int ? value : int.tryParse('$value'))
            .whereType<int>()
            .toList();
      }
    } catch (_) {
      // fall through to legacy parse
    }
    return jsonString
        .split(',')
        .map((value) => int.tryParse(value))
        .whereType<int>()
        .toList();
  }
}
