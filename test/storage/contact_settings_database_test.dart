import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/contact_option_storage.dart';
import 'package:meshcore_open/storage/contact_settings_store.dart';
import 'package:meshcore_open/storage/legacy_key_migration.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _nodeA = 'aaaaaaaaaa000000000000000000000000000000000000000000000000000000';
const _nodeB = 'bbbbbbbbbb000000000000000000000000000000000000000000000000000000';
const _contact = 'cccccccccc000000000000000000000000000000000000000000000000000000';
const _other = 'dddddddddd000000000000000000000000000000000000000000000000000000';

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('synthetic contact preferences');
  }
}

Future<String?> _sqliteProblem() async {
  final db = MessageHistoryDatabase.withExecutor(NativeDatabase.memory());
  try {
    await db.customSelect('SELECT 1').get();
    return null;
  } catch (error) {
    return 'SQLite unavailable: $error';
  } finally {
    try {
      await db.close();
    } catch (_) {
      // A failed SQLite open may not leave an executor that can be closed.
    }
  }
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sqliteProblem = await _sqliteProblem();
  final storage = MessageHistoryStorage.instance;
  late Directory directory;
  late File file;
  late MessageHistoryDatabase database;
  late PathProviderPlatform savedPaths;

  Future<void> preferences([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    PrefsManager.reset();
    await PrefsManager.initialize();
  }

  MessageHistoryDatabase openDatabase() =>
      MessageHistoryDatabase.withExecutor(NativeDatabase(file));

  Future<void> open() async {
    await storage.initializeAndMigrate(databaseFactory: () {
      database = openDatabase();
      return database;
    });
    expect(storage.hasDatabase, isTrue);
  }

  Future<void> reopen() async {
    await storage.resetForTesting();
    await open();
  }

  ContactSettingsStore store([String node = _nodeA]) =>
      ContactSettingsStore()..setPublicKeyHex = node;

  group('native contact options in SQLite', () {
    setUp(() async {
      savedPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _NoPreferencesDirectory();
      await storage.resetForTesting();
      await preferences();
      directory = await Directory.systemTemp.createTemp('mcoa-contact-options-');
      file = File('${directory.path}${Platform.pathSeparator}history.sqlite');
    });
    tearDown(() async {
      await storage.resetForTesting();
      PrefsManager.reset();
      PathProviderPlatform.instance = savedPaths;
      await directory.delete(recursive: true);
    });

    test('all eleven legacy options migrate, warm the first read and survive reopening', () async {
      final legacy = <String, Object>{
        'contact_mcmp_aaaaaaaaaa$_contact': true,
        'contact_mcmp_version_aaaaaaaaaa$_contact': 2,
        'contact_mcmp_use_sign_aaaaaaaaaa$_contact': true,
        'contact_mcotxt_aaaaaaaaaa$_contact': false,
        'contact_mcotxt_plain_when_smaller_aaaaaaaaaa$_contact': false,
        'contact_smaz_aaaaaaaaaa$_contact': false,
        'contact_cyr2lat_aaaaaaaaaa$_contact': false,
        'contact_cyr2lat_aaaaaaaaaaprofile_$_contact': 'test-profile',
        'contact_sending_delay_aaaaaaaaaa$_contact': true,
        'contact_quick_answer_ids_aaaaaaaaaa$_contact': ['one', 'two'],
        'contact_url_images_aaaaaaaaaa$_contact': true,
      };
      await preferences({...legacy, 'unrelated': 'keep'});
      await open();
      expect((await database.readContactOptionRows()).length, 11);
      expect(PrefsManager.instance.getKeys(), {'unrelated'});
      await reopen();
      final c = MeshCoreConnector();
      addTearDown(c.dispose);
      c.bindContactSettingsToNodeForTest(_nodeA);
      // No pump, second opening or asynchronous ensure is allowed here.
      expect(c.isContactMcmpEnabled(_contact), isTrue);
      expect(c.contactMcmpVersion(_contact), 2);
      expect(c.contactMcmpUseSign(_contact), isTrue);
      expect(c.isContactMCOtxtEnabled(_contact), isFalse);
      expect(c.isContactMCOtxtPlainWhenSmaller(_contact), isFalse);
      expect(c.isContactSmazEnabled(_contact), isFalse);
      expect(c.isContactCyr2LatEnabled(_contact), isFalse);
      expect(c.getContactCyr2LatProfileId(_contact), 'test-profile');
      expect(c.isContactSendingDelayEnabled(_contact), isTrue);
      expect(c.getContactQuickAnswerIds(_contact), ['one', 'two']);
      expect(c.isContactUrlImagesEnabled(_contact), isTrue);
      expect(PrefsManager.instance.getString('unrelated'), 'keep');
    });

    test('new saves and clears are SQL-only and keep node/contact boundaries', () async {
      await open();
      final s = store();
      await s.saveCompressionSelection(_contact, 'mcotxt_enabled', true);
      await s.saveMcmpVersion(_contact, 2);
      await s.saveMcmpUseSign(_contact, true);
      await s.saveMCOtxtPlainWhenSmaller(_contact, false);
      await s.saveCyr2LatProfileId(_contact, 'profile');
      await s.saveSendingDelayEnabled(_contact, true);
      await s.saveQuickAnswerIds(_contact, ['one', '', 'one', 'two']);
      await s.saveUrlImagesEnabled(_contact, true);
      await store(_nodeB).saveMcmpEnabled(_contact, true);
      await s.saveSmazEnabled(_other, true);
      expect(PrefsManager.instance.getKeys(), isEmpty);
      await reopen();
      final saved = store().readSettings(_contact)!;
      expect(saved.mcotxtEnabled, isTrue);
      expect(saved.mcmpEnabled, isFalse);
      expect(saved.smazEnabled, isFalse);
      expect(saved.cyr2LatEnabled, isFalse);
      expect(saved.mcmpVersion, 2);
      expect(saved.mcmpUseSign, isTrue);
      expect(saved.mcotxtPlainWhenSmaller, isFalse);
      expect(saved.cyr2LatProfileId, 'profile');
      expect(saved.sendingDelayEnabled, isTrue);
      expect(saved.quickAnswerIds, ['one', 'two']);
      expect(saved.urlImagesEnabled, isTrue);
      expect(store(_nodeB).readSettings(_contact)!.mcmpEnabled, isTrue);
      expect(store().readSettings(_other)!.smazEnabled, isTrue);
      await store().saveCyr2LatProfileId(_contact, null);
      await store().saveQuickAnswerIds(_contact, []);
      await store().saveUrlImagesEnabled(_contact, false);
      await reopen();
      expect(store().readSettings(_contact)!.cyr2LatProfileId, isNull);
      expect(store().readSettings(_contact)!.quickAnswerIds, isEmpty);
      expect(store().readSettings(_contact)!.urlImagesEnabled, isFalse);
      expect(PrefsManager.instance.getKeys(), isEmpty);
    });

    test('retry after interrupted preference cleanup keeps newer SQL choices', () async {
      await preferences({'contact_mcmp_aaaaaaaaaa$_contact': true});
      await open();
      await store().saveMcmpEnabled(_contact, false);
      await store().saveQuickAnswerIds(_contact, []);
      // Recreate the source keys left by an interruption after SQL commit.
      await PrefsManager.instance.setBool('contact_mcmp_aaaaaaaaaa$_contact', true);
      await PrefsManager.instance.setStringList('contact_quick_answer_ids_aaaaaaaaaa$_contact', ['stale']);
      await reopen();
      expect(store().readSettings(_contact)!.mcmpEnabled, isFalse);
      expect(store().readSettings(_contact)!.quickAnswerIds, isEmpty);
      expect(PrefsManager.instance.getKeys(), isEmpty);
    });

    test('failed migration rolls back rows and leaves source preferences for retry', () async {
      final seed = openDatabase();
      await seed.customSelect('SELECT 1').get();
      await seed.customStatement("CREATE TRIGGER reject_option BEFORE INSERT ON contact_settings "
          "WHEN NEW.name = 'mcmp_version' BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END");
      await seed.close();
      final legacy = <String, Object>{
        'contact_mcmp_aaaaaaaaaa$_contact': true,
        'contact_mcmp_version_aaaaaaaaaa$_contact': 2,
      };
      await preferences(legacy);
      await expectLater(open(), throwsA(anything));
      expect(PrefsManager.instance.getKeys(), legacy.keys.toSet());
      final inspect = openDatabase();
      expect(await inspect.readContactOptionRows(), isEmpty);
      await inspect.customStatement('DROP TRIGGER reject_option');
      await inspect.close();
      await open();
      expect(store().readSettings(_contact)!.mcmpEnabled, isTrue);
      expect(store().readSettings(_contact)!.mcmpVersion, 2);
      expect(PrefsManager.instance.getKeys(), isEmpty);
    });

    test('a failed codec selection is atomic on disk and in the storage cache', () async {
      await open();
      await store().saveCompressionSelection(_contact, 'mcmp_enabled', true);
      await database.customStatement("CREATE TEMP TRIGGER reject_option BEFORE INSERT ON contact_settings "
          "WHEN NEW.name = 'smaz_enabled' BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END");
      await expectLater(
        store().saveCompressionSelection(_contact, 'cyr2lat_enabled', true),
        throwsA(anything),
      );
      expect(store().readSettings(_contact)!.mcmpEnabled, isTrue);
      expect(store().readSettings(_contact)!.cyr2LatEnabled, isFalse);
      await database.customStatement('DROP TRIGGER reject_option');
      await reopen();
      expect(store().readSettings(_contact)!.mcmpEnabled, isTrue);
      expect(store().readSettings(_contact)!.cyr2LatEnabled, isFalse);
      await store().saveCompressionSelection(_contact, 'mcotxt_enabled', true);
      expect(store().readSettings(_contact)!.mcotxtEnabled, isTrue);
    });

    test('linking history copies only missing options and does not copy the region tenant', () async {
      await open();
      await store().saveMcmpEnabled(_other, true);
      await store().saveQuickAnswerIds(_other, ['one']);
      await store().saveCyr2LatProfileId(_other, 'source-profile');
      await store().saveMcmpEnabled(_contact, false);
      await store().saveQuickAnswerIds(_contact, []);
      await storage.saveContactSetting(nodeKey: 'aaaaaaaaaa', contactKey: _other, name: 'flood_region', value: 'region-source');
      await store().copySettings(from: _other, to: _contact);
      await reopen();
      final target = store().readSettings(_contact)!;
      expect(target.mcmpEnabled, isFalse);
      expect(target.quickAnswerIds, isEmpty);
      expect(target.cyr2LatProfileId, 'source-profile');
      expect((await storage.loadContactSettings('aaaaaaaaaa', 'flood_region')).keys, [_other]);
    });

    test('legacy unscoped SMAZ is adopted once, after a real node requests it', () async {
      await preferences({'contact_smaz_$_contact': true});
      await open();
      expect(await database.readContactOptionRows(), isEmpty);
      scopesWithoutLegacyMigration.add('bbbbbbbbbb');
      addTearDown(() => scopesWithoutLegacyMigration.remove('bbbbbbbbbb'));
      expect(await store(_nodeB).loadSmazEnabled(_contact), isFalse);
      expect(PrefsManager.instance.containsKey('contact_smaz_$_contact'), isTrue);
      expect(store().readSettings(_contact)!.smazEnabled, isTrue);
      expect(await store().loadSmazEnabled(_contact), isTrue);
      expect(PrefsManager.instance.getKeys(), isEmpty);
      await reopen();
      expect(store().readSettings(_contact)!.smazEnabled, isTrue);
      expect(store(_nodeB).readSettings(_contact)!.smazEnabled, isFalse);
    });

    test('invalid keys and incorrectly typed values stay in preferences', () async {
      final untouched = <String, Object>{
        'contact_mcmp_aaaaaaaaaa$_contact': 'not-a-bool',
        'contact_mcmp_invalid': true,
        'contact_unknown_aaaaaaaaaa$_contact': true,
        'contact_quick_answer_ids_aaaaaaaaaa$_contact': 'not-a-list',
        'unrelated': 7,
      };
      await preferences(untouched);
      await open();
      expect(await database.readContactOptionRows(), isEmpty);
      expect(PrefsManager.instance.getKeys(), untouched.keys.toSet());
    });

    test('native connector serializes quick switches and pending writes retain their node', () async {
      await open();
      final c = MeshCoreConnector();
      addTearDown(c.dispose);
      c.bindContactSettingsToNodeForTest(_nodeA);
      final first = c.setContactMcmpEnabled(_contact, true);
      final next = c.setContactMCOtxtEnabled(_contact, true);
      c.bindContactSettingsToNodeForTest(_nodeB);
      expect(c.isContactMCOtxtEnabled(_contact), isFalse);
      await Future.wait([first, next]);
      expect(c.isContactMCOtxtEnabled(_contact), isFalse);
      await reopen();
      expect(store().readSettings(_contact)!.mcotxtEnabled, isTrue);
      expect(store().readSettings(_contact)!.mcmpEnabled, isFalse);
      expect(store(_nodeB).readSettings(_contact)!.mcotxtEnabled, isFalse);
      expect(PrefsManager.instance.getKeys(), isEmpty);
    });

    test('option definitions preserve native types including false and empty values', () {
      expect(contactOptionDefinitions['mcmp_enabled']!.decode('0'), isFalse);
      expect(contactOptionDefinitions['mcmp_version']!.decode('2'), 2);
      expect(contactOptionDefinitions['cyr2lat_profile']!.decode(''), '');
      expect(contactOptionDefinitions['quick_answer_ids']!.decode('[]'), isEmpty);
      expect(contactOptionDefinitions['quick_answer_ids']!.decode('[1]'), isNull);
    });
  }, skip: sqliteProblem);
}
