import '../models/app_settings.dart';
import '../utils/app_logger.dart';
import 'prefs_manager.dart';

class ChannelSettingsStore {
  static const String _keyPrefix = 'channel_smaz_';
  static const String _mcmpKeyPrefix = 'channel_mcmp_';
  static const String _cyr2latKeyPrefix = 'channel_cyr2lat_';
  static const String _sendingDelayKeyPrefix = 'channel_sending_delay_';
  // Store quick answer ids, not text, so editing a reply keeps chat assignment.
  static const String _quickAnswersKeyPrefix = 'channel_quick_answer_ids_';
  static const String _widgetColorKeyPrefix = 'channel_widget_color_';
  static const String _widgetTextColorKeyPrefix = 'channel_widget_text_color_';

  String publicKeyHex = '';
  set setPublicKeyHex(String value) =>
      publicKeyHex = value.length > 10 ? value.substring(0, 10) : '';

  String get keyFor => '$_keyPrefix$publicKeyHex';
  String get keyForMcmp => '$_mcmpKeyPrefix$publicKeyHex';
  String get keyForCyr2Lat => '$_cyr2latKeyPrefix$publicKeyHex';
  String get keyForSendingDelay => '$_sendingDelayKeyPrefix$publicKeyHex';
  String get keyForQuickAnswerIds => '$_quickAnswersKeyPrefix$publicKeyHex';
  String get keyForWidgetColor => '$_widgetColorKeyPrefix$publicKeyHex';
  String get keyForWidgetTextColor => '$_widgetTextColorKeyPrefix$publicKeyHex';

  Future<bool> loadSmazEnabled(int channelIndex) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load channel settings.',
      );
      return false;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyFor$channelIndex';
    final oldKey = '$_keyPrefix$channelIndex';
    bool? enabled = prefs.getBool(key);
    if (enabled == null) {
      // Attempt migration from legacy unscoped key on first load
      enabled = prefs.getBool(oldKey);
      prefs.remove(oldKey);
      if (enabled != null) {
        appLogger.info(
          'Migrating channel settings from legacy key $oldKey to scoped key $key',
        );
        await prefs.setBool(key, enabled);
      }
    }
    return enabled ?? false;
  }

  Future<void> saveSmazEnabled(int channelIndex, bool enabled) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot save channel settings.',
      );
      return;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyFor$channelIndex';
    await prefs.setBool(key, enabled);
  }

  Future<bool> loadMcmpEnabled(int channelIndex) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load channel MCMP settings.',
      );
      return false;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForMcmp$channelIndex';
    return prefs.getBool(key) ?? false;
  }

  Future<void> saveMcmpEnabled(int channelIndex, bool enabled) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot save channel MCMP settings.',
      );
      return;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForMcmp$channelIndex';
    await prefs.setBool(key, enabled);
  }

  Future<bool> loadCyr2LatEnabled(int channelIndex) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load channel Cyr2Lat settings.',
      );
      return false;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForCyr2Lat$channelIndex';
    return prefs.getBool(key) ?? false;
  }

  Future<void> saveCyr2LatEnabled(int channelIndex, bool enabled) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot save channel Cyr2Lat settings.',
      );
      return;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForCyr2Lat$channelIndex';
    await prefs.setBool(key, enabled);
  }

  Future<bool> loadSendingDelayEnabled(int channelIndex) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load channel sending delay settings.',
      );
      return false;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForSendingDelay$channelIndex';
    return prefs.getBool(key) ?? false;
  }

  Future<void> saveSendingDelayEnabled(int channelIndex, bool enabled) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot save channel sending delay settings.',
      );
      return;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForSendingDelay$channelIndex';
    await prefs.setBool(key, enabled);
  }

  Future<List<String>> loadQuickAnswerIds(int channelIndex) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load channel quick answers.',
      );
      return const [];
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForQuickAnswerIds$channelIndex';
    return AppSettings.normalizeQuickAnswerIds(prefs.getStringList(key));
  }

  Future<void> saveQuickAnswerIds(
    int channelIndex,
    List<String> answers,
  ) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot save channel quick answers.',
      );
      return;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForQuickAnswerIds$channelIndex';
    await prefs.setStringList(
      key,
      AppSettings.normalizeQuickAnswerIds(answers),
    );
  }

  Future<String?> loadCyr2LatProfileId(int channelIndex) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load channel settings.',
      );
      return null;
    }
    final prefs = PrefsManager.instance;
    final key = '${keyForCyr2Lat}profile_$channelIndex';
    return prefs.getString(key);
  }

  Future<void> saveCyr2LatProfileId(int channelIndex, String? profileId) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot save channel settings.',
      );
      return;
    }
    final prefs = PrefsManager.instance;
    final key = '${keyForCyr2Lat}profile_$channelIndex';
    if (profileId == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, profileId);
    }
  }

  Future<int?> loadWidgetColor(int channelIndex) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load channel widget color.',
      );
      return null;
    }
    final prefs = PrefsManager.instance;
    return prefs.getInt('$keyForWidgetColor$channelIndex');
  }

  Future<void> saveWidgetColor(int channelIndex, int? colorValue) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot save channel widget color.',
      );
      return;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForWidgetColor$channelIndex';
    if (colorValue == null) {
      await prefs.remove(key);
    } else {
      await prefs.setInt(key, colorValue);
    }
  }

  Future<int?> loadWidgetTextColor(int channelIndex) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load channel widget text color.',
      );
      return null;
    }
    final prefs = PrefsManager.instance;
    return prefs.getInt('$keyForWidgetTextColor$channelIndex');
  }

  Future<void> saveWidgetTextColor(int channelIndex, int? colorValue) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot save channel widget text color.',
      );
      return;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForWidgetTextColor$channelIndex';
    if (colorValue == null) {
      await prefs.remove(key);
    } else {
      await prefs.setInt(key, colorValue);
    }
  }
}
