import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/channel_identity_store.dart';
import 'package:meshcore_open/storage/channel_settings_store.dart';
import 'package:meshcore_open/storage/contact_settings_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';

const _nodeA = 'aaaaaaaaaa000000000000000000000000000000000000000000000000000000';
const _nodeB = 'bbbbbbbbbb000000000000000000000000000000000000000000000000000000';
const _contact = 'cccccccccc000000000000000000000000000000000000000000000000000000';
const _other = 'dddddddddd000000000000000000000000000000000000000000000000000000';

class _NoPaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async =>
      throw MissingPluginException('synthetic URL choices');
}

class _Settings extends AppSettingsService {
  AppSettings value = AppSettings();
  @override
  AppSettings get settings => value;
  void showByDefault(bool enabled) {
    value = value.copyWith(showLinkImagesByDefault: enabled);
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PathProviderPlatform previousPaths;
  setUp(() async {
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPaths();
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    ChannelIdentities.instance.resetForTesting();
    await ChannelIdentities.instance.load();
  });
  tearDown(() {
    ChannelIdentities.instance.resetForTesting();
    PathProviderPlatform.instance = previousPaths;
    PrefsManager.reset();
  });

  test('nullable choice readers preserve old bool loaders and explicit off', () async {
    final channels = ChannelSettingsStore()..setPublicKeyHex = _nodeA;
    channels.replaceChannels([
      Channel(index: 0, name: 'Example', psk: Uint8List.fromList(List.filled(16, 1))),
    ]);
    final contacts = ContactSettingsStore()..setPublicKeyHex = _nodeA;
    expect(await channels.loadUrlImagesChoice(0), isNull);
    expect(await contacts.loadUrlImagesChoice(_contact), isNull);
    expect(await channels.loadUrlImagesEnabled(0), isFalse);
    expect(await contacts.loadUrlImagesEnabled(_contact), isFalse);
    expect(contacts.readSettings(_contact)!.urlImagesChoice, isNull);
    await channels.saveUrlImagesEnabled(0, false);
    await contacts.saveUrlImagesEnabled(_contact, false);
    expect(await channels.loadUrlImagesChoice(0), isFalse);
    expect(await contacts.loadUrlImagesChoice(_contact), isFalse);
    expect(contacts.readSettings(_contact)!.urlImagesChoice, isFalse);
  });

  testWidgets('live default keeps explicit contact choices and rebinds node scope', (tester) async {
    final settings = _Settings();
    final connector = MeshCoreConnector();
    var connectorDisposed = false;
    addTearDown(() {
      if (!connectorDisposed) connector.dispose();
      settings.dispose();
    });
    // Attach only settings; native notification/BLE initialization is outside
    // this test. The normal sync snapshot cache and UI batcher remain real.
    connector.attachAppSettingsServiceForTest(settings);
    connector.bindContactSettingsToNodeForTest(_nodeA);
    final a = ContactSettingsStore()..setPublicKeyHex = _nodeA;
    final b = ContactSettingsStore()..setPublicKeyHex = _nodeB;
    await a.saveUrlImagesEnabled(_contact, false);
    await b.saveUrlImagesEnabled(_contact, true);
    final savedKeys = PrefsManager.instance.getKeys();
    var notifications = 0;
    connector.addListener(() => notifications++);
    expect(connector.isContactUrlImagesEnabled(_other), isFalse);
    expect(connector.isChannelUrlImagesEnabled(0), isFalse);
    settings.showByDefault(true);
    await tester.pump(const Duration(milliseconds: 60));
    expect(notifications, greaterThan(0));
    expect(connector.isChannelUrlImagesEnabled(0), isTrue);
    expect(connector.isContactUrlImagesEnabled(_other), isTrue);
    expect(connector.isContactUrlImagesEnabled(_contact), isFalse);
    for (var i = 0; i < 100; i++) {
      expect(connector.isContactUrlImagesEnabled(_other), isTrue);
    }
    expect(PrefsManager.instance.getKeys(), savedKeys);
    connector.bindContactSettingsToNodeForTest(_nodeB);
    settings.showByDefault(false);
    await tester.pump(const Duration(milliseconds: 60));
    expect(connector.isContactUrlImagesEnabled(_contact), isTrue);
    expect(connector.isContactUrlImagesEnabled(_other), isFalse);
    connector.dispose();
    connectorDisposed = true;
    // The settings publisher must not call the disposed connector.
    settings.showByDefault(true);
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.takeException(), isNull);
  });
}
