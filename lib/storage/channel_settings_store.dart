import '../models/app_settings.dart';
import '../utils/app_logger.dart';
import 'channel_name_keyed_store.dart';
import 'prefs_manager.dart';

class ChannelSettingsStore with ChannelNameKeyedStore {
  static const String _keyPrefix = 'channel_smaz_';
  static const String _mcmpKeyPrefix = 'channel_mcmp_';
  static const String _mcmpVersionKeyPrefix = 'channel_mcmp_version_';
  static const String _mcmpUseSignKeyPrefix = 'channel_mcmp_use_sign_';
  static const String _cyr2latKeyPrefix = 'channel_cyr2lat_';
  static const String _sendingDelayKeyPrefix = 'channel_sending_delay_';
  static const String _quickAnswersKeyPrefix = 'channel_quick_answer_ids_';
  static const String _widgetColorKeyPrefix = 'channel_widget_color_';
  static const String _widgetTextColorKeyPrefix = 'channel_widget_text_color_';

  String publicKeyHex = '';
  set setPublicKeyHex(String value) =>
      publicKeyHex = value.length >= 10 ? value.substring(0, 10) : '';

  String get keyFor => '$_keyPrefix$publicKeyHex';
  String get keyForMcmp => '$_mcmpKeyPrefix$publicKeyHex';
  String get keyForMcmpVersion => '$_mcmpVersionKeyPrefix$publicKeyHex';
  String get keyForMcmpUseSign => '$_mcmpUseSignKeyPrefix$publicKeyHex';
  String get keyForCyr2Lat => '$_cyr2latKeyPrefix$publicKeyHex';
  String get keyForSendingDelay => '$_sendingDelayKeyPrefix$publicKeyHex';
  String get keyForQuickAnswerIds => '$_quickAnswersKeyPrefix$publicKeyHex';
  String get keyForWidgetColor => '$_widgetColorKeyPrefix$publicKeyHex';
  String get keyForWidgetTextColor => '$_widgetTextColorKeyPrefix$publicKeyHex';

  Future<T?> _loadValue<T>({
    required String nameKeyPrefix,
    required int channelIndex,
    required T? Function(String key) read,
    required Future<bool> Function(String key, T value) write,
    List<String> additionalLegacyKeys = const [],
  }) async {
    if (publicKeyHex.isEmpty) return null;
    final nameKey = channelStorageKey(nameKeyPrefix, channelIndex);
    if (nameKey == null) return null;
    final current = read(nameKey);
    if (current != null) return current;
    if (!allowsLegacyIndexMigration) return null;

    for (final legacyKey in <String>[
      '$nameKeyPrefix$channelIndex',
      ...additionalLegacyKeys,
    ]) {
      final legacy = read(legacyKey);
      if (legacy == null) continue;
      await write(nameKey, legacy);
      await PrefsManager.instance.remove(legacyKey);
      appLogger.info('Migrated channel setting to name-keyed storage $nameKey');
      return legacy;
    }
    return null;
  }

