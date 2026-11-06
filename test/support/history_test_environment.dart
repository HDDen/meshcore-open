import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:meshcore_open/storage/channel_identity_store.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real history stores over a fresh SQLite database, with no user directories.
/// Call setup/teardown outside testWidgets' FakeAsync zone.
class HistoryTestEnvironment {
  PathProviderPlatform? _previousPaths;

  Future<void> setUp() async {
    _previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoUserDirectories();
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    await MessageHistoryStorage.instance.resetForTesting();
    await MessageHistoryStorage.instance.initializeAndMigrate(
      databaseFactory: () =>
          MessageHistoryDatabase.withExecutor(NativeDatabase.memory()),
    );
    ChannelIdentities.instance.resetForTesting();
    await ChannelIdentities.instance.load();
  }

  Future<void> tearDown() async {
    try {
      ChannelIdentities.instance.resetForTesting();
      await MessageHistoryStorage.instance.resetForTesting();
      PrefsManager.reset();
    } finally {
      final previous = _previousPaths;
      if (previous != null) PathProviderPlatform.instance = previous;
      _previousPaths = null;
    }
  }
}

class _NoUserDirectories extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async =>
      throw MissingPluginException('In-memory test history has no directory');
}
