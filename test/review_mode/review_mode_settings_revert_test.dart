import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/review_mode/review_mode_storage.dart';
import 'package:meshcore_open/storage/channel_identity_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';

class _NoDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('Synthetic preferences without a directory');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PathProviderPlatform paths;
  late AppSettingsService settings;
  setUpAll(() {
    paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoDirectory();
  });
  tearDownAll(() => PathProviderPlatform.instance = paths);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    ChannelIdentities.instance.resetForTesting();
    settings = AppSettingsService();
  });
  tearDown(() async {
    await endReviewModeSession(settings);
    settings.dispose();
    ChannelIdentities.instance.resetForTesting();
    PrefsManager.reset();
  });

  test('selecting All clears an inherited restriction and mode changes are exclusive', () async {
    await settings.muteChannel('Before');
    expect(settings.getChannelNotificationMode('After'), ChannelNotificationMode.all);
    await ChannelIdentities.instance.link(
      const ChannelIdentity('synthetic-key', 'Before'),
      const ChannelIdentity('synthetic-key', 'After'),
    );
    expect(settings.getChannelNotificationMode('After'), ChannelNotificationMode.mentionsOnly);
    await settings.setChannelNotificationMode('After', ChannelNotificationMode.muted);
    expect(settings.settings.mutedChannels, isEmpty);
    expect(settings.getChannelNotificationMode('Before'), ChannelNotificationMode.muted);
    await settings.unmuteChannel('After');
    expect(settings.getChannelNotificationMode('Before'), ChannelNotificationMode.all);
    expect(settings.settings.silencedChannels, isEmpty);
  });

  test('review restores both restrictions, retaining the first interrupted snapshot', () async {
    await settings.muteChannel('Mentions');
    await settings.setChannelNotificationMode('Silent', ChannelNotificationMode.muted);
    await beginReviewModeSession(settings);
    await settings.unmuteChannel('Mentions');
    await settings.unmuteChannel('Silent');
    await settings.setChannelNotificationMode('Temporary', ChannelNotificationMode.muted);
    await beginReviewModeSession(settings);
    await endReviewModeSession(settings);
    expect(settings.getChannelNotificationMode('Mentions'), ChannelNotificationMode.mentionsOnly);
    expect(settings.getChannelNotificationMode('Silent'), ChannelNotificationMode.muted);
    expect(settings.getChannelNotificationMode('Temporary'), ChannelNotificationMode.all);
    await endReviewModeSession(settings);
    expect(settings.getChannelNotificationMode('Silent'), ChannelNotificationMode.muted);
  });

  test('old interrupted review snapshot restores its original mentions exception', () async {
    await PrefsManager.instance.setStringList('review_mode_saved_muted_channels', ['Old']);
    await settings.muteChannel('Temporary');
    await endReviewModeSession(settings);
    expect(settings.getChannelNotificationMode('Old'), ChannelNotificationMode.mentionsOnly);
    expect(settings.getChannelNotificationMode('Temporary'), ChannelNotificationMode.all);
  });
}
