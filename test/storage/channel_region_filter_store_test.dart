import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/backup_channel_settings.dart';
import 'package:meshcore_open/helpers/channel_region_filter.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/storage/backup_channel_settings_store.dart';
import 'package:meshcore_open/storage/channel_region_filter_store.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('filter store and backup read SQL, preserve explicit reset and map channel IDs', () async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    final history = MessageHistoryStorage.instance;
    await history.resetForTesting();
    await history.initializeAndMigrate(databaseFactory: () =>
      MessageHistoryDatabase.withExecutor(NativeDatabase.memory()));
    addTearDown(() async {
      await history.resetForTesting();
      PrefsManager.reset();
    });
    const scope = 'ababababab';
    final channel = Channel.fromHex(3, 'North', Channel.publicChannelPsk);
    final id = channel.storageId!;
    final store = ChannelRegionFilterStore();
    expect(await store.read(scope, id), isNull);
    await store.write(scope, id, {'north', ChannelRegionFilter.unknown});
    expect(ChannelRegionFilter.decode(await ChannelRegionFilterStore().read(scope, id)),
      {'north', ChannelRegionFilter.unknown});
    final moved = Channel.fromHex(9, 'Renamed', Channel.publicChannelPsk);
    final backups = BackupChannelSettingsStore(scope, [moved]);
    final bindings = backupChannelBindings([moved]);
    expect(await backups.readRegionFilters(bindings.values), {
      (id, BackupChannelOption.hiddenRegions): '["!unknown","north"]',
    });
    await store.write(scope, id, {});
    expect(await backups.writeIfMissing((bindings[id]!, BackupChannelOption.hiddenRegions),
      '["south"]'), isFalse);
    expect(await store.read(scope, id), '[]');
    expect(await backups.readRegionFilters(bindings.values), {
      (id, BackupChannelOption.hiddenRegions): '[]',
    });
    expect(PrefsManager.instance.getKeys().where((key) => key.startsWith('channel_region_filter:')), isEmpty);
  });
}
