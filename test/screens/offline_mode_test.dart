import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mco_service/mco_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show AndroidFlutterLocalNotificationsPlugin;
import 'package:provider/provider.dart';
import '../support/history_test_environment.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/review_mode/review_radio.dart';
import 'package:meshcore_open/screens/channel_chat_screen.dart';
import 'package:meshcore_open/screens/channels_screen.dart';
import 'package:meshcore_open/screens/chat_screen.dart';
import 'package:meshcore_open/screens/contacts_screen.dart';
import 'package:meshcore_open/services/app_debug_log_service.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/ble_debug_log_service.dart';
import 'package:meshcore_open/services/chat_text_scale_service.dart';
import 'package:meshcore_open/services/image_codec_service.dart';
import 'package:meshcore_open/services/map_tile_cache_service.dart';
import 'package:meshcore_open/services/message_retry_service.dart';
import 'package:meshcore_open/services/network_map/network_map_upload_service.dart';
import 'package:meshcore_open/services/path_history_service.dart';
import 'package:meshcore_open/services/received_image_store.dart';
import 'package:meshcore_open/services/storage_service.dart';
import 'package:meshcore_open/services/timeout_prediction_service.dart';
import 'package:meshcore_open/services/translation_service.dart';
import 'package:meshcore_open/services/ui_view_state_service.dart';
import 'package:meshcore_open/storage/channel_message_store.dart';
import 'package:meshcore_open/storage/channel_store.dart';
import 'package:meshcore_open/storage/contact_store.dart';
import 'package:meshcore_open/storage/last_radio_store.dart';
import 'package:meshcore_open/storage/message_store.dart';
import 'package:meshcore_open/theme/mesh_theme.dart';
import 'package:meshcore_open/widgets/offline_composer_bar.dart';
import 'package:meshcore_open/widgets/connect_sheet.dart';
import 'package:meshcore_open/widgets/offline_history_button.dart';
import 'package:meshcore_open/screens/bookmarks_screen.dart';
import 'package:meshcore_open/models/bookmarked_message.dart';
import 'package:meshcore_open/helpers/legacy_offline_access.dart';

// No private runtime or network is needed to build the contact header menu.
class _ContactMenuSections extends ChangeNotifier implements SettingsSectionsService {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #contactHeaderActionItems) {
      return <PopupMenuEntry<dynamic>>[];
    }
    if (invocation.memberName == #contactActionTiles) return <Widget>[];
    return super.noSuchMethod(invocation);
  }
}

final _radioKey = Uint8List.fromList(List<int>.generate(32, (i) => 0xA0 + i));
final _radioHex = pubKeyToHex(_radioKey);
final _aliceKey = Uint8List.fromList(List<int>.generate(32, (i) => 0x10 + i));
final _psk = Uint8List.fromList(List<int>.generate(16, (i) => 0x40 + i));

final _l10n = lookupAppLocalizations(const Locale('en'));

Future<void> _seedRadio() async {
  final alice = Contact(
    publicKey: _aliceKey,
    name: 'Alice',
    type: advTypeChat,
    pathLength: 1,
    path: Uint8List.fromList([0x22]),
    lastSeen: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  );
  await (ContactStore()..setPublicKeyHex = _radioHex).saveContacts([alice]);
  final channel = Channel(index: 0, name: 'Base Camp', psk: _psk);
  final channelStore = ChannelStore()..setPublicKeyHex = _radioHex;
  await channelStore.saveChannels([channel]);

  await (ChannelMessageStore()
        ..setPublicKeyHex = _radioHex
        ..registerChannel(channel))
      .saveChannelMessages(channel.index, [
        ChannelMessage(
          senderName: 'Bob',
          text: 'camp is up',
          timestamp: DateTime.fromMillisecondsSinceEpoch(1700000001000),
          isOutgoing: false,
          status: ChannelMessageStatus.sent,
          channelIndex: 0,
        ),
      ]);
  await (MessageStore()..setPublicKeyHex = _radioHex)
      .saveMessages(alice.publicKeyHex, [
        Message(
          senderKey: _aliceKey,
          text: 'hi there',
          timestamp: DateTime.fromMillisecondsSinceEpoch(1700000002000),
          isOutgoing: false,
          status: MessageStatus.delivered,
        ),
      ]);
  await LastRadioStore().save(
    LastRadio(
      publicKeyHex: _radioHex,
      name: 'Base',
      transport: LastRadio.transportBle,
      bleRemoteId: 'AA:BB:CC:DD:EE:FF',
      savedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    ),
  );
}

Future<Widget> _app(
  WidgetTester tester,
  MeshCoreConnector connector,
  Widget home,
) async {
  final storage = StorageService();
  final settings = await tester.runAsync(() async {
    final service = AppSettingsService();
    try {
      await service.loadSettings();
      // Header polling is covered separately; keep radio I/O in runAsync here.
      await service.updateSettings(service.settings.copyWith(
        showQuickActionsInMainHeader: false,
        showQuickActionsInChannelHeader: false,
        showQuickActionsInContactHeader: false,
      ));
      return service;
    } catch (_) {
      service.dispose();
      rethrow;
    }
  });
  if (settings == null) {
    throw StateError('Offline fixture settings initialization failed');
  }
  addTearDown(() async {
    // Widgets release polling owners and listeners before their services die,
    // including when an assertion exits the test before its explicit unmount.
    await tester.pumpWidget(const SizedBox.shrink());
    settings.dispose();
  });
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: connector),
      ChangeNotifierProvider<SettingsSectionsService>(
        create: (_) => _ContactMenuSections(),
      ),
      ChangeNotifierProvider(create: (_) => MessageRetryService()),
      ChangeNotifierProvider(create: (_) => PathHistoryService(storage)),
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider(create: (_) => BleDebugLogService()),
      ChangeNotifierProvider(create: (_) => AppDebugLogService()),
      ChangeNotifierProvider(create: (_) => ChatTextScaleService()),
      ChangeNotifierProvider(create: (_) => TranslationService(settings)),
      ChangeNotifierProvider(create: (_) => UiViewStateService()),
      Provider.value(value: storage),
      ChangeNotifierProvider(
        create: (_) => MapTileCacheService(appSettingsService: settings),
      ),
      ChangeNotifierProvider(create: (_) => TimeoutPredictionService(storage)),
      ChangeNotifierProvider(create: (_) => ImageCodecService(settings)),
      ChangeNotifierProvider(create: (_) => ReceivedImageStore()),
      ChangeNotifierProvider(
        create: (_) => NetworkMapUploadService(
          connector: connector,
          settings: settings,
        ),
      ),
    ],
    child: MaterialApp(
      theme: MeshTheme.light(),
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  int seconds = 8,
}) async {
  await tester.runAsync(() async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (!condition()) {
      if (DateTime.now().isAfter(end)) fail('Timed out waiting for condition');
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  });
}

// Construct I/O owners in the same real async zone as their store loads.
// ContactStore/ChannelStore create Future.value() write queues in constructors;
// creating those in FakeAsync and awaiting them in runAsync deadlocks until
// fake microtasks run, while the test is waiting for runAsync to return.
Future<MeshCoreConnector> _newConnector(WidgetTester tester) async {
  final connector = await tester.runAsync(() async => MeshCoreConnector());
  if (connector == null) {
    throw StateError('Offline fixture connector creation failed');
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    connector.dispose();
  });
  return connector;
}

/// Restores the seeded radio into a connector that never connects.
Future<MeshCoreConnector> _offlineConnector(WidgetTester tester) async {
  final connector = await _newConnector(tester);
  await tester.runAsync(connector.restoreLastRadio);
  expect(connector.isConnected, isFalse);
  expect(connector.channels, isNotEmpty);
  return connector;
}

