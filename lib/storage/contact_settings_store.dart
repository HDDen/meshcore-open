import '../models/app_settings.dart';
import '../utils/app_logger.dart';
import 'prefs_manager.dart';

class ContactSettingsStore {
  static const String _keyPrefix = 'contact_smaz_';
  static const String _mcmpKeyPrefix = 'contact_mcmp_';
  static const String _mcmpVersionKeyPrefix = 'contact_mcmp_version_';
  static const String _mcmpUseSignKeyPrefix = 'contact_mcmp_use_sign_';
  static const String _cyr2latKeyPrefix = 'contact_cyr2lat_';
  static const String _sendingDelayKeyPrefix = 'contact_sending_delay_';
  // Store quick answer ids, not text, so editing a reply keeps chat assignment.
  static const String _quickAnswersKeyPrefix = 'contact_quick_answer_ids_';

  String publicKeyHex = '';
  set setPublicKeyHex(String value) =>
      publicKeyHex = value.length > 10 ? value.substring(0, 10) : '';

  String get keyFor => '$_keyPrefix$publicKeyHex';
  String get keyForMcmp => '$_mcmpKeyPrefix$publicKeyHex';
  String get keyForMcmpVersion => '$_mcmpVersionKeyPrefix$publicKeyHex';
  String get keyForMcmpUseSign => '$_mcmpUseSignKeyPrefix$publicKeyHex';
  String get keyForCyr2Lat => '$_cyr2latKeyPrefix$publicKeyHex';
  String get keyForSendingDelay => '$_sendingDelayKeyPrefix$publicKeyHex';
  String get keyForQuickAnswerIds => '$_quickAnswersKeyPrefix$publicKeyHex';

  Future<bool> loadSmazEnabled(String contactKeyHex) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load contact settings.',
      );
      return false;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyFor$contactKeyHex';
    final oldKey = '$_keyPrefix$contactKeyHex';
    bool? enabled = prefs.getBool(key);
    if (enabled == null) {
      // Attempt migration from legacy unscoped key on first load
      enabled = prefs.getBool(oldKey);
      prefs.remove(oldKey);
      if (enabled != null) {
        appLogger.info(
          'Migrating contact settings from legacy key $oldKey to scoped key $key',
        );
        await prefs.setBool(key, enabled);
      }
    }
    return prefs.getBool(key) ?? false;
  }

  Future<void> saveSmazEnabled(String contactKeyHex, bool enabled) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot save contact settings.',
      );
      return;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyFor$contactKeyHex';
    await prefs.setBool(key, enabled);
  }

  Future<bool> loadMcmpEnabled(String contactKeyHex) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load contact MCMP settings.',
      );
      return false;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForMcmp$contactKeyHex';
    return prefs.getBool(key) ?? false;
  }

  Future<void> saveMcmpEnabled(String contactKeyHex, bool enabled) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot save contact MCMP settings.',
      );
      return;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForMcmp$contactKeyHex';
    await prefs.setBool(key, enabled);
  }

  /// Default MCMP version for a channel or contact that never had one saved.
  ///
  /// v3 is the current container; v2 is kept only so existing conversations
  /// that were pinned to it keep working. Applies to everything with no stored
  /// value, not only to newly created entries — there is deliberately no
  /// migration, so a channel or contact whose version was never written moves
  /// to v3 on its own. `MeshCoreConnector` repeats this default in its
  /// in-memory getters, for the window before the stored value is read back.
  Future<int> loadMcmpVersion(String contactKeyHex) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load contact MCMP version.',
      );
      return 3;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForMcmpVersion$contactKeyHex';
    return prefs.getInt(key) ?? 3;
  }

  Future<void> saveMcmpVersion(String contactKeyHex, int version) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot save contact MCMP version.',
      );
      return;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForMcmpVersion$contactKeyHex';
    await prefs.setInt(key, version);
  }

  /// Whether v3 messages are signed, for a channel or contact that never had
  /// the flag saved.
  ///
  /// Off: the v3 container is taken for its structure — timestamp, precise
  /// reply anchor, compression — while a signature costs 64 body bytes and a
  /// `CMD_SIGN_*` round trip through the node, which firmware without those
  /// commands answers only by timing out. Signing is opted into per
  /// conversation instead. Read only where it can apply: channels, and room
  /// servers; a direct message is authenticated by its own transport.
  Future<bool> loadMcmpUseSign(String contactKeyHex) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load contact MCMP sign setting.',
      );
      return false;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForMcmpUseSign$contactKeyHex';
    return prefs.getBool(key) ?? false;
  }

  Future<void> saveMcmpUseSign(String contactKeyHex, bool useSign) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot save contact MCMP sign setting.',
      );
      return;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForMcmpUseSign$contactKeyHex';
    await prefs.setBool(key, useSign);
  }

  Future<bool> loadCyr2LatEnabled(String contactKeyHex) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load contact Cyr2Lat settings.',
      );
      return false;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForCyr2Lat$contactKeyHex';
    return prefs.getBool(key) ?? false;
  }

  Future<void> saveCyr2LatEnabled(String contactKeyHex, bool enabled) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot save contact Cyr2Lat settings.',
      );
      return;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForCyr2Lat$contactKeyHex';
    await prefs.setBool(key, enabled);
  }

  Future<bool> loadSendingDelayEnabled(String contactKeyHex) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load contact sending delay settings.',
      );
      return false;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForSendingDelay$contactKeyHex';
    return prefs.getBool(key) ?? false;
  }

  Future<void> saveSendingDelayEnabled(
    String contactKeyHex,
    bool enabled,
  ) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot save contact sending delay settings.',
      );
      return;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForSendingDelay$contactKeyHex';
    await prefs.setBool(key, enabled);
  }

  Future<List<String>> loadQuickAnswerIds(String contactKeyHex) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load contact quick answers.',
      );
      return const [];
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForQuickAnswerIds$contactKeyHex';
    return AppSettings.normalizeQuickAnswerIds(prefs.getStringList(key));
  }

  Future<void> saveQuickAnswerIds(
    String contactKeyHex,
    List<String> answerIds,
  ) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot save contact quick answers.',
      );
      return;
    }
    final prefs = PrefsManager.instance;
    final key = '$keyForQuickAnswerIds$contactKeyHex';
    await prefs.setStringList(
      key,
      AppSettings.normalizeQuickAnswerIds(answerIds),
    );
  }

  Future<String?> loadCyr2LatProfileId(String contactKeyHex) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load contact settings.',
      );
      return null;
    }
    final prefs = PrefsManager.instance;
    final key = '${keyForCyr2Lat}profile_$contactKeyHex';
    return prefs.getString(key);
  }

  Future<void> saveCyr2LatProfileId(
    String contactKeyHex,
    String? profileId,
  ) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot save contact settings.',
      );
      return;
    }
    final prefs = PrefsManager.instance;
    final key = '${keyForCyr2Lat}profile_$contactKeyHex';
    if (profileId == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, profileId);
    }
  }
}
