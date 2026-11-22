import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/storage/legacy_key_migration.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/storage/unread_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _Preferences extends InMemorySharedPreferencesStore {
  _Preferences() : super.withData({'flutter.contact_unread_count': '{"alice":3}'});
  bool failWrites = false;
  final calls = <String>[];

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    calls.add('set:$key');
    if (failWrites) return false;
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    calls.add('remove:$key');
    return super.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Preferences preferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = _Preferences();
    SharedPreferencesStorePlatform.instance = preferences;
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(() {
    scopesWithoutLegacyMigration.clear();
    PrefsManager.reset();
    SharedPreferences.setMockInitialValues({});
  });

  for (final fail in [false, true]) {
    test('unread migration removes legacy data only after a successful write (failure=$fail)', () async {
      preferences.failWrites = fail;
      final store = UnreadStore()..setPublicKeyHex = 'aaaaaaaaaa012345';
      addTearDown(store.dispose);
      expect(await store.loadContactUnreadCount(), {'alice': 3});
      expect(PrefsManager.instance.containsKey('contact_unread_count'), fail);
      expect(preferences.calls, [
        'set:flutter.contact_unread_countaaaaaaaaaa',
        if (!fail) 'remove:flutter.contact_unread_count',
      ]);
    });
  }

  test('review scope leaves legacy unread counts for the real radio', () async {
    scopesWithoutLegacyMigration.add('aaaaaaaaaa');
    final store = UnreadStore()..setPublicKeyHex = 'aaaaaaaaaa012345';
    addTearDown(store.dispose);
    expect(await store.loadContactUnreadCount(), isEmpty);
    expect(preferences.calls, isEmpty);
    expect(PrefsManager.instance.getString('contact_unread_count'), '{"alice":3}');
  });
}