import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/theme_image_codec.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/chat_background.dart';
import 'package:meshcore_open/models/custom_theme.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/chat_background_image_store.dart';
import 'package:meshcore_open/services/chat_background_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _contact = 'contact:abc';
const _local = ChatBackground.color(Color(0xFF604080));
const _themeBackground = ChatBackground.color(Color(0xFF105070));
const _theme = CustomTheme(
  id: 'custom:ocean',
  name: 'Ocean',
  background: Color(0xFF102031),
  accent: Color(0xFF55BBDD),
  chatBackground: _themeBackground,
);

class _TrackingStore extends InMemoryChatBackgroundImageStore {
  int reads = 0;
  int scans = 0;

  @override
  Future<Uint8List?> read(String id) {
    reads++;
    return super.read(id);
  }

  @override
  Future<Set<String>> listIds() {
    scans++;
    return super.listIds();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppSettingsService settings;
  late _TrackingStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    settings = AppSettingsService();
    await settings.loadSettings();
    store = _TrackingStore();
    addTearDown(settings.dispose);
  });

  tearDown(PrefsManager.reset);

  ChatBackgroundService open() {
    final service = ChatBackgroundService(
      settings,
      imageStore: store,
      encodeImage: (bytes) async => bytes,
    );
    addTearDown(service.dispose);
    return service;
  }

  test('U19b: a theme can supply or override a saved per-chat background', () async {
    final service = open();
    await service.setChatBackground(_contact, _local);
    await settings.saveCustomTheme(_theme, apply: true);
    expect(service.resolve(_contact), _local);
    expect(service.resolve('contact:other'), _themeBackground);

    await settings.saveCustomTheme(_theme.copyWith(chatBackgroundEverywhere: true));
    expect(service.resolve(_contact), _themeBackground);
    expect(service.chatBackground(_contact), _local);

    await settings.setThemeMode('light');
    expect(service.resolve(_contact), _local);
    expect(service.resolve('contact:other'), isNull);
    expect(open().chatBackground(_contact), _local);
    expect(store.reads, 0);
    expect(store.scans, 0);
  });

  test('U19b: a background follows the channel key across slots and renames', () async {
    final service = open();
    final channel = Channel.fromHex(1, 'Before', '01' * 16);
    final moved = Channel.fromHex(8, 'After', '01' * 16);
    final replacement = Channel.fromHex(1, 'Before', '02' * 16);
    final key = ChatBackgroundService.channelKey(channel);
    await service.setChatBackground(key, _local);

    expect(service.resolve(ChatBackgroundService.channelKey(moved)), _local);
    expect(service.resolve(ChatBackgroundService.channelKey(replacement)), isNull);
    final placeholder = ChatBackgroundService.channelKey(Channel.empty(1));
    expect(placeholder, isEmpty);
    await expectLater(
      service.setChatBackground(placeholder, _local),
      throwsArgumentError,
    );
  });

  test('U19b: photos load on demand and concurrent lookups share a read', () async {
    final service = open();
    final bytes = Uint8List.fromList([1, 2, 3]);
    final id = (await service.addImage(bytes))!;
    await service.setChatBackground(_contact, ChatBackground.image(id));
    final reopened = open();
    expect(reopened.resolve(_contact)?.imageId, id);
    expect(store.reads, 0);

    final loaded = Future<void>.delayed(Duration.zero);
    expect(reopened.imageBytes(id), isNull);
    expect(reopened.imageBytes(id), isNull);
    await loaded;
    expect(reopened.imageBytes(id), bytes);
    expect(store.reads, 1);
    expect(store.scans, 0);
  });

  test('U19b: local PNG artwork becomes a readable JPEG XL icon', () async {
    final recorder = PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 256, 128),
      Paint()..color = const Color(0x807733CC),
    );
    final picture = recorder.endRecording();
    addTearDown(picture.dispose);
    final source = await picture.toImage(256, 128);
    addTearDown(source.dispose);
    final png = (await source.toByteData(format: ImageByteFormat.png))!;

    final icon = await shrinkThemeIconImage(png.buffer.asUint8List());
    expect(icon, isNotNull);
    final decoded = await decodeThemePicture(icon!, 128);
    addTearDown(decoded.dispose);
    expect((decoded.width, decoded.height), (128, 64));
  });

  test('U19b: cleanup preserves drafts and references shared by a theme', () async {
    final service = open();
    final bytes = Uint8List.fromList([1, 2, 3]);
    final inline = _themeBackground.withInlineImage(bytes);
    final prepared = await service.storeThemeImages(
      _theme.copyWith(chatBackground: inline),
    );
    final id = prepared.chatBackground!.imageId!;
    expect(prepared.chatBackground!.inlineImage, isNull);
    await service.collectGarbage();
    expect(store.images[id], bytes);

    await settings.saveCustomTheme(prepared, apply: true);
    final exported = await service.embedThemeImages(prepared);
    expect(exported.chatBackground!.inlineImage, bytes);

    await service.setChatBackground(_contact, ChatBackground.image(id));
    await service.setChatBackground(_contact, null);
    await service.collectGarbage();
    expect(store.images[id], bytes);

    await settings.deleteCustomTheme(prepared.id);
    await service.collectGarbage();
    expect(store.images, isEmpty);
  });
}
