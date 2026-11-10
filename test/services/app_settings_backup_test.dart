import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/app_settings_backup.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/backup_file_codec.dart';
import 'package:meshcore_open/services/backup_import_planner.dart';
import 'package:meshcore_open/services/backup_snapshot.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a portable backup exposes only selected display preferences', () async {
    final snapshot = BackupSnapshot(
      createdAt: DateTime.utc(2026),
      appSettings: AppSettingsBackup.capture(
        AppSettings(
          themeMode: 'dark',
          languageOverride: 'ru',
          unitSystem: UnitSystem.imperial,
          uiScale: 1.25,
          enableTimeSeconds: true,
          activeThemeId: 'private-theme',
          uploadIpfsApiKey: 'private-upload-key',
          mapTileApiKey: 'private-map-key',
          tcpServerAddress: 'private-node-address',
          networkMapUploadEnabled: true,
        ),
      ),
    );
    expect(snapshot.fileName, startsWith('meshcore-settings-'));
    final encoded = await snapshot.encode(password: '');
    final decoded = await const BackupFileCodec().decode(encoded, password: '');
    expect(decoded['items'], [AppSettingsBackup.section]);
    expect(decoded['sourcePublicKey'], '');
    expect(encoded, isNot(contains('private-')));
    expect(encoded, isNot(contains('network_map_upload_enabled')));
    final plan = await const BackupImportPlanner().inspect(encoded, password: '');
    expect(plan.sourcePublicKey, isNull);
    expect(plan.channels, isNull);
    expect(plan.contacts, isNull);
    expect(plan.appSettings!.values, containsPair('theme_mode', 'dark'));
    expect(plan.appSettings!.values, containsPair('unit_system', 'imperial'));
    expect(plan.appSettings!.values, containsPair('ui_scale', 1.25));
  });

  test('upstream settings import accepts only valid supported values', () async {
    const codec = BackupFileCodec();
    const planner = BackupImportPlanner();
    final payload = {
      'format': BackupFileCodec.payloadFormat,
      'version': BackupFileCodec.formatVersion,
      'sourcePublicKey': '',
      'items': ['appSettings'],
      'sections': {
        'appSettings': {
          'preferences': {
            'app_settings': jsonEncode({
              'enable_time_seconds': true,
              'theme_mode': 'unsupported',
              'ui_scale': 9,
              'language_override': 'invalid',
              'show_hops': 'false',
              'tcp_server_address': 'replacement',
              'map_tile_api_key': 'replacement',
            }),
          },
        },
      },
    };
    final encoded = await codec.encode(payload, password: '');
    final plan = await planner.inspect(encoded, password: '');
    expect(plan.appSettings!.values, {'enable_time_seconds': true});

    final unselected = await codec.encode({
      ...payload,
      'items': <String>[],
    }, password: '');
    expect((await planner.inspect(unselected, password: '')).appSettings, isNull);
  });

  test('restore checks the preview and saves into the current preferences',
      () async {
    final initial = AppSettings(
      languageOverride: 'ru',
      tcpServerAddress: 'existing',
      mapTileApiKey: 'existing-key',
      activeThemeId: 'existing-theme',
    );
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode(initial.toJson()),
    });
    PrefsManager.reset();
    addTearDown(PrefsManager.reset);
    await PrefsManager.initialize();
    final service = AppSettingsService();
    addTearDown(service.dispose);
    await service.loadSettings();
    final backup = AppSettingsBackup.fromJson({
      'language_override': null,
      'ui_scale': 1.5,
      'tcp_server_address': 'replacement',
    });
    final stale = backup.preview(service.settings);
    await service.setUiScale(1.25);
    expect(await service.restoreAppSettingsBackup(stale), isFalse);
    expect(service.settings.languageOverride, 'ru');
    expect(service.settings.uiScale, 1.25);

    final preview = backup.preview(service.settings);
    expect(preview.changes, {'language_override': null, 'ui_scale': 1.5});
    await service.updateSettings(
      service.settings.copyWith(tcpServerAddress: 'edited since preview'),
    );
    expect(await service.restoreAppSettingsBackup(preview), isTrue);
    final reloaded = AppSettingsService();
    addTearDown(reloaded.dispose);
    await reloaded.loadSettings();
    expect(reloaded.settings.languageOverride, isNull);
    expect(reloaded.settings.uiScale, 1.5);
    expect(reloaded.settings.tcpServerAddress, 'edited since preview');
    expect(reloaded.settings.mapTileApiKey, 'existing-key');
    expect(reloaded.settings.activeThemeId, 'existing-theme');
  });

  test('a bad section cannot block a restore of other selected data', () async {
    const codec = BackupFileCodec();
    const planner = BackupImportPlanner();
    final key = List.filled(64, 'a').join();
    final channelKey = 'channels${key.substring(0, 10)}';
    final sections = {
      'channels': {
        'preferences': {channelKey: '[]'},
      },
      'appSettings': {
        'preferences': {'app_settings': '{"theme_mode":"dark"}'},
      },
    };
    final payload = {
      'format': BackupFileCodec.payloadFormat,
      'version': BackupFileCodec.formatVersion,
      'sourcePublicKey': key,
      'items': ['channels', 'appSettings'],
    };
    final badSettings = await codec.encode({
      ...payload,
      'sections': {
        ...sections,
        'appSettings': {
          'preferences': {'app_settings': 'incomplete JSON'},
        },
      },
    }, password: '');
    final radioPlan = await planner.inspect(badSettings, password: '');
    expect(radioPlan.appSettings, isNull);
    expect(radioPlan.channels, isEmpty);

    final badRadioList = await codec.encode({
      ...payload,
      'sections': {
        ...sections,
        'channels': {
          'preferences': {channelKey: 'incomplete JSON'},
        },
      },
    }, password: '');
    final settingsPlan = await planner.inspect(
      badRadioList,
      password: '',
      appSettingsOnly: true,
    );
    expect(settingsPlan.appSettings!.values, {'theme_mode': 'dark'});
    expect(settingsPlan.channels, isNull);
  });
}
