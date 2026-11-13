import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/helpers/contact_share_helper.dart';
import 'package:meshcore_open/helpers/mcotxt_app_codec.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/additional_identity_message.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/screens/additional_identity_chat_screen.dart';
import 'package:meshcore_open/screens/channel_chat_screen.dart';
import 'package:meshcore_open/screens/chat_screen.dart';
import 'package:meshcore_open/services/additional_identity_inbox.dart';
import 'package:meshcore_open/services/additional_identity_vault.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/chat_text_scale_service.dart';
import 'package:meshcore_open/services/ui_view_state_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/byte_count_input.dart';
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
  _PagedNode({super.additionalIdentityInbox}) {
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

class _ContactShareNode extends _PagedNode {
  _ContactShareNode(AdditionalIdentityInbox inbox)
    : super(additionalIdentityInbox: inbox);

  List<Contact> contactList = [_contact];

  @override
  List<Contact> get contacts => contactList;

  @override
  bool get hasLoadedContacts => true;
}

class _SenderPickerInbox extends AdditionalIdentityInbox {
  final selections = <String, String>{};
  List<AdditionalIdentityMessage> rows = const [];

  @override
  Future<List<AdditionalIdentityMessage>> messages(
    String recipientKey,
    String senderKey, {
    (int, int)? before,
  }) async => rows;

  @override
  Future<String?> preferredSender(String peerKey) async => selections[peerKey];

  @override
  Future<void> setPreferredSender(String peerKey, String? identityKey) async {
    if (identityKey == null) {
      selections.remove(peerKey);
    } else {
      selections[peerKey] = identityKey;
    }
  }

  @override
  Future<void> markRead(String recipientKey, String senderKey) async {}
}

class _SenderPickerNode extends _PagedNode {
  _SenderPickerNode(_SenderPickerInbox inbox)
    : super(additionalIdentityInbox: inbox);

  final sent = <(String, String, String)>[];

  @override
  String? get selfName => 'Radio node';

  @override
  List<Message> getMessages(Contact contact) => [
    _directPost('radio', 'History of the radio node', 1),
  ];

  @override
  List<Message> getMessagesForAdditionalSender(Contact contact, String key) => [
    _directPost('identity:$key:1', 'History of the additional key', 2),
  ];

  @override
  int additionalIdentityMaxTextBytes(Contact peer) => 100;

  @override
  Future<void> sendAdditionalIdentityMessage(
    String identityKey,
    Contact peer,
    String text,
  ) async {
    sent.add((identityKey, peer.publicKeyHex, text));
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
      const lnaText = 'Outgoing message sent with a power boost and LNA';
      if (inChannel) {
        node.setChannelMessagesForTest(_channel.index, [
          _channelPost('normal', regularText, 1).copyWith(isOutgoing: true),
          _channelPost('boosted', boostedText, 2).copyWith(
            isOutgoing: true,
            resendCount: 2,
            sentWithTxPowerBoost: true,
          ),
          _channelPost('lna', lnaText, 3).copyWith(
            isOutgoing: true,
            resendCount: 2,
            sentWithTxPowerBoost: true,
            sentWithAdaptiveLna: true,
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
            _directPost('lna', lnaText, 3).copyWith(
              isOutgoing: true,
              tripTimeMs: 1200,
              sentWithTxPowerBoost: true,
              sentWithAdaptiveLna: true,
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

      final badges = find.byType(TxPowerBoostBadge);
      expect(badges, findsNWidgets(2));
      final badge = find.ancestor(
        of: find.byTooltip('Sent with boosted TX power'),
        matching: badges,
      );
      final lnaBadge = find.byTooltip('Sent with boosted TX power and LNA enabled by the app');
      expect(badge, findsOneWidget);
      expect(lnaBadge, findsOneWidget);
      Color? iconColor(Finder root) => tester.widget<Icon>(find.descendant(
        of: root, matching: find.byIcon(Icons.bolt),
      )).color;
      expect(iconColor(lnaBadge), Colors.red);
      expect(iconColor(badge), tester.widget<TxPowerBoostBadge>(badge).color);
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
      expect(badges, findsNWidgets(2));
      expect(iconColor(lnaBadge), Colors.red);
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

  testWidgets('channel contact picker shares additional keys before node contacts', (
    tester,
  ) async {
    final entry = (await tester.runAsync(() async {
      final seed = hex.decode(
        '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
      );
      final expanded = Uint8List.fromList((await Sha512().hash(seed)).bytes);
      expanded[0] &= 248;
      expanded[31] = (expanded[31] & 63) | 64;
      return AdditionalIdentityEntry.parse('Additional key', hex.encode(expanded));
    }))!;
    final inbox = AdditionalIdentityInbox()..unlock([entry]);
    final node = _ContactShareNode(inbox);
    final settings = AppSettingsService();
    final scale = ChatTextScaleService();
    final view = UiViewStateService();
    addTearDown(node.dispose);
    addTearDown(settings.dispose);
    addTearDown(scale.dispose);
    addTearDown(view.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MeshCoreConnector>.value(value: node),
          ChangeNotifierProvider<AppSettingsService>.value(value: settings),
          ChangeNotifierProvider<ChatTextScaleService>.value(value: scale),
          ChangeNotifierProvider<UiViewStateService>.value(value: view),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChannelChatScreen(channel: _channel),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var notificationWorkStarted = false;
    void observeBackgroundWork() {
      if (node.backgroundWorkSnapshot.countFor(BackgroundWorkKind.notification) >
          0) {
        notificationWorkStarted = true;
      }
    }

    node.addBackgroundWorkListener(observeBackgroundWork);
    addTearDown(() => node.removeBackgroundWorkListener(observeBackgroundWork));

    Future<void> openPicker() async {
      await tester.tap(find.byTooltip('Chat actions menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share contact'));
      await tester.pumpAndSettle();
      expect(notificationWorkStarted, isFalse);
    }

    final composer = find.descendant(
      of: find.byType(ByteCountedTextField),
      matching: find.byType(TextField),
    );
    final keyCard = find.text(entry.name);
    final contact = find.text(_contact.name);
    final publicKey = entry.identity.publicKeyHex;

    await openPicker();
    expect(keyCard, findsOneWidget);
    expect(contact, findsOneWidget);
    expect(tester.getTopLeft(keyCard).dy, lessThan(tester.getTopLeft(contact).dy));
    await tester.tap(keyCard);
    await tester.pumpAndSettle();

    final draft = tester.widget<TextField>(composer).controller!;
    expect(draft.text, '<$publicKey:$advTypeChat:${entry.name}>');

    draft.clear();
    await openPicker();
    await tester.tap(contact);
    await tester.pumpAndSettle();
    expect(draft.text, formatContactShareTextForContact(_contact));

    draft.clear();
    node.contactList = const [];
    await openPicker();
    expect(keyCard, findsOneWidget);
    expect(contact, findsNothing);
    await tester.tap(keyCard);
    await tester.pumpAndSettle();
    expect(draft.text, '<$publicKey:$advTypeChat:${entry.name}>');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('additional identity chat shows the regular message indicators', (
    tester,
  ) async {
    final inbox = _SenderPickerInbox();
    final node = _SenderPickerNode(inbox);
    final settings = AppSettingsService();
    final scale = ChatTextScaleService();
    addTearDown(node.dispose);
    addTearDown(settings.dispose);
    addTearDown(scale.dispose);
    final identityKey = 'af' * 32;
    final timestamp = _time.millisecondsSinceEpoch ~/ 1000;
    const text = 'A message sent from the additional key';
    inbox.rows = [
      (
        recipientKey: identityKey,
        senderKey: _contact.publicKeyHex,
        senderName: _contact.name,
        peerType: advTypeChat,
        roomAuthorHex: null,
        timestampSeconds: timestamp,
        receivedAtMs: _time.millisecondsSinceEpoch,
        wireText: MCOtxtAppCodec.encodeTextTransport(
          text: text,
          timestamp: timestamp,
        ),
        text: text,
        isUnread: false,
        isOutgoing: true,
        status: MessageStatus.delivered,
        rowId: 1,
        sentByFlood: true,
        region: 'bots',
        path: Uint8List(0),
        dispatchedAtMs: _time.millisecondsSinceEpoch + 2000,
        tripTimeMs: 1800,
        airtimeMs: 90,
        usedCyr2Lat: false,
      ),
    ];
    await settings.updateSettings(
      settings.settings.copyWith(
        enableMessageTracing: true,
        showCompressionRatio: true,
        showMessageRegion: true,
      ),
    );
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
          home: AdditionalIdentityChatScreen(
            inbox: inbox,
            connector: node,
            peer: _contact,
            recipientKey: identityKey,
            recipientName: 'Extra key',
            senderKey: _contact.publicKeyHex,
            senderName: _contact.name,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bubble = find.byType(ContactMessageBubble);
    expect(bubble, findsOneWidget);
    expect(find.descendant(of: bubble, matching: find.byIcon(Icons.check)), findsOneWidget);
    expect(find.descendant(of: bubble, matching: find.byIcon(Icons.speed)), findsOneWidget);
    expect(find.text('(2)'), findsOneWidget);
    expect(find.text('1.8s'), findsOneWidget);
    expect(find.byTooltip('Send attempts'), findsOneWidget);
    expect(find.byTooltip('Time on air'), findsOneWidget);
    expect(find.text('90 ms'), findsOneWidget);
    expect(find.textContaining('% MCOtxt'), findsOneWidget);
    expect(find.textContaining('bots'), findsOneWidget);
    expect(find.byType(TxPowerBoostBadge), findsNothing);

    await settings.updateSettings(
      settings.settings.copyWith(enableMessageTracing: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('1.8s'), findsNothing);
    expect(find.byTooltip('Time on air'), findsNothing);
    expect(find.textContaining('% MCOtxt'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('sender selection keeps the chat and draft tied to the chosen key', (
    tester,
  ) async {
    final entry = (await tester.runAsync(() async {
      const seed = '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';
      final expanded = Uint8List.fromList((await Sha512().hash(hex.decode(seed))).bytes);
      expanded[0] &= 248;
      expanded[31] = (expanded[31] & 63) | 64;
      return AdditionalIdentityEntry.parse('Additional sender', hex.encode(expanded));
    }))!;
    final key = entry.identity.publicKeyHex;
    final inbox = _SenderPickerInbox()..unlock([entry]);
    final node = _SenderPickerNode(inbox);
    final settings = AppSettingsService();
    final scale = ChatTextScaleService();
    addTearDown(node.dispose);
    addTearDown(settings.dispose);
    addTearDown(scale.dispose);

    Future<void> openChat({
      bool showRadioHistoryInitially = false,
      String? roomLoginSenderKey,
    }) async {
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
          home: ChatScreen(
            contact: roomLoginSenderKey == null
                ? _contact
                : _contact.copyWith(type: advTypeRoom),
            showRadioHistoryInitially: showRadioHistoryInitially,
            roomLoginSenderKey: roomLoginSenderKey,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Finder sender(String name) => find.descendant(
      of: find.byType(AppBar),
      matching: find.text('Sender: $name', findRichText: true),
    );
    final composer = find.descendant(
      of: find.byType(ByteCountedTextField),
      matching: find.byType(TextField),
    );
    final send = find.byTooltip('Send message');
    final radioHistory = find.text('History of the radio node', findRichText: true);
    final keyHistory = find.text('History of the additional key', findRichText: true);
    try {
      await openChat();
      expect(radioHistory, findsOneWidget);
      expect(keyHistory, findsNothing);
      expect(node.routeIsCurrent?.call(), isTrue);
      final radioActivations = node.activations;
      await tester.tap(sender('Radio node'));
      await tester.pumpAndSettle();
      final option = find.widgetWithText(ListTile, entry.name);
      expect(find.descendant(of: option, matching: find.text(key)), findsOneWidget);
      await tester.tap(option);
      await tester.pumpAndSettle();

      expect(sender(entry.name), findsOneWidget);
      expect(radioHistory, findsNothing);
      expect(keyHistory, findsOneWidget);
      expect(node.routeIsCurrent?.call(), isFalse);
      expect(node.activations, radioActivations);
      expect(inbox.selections, {_contact.publicKeyHex: key});
      await tester.enterText(composer, 'From the selected key');
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(node.sent, [(key, _contact.publicKeyHex, 'From the selected key')]);
      expect(tester.widget<TextField>(composer).controller!.text, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await openChat(roomLoginSenderKey: '');
      expect(sender('Radio node'), findsOneWidget);
      expect(radioHistory, findsOneWidget);
      expect(inbox.selections, {_contact.publicKeyHex: key});

      await tester.pumpWidget(const SizedBox.shrink());
      inbox.selections.clear();
      await openChat(roomLoginSenderKey: key);
      expect(sender(entry.name), findsOneWidget);
      expect(keyHistory, findsOneWidget);
      expect(inbox.selections, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      inbox.selections[_contact.publicKeyHex] = key;
      await openChat(showRadioHistoryInitially: true);
      expect(sender('Radio node'), findsOneWidget);
      expect(radioHistory, findsOneWidget);
      expect(node.routeIsCurrent?.call(), isTrue);
      expect(inbox.selections, {_contact.publicKeyHex: key});

      await tester.pumpWidget(const SizedBox.shrink());
      final activationsBeforeReopening = node.activations;
      await openChat();
      expect(sender(entry.name), findsOneWidget);
      expect(node.routeIsCurrent?.call(), isFalse);
      expect(node.activations, activationsBeforeReopening);
      inbox.unlock([]);
      await tester.pumpAndSettle();
      expect(sender('Key unavailable'), findsOneWidget);
      await tester.enterText(composer, 'Keep this draft');
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(node.sent, hasLength(1));
      expect(tester.widget<TextField>(composer).controller!.text, 'Keep this draft');
      expect(tester.takeException(), isNull);

      await tester.tap(sender('Key unavailable'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Radio node'));
      await tester.pumpAndSettle();
      // With every additional key locked, returning to the radio hides the picker.
      expect(sender('Radio node'), findsNothing);
      expect(sender('Key unavailable'), findsNothing);
      expect(radioHistory, findsOneWidget);
      expect(node.routeIsCurrent?.call(), isTrue);
      expect(inbox.selections, isEmpty);
      expect(tester.widget<TextField>(composer).controller!.text, 'Keep this draft');
      await tester.enterText(composer, '');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    }
  });

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