  Future<void> _saveValue<T>({
    required String nameKeyPrefix,
    required int channelIndex,
    required T? value,
    required Future<bool> Function(String key, T value) write,
  }) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot save channel setting.');
      return;
    }
    final key = channelStorageKey(nameKeyPrefix, channelIndex);
    if (key == null) {
      appLogger.warn('Channel name is not registered. Cannot save setting.');
      return;
    }
    if (value == null) {
      await PrefsManager.instance.remove(key);
    } else {
      await write(key, value);
    }
  }

  Future<bool> loadSmazEnabled(int channelIndex) async =>
      await _loadValue<bool>(
        nameKeyPrefix: keyFor,
        channelIndex: channelIndex,
        read: PrefsManager.instance.getBool,
        write: PrefsManager.instance.setBool,
        additionalLegacyKeys: ['$_keyPrefix$channelIndex'],
      ) ??
      false;

  Future<void> saveSmazEnabled(int channelIndex, bool enabled) =>
      _saveValue<bool>(
        nameKeyPrefix: keyFor,
        channelIndex: channelIndex,
        value: enabled,
        write: PrefsManager.instance.setBool,
      );

  Future<bool> loadMcmpEnabled(int channelIndex) async =>
      await _loadValue<bool>(
        nameKeyPrefix: keyForMcmp,
        channelIndex: channelIndex,
        read: PrefsManager.instance.getBool,
        write: PrefsManager.instance.setBool,
      ) ??
      false;

  Future<void> saveMcmpEnabled(int channelIndex, bool enabled) =>
      _saveValue<bool>(
        nameKeyPrefix: keyForMcmp,
        channelIndex: channelIndex,
        value: enabled,
        write: PrefsManager.instance.setBool,
      );

  Future<int> loadMcmpVersion(int channelIndex) async =>
      await _loadValue<int>(
        nameKeyPrefix: keyForMcmpVersion,
        channelIndex: channelIndex,
        read: PrefsManager.instance.getInt,
        write: PrefsManager.instance.setInt,
      ) ??
      2;

  Future<void> saveMcmpVersion(int channelIndex, int version) =>
      _saveValue<int>(
        nameKeyPrefix: keyForMcmpVersion,
        channelIndex: channelIndex,
        value: version,
        write: PrefsManager.instance.setInt,
      );

  Future<bool> loadMcmpUseSign(int channelIndex) async =>
      await _loadValue<bool>(
        nameKeyPrefix: keyForMcmpUseSign,
        channelIndex: channelIndex,
        read: PrefsManager.instance.getBool,
        write: PrefsManager.instance.setBool,
      ) ??
      true;

  Future<void> saveMcmpUseSign(int channelIndex, bool useSign) =>
      _saveValue<bool>(
        nameKeyPrefix: keyForMcmpUseSign,
        channelIndex: channelIndex,
        value: useSign,
        write: PrefsManager.instance.setBool,
      );

  Future<bool> loadCyr2LatEnabled(int channelIndex) async =>
      await _loadValue<bool>(
        nameKeyPrefix: keyForCyr2Lat,
        channelIndex: channelIndex,
        read: PrefsManager.instance.getBool,
        write: PrefsManager.instance.setBool,
      ) ??
      false;

  Future<void> saveCyr2LatEnabled(int channelIndex, bool enabled) =>
      _saveValue<bool>(
        nameKeyPrefix: keyForCyr2Lat,
        channelIndex: channelIndex,
        value: enabled,
        write: PrefsManager.instance.setBool,
      );

  Future<bool> loadSendingDelayEnabled(int channelIndex) async =>
      await _loadValue<bool>(
        nameKeyPrefix: keyForSendingDelay,
        channelIndex: channelIndex,
        read: PrefsManager.instance.getBool,
        write: PrefsManager.instance.setBool,
      ) ??
      false;

  Future<void> saveSendingDelayEnabled(int channelIndex, bool enabled) =>
      _saveValue<bool>(
        nameKeyPrefix: keyForSendingDelay,
        channelIndex: channelIndex,
        value: enabled,
        write: PrefsManager.instance.setBool,
      );

  Future<List<String>> loadQuickAnswerIds(int channelIndex) async {
    final value = await _loadValue<List<String>>(
      nameKeyPrefix: keyForQuickAnswerIds,
      channelIndex: channelIndex,
      read: PrefsManager.instance.getStringList,
      write: PrefsManager.instance.setStringList,
    );
    return AppSettings.normalizeQuickAnswerIds(value);
  }

  Future<void> saveQuickAnswerIds(int channelIndex, List<String> answerIds) =>
      _saveValue<List<String>>(
        nameKeyPrefix: keyForQuickAnswerIds,
        channelIndex: channelIndex,
        value: AppSettings.normalizeQuickAnswerIds(answerIds),
        write: PrefsManager.instance.setStringList,
      );

  Future<String?> loadCyr2LatProfileId(int channelIndex) => _loadValue<String>(
    nameKeyPrefix: '${keyForCyr2Lat}profile_',
    channelIndex: channelIndex,
    read: PrefsManager.instance.getString,
    write: PrefsManager.instance.setString,
  );

  Future<void> saveCyr2LatProfileId(int channelIndex, String? profileId) =>
      _saveValue<String>(
        nameKeyPrefix: '${keyForCyr2Lat}profile_',
        channelIndex: channelIndex,
        value: profileId,
        write: PrefsManager.instance.setString,
      );

  Future<int?> loadWidgetColor(int channelIndex) => _loadValue<int>(
    nameKeyPrefix: keyForWidgetColor,
    channelIndex: channelIndex,
    read: PrefsManager.instance.getInt,
    write: PrefsManager.instance.setInt,
  );

  Future<void> saveWidgetColor(int channelIndex, int? colorValue) =>
      _saveValue<int>(
        nameKeyPrefix: keyForWidgetColor,
        channelIndex: channelIndex,
        value: colorValue,
        write: PrefsManager.instance.setInt,
      );

  Future<int?> loadWidgetTextColor(int channelIndex) => _loadValue<int>(
    nameKeyPrefix: keyForWidgetTextColor,
    channelIndex: channelIndex,
    read: PrefsManager.instance.getInt,
    write: PrefsManager.instance.setInt,
  );

  Future<void> saveWidgetTextColor(int channelIndex, int? colorValue) =>
      _saveValue<int>(
        nameKeyPrefix: keyForWidgetTextColor,
        channelIndex: channelIndex,
        value: colorValue,
        write: PrefsManager.instance.setInt,
      );

  Future<void> clearChannelSettings(int channelIndex) async {
    final prefixes = <String>[
      keyFor,
      keyForMcmp,
      keyForMcmpVersion,
      keyForMcmpUseSign,
      keyForCyr2Lat,
      '${keyForCyr2Lat}profile_',
      keyForSendingDelay,
      keyForQuickAnswerIds,
      keyForWidgetColor,
      keyForWidgetTextColor,
    ];
    for (final prefix in prefixes) {
      final nameKey = channelStorageKey(prefix, channelIndex);
      if (nameKey != null) await PrefsManager.instance.remove(nameKey);
      await PrefsManager.instance.remove('$prefix$channelIndex');
    }
  }
}
