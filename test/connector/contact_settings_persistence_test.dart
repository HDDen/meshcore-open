import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/contact_settings_snapshot.dart';
import 'package:meshcore_open/storage/contact_settings_store.dart';
import 'package:meshcore_open/storage/legacy_key_migration.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Preference-only fallback contract. Native SQLite/reopen/rollback coverage is in
// test/storage/contact_settings_database_test.dart.
const _nodeA = 'aaaaaaaaaa000000000000000000000000000000000000000000000000000000';
const _nodeB = 'bbbbbbbbbb000000000000000000000000000000000000000000000000000000';
const _contact = 'cccccccccc000000000000000000000000000000000000000000000000000000';
const _otherContact = 'dddddddddd000000000000000000000000000000000000000000000000000000';

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('in-memory contact preferences');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PathProviderPlatform savedPaths;

  Future<void> initPrefs([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    PrefsManager.reset();
    await PrefsManager.initialize();
  }

  Map<String, Object> savedPreferences() {
    final prefs = PrefsManager.instance;
    return {for (final key in prefs.getKeys()) key: prefs.get(key)!};
  }

  MeshCoreConnector connector([String? node = _nodeA]) {
    final result = MeshCoreConnector();
    addTearDown(result.dispose);
    if (node != null) {
      result.bindContactSettingsToNodeForTest(node);
    }
    return result;
  }

  ContactSettingsStore store([String node = _nodeA]) =>
      ContactSettingsStore()..setPublicKeyHex = node;

  setUpAll(() {
    savedPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferencesDirectory();
  });
  tearDownAll(() => PathProviderPlatform.instance = savedPaths);
  setUp(initPrefs);
  tearDown(PrefsManager.reset);

  test('first read restores all options before any async load completes', () async {
    final disk = store();
    await disk.saveMcmpEnabled(_contact, true);
    await disk.saveMcmpVersion(_contact, 2);
    await disk.saveMcmpUseSign(_contact, true);
    await disk.saveMCOtxtEnabled(_contact, true);
    await disk.saveMCOtxtPlainWhenSmaller(_contact, false);
    await disk.saveSmazEnabled(_contact, true);
    await disk.saveCyr2LatEnabled(_contact, true);
    await disk.saveCyr2LatProfileId(_contact, 'test-profile');
    await disk.saveSendingDelayEnabled(_contact, true);
    await disk.saveQuickAnswerIds(_contact, ['one', 'two']);
    await disk.saveUrlImagesEnabled(_contact, true);
    final persisted = savedPreferences();
    await initPrefs(persisted); // A new preferences instance, like a new process.
    final c = connector();
    expect(c.isContactMcmpEnabled(_contact), isTrue);
    expect(c.contactMcmpVersion(_contact), 2);
    expect(c.contactMcmpUseSign(_contact), isTrue);
    expect(c.isContactMCOtxtEnabled(_contact), isTrue);
    expect(c.isContactMCOtxtPlainWhenSmaller(_contact), isFalse);
    expect(c.isContactSmazEnabled(_contact), isTrue);
    expect(c.isContactCyr2LatEnabled(_contact), isTrue);
    expect(c.getContactCyr2LatProfileId(_contact), 'test-profile');
    expect(c.isContactSendingDelayEnabled(_contact), isTrue);
    expect(c.getContactQuickAnswerIds(_contact), ['one', 'two']);
    expect(c.isContactUrlImagesEnabled(_contact), isTrue);
    expect(savedPreferences(), persisted); // Reading must not rewrite settings.
  });

  final codecs = <String, Future<void> Function(MeshCoreConnector, bool)>{
    'MCMP': (c, value) => c.setContactMcmpEnabled(_contact, value),
    'MCOtxt': (c, value) => c.setContactMCOtxtEnabled(_contact, value),
    'SMAZ': (c, value) => c.setContactSmazEnabled(_contact, value),
    'Cyr2Lat': (c, value) => c.setContactCyr2LatEnabled(_contact, value),
  };
  for (final selected in codecs.keys) {
    test('$selected and independent options survive a new connector and preferences', () async {
      final c = connector();
      for (final setCodec in codecs.values) {
        await setCodec(c, true);
      }
      await codecs[selected]!(c, true);
      await c.setContactMcmpVersion(_contact, 2);
      await c.setContactMcmpUseSign(_contact, true);
      await c.setContactMCOtxtPlainWhenSmaller(_contact, false);
      await c.setContactCyr2LatProfileId(_contact, 'test-profile');
      await c.setContactSendingDelayEnabled(_contact, true);
      await c.setContactQuickAnswerIds(_contact, ['one', '', 'one', 'two']);
      await c.setContactUrlImagesEnabled(_contact, true);
      await initPrefs(savedPreferences());
      final reopened = connector();
      expect(reopened.isContactMcmpEnabled(_contact), selected == 'MCMP');
      expect(reopened.isContactMCOtxtEnabled(_contact), selected == 'MCOtxt');
      expect(reopened.isContactSmazEnabled(_contact), selected == 'SMAZ');
      expect(reopened.isContactCyr2LatEnabled(_contact), selected == 'Cyr2Lat');
      expect(reopened.contactMcmpVersion(_contact), 2);
      expect(reopened.contactMcmpUseSign(_contact), isTrue);
      expect(reopened.isContactMCOtxtPlainWhenSmaller(_contact), isFalse);
      expect(reopened.getContactCyr2LatProfileId(_contact), 'test-profile');
      expect(reopened.isContactSendingDelayEnabled(_contact), isTrue);
      expect(reopened.getContactQuickAnswerIds(_contact), ['one', 'two']);
      expect(reopened.isContactUrlImagesEnabled(_contact), isTrue);
      expect(reopened.isContactMcmpEnabled(_otherContact), isFalse);
      expect(reopened.getContactQuickAnswerIds(_otherContact), isEmpty);
    });
  }

  test('opening the sheet then editing cannot be undone by a late load', () async {
    final c = connector();
    c.ensureContactMcmpSettingLoaded(_contact);
    c.ensureContactMCOtxtSettingLoaded(_contact);
    c.ensureContactSmazSettingLoaded(_contact);
    c.ensureContactCyr2LatSettingLoaded(_contact);
    c.ensureContactQuickAnswerIdsLoaded(_contact);
    final save = c.setContactMcmpEnabled(_contact, true);
    expect(c.isContactMcmpEnabled(_contact), isTrue);
    await save;
    expect(c.isContactMcmpEnabled(_contact), isTrue);
    expect(connector().isContactMcmpEnabled(_contact), isTrue);
  });

  test('a quick enable and disable leaves MCMP disabled after restart', () async {
    final c = connector();
    await Future.wait([
      c.setContactMcmpEnabled(_contact, true),
      c.setContactMcmpEnabled(_contact, false),
    ]);
    expect(c.isContactMcmpEnabled(_contact), isFalse);
    expect(connector().isContactMcmpEnabled(_contact), isFalse);
  });

  test('rapid codec switches retain only the last selection on disk', () async {
    final c = connector();
    await Future.wait([
      c.setContactMcmpEnabled(_contact, true),
      c.setContactSmazEnabled(_contact, true),
      c.setContactMCOtxtEnabled(_contact, true),
    ]);
    final reopened = connector();
    expect(reopened.isContactMcmpEnabled(_contact), isFalse);
    expect(reopened.isContactSmazEnabled(_contact), isFalse);
    expect(reopened.isContactCyr2LatEnabled(_contact), isFalse);
    expect(reopened.isContactMCOtxtEnabled(_contact), isTrue);
  });

  test('switching nodes isolates every cached option and queued write', () async {
    final c = connector();
    await c.setContactSendingDelayEnabled(_contact, true);
    await c.setContactQuickAnswerIds(_contact, ['one']);
    await c.setContactUrlImagesEnabled(_contact, true);
    final pending = c.setContactMcmpEnabled(_contact, true);
    c.bindContactSettingsToNodeForTest(_nodeB);
    expect(c.isContactMcmpEnabled(_contact), isFalse);
    expect(c.isContactSendingDelayEnabled(_contact), isFalse);
    expect(c.getContactQuickAnswerIds(_contact), isEmpty);
    expect(c.isContactUrlImagesEnabled(_contact), isFalse);
    await pending;
    expect(c.isContactMcmpEnabled(_contact), isFalse);
    expect(await store(_nodeB).loadMcmpEnabled(_contact), isFalse);
    c.bindContactSettingsToNodeForTest(_nodeA);
    expect(c.isContactMcmpEnabled(_contact), isTrue);
    expect(c.isContactSendingDelayEnabled(_contact), isTrue);
    expect(c.getContactQuickAnswerIds(_contact), ['one']);
    expect(c.isContactUrlImagesEnabled(_contact), isTrue);
  });

  test('reading before SELF_INFO never caches defaults for the real node', () async {
    await store().saveMcmpEnabled(_contact, true);
    final c = connector(null);
    c.ensureContactMcmpSettingLoaded(_contact);
    expect(c.isContactMcmpEnabled(_contact), isFalse);
    c.bindContactSettingsToNodeForTest(_nodeA);
    expect(c.isContactMcmpEnabled(_contact), isTrue);
  });

  test('disabling and clearing options persists without changing defaults elsewhere', () async {
    final c = connector();
    await c.setContactSendingDelayEnabled(_contact, true);
    await c.setContactSendingDelayEnabled(_contact, false);
    await c.setContactUrlImagesEnabled(_contact, true);
    await c.setContactUrlImagesEnabled(_contact, false);
    await c.setContactMcmpUseSign(_contact, true);
    await c.setContactMcmpUseSign(_contact, false);
    await c.setContactMcmpVersion(_contact, 2);
    await c.setContactMcmpVersion(_contact, 3);
    await c.setContactCyr2LatProfileId(_contact, 'profile');
    await c.setContactCyr2LatProfileId(_contact, null);
    await c.setContactQuickAnswerIds(_contact, ['one']);
    await c.setContactQuickAnswerIds(_contact, []);
    final reopened = connector();
    expect(reopened.isContactSendingDelayEnabled(_contact), isFalse);
    expect(reopened.isContactUrlImagesEnabled(_contact), isFalse);
    expect(reopened.contactMcmpUseSign(_contact), isFalse);
    expect(reopened.contactMcmpVersion(_contact), 3);
    expect(reopened.getContactCyr2LatProfileId(_contact), isNull);
    expect(reopened.getContactQuickAnswerIds(_contact), isEmpty);
    expect(reopened.isContactMCOtxtPlainWhenSmaller(_otherContact), isTrue);
  });

  test('SMAZ legacy migration survives synchronous first read and keeps exclusions', () async {
    await initPrefs({'contact_smaz_$_contact': true});
    scopesWithoutLegacyMigration.add(_nodeB.substring(0, 10));
    addTearDown(() => scopesWithoutLegacyMigration.remove(_nodeB.substring(0, 10)));
    expect(connector(_nodeB).isContactSmazEnabled(_contact), isFalse);
    expect(connector().isContactSmazEnabled(_contact), isTrue);
    await store().loadSmazEnabled(_contact);
    expect(PrefsManager.instance.containsKey('contact_smaz_$_contact'), isFalse);
    expect(connector().isContactSmazEnabled(_contact), isTrue);
  });

  test('a failed codec write does not block subsequent selections', () async {
    final queue = ContactCompressionWrites();
    final gate = Completer<void>();
    final writes = <String>[];
    final first = queue.run(() async {
      await gate.future;
      throw StateError('synthetic write failure');
    });
    final failed = expectLater(first, throwsStateError);
    final next = queue.run(() async => writes.add('next'));
    gate.complete();
    await failed;
    await next;
    expect(writes, ['next']);
  });
}
