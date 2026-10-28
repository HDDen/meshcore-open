import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_group_helper.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/channel_group.dart';
import 'package:meshcore_open/storage/channel_group_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Проверяем хранилище порядка/настройку до добавления служебной строки в UI.
// Это не widget-тест ещё не реализованного закрепления или drag-and-drop.
const _serviceKey = 'service:companion-cli';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final nodeA = '01' * 32;
  final nodeB = '02' * 32;
  final peer = 'ab' * 32;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  test('baseline: opaque service order survives peer normalization without reordering channels', () {
    expect(normalizeChannelScreenOrderForPeers([
      'channel:2', _serviceKey, 'room:$peer', 'contact:${peer.toUpperCase()}',
      'channel:1', _serviceKey,
    ]), ['channel:2', _serviceKey, 'peer:$peer', 'channel:1']);
  });

  test('baseline: manual screen order reloads per node and keeps groups unchanged', () async {
    final a = ChannelGroupStore()..setPublicKeyHex = nodeA;
    final b = ChannelGroupStore()..setPublicKeyHex = nodeB;
    const group = ChannelGroup(name: 'Synthetic group', channelNames: ['Alpha'], sortOrder: 2);
    await a.saveGroups([group]);
    await a.saveScreenOrder(['channel:2', _serviceKey, 'group:synthetic group', 'channel:1']);
    await b.saveScreenOrder([_serviceKey, 'channel:3']);

    final reloadedA = ChannelGroupStore()..setPublicKeyHex = nodeA;
    expect(await reloadedA.loadScreenOrder(),
      ['channel:2', _serviceKey, 'group:synthetic group', 'channel:1']);
    expect(await b.loadScreenOrder(), [_serviceKey, 'channel:3']);
    expect((await reloadedA.loadGroups()).single.toJson(), group.toJson());
    expect(await b.loadGroups(), isEmpty);
  });

  test('baseline: channels contact visibility and legacy sorting are independent settings', () {
    final settings = AppSettings().copyWith(
      roomServerShowNotemptyContactsOnChatscreen: true,
      roomServerDisableRoomAndContactsSorting: true,
    );
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.roomServerShowNotemptyContactsOnChatscreen, isTrue);
    expect(restored.roomServerDisableRoomAndContactsSorting, isTrue);
    expect(restored.copyWith(roomServerShowNotemptyContactsOnChatscreen: false)
      .roomServerDisableRoomAndContactsSorting, isTrue);
  });
}
