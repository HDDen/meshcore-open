import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/screens/channel_chat_screen.dart';
import 'package:meshcore_open/screens/chat_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/chat_text_scale_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/message_search_sheet.dart';
import 'package:meshcore_open/widgets/swipe_reply_bubble.dart';
import 'package:meshcore_open/widgets/tx_power_boost_badge.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _time = DateTime.utc(2026, 1, 1, 12);
final _contact = Contact(
  publicKey: Uint8List(32)..[0] = 42,
  name: 'Alice',
  type: advTypeChat,
  pathLength: -1,
  path: Uint8List(0),
  lastSeen: _time,
);
final _channel = Channel.fromHex(0, 'Test channel', Channel.publicChannelPsk);
const _olderText = 'Result from an older page';
const _olderId = 'older';

Message _directPost(String id, String text, int seconds) => Message(
  messageId: id,
  senderKey: _contact.publicKey,
  text: text,
  timestamp: _time.add(Duration(seconds: seconds)),
  receivedAt: _time.add(Duration(seconds: seconds)),
  isOutgoing: false,
  status: MessageStatus.delivered,
);

ChannelMessage _channelPost(String id, String text, int seconds) =>
    ChannelMessage(
      messageId: id,
      channelIndex: _channel.index,
      senderName: _contact.name,
      text: text,
      timestamp: _time.add(Duration(seconds: seconds)),
      receivedAt: _time.add(Duration(seconds: seconds)),
      isOutgoing: false,
      status: ChannelMessageStatus.sent,
    );

class _PagedNode extends MeshCoreConnector {
  _PagedNode() {
    setChannelMessagesForTest(_channel.index, _recentChannel);
  }

  final _recentDirect = [
    for (var i = 1; i <= 16; i++) _directPost('direct-$i', 'Recent post $i', i),
  ];
  final _recentChannel = [
    for (var i = 1; i <= 16; i++) _channelPost('channel-$i', 'Recent post $i', i),
  ];
  bool pageAvailable = false;
  int olderPagesLoaded = 0;
  Object? loadedScope;
  bool Function()? routeIsCurrent;
  int activations = 0;

  @override
  bool get isConnected => true;

  @override
  List<Message> getMessages(Contact contact) => _recentDirect;

  @override
  void setActiveContact(String? contactKeyHex) {
    if (contactKeyHex != null) activations++;
  }

  @override
  void setActiveChannel(int? channelIndex) {
    if (channelIndex != null) activations++;
  }

  @override
  VoidCallback trackContactChatRoute(String contactKeyHex, bool Function() isCurrent) {
    routeIsCurrent = isCurrent;
    return super.trackContactChatRoute(contactKeyHex, isCurrent);
  }

  @override
  VoidCallback trackChannelChatRoute(int channelIndex, bool Function() isCurrent) {
    routeIsCurrent = isCurrent;
    return super.trackChannelChatRoute(channelIndex, isCurrent);
  }

  @override
  Future<List<Message>> loadOlderMessages(String contactKeyHex, {
    int count = 50,
  }) async {
    if (!pageAvailable) return [];
    loadedScope = contactKeyHex;
    pageAvailable = false;
    olderPagesLoaded++;
    final older = _directPost(_olderId, _olderText, 0);
    _recentDirect.insert(0, older);
    notifyListeners();
    return [older];
  }

