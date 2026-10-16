import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';

// Preserve the current bookmark rules before merging the SSID extension.
void main() {
  setUp(() async {
    PrefsManager.reset();
    SharedPreferences.setMockInitialValues({});
    await PrefsManager.initialize();
  });

  test('reconnecting keeps endpoint identity and bookmark details', () async {
    final service = AppSettingsService();
    addTearDown(service.dispose);
    await service.recordTcpConnection(' mesh.local ', 5000);
    await service.setTcpConnectionBookmarkDetails(
      service.settings.tcpConnectionBookmarks.single,
      name: ' Home node ',
      isFavorite: true,
    );
    await service.recordTcpConnection('MESH.local', 5000);

    final bookmark = service.settings.tcpConnectionBookmarks.single;
    expect(bookmark.host, 'MESH.local');
    expect(bookmark.port, 5000);
    expect(bookmark.name, 'Home node');
    expect(bookmark.isFavorite, isTrue);

    final reloaded = AppSettingsService();
    addTearDown(reloaded.dispose);
    await reloaded.loadSettings();
    expect(reloaded.settings.tcpServerAddress, 'MESH.local');
    expect(reloaded.settings.tcpServerPort, 5000);
    expect(
      reloaded.settings.tcpConnectionBookmarks.single.toJson(),
      bookmark.toJson(),
    );
  });

  test('bookmark cap evicts an old non-favorite before a favorite', () async {
    final service = AppSettingsService();
    addTearDown(service.dispose);
    final old = DateTime.utc(2026, 1, 1);
    await service.updateSettings(
      AppSettings(
        tcpConnectionBookmarks: [
          TcpConnectionBookmark(
            host: 'favorite.local',
            port: 5000,
            lastConnectedAt: old,
            isFavorite: true,
          ),
          for (var i = 1; i <= 4; i++)
            TcpConnectionBookmark(
              host: 'node$i.local',
              port: 5000,
              lastConnectedAt: old.add(Duration(days: i)),
            ),
        ],
      ),
    );

    await service.recordTcpConnection('new.local', 5000);
    final bookmarks = service.settings.tcpConnectionBookmarks;
    expect(bookmarks, hasLength(5));
    expect(bookmarks.first.host, 'favorite.local');
    expect(bookmarks.map((item) => item.host), contains('new.local'));
    expect(bookmarks.map((item) => item.host), isNot(contains('node1.local')));
  });

  test('legacy bookmark JSON and unrelated copies keep endpoint metadata', () {
    final bookmark = TcpConnectionBookmark.fromJson({
      'host': 'mesh.local',
      'port': 5000,
      'name': 'Home',
      'is_favorite': true,
      'last_connected_at': '2026-01-01T00:00:00.000Z',
    });
    final settings = AppSettings(tcpConnectionBookmarks: [bookmark]);
    expect(bookmark.wifiSsid, isEmpty);
    final copied = settings.copyWith(tcpServerPort: 6000);
    final decoded = AppSettings.fromJson(copied.toJson());
    expect(decoded.tcpConnectionBookmarks.single.toJson(), bookmark.toJson());
    expect(decoded.tcpServerPort, 6000);
  });

  test('background TCP defaults on without overriding an explicit opt-out', () {
    expect(AppSettings().backgroundTcpEnabled, isTrue);
    expect(AppSettings.fromJson({}).backgroundTcpEnabled, isTrue);
    final saved = AppSettings.fromJson({'background_tcp_enabled': false});
    expect(AppSettings.fromJson(saved.toJson()).backgroundTcpEnabled, isFalse);
  });

  test('SSID survives persistence, reconnect and a name-only edit', () async {
    final service = AppSettingsService();
    addTearDown(service.dispose);
    await service.recordTcpConnection(
      ' mesh.local ',
      5000,
      wifiSsid: ' Mesh Wi-Fi ',
    );
    expect(service.settings.tcpServerWifiSsid, 'Mesh Wi-Fi');
    expect(service.settings.tcpConnectionBookmarks.single.wifiSsid, 'Mesh Wi-Fi');

    // Existing callers without the new argument must not erase bookmark SSIDs.
    await service.recordTcpConnection('MESH.local', 5000);
    await service.setTcpConnectionBookmarkName(
      service.settings.tcpConnectionBookmarks.single,
      'Renamed',
    );
    final reloaded = AppSettingsService();
    addTearDown(reloaded.dispose);
    await reloaded.loadSettings();
    final bookmark = reloaded.settings.tcpConnectionBookmarks.single;
    expect(bookmark.wifiSsid, 'Mesh Wi-Fi');
    expect(bookmark.name, 'Renamed');
  });

  test('SSID edit is scoped to its endpoint and survives settings copies', () async {
    final service = AppSettingsService();
    addTearDown(service.dispose);
    await service.recordTcpConnection('first.local', 5000, wifiSsid: 'First');
    await service.recordTcpConnection('second.local', 5000, wifiSsid: 'Second');
    final first = service.settings.tcpConnectionBookmarks.firstWhere(
      (bookmark) => bookmark.host == 'first.local',
    );
    await service.setTcpConnectionBookmarkDetails(
      first,
      name: 'First node',
      isFavorite: true,
      wifiSsid: ' Updated Wi-Fi ',
    );
    final settings = AppSettings.fromJson(
      service.settings.copyWith(jumpToOldestUnread: true).toJson(),
    );
    expect(settings.tcpServerWifiSsid, 'Second');
    expect(settings.tcpConnectionBookmarks.first.wifiSsid, 'Updated Wi-Fi');
    expect(settings.tcpConnectionBookmarks.last.wifiSsid, 'Second');
  });
}