PopupMenuItem<Object?> _menuItem(String label) =>
    find
            .ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
            )
            .evaluate()
            .single
            .widget
        as PopupMenuItem<Object?>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notifications = MethodChannel('dexterous.com/flutter/local_notifications');
  setUpAll(() {
    // SELF_INFO binds notifications. Test the real service with a platform
    // adapter and mocked calls, without accessing OS notification APIs.
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, (call) async {
      if (call.method == 'initialize' || call.method == 'areNotificationsEnabled') {
        return true;
      }
      return null;
    });
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, null);
  });

  final tempDir = Directory.systemTemp.createTempSync('offline_mode_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir.path,
      );

  final history = HistoryTestEnvironment();
  setUp(() async {
    await history.setUp();
    await _seedRadio();
  });
  tearDown(history.tearDown);

  for (final legacy in [false, true]) {
    testWidgets('offline entry chooses ${legacy ? "legacy picker" : "saved upstream radio"}', (tester) async {
      LegacyOfflineAccess.instance.setEnabled(legacy);
      addTearDown(() => LegacyOfflineAccess.instance.setEnabled(false));
      final connector = await _offlineConnector(tester);
      await tester.pumpWidget(await _app(tester, connector,
        Scaffold(body: OfflineHistoryButton(connector: connector))));
      await _settle(tester);
      final offline = find.widgetWithText(FilledButton, _l10n.app_offline);
      expect(tester.widget<FilledButton>(offline).onPressed, isNotNull);
      await tester.tap(offline);
      await _settle(tester);
      if (legacy) {
        expect(find.text(_l10n.app_offline_sharedMode), findsOneWidget);
        expect(find.byType(ChannelsScreen), findsNothing);
        await tester.runAsync(() async {
          await tester.tap(find.ancestor(of: find.byIcon(Icons.memory_outlined).first, matching: find.byType(ListTile)));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await _settle(tester);
      } else {
        expect(find.text(_l10n.app_offline_sharedMode), findsNothing);
      }
      expect(find.byType(ChannelsScreen), findsOneWidget);
      expect(find.text('Base Camp'), findsOneWidget);
      expect(connector.isLegacyOfflineSession, legacy);
      expect(connector.isOfflineMode, isTrue);
      Navigator.of(tester.element(find.byType(ChannelsScreen))).pop();
      await _settle(tester);
      expect(find.byType(ChannelsScreen), findsNothing);
      expect(connector.isLegacyOfflineSession, isFalse);
      expect(connector.hasRadioData, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final channelBookmark in [false, true]) {
    testWidgets('bookmark opens original ${channelBookmark ? "channel" : "DM"}; copy and remove stay independent', (tester) async {
      final connector = await _offlineConnector(tester);
      final channel = connector.channels.single;
      final contact = connector.contacts.single;
      final bookmark = channelBookmark
          ? BookmarkedMessage.fromChannel(message: connector.getChannelMessages(channel).single,
              channelId: channel.storageId!, channelName: channel.name, senderName: 'Bob')
          : BookmarkedMessage.fromContact(message: connector.getMessages(contact).first,
              contactKey: contact.publicKeyHex, contactName: contact.name, senderName: 'Alice');
      await tester.runAsync(() => connector.setBookmarkedMessage(bookmark, isBookmarked: true));
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(await _app(tester, connector, const BookmarksScreen()));
      Future<void> until(bool Function() ready) async {
        for (var i = 0; i < 100 && !ready(); i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(ready(), isTrue);
      }
      await until(() => find.byTooltip(_l10n.common_copy).evaluate().isNotEmpty);
      await tester.tap(find.byTooltip(_l10n.common_copy));
      await _settle(tester);
      expect(copied, bookmark.text);
      expect(find.byType(BookmarksScreen), findsOneWidget);
      expect(find.byType(ChatScreen), findsNothing);
      expect(find.byType(ChannelChatScreen), findsNothing);
      await tester.tap(find.byType(Card).first);
      await _settle(tester);
      if (channelBookmark) {
        expect(tester.widget<ChannelChatScreen>(find.byType(ChannelChatScreen)).initialMessageId, bookmark.messageId);
      } else {
        final chat = tester.widget<ChatScreen>(find.byType(ChatScreen));
        expect(chat.initialMessageId, bookmark.messageId);
        expect(chat.showRadioHistoryInitially, isTrue);
      }
      expect(find.text(bookmark.text), findsWidgets);
      await tester.pump(const Duration(seconds: 2));
      Navigator.of(tester.element(find.byType(channelBookmark ? ChannelChatScreen : ChatScreen))).pop();
      await _settle(tester);
      await tester.tap(find.byTooltip(_l10n.bookmarks_remove));
      await until(() => find.text(_l10n.bookmarks_empty).evaluate().isNotEmpty);
      expect(find.byType(BookmarksScreen), findsOneWidget);
      expect(find.byType(ChatScreen), findsNothing);
      expect(find.byType(ChannelChatScreen), findsNothing);
      expect(await tester.runAsync(connector.loadBookmarkedMessages), isEmpty);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Channels screen stays put offline with saved data and a '
      'Connect control', (tester) async {
    final connector = await _offlineConnector(tester);
    await tester.pumpWidget(
      await _app(tester, connector, const ChannelsScreen()),
    );
    await _settle(tester);

    expect(find.byType(ChannelsScreen), findsOneWidget);
    expect(find.text('Base Camp'), findsOneWidget);
    expect(find.byType(ConnectButton), findsOneWidget);
    expect(find.text(_l10n.appBar_offlineSubtitle('Base')), findsOneWidget);
    // Adding a channel needs the radio.
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    expect(find.text(_l10n.common_connect), findsWidgets);
    expect(find.text(_l10n.common_disconnect), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Contacts screen stays put offline and disables radio actions', (
    tester,
  ) async {
    final connector = await _offlineConnector(tester);
    await tester.pumpWidget(
      await _app(tester, connector, const ContactsScreen()),
    );
    await _settle(tester);

    expect(find.byType(ContactsScreen), findsOneWidget);
    expect(find.text('Alice'), findsWidgets);
    expect(find.byType(ConnectButton), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    expect(find.text(_l10n.contacts_floodAdvert), findsNothing);
    expect(find.text(_l10n.contacts_zeroHopAdvert), findsNothing);
    expect(find.text(_l10n.contacts_addContactFromClipboard), findsNothing);
    expect(_menuItem(_l10n.common_connect).enabled, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Channel chat offline is read-only', (tester) async {
    final connector = await _offlineConnector(tester);
    await tester.pumpWidget(
      await _app(
        tester,
        connector,
        ChannelChatScreen(channel: connector.channels.single),
      ),
    );
    await _settle(tester);

    expect(find.textContaining('camp is up'), findsWidgets);
    expect(find.byType(OfflineComposerBar), findsOneWidget);
    expect(find.text(_l10n.chat_composerOffline), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ConnectButton), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    expect(find.text(_l10n.channels_editChannel), findsNothing);
    expect(find.text(_l10n.contact_clearChat), findsNothing);
    expect(find.text(_l10n.channels_deleteChannel), findsNothing);
    // Per-device preferences stay available.

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('DM chat offline is read-only', (tester) async {
    final connector = await _offlineConnector(tester);
    final alice = connector.contacts.single;
    await tester.pumpWidget(
      await _app(tester, connector, ChatScreen(contact: alice)),
    );
    await _settle(tester);

    expect(find.textContaining('hi there'), findsWidgets);
    expect(find.byType(OfflineComposerBar), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    expect(find.text(_l10n.contact_clearChat), findsNothing);
    expect(find.text(_l10n.contact_telemetry), findsNothing);
    expect(find.text(_l10n.contact_info), findsNothing);
    expect(_menuItem(_l10n.chat_searchMessages).enabled, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a draft typed while connected survives a disconnect and '
      'reconnect', (tester) async {
    final connector = await _newConnector(tester);
    connector.reviewRadioFactoryForTest = () => ReviewRadio(
      scheduledMessageInterval: const Duration(hours: 1),
      ackDelay: const Duration(hours: 1),
      replyDelay: const Duration(hours: 1),
    );
    await tester.runAsync(connector.connectReview);
    await _waitFor(tester, () => connector.contacts.isNotEmpty);
    final contact = connector.contacts.firstWhere((c) => c.type == advTypeChat);

    await tester.pumpWidget(
      await _app(tester, connector, ChatScreen(contact: contact)),
    );
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'half written');
    await _settle(tester);

    await tester.runAsync(connector.disconnect);
    // Connector notifications are debounced on a real timer.
    await _waitFor(tester, () => !connector.isConnected);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await _settle(tester);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.byType(OfflineComposerBar), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.runAsync(connector.connectReview);
    await _waitFor(tester, () => connector.isConnected);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await _settle(tester);
    expect(find.byType(OfflineComposerBar), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'half written');

    await tester.runAsync(connector.disconnect);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });
}
