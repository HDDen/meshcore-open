import '../helpers/contact_option_storage.dart';
import '../helpers/contact_settings_snapshot.dart';
import '../models/app_settings.dart';
import 'legacy_key_migration.dart';
import 'message_history_storage.dart';
import 'prefs_manager.dart';

/// App-side options in contact_settings, keyed by node/contact/option. Native
/// startup migrates preferences and warms the SQL cache before this is used.
/// Web has no history database and keeps the established preferences backend.
class ContactSettingsStore {
  String publicKeyHex = '';
  set setPublicKeyHex(String value) =>
      publicKeyHex = value.length >= 10 ? value.substring(0, 10).toLowerCase() : '';

  String _legacyKey(String name, String contact) =>
      contactOptionDefinitions[name]!.legacyKey(publicKeyHex, contact);

  Object? _read(String name, String contact) {
    if (publicKeyHex.isEmpty) {
      return null;
    }
    final storage = MessageHistoryStorage.instance;
    if (storage.hasDatabase) {
      return contactOptionDefinitions[name]!.decode(
        storage.contactOption(publicKeyHex, contact, name),
      );
    }
    return PrefsManager.instance.get(_legacyKey(name, contact));
  }

  Future<void> _write(String name, String contact, Object? value) async {
    if (publicKeyHex.isEmpty) {
      return;
    }
    final storage = MessageHistoryStorage.instance;
    if (storage.hasDatabase) {
      final encoded = contactOptionDefinitions[name]!.encode(value);
      if (value != null && encoded == null) {
        throw ArgumentError('Invalid contact option $name');
      }
      await storage.writeContactOptions(publicKeyHex, contact, {name: encoded});
      return;
    }
    final prefs = PrefsManager.instance;
    final key = _legacyKey(name, contact);
    switch (value) {
      case null:
        if (prefs.containsKey(key)) {
          await prefs.remove(key);
        }
      case bool flag:
        await prefs.setBool(key, flag);
      case int number:
        await prefs.setInt(key, number);
      case String text:
        await prefs.setString(key, text);
      case List<String> list:
        await prefs.setStringList(key, list);
      default:
        throw ArgumentError('Invalid contact option $name');
    }
  }

  bool _smaz(String contact) =>
      (_read('smaz_enabled', contact) as bool?) ??
      (canMigrateLegacyKeys(publicKeyHex)
          ? PrefsManager.instance.getBool('contact_smaz_$contact')
          : null) ??
      false;

  /// Both SQL and preferences caches are ready synchronously before the UI.
  ContactSettingsSnapshot? readSettings(String contactKeyHex) {
    if (publicKeyHex.isEmpty) {
      return null;
    }
    final version = _read('mcmp_version', contactKeyHex) as int? ?? 3;
    return ContactSettingsSnapshot(
      mcmpEnabled: _read('mcmp_enabled', contactKeyHex) as bool? ?? false,
      mcmpVersion: version == 3 ? 3 : 2,
      mcmpUseSign: _read('mcmp_use_sign', contactKeyHex) as bool? ?? false,
      mcotxtEnabled: _read('mcotxt_enabled', contactKeyHex) as bool? ?? false,
      mcotxtPlainWhenSmaller: _read('mcotxt_plain_when_smaller', contactKeyHex) as bool? ?? true,
      smazEnabled: _smaz(contactKeyHex),
      cyr2LatEnabled: _read('cyr2lat_enabled', contactKeyHex) as bool? ?? false,
      cyr2LatProfileId: _read('cyr2lat_profile', contactKeyHex) as String?,
      sendingDelayEnabled: _read('sending_delay_enabled', contactKeyHex) as bool? ?? false,
      quickAnswerIds: AppSettings.normalizeQuickAnswerIds(_read('quick_answer_ids', contactKeyHex)),
      urlImagesEnabled: _read('url_images_enabled', contactKeyHex) as bool? ?? false,
    );
  }

  ContactSettingsStore scopedCopy() => ContactSettingsStore()..publicKeyHex = publicKeyHex;

  Future<void> copySettings({required String from, required String to}) async {
    if (publicKeyHex.isEmpty || from == to) {
      return;
    }
    final storage = MessageHistoryStorage.instance;
    if (storage.hasDatabase) {
      await storage.copyContactOptions(publicKeyHex, from, to);
      return;
    }
    for (final name in contactOptionDefinitions.keys) {
      final source = _read(name, from);
      if (source != null && _read(name, to) == null) {
        await _write(name, to, source);
      }
    }
  }