  @override
  Future<List<ChannelMessage>> loadOlderChannelMessages(int channelIndex, {
    int count = 50,
  }) async {
    if (!pageAvailable) return [];
    loadedScope = channelIndex;
    pageAvailable = false;
    olderPagesLoaded++;
    final older = _channelPost(_olderId, _olderText, 0);
    _recentChannel.insert(0, older);
    setChannelMessagesForTest(channelIndex, _recentChannel);
    notifyListeners();
    return [older];
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  for (final inChannel in [false, true]) {
    final scope = inChannel ? 'channel' : 'contact';
    testWidgets('TX power boost appears after send details in the $scope bubble',
        (tester) async {
      final node = _PagedNode();
      final settings = AppSettingsService();
      final scale = ChatTextScaleService();
      addTearDown(node.dispose);
      addTearDown(settings.dispose);
      addTearDown(scale.dispose);

      const boostedText = 'Outgoing message sent with a power boost';
      const regularText = 'Outgoing message sent with normal power';
      if (inChannel) {
        node.setChannelMessagesForTest(_channel.index, [
          _channelPost('normal', regularText, 1).copyWith(isOutgoing: true),
          _channelPost('boosted', boostedText, 2).copyWith(
            isOutgoing: true,
            resendCount: 2,
            sentWithTxPowerBoost: true,
          ),
        ]);
      } else {
        node._recentDirect
          ..clear()
          ..addAll([
            _directPost('normal', regularText, 1).copyWith(isOutgoing: true),
            _directPost('boosted', boostedText, 2).copyWith(
              isOutgoing: true,
              tripTimeMs: 1200,
              sentWithTxPowerBoost: true,
            ),
          ]);
      }

      await settings.updateSettings(
        settings.settings.copyWith(enableMessageTracing: true),
      );
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<MeshCoreConnector>.value(value: node),
          ChangeNotifierProvider<AppSettingsService>.value(value: settings),
          ChangeNotifierProvider<ChatTextScaleService>.value(value: scale),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: inChannel
              ? ChannelChatScreen(channel: _channel)
              : ChatScreen(contact: _contact),
        ),
      ));
      await tester.pumpAndSettle();

      final badge = find.byType(TxPowerBoostBadge);
      expect(badge, findsOneWidget);
      expect(find.byTooltip('Sent with boosted TX power'), findsOneWidget);
      final metadata = tester.element(badge).findAncestorWidgetOfExactType<Wrap>()!;
      final previous = metadata.children.indexWhere(
        (widget) => widget is Text && widget.data == (inChannel ? '3' : '1.2s'),
      );
      expect(previous, isNonNegative);
      expect(metadata.children.indexWhere((widget) => widget is TxPowerBoostBadge),
        greaterThan(previous));

      await settings.updateSettings(
        settings.settings.copyWith(enableMessageTracing: false),
      );
      await tester.pumpAndSettle();
      expect(badge, findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });
    testWidgets('U34 baseline: search opens and pages to an old $scope message', (
      tester,
    ) async {
      final node = _PagedNode();
      final settings = AppSettingsService();
      final scale = ChatTextScaleService();
      addTearDown(node.dispose);
      addTearDown(settings.dispose);
      addTearDown(scale.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MeshCoreConnector>.value(value: node),
            ChangeNotifierProvider<AppSettingsService>.value(value: settings),
            ChangeNotifierProvider<ChatTextScaleService>.value(value: scale),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: inChannel
                ? ChannelChatScreen(channel: _channel)
                : ChatScreen(contact: _contact),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(node.routeIsCurrent?.call(), isTrue);

      final appBar = find.byType(AppBar);
      final l10n = AppLocalizations.of(tester.element(appBar));
      await tester.tap(find.descendant(
        of: appBar,
        matching: find.byType(PopupMenuButton<String>),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.chat_searchMessages));
      await tester.pumpAndSettle();
      final sheetFinder = find.byType(MessageSearchSheet);
      final sheet = tester.widget<MessageSearchSheet>(sheetFinder);
      expect(node.routeIsCurrent?.call(), isFalse);
      final beforeReturn = node.activations;
      expect(sheet.channelFilter, inChannel ? same(_channel) : isNull);
      expect(sheet.contactFilter, inChannel ? isNull : same(_contact));
      final older = find.text(_olderText, findRichText: true).hitTestable();
      expect(older, findsNothing);

      // Exercise the sheet's real result callback with a synthetic search hit.
      // Storage and search-worker tests cover how the hit is produced.
      node.pageAvailable = true;
      var completed = false;
      final opened = sheet.onOpenResult(MessageSearchResult(
        type: inChannel ? MessageSearchEntryType.channel : MessageSearchEntryType.contact,
        channel: inChannel ? _channel : null,
        contact: inChannel ? null : _contact,
        messageId: _olderId,
        timestamp: _time,
        senderName: _contact.name,
        text: _olderText,
        dedupeKey: _olderId,
        sourceId: scope,
      )).then((_) => completed = true);
      for (var i = 0; i < 30 && !completed; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(completed, isTrue);
      await opened;
      await tester.pumpAndSettle();
      expect(node.olderPagesLoaded, 1);
      expect(node.loadedScope, inChannel ? _channel.index : _contact.publicKeyHex);
      expect(sheetFinder, findsNothing);
      expect(older, findsOneWidget);
      expect(node.routeIsCurrent?.call(), isTrue);
      expect(node.activations, greaterThan(beforeReturn));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });
  }

  testWidgets('U34 baseline: a deliberate left swipe replies once', (tester) async {
    var replies = 0;
    const target = ValueKey('message');
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: SwipeReplyBubble(
        onReply: () => replies++,
        child: const ColoredBox(
          key: target,
          color: Colors.blue,
          child: SizedBox(width: 240, height: 60),
        ),
      ))),
    ));
    final start = tester.getCenter(find.byKey(target));
    final short = await tester.startGesture(start);
    await short.moveBy(const Offset(-30, 0));
    await short.up();
    await tester.pumpAndSettle();
    expect(replies, 0);

    final cancelled = await tester.startGesture(start);
    await cancelled.moveBy(const Offset(-80, 0));
    await cancelled.cancel();
    await tester.pumpAndSettle();
    expect(replies, 0);

    final swipe = await tester.startGesture(start);
    await swipe.moveBy(const Offset(-80, 0));
    await swipe.up();
    await tester.pumpAndSettle();
    expect(replies, 1);
  });

  testWidgets('U34: vertical scrolling and late vertical drift do not reply', (tester) async {
    var replies = 0;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    const target = ValueKey('message');
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ListView(
        controller: scroll,
        children: [
          const SizedBox(height: 100),
          SwipeReplyBubble(
            onReply: () => replies++,
            child: const ColoredBox(
              key: target,
              color: Colors.blue,
              child: SizedBox(height: 64),
            ),
          ),
          const SizedBox(height: 1400),
        ],
      )),
    ));

    final scrollThenDrift = await tester.startGesture(tester.getCenter(find.byKey(target)));
    await scrollThenDrift.moveBy(const Offset(0, -35));
    await scrollThenDrift.moveBy(const Offset(-85, -50));
    await scrollThenDrift.up();
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(replies, 0);

    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    final swipeThenScroll = await tester.startGesture(tester.getCenter(find.byKey(target)));
    await swipeThenScroll.moveBy(const Offset(-80, 0));
    await swipeThenScroll.moveBy(const Offset(0, -110));
    await swipeThenScroll.up();
    await tester.pumpAndSettle();
    expect(replies, 0);
  });
}