  /// Preserve old unscoped SMAZ adoption, but remove its source only after the
  /// SQL import commits. An existing SQL value (even false) always wins.
  Future<bool> loadSmazEnabled(String contactKeyHex) async {
    if (publicKeyHex.isEmpty) {
      return false;
    }
    final captured = scopedCopy();
    final scope = captured.publicKeyHex;
    final legacyKey = 'contact_smaz_$contactKeyHex';
    final prefs = PrefsManager.instance;
    if (captured._read('smaz_enabled', contactKeyHex) == null &&
        canMigrateLegacyKeys(scope) && prefs.get(legacyKey) is bool) {
      final storage = MessageHistoryStorage.instance;
      if (storage.hasDatabase) {
        await storage.importLegacyContactSmaz(scope, contactKeyHex);
      } else {
        await captured._write('smaz_enabled', contactKeyHex, prefs.getBool(legacyKey));
        await prefs.remove(legacyKey);
      }
    }
    return captured._read('smaz_enabled', contactKeyHex) as bool? ?? false;
  }

  /// A selection is all four codec flags in one SQLite transaction.
  Future<void> saveCompressionSelection(String contact, String selected, bool enabled) async {
    const codecs = ['mcmp_enabled', 'mcotxt_enabled', 'smaz_enabled', 'cyr2lat_enabled'];
    if (!codecs.contains(selected)) {
      throw ArgumentError('Unknown codec');
    }
    if (publicKeyHex.isEmpty) {
      return;
    }
    final values = <String, String?>{
      if (enabled) for (final codec in codecs) codec: '0',
      selected: enabled ? '1' : '0',
    };
    final storage = MessageHistoryStorage.instance;
    if (storage.hasDatabase) {
      await storage.writeContactOptions(publicKeyHex, contact, values);
    } else {
      for (final entry in values.entries) {
        await _write(entry.key, contact, entry.value == '1');
      }
    }
  }

  Future<void> saveSmazEnabled(String contact, bool value) => _write('smaz_enabled', contact, value);

  Future<bool> loadMcmpEnabled(String contact) async =>
      _read('mcmp_enabled', contact) as bool? ?? false;

  Future<void> saveMcmpEnabled(String contact, bool value) =>
      _write('mcmp_enabled', contact, value);

  Future<int> loadMcmpVersion(String contact) async =>
      _read('mcmp_version', contact) as int? ?? 3;

  Future<void> saveMcmpVersion(String contact, int value) =>
      _write('mcmp_version', contact, value);

  Future<bool> loadMcmpUseSign(String contact) async =>
      _read('mcmp_use_sign', contact) as bool? ?? false;

  Future<void> saveMcmpUseSign(String contact, bool value) =>
      _write('mcmp_use_sign', contact, value);

  Future<bool> loadMCOtxtEnabled(String contact) async =>
      _read('mcotxt_enabled', contact) as bool? ?? false;

  Future<void> saveMCOtxtEnabled(String contact, bool value) =>
      _write('mcotxt_enabled', contact, value);

  Future<bool> loadMCOtxtPlainWhenSmaller(String contact) async =>
      _read('mcotxt_plain_when_smaller', contact) as bool? ?? true;

  Future<void> saveMCOtxtPlainWhenSmaller(String contact, bool value) =>
      _write('mcotxt_plain_when_smaller', contact, value);

  Future<bool> loadCyr2LatEnabled(String contact) async =>
      _read('cyr2lat_enabled', contact) as bool? ?? false;

  Future<void> saveCyr2LatEnabled(String contact, bool value) =>
      _write('cyr2lat_enabled', contact, value);

  Future<bool> loadSendingDelayEnabled(String contact) async =>
      _read('sending_delay_enabled', contact) as bool? ?? false;

  Future<void> saveSendingDelayEnabled(String contact, bool value) =>
      _write('sending_delay_enabled', contact, value);

  Future<bool> loadUrlImagesEnabled(String contact) async =>
      _read('url_images_enabled', contact) as bool? ?? false;

  Future<void> saveUrlImagesEnabled(String contact, bool value) =>
      _write('url_images_enabled', contact, value);

  Future<List<String>> loadQuickAnswerIds(String contact) async =>
      AppSettings.normalizeQuickAnswerIds(_read('quick_answer_ids', contact));

  Future<void> saveQuickAnswerIds(String contact, List<String> ids) =>
      _write('quick_answer_ids', contact, AppSettings.normalizeQuickAnswerIds(ids));

  Future<String?> loadCyr2LatProfileId(String contact) async =>
      _read('cyr2lat_profile', contact) as String?;

  Future<void> saveCyr2LatProfileId(String contact, String? id) =>
      _write('cyr2lat_profile', contact, id);
}
