import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:mco_service/mco_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/companion_cli_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_group.dart';
import 'package:meshcore_open/models/companion_cli_entry.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/community.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/screens/companion_cli_screen.dart';
import 'package:meshcore_open/screens/contacts_screen.dart';
import 'package:meshcore_open/screens/channels_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/companion_cli_session.dart';
import 'package:meshcore_open/services/ui_view_state_service.dart';
import 'package:meshcore_open/storage/channel_group_store.dart';
import 'package:meshcore_open/storage/community_store.dart';
import 'package:meshcore_open/storage/companion_cli_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/utils/contact_filter_types.dart';
import 'package:meshcore_open/utils/platform_info.dart';
import 'package:meshcore_open/widgets/companion_cli_tile.dart';
import 'package:meshcore_open/widgets/middle_ellipsis_text.dart';
import 'package:meshcore_open/widgets/repeater_login_dialog.dart';
import 'package:meshcore_open/widgets/companion_cli_command_help_sheet.dart';
import '../support/wrapping_label_expectations.dart';

class _NoPreferenceDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async =>
      throw MissingPluginException('Synthetic CLI and Community preferences');
}

class _ContactMenuSections extends ChangeNotifier implements SettingsSectionsService {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #contactActionTiles) return <Widget>[];
    return super.noSuchMethod(invocation);
  }
}

class _History implements CompanionCliHistory {
  final rows = <String, CompanionCliEntry>{};
  final revisions = <String, int>{};
  @override
  int revision(String nodeKey) => revisions[nodeKey] ?? 0;
  @override
  Future<void> clear(String nodeKey) async {
    rows.removeWhere((_, entry) => entry.nodeKey == nodeKey);
    revisions[nodeKey] = revision(nodeKey) + 1;
  }
  @override
  Future<List<CompanionCliEntry>> load() async => rows.values.toList();
  @override
  Future<bool> save(CompanionCliEntry entry, {int? revision}) async {
    if (revision != null && this.revision(entry.nodeKey) != revision) {
      return false;
    }
    rows[entry.id] = entry;
    return true;
  }
}

class _Connector extends MeshCoreConnector {
  _Connector() {
    testSession = CompanionCliSession(history: history,
      nodeKey: () => selfPublicKeyHex, nodeName: () => selfName!,
      available: () => isConnected && supported,
      send: (frame) async {
        writes.add(frame.toList());
        testSession.observeReply(Uint8List.fromList([
          29, ...frame.sublist(1, 4), ...utf8.encode('SYNTHETIC_CONSOLE_REPLY'),
        ]));
      });
  }
  final history = _History();
  final writes = <List<int>>[];
  final channelOrders = <List<int>>[];
  final deletions = <({String key, bool keepMessages})>[];
  final deletionAckChoices = <bool>[];
  Object? deleteFailure;
  @override
  Future<void> deleteContact(Contact contact, {
    bool waitForAck = true,
    bool keepMessages = false,
  }) async {
    deletions.add((key: contact.publicKeyHex, keepMessages: keepMessages));
    deletionAckChoices.add(waitForAck);
    final failure = deleteFailure;
    if (failure != null) throw failure;
    contactData.removeWhere((entry) => entry.publicKeyHex == contact.publicKeyHex);
    refreshContactRows();
  }
  late final CompanionCliSession testSession;
  bool supported = true;
  bool loaded = true;
  int radioHashWidth = 1;
  @override
  int get pathHashByteWidth => radioHashWidth;
  final contactData = <Contact>[];
  final messagesByContact = <String, List<Message>>{};
  final unreadByContact = <String, int>{};
  int contactRowsRevision = 0;
  @override
  int get contactsRevision => contactRowsRevision;
  void refreshContactRows() {
    contactRowsRevision++;
    notifyListeners();
  }
  @override
  List<Message> getLoadedMessages(Contact contact) =>
      messagesByContact[contact.publicKeyHex] ?? super.getLoadedMessages(contact);
  @override
  int getUnreadCountForContact(Contact contact) =>
      unreadByContact[contact.publicKeyHex] ?? super.getUnreadCountForContact(contact);
  final channelData = <Channel>[
    Channel(index: 1, name: 'Alpha', psk: Uint8List.fromList(List.filled(16, 1))),
    Channel(index: 2, name: 'Beta', psk: Uint8List.fromList(List.filled(16, 2))),
  ];
  @override
  bool get isConnected => true;
  @override
  bool get hasReadableSession => true;
  @override
  String get selfPublicKeyHex => nodeKey;
  String nodeKey = '01' * 32;
  @override
  String? get selfName => 'Synthetic node A';
  @override
  bool get supportsCompanionCli => supported;
  @override
  CompanionCliSession get companionCli => testSession;
  @override
  List<Contact> get contacts => contactData;
  @override
  List<Contact> get localRepeaters => const [];
  @override
  List<Channel> get channels => channelData;
  @override
  bool get hasLoadedContacts => loaded;
  @override
  bool get hasLoadedChannels => true;
  @override
  Future<void> getChannels({int? maxChannels, bool force = false}) async {}
  @override
  Future<void> setChannelOrder(List<int> order) async {
    channelOrders.add(List<int>.of(order));
  }
  @override
  void dispose() { testSession.dispose(); super.dispose(); }
}

void main() {
  late _Connector connector;
  late AppSettingsService settings;
  late UiViewStateService view;
  late PathProviderPlatform previousPaths;
  setUp(() async {
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferenceDirectory();
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    connector = _Connector();
    settings = AppSettingsService();
    view = UiViewStateService();
    await view.initialize();
  });
  tearDown(() {
    connector.dispose(); settings.dispose(); view.dispose(); PrefsManager.reset();
    PathProviderPlatform.instance = previousPaths;
  });

  Future<void> show(WidgetTester tester, Widget screen, {
    String locale = 'en',
    double textScale = 1,
    double pixelRatio = 1,
    Size logicalSize = const Size(1000, 1400),
    TargetPlatform? platform,
    double bottomPadding = 0,
    double keyboardInset = 0,
  }) async {
    tester.view.physicalSize = logicalSize * pixelRatio;
    tester.view.devicePixelRatio = pixelRatio;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset * pixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<MeshCoreConnector>.value(value: connector),
      ChangeNotifierProvider<AppSettingsService>.value(value: settings),
      ChangeNotifierProvider<UiViewStateService>.value(value: view),
    ], child: MaterialApp(locale: Locale(locale),
      theme: platform == null ? null : ThemeData(platform: platform),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          padding: MediaQuery.paddingOf(context).copyWith(bottom: bottomPadding),
        ),
        child: child!), home: screen)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Rect cardSurface(WidgetTester tester, Finder card) => tester.getRect(
    find.descendant(of: card, matching: find.byType(Material)).first);

  testWidgets('U29 baseline: tab switching preserves the contacts search',
      (tester) async {
    connector.contactData.add(Contact(
      publicKey: Uint8List.fromList(List.filled(32, 0x45)),
      name: 'Synthetic contact',
      type: advTypeChat,
      pathLength: -1,
      path: Uint8List(0),
      lastSeen: DateTime.utc(2026),
    ));
    await show(tester, const ContactsScreen(hideBackButton: true),
        logicalSize: const Size(450, 820), textScale: 2);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ContactsScreen)),
    );
    await tester.tap(find.byTooltip(l10n.contacts_searchOpen));
    await tester.pumpAndSettle();
    final search = find.byType(TextField);
    expect(tester.getSize(search).height, greaterThan(48));
    await tester.enterText(search, 'Synthetic');
    await tester.pump(const Duration(milliseconds: 350));
    expect(view.contactsSearchText, 'Synthetic');
    expect(find.text('Synthetic contact'), findsOneWidget);

    final switchBar = find.byType(NavigationBar);
    Finder destination(String label) =>
        find.descendant(of: switchBar, matching: find.text(label));
    await tester.tap(destination(l10n.nav_channels));
    await tester.pumpAndSettle();
    expect(find.byType(ChannelsScreen), findsOneWidget);
    await tester.tap(destination(l10n.nav_contacts));
    await tester.pumpAndSettle();
    expect(find.byType(ContactsScreen), findsOneWidget);
    expect(tester.widget<TextField>(search).controller!.text, 'Synthetic');
    expect(view.contactsSearchExpanded, isTrue);
    expect(find.text('Synthetic contact'), findsOneWidget);
    expect(connector.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final scenario in [
      (dpr: 1.0, scale: 1.0),
      (dpr: 3.0, scale: 1.0),
      (dpr: 3.0, scale: 1.8),
    ]) {
      testWidgets('quick-command thumb stays below chips: $platform $scenario', (tester) async {
        await show(tester, CompanionCliScreen(connector: connector),
          locale: 'ru', platform: platform, pixelRatio: scenario.dpr,
          textScale: scenario.scale, logicalSize: const Size(390, 844),
          bottomPadding: platform == TargetPlatform.iOS ? 34 : 24);
        await tester.pumpAndSettle();
        final bar = find.byKey(const ValueKey('companion-cli-quick-commands'));
        final viewport = find.descendant(of: bar,
          matching: find.byType(SingleChildScrollView));
        await tester.drag(viewport, const Offset(-220, 0));
        await tester.pump(const Duration(milliseconds: 100));
        final paint = find.descendant(of: bar, matching: find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.foregroundPainter is ScrollbarPainter,
        ));
        expect(paint, findsOneWidget);
        final painter = tester.widget<CustomPaint>(paint).foregroundPainter! as ScrollbarPainter;
        final padding = painter.padding.resolve(TextDirection.ltr);
        expect(padding.bottom, 0);
        final chips = find.descendant(of: bar, matching: find.byType(ActionChip));
        final chipBottom = tester.getRect(chips.first).bottom;
        // The painter places the horizontal thumb against its local bottom.
        // Include the iOS enlarged 8px thumb, not just the idle 3px one.
        final thickness = platform == TargetPlatform.iOS ? 8.0 : painter.thickness;
        final thumbTop = tester.getRect(paint).bottom - padding.bottom -
            painter.crossAxisMargin - thickness;
        expect(thumbTop, greaterThanOrEqualTo(chipBottom));
        final scroll = tester.widget<SingleChildScrollView>(viewport).controller!;
        expect(scroll.offset, greaterThan(0));
        await tester.pumpAndSettle();
        final visibleChip = chips.hitTestable().first;
        await tester.tap(visibleChip);
        await tester.pump();
        final input = tester.widget<TextField>(find.byKey(const ValueKey('companion-cli-input')));
        expect(input.controller!.text, isNotEmpty);
        expect(connector.writes, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final locale in ['ru', 'en']) {
    testWidgets('Companion help searches categories and inserts a template without sending ($locale)', (tester) async {
      await show(tester, CompanionCliScreen(connector: connector), locale: locale, textScale: 1.5);
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(tester.element(find.byType(CompanionCliScreen)));
      final help = find.byTooltip(l10n.repeater_commandHelp);
      expect(help, findsOneWidget);
      await tester.tap(help);
      await tester.pumpAndSettle();
      expect(find.byType(CompanionCliCommandHelpSheet), findsOneWidget);
      final search = find.byKey(const ValueKey('companion-cli-help-search'));
      await tester.enterText(search, 'wifi');
      await tester.pump();
      expect(find.text(l10n.companionCli_helpWifiTitle), findsOneWidget);
      expect(find.text(l10n.companionCli_helpWifiNote), findsOneWidget);
      expect(find.text('get wifi.ssid'), findsWidgets);
      await tester.enterText(search, 'not-a-cli-command');
      await tester.pump();
      expect(find.text(l10n.repeater_cliNoMatchingCommands), findsOneWidget);
      await tester.enterText(search, 'set pin');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('companion-cli-help:set pin <PIN>')));
      await tester.pumpAndSettle();
      expect(find.byType(CompanionCliCommandHelpSheet), findsNothing);
      final input = tester.widget<TextField>(find.byKey(const ValueKey('companion-cli-input')));
      expect(input.controller!.text, 'set pin ');
      expect(input.controller!.selection.baseOffset, 'set pin '.length);
      expect(input.focusNode!.hasFocus, isTrue);
      expect(connector.writes, isEmpty);
      // The catalog also remains available while sending is unavailable.
      connector.supported = false;
      connector.notifyListeners();
      await tester.pump();
      await tester.tap(help);
      await tester.pumpAndSettle();
      await tester.enterText(search, 'shutdown');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('companion-cli-help:shutdown')));
      await tester.pumpAndSettle();
      expect(input.controller!.text, 'shutdown');
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('companion-cli-send'))).onPressed, isNull);
      expect(connector.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('terminal header and quick commands fill the screen without duplicate clear ($locale)', (tester) async {
      await show(tester, CompanionCliScreen(connector: connector), locale: locale, textScale: 1.5);
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(tester.element(find.byType(CompanionCliScreen)));
      final label = locale == 'ru' ? 'CLI ноды: Synthetic node A' : 'Node CLI: Synthetic node A';
      final title = find.text(label);
      expect(title, findsOneWidget);
      expect(tester.widget<Text>(title).textAlign, TextAlign.center);
      expect(find.text(l10n.companionCli_localOnly), findsNothing);
      expect(find.byTooltip(l10n.repeater_clearHistory), findsNothing);
      expect(find.byIcon(Icons.clear_all), findsNothing);
      final quickBar = find.byKey(const ValueKey('companion-cli-quick-commands'));
      final rect = tester.getRect(quickBar);
      final screen = tester.getRect(find.byType(Scaffold));
      expect(rect.left, screen.left);
      expect(rect.right, screen.right);
      // Same mobile padding / desktop scrollbar clearance as RepeaterCliScreen.
      expect(tester.widget<Container>(quickBar).padding,
        EdgeInsets.fromLTRB(8, 6, 8, PlatformInfo.isDesktop ? 0 : 6));
      expect(connector.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('console keeps source labels, supports shared history and sends local frames ($locale)', (tester) async {
      for (final node in ['01' * 32, '02' * 32]) {
        connector.history.rows[node] = CompanionCliEntry(id: node, nodeKey: node,
          nodeName: node.startsWith('01') ? 'Synthetic node A' : 'Synthetic node B',
          command: 'ver', response: 'Synthetic old reply', status: CompanionCliStatus.replied,
          createdAt: DateTime.utc(2026));
      }
      await show(tester, CompanionCliScreen(connector: connector), locale: locale);
      expect(find.textContaining('Synthetic node B'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('companion-cli-shared')));
      await tester.pump();
      expect(find.textContaining('Synthetic node B'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('companion-cli-input')),
        'set wifi.pwd SYNTHETIC_ONLY');
      await tester.tap(find.byKey(const ValueKey('companion-cli-send')));
      await tester.pumpAndSettle();
      expect(connector.writes.single.first, 66);
      expect(connector.history.rows.values.any((entry) =>
        entry.command == 'set wifi.pwd SYNTHETIC_ONLY' &&
        entry.response == 'SYNTHETIC_CONSOLE_REPLY'), isTrue);
      connector.supported = false;
      connector.testSession.connectionChanged();
      await tester.pump();
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('companion-cli-send'))).onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final screen in ['contacts', 'channels', 'legacy channels']) {
    testWidgets('unsupported firmware hides the CLI entry on $screen', (tester) async {
      connector.supported = false;
      await settings.updateSettings(settings.settings.copyWith(
        roomServerShowNotemptyContactsOnChatscreen: true,
        roomServerDisableRoomAndContactsSorting: screen == 'legacy channels'));
      await show(tester, screen == 'contacts'
        ? const ContactsScreen(hideBackButton: true)
        : const ChannelsScreen(hideBackButton: true));
      await tester.pumpAndSettle();
      expect(find.byType(CompanionCliTile), findsNothing);
      connector.supported = true;
      connector.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(CompanionCliTile), findsOneWidget);
      expect(connector.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final (language, scale) in [
    ('en', 1.0), ('en', 1.5), ('ru', 1.0), ('ru', 1.5),
  ]) {
    testWidgets(
      'U06a2: routing badge follows radio width and keeps full key and stored route ($language, scale=$scale)',
      (tester) async {
        final contact = Contact(
          publicKey: Uint8List.fromList([
            0xA3, 0x0F, 0xB2, ...List<int>.filled(29, 0x44),
          ]),
          name: 'Synthetic routing contact',
          latitude: 55.75,
          longitude: 37.62,
          type: advTypeRepeater,
          flags: contactFlagFavorite,
          pathLength: 1,
          path: Uint8List.fromList([0xAA, 0xBB, 0xCC]),
          pathHashWidth: 3,
          lastSeen: DateTime.utc(2026),
        );
        connector.contactData.add(contact);
        await show(
          tester,
          const ContactsScreen(hideBackButton: true),
          locale: language,
          textScale: scale,
          logicalSize: const Size(390, 844),
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(ContactsScreen)),
        );
        final fullKey = 'A30FB2${'44' * 29}';
        // testWidgets enables semantics and disposes its handle itself.
        // Changing the radio width must not truncate contact identity or
        // reinterpret an already stored three-byte route as three hops.
        for (final width in [1, 2, 3, 1]) {
          connector.radioHashWidth = width;
          connector.refreshContactRows();
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text(contact.name), findsOneWidget);
          expect(
            tester.widget<MiddleEllipsisText>(
              find.byType(MiddleEllipsisText),
            ).text,
            fullKey,
          );
          final prefix = {1: 'A3', 2: 'A30F', 3: 'A30FB2'}[width]!;
          final badge = find.text(prefix);
          expect(badge, findsOneWidget);
          // InkWell merges the badge into the contact's accessible label.
          // Verify the real node still speaks the complete prefix, without
          // requiring a separate accessibility focus stop for the badge.
          final spokenPrefix = l10n.contacts_keyPrefixSemantics(
            prefix.split('').join(' '),
          );
          expect(
            tester.getSemantics(badge).label.split('\n'),
            contains(spokenPrefix),
          );
          final path = find.text(l10n.chat_hopsCount(1));
          expect(path, findsOneWidget);
          expect(
            tester.getRect(badge).right,
            lessThan(tester.getRect(path).left),
          );
          expect(find.byIcon(Icons.star), findsOneWidget);
          final location = find.byIcon(Icons.location_on);
          expect(location, findsOneWidget);
          final trailingRow = find.ancestor(of: location, matching: find.byType(Row)).first;
          final lastSeen = find.descendant(of: trailingRow, matching: find.byType(Text));
          expect(lastSeen, findsOneWidget);
          expect(tester.getRect(lastSeen).left - tester.getRect(location).right, closeTo(6, 0.01));
          expect(tester.getRect(lastSeen).right, closeTo(tester.getRect(trailingRow).right, 0.01));
          expect(
            tester.getRect(find.byType(CompanionCliTile)).bottom,
            lessThan(tester.getRect(find.text(contact.name)).top),
          );
          expect(connector.writes, isEmpty);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final language in ['en', 'ru']) {
    for (final layout in [
      (name: 'baseline', size: const Size(1000, 1400), scale: 1.0, inset: 0.0),
      (name: 'landscape', size: const Size(568, 320), scale: 2.0, inset: 0.0),
      (name: 'keyboard', size: const Size(1000, 1400), scale: 2.0, inset: 1120.0),
    ]) {
      testWidgets('U11b3 ${layout.name}: add-contact sheet retains all fork actions without sending ($language)', (tester) async {
        try {
          await show(tester, const ContactsScreen(hideBackButton: true),
              locale: language, logicalSize: layout.size,
              textScale: layout.scale, keyboardInset: layout.inset);
          final l10n = AppLocalizations.of(tester.element(find.byType(ContactsScreen)));
          await tester.tap(find.byType(FloatingActionButton));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          final sheet = find.byType(BottomSheet);
          expect(sheet, findsOneWidget);
          for (final label in [
            l10n.contacts_addContactByPubkey,
            l10n.contacts_addContactFromClipboard,
            l10n.contacts_scanQrCode,
            l10n.discoveredContacts_Title,
          ]) {
            expect(find.descendant(of: sheet,
                matching: find.widgetWithText(ListTile, label)), findsOneWidget);
          }
          expect(connector.writes, isEmpty);
          if (layout.name != 'baseline') {
            final scrollable = find.descendant(of: sheet, matching: find.byType(Scrollable));
            expect(scrollable, findsOneWidget);
            final position = tester.state<ScrollableState>(scrollable).position;
            expect(position.maxScrollExtent, greaterThan(0));
            final lastAction = find.descendant(of: sheet, matching:
                find.widgetWithText(ListTile, l10n.discoveredContacts_Title));
            await tester.ensureVisible(lastAction);
            await tester.pump();
            expect(position.pixels, greaterThan(0));
            expect(lastAction.hitTestable(), findsOneWidget);
            final firstAction = find.descendant(of: sheet, matching:
                find.widgetWithText(ListTile, l10n.contacts_addContactByPubkey));
            await tester.ensureVisible(firstAction);
            await tester.pump();
            expect(firstAction.hitTestable(), findsOneWidget);
            // A scrollable sheet can occupy the whole viewport, leaving no
            // exposed modal barrier to tap. Back must still dismiss it safely.
            await tester.binding.handlePopRoute();
          } else {
            await tester.tapAt(const Offset(8, 8));
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          expect(sheet, findsNothing);
          expect(find.byType(CompanionCliTile), findsOneWidget);
          expect(connector.writes, isEmpty);
          expect(connector.contactData, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      });
    }

    testWidgets('U11b3 baseline: channel actions retain sharing and notifications without sending ($language)', (tester) async {
      await settings.updateSettings(settings.settings.copyWith(
          roomServerShowNotemptyContactsOnChatscreen: true));
      try {
        await show(tester, const ChannelsScreen(hideBackButton: true), locale: language);
        final l10n = AppLocalizations.of(tester.element(find.byType(ChannelsScreen)));
        await tester.longPress(find.text('Alpha'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final sheet = find.byType(BottomSheet);
        expect(sheet, findsOneWidget);
        for (final label in [
          l10n.channels_editChannel,
          l10n.common_share,
          l10n.channels_notificationSettings,
          l10n.channels_deleteChannel,
        ]) {
          expect(find.descendant(of: sheet,
              matching: find.widgetWithText(ListTile, label)), findsOneWidget);
        }
        expect(connector.writes, isEmpty);
        await tester.tapAt(const Offset(8, 8));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(sheet, findsNothing);
        expect(find.byType(CompanionCliTile), findsOneWidget);
        expect(connector.channelData.map((channel) => channel.name), ['Alpha', 'Beta']);
        expect(connector.writes, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }

  for (final language in ['en', 'ru']) {
    for (final layout in [
      (name: 'baseline', size: const Size(1000, 1400), scale: 1.0),
      (name: 'phone', size: const Size(320, 568), scale: 2.0),
      (name: 'landscape', size: const Size(568, 360), scale: 2.0),
    ]) {
      testWidgets('U11b4 ${layout.name}: Community selection is local until channel creation ($language)', (tester) async {
        final longLabels = layout.name != 'baseline';
        final north = !longLabels ? 'North' : language == 'en'
            ? 'North regional group' : 'Северное региональное сообщество';
        final south = !longLabels ? 'South' : language == 'en'
            ? 'South regional group' : 'Южное региональное сообщество';
        // Fixed synthetic secrets; no random key generation or network source.
        final communities = [
          Community(id: 'north', name: north,
              secret: Uint8List.fromList(List.filled(32, 0x11)),
              createdAt: DateTime.utc(2026, 1, 1)),
          Community(id: 'south', name: south,
              secret: Uint8List.fromList(List.filled(32, 0x22)),
              createdAt: DateTime.utc(2026, 1, 2)),
        ];
        final store = CommunityStore()..setPublicKeyHex = connector.selfPublicKeyHex;
        await store.saveCommunities(communities);
        final transportFrames = <List<int>>[];
        connector.setFrameWriterForTest((frame) async {
          transportFrames.add(frame.toList());
        });
        try {
          await show(tester, const ChannelsScreen(hideBackButton: true),
              locale: language, logicalSize: layout.size, textScale: layout.scale);
          await tester.pumpAndSettle();
          final l10n = AppLocalizations.of(tester.element(find.byType(ChannelsScreen)));
          await tester.tap(find.byType(FloatingActionButton));
          await tester.pumpAndSettle();
          final sheet = find.byType(DraggableScrollableSheet);
          final scrollable = find.descendant(of: sheet, matching: find.byType(Scrollable)).first;
          final hashtag = find.text(l10n.channels_joinHashtagChannel);
          await tester.scrollUntilVisible(hashtag, 200,
              scrollable: scrollable, maxScrolls: 30);
          await tester.pumpAndSettle();
          expect(hashtag.hitTestable(), findsOneWidget);
          await tester.tap(hashtag);
          await tester.pumpAndSettle();
          final communityType = find.widgetWithText(RadioListTile<bool>, l10n.community_communityHashtag);
          await tester.scrollUntilVisible(communityType, 160,
              scrollable: scrollable, maxScrolls: 30);
          await tester.pumpAndSettle();
          expect(communityType.hitTestable(), findsOneWidget);
          await tester.tap(communityType);
          await tester.pumpAndSettle();
          final field = find.byType(DropdownButtonFormField<Community>);
          await tester.scrollUntilVisible(field, 160,
              scrollable: scrollable, maxScrolls: 30);
          await tester.pumpAndSettle();
          final button = find.descendant(of: field, matching: find.byType(DropdownButton<Community>));
          expect(tester.widget<DropdownButton<Community>>(button).value!.id, 'north');
          final arrow = find.descendant(of: field, matching: find.byIcon(Icons.arrow_drop_down));
          await tester.ensureVisible(arrow);
          await tester.pump();
          expect(arrow.hitTestable(), findsOneWidget);
          await tester.tap(arrow);
          await tester.pumpAndSettle();
          final option = await revealDropdownOption(tester, south);
          if (longLabels) {
            expectCompleteWrappingLabel(tester, option, wraps: layout.name == 'phone');
          }
          await tester.tap(option);
          await tester.pumpAndSettle();
          expect(tester.widget<DropdownButton<Community>>(button).value!.id, 'south');
          if (longLabels) {
            expectCompleteWrappingLabel(tester,
                find.descendant(of: field, matching: find.text(south)),
                wraps: layout.name == 'phone');
          }
          expect(transportFrames, isEmpty);
          expect(connector.writes, isEmpty);
          expect(connector.channelData.map((channel) => channel.name), ['Alpha', 'Beta']);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(sheet, findsNothing);
          expect(transportFrames, isEmpty);
          expect((await store.loadCommunities()).map((item) => item.toJson()),
              communities.map((item) => item.toJson()));
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          connector.setFrameWriterForTest(null);
        }
      });
    }
  }

  testWidgets('compact contacts CLI starts below filters and above contact rows', (tester) async {
    connector.contactData.add(Contact(
      publicKey: Uint8List.fromList(List.filled(32, 3)),
      name: 'Synthetic geometry contact', type: advTypeChat,
      pathLength: -1, path: Uint8List(0), lastSeen: DateTime.utc(2026),
    ));
    await show(tester, const ContactsScreen(hideBackButton: true));
    final surface = cardSurface(tester, find.byType(CompanionCliTile));
    final l10n = AppLocalizations.of(tester.element(find.byType(ContactsScreen)));
    expect(find.text(l10n.companionCli_description), findsNothing);
    final avatar = find.descendant(of: find.byType(CompanionCliTile),
      matching: find.byType(CircleAvatar));
    expect(tester.getSize(avatar), const Size(32, 32));
    expect(surface.height, lessThan(62));
    final groupButton = find.ancestor(of: find.text(l10n.listFilter_all),
      matching: find.byType(PopupMenuButton<String>));
    expect(groupButton, findsOneWidget);
    final filters = tester.getRect(groupButton);
    final header = tester.getRect(find.byType(AppBar));
    expect(surface.top - filters.bottom, closeTo(filters.top - header.bottom, 0.01));
    expect(surface.bottom, lessThan(tester.getRect(find.text('Synthetic geometry contact')).top));
    expect(surface.left, 16);
    expect(surface.right, 984);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final secondaryClick in [false, true]) {
    testWidgets('repeater ${secondaryClick ? 'right-click' : 'long press'} opens contact actions without login', (tester) async {
      connector.contactData.add(Contact(
        publicKey: Uint8List.fromList(List.filled(32, 7)),
        name: 'Synthetic repeater actions', type: advTypeRepeater,
        pathLength: -1, path: Uint8List(0), lastSeen: DateTime.utc(2026),
      ));
      await show(tester, ChangeNotifierProvider<SettingsSectionsService>(
        create: (_) => _ContactMenuSections(),
        child: const ContactsScreen(hideBackButton: true),
      ));
      await tester.pumpAndSettle();
      final row = find.text('Synthetic repeater actions');
      if (secondaryClick) {
        await tester.tap(row, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      } else {
        await tester.longPress(row);
      }
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(tester.element(find.byType(ContactsScreen)));
      expect(find.text(l10n.listFilter_addToFavorites), findsOneWidget);
      expect(find.text(l10n.contacts_ShareContact), findsOneWidget);
      expect(find.text(l10n.contacts_deleteContact), findsOneWidget);
      expect(find.byType(RepeaterLoginDialog), findsNothing);
      expect(connector.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, skip: secondaryClick && !PlatformInfo.isDesktop);
  }

  for (final action in ['cancel', 'delete', 'keep history']) {
    testWidgets('U06c2 baseline: contact deletion confirmation $action', (tester) async {
      final contact = Contact(
        publicKey: Uint8List.fromList(List<int>.filled(32, 0x55)),
        name: 'Synthetic delete target', type: advTypeRepeater,
        pathLength: -1, path: Uint8List(0), lastSeen: DateTime.utc(2026),
      );
      connector.contactData.add(contact);
      await show(tester, ChangeNotifierProvider<SettingsSectionsService>(
        create: (_) => _ContactMenuSections(),
        child: const ContactsScreen(hideBackButton: true),
      ));
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(tester.element(find.byType(ContactsScreen)));
      await tester.longPress(find.text(contact.name));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.contacts_deleteContact));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(connector.deletions, isEmpty);
      final checkbox = find.widgetWithText(CheckboxListTile, l10n.contacts_keepChatHistory);
      expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
      if (action == 'keep history') {
        await tester.tap(checkbox);
        await tester.pump();
      }
      await tester.tap(find.widgetWithText(TextButton,
          action == 'cancel' ? l10n.common_cancel : l10n.common_delete));
      await tester.pumpAndSettle();
      expect(connector.deletions, action == 'cancel' ? isEmpty :
          [(key: contact.publicKeyHex, keepMessages: action == 'keep history')]);
      expect(connector.deletionAckChoices, action == 'cancel' ? isEmpty : [true]);
      expect(connector.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final autoAdd in [false, true]) {
    testWidgets('U06c2: delete warning follows auto-add and errors remain visible ($autoAdd)', (tester) async {
      final contact = Contact(
        publicKey: Uint8List.fromList(List<int>.filled(32, 0x66)),
        name: 'Synthetic failed deletion', type: advTypeRepeater,
        pathLength: -1, path: Uint8List(0), lastSeen: DateTime.utc(2026),
      );
      connector.contactData.add(contact);
      connector.deleteFailure = StateError('Synthetic remove failure');
      connector.handleFrameForTest([respCodeAutoAddConfig, autoAdd ? autoAddRepeaterFlag : 0]);
      await show(tester, ChangeNotifierProvider<SettingsSectionsService>(
        create: (_) => _ContactMenuSections(),
        child: const ContactsScreen(hideBackButton: true),
      ));
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(tester.element(find.byType(ContactsScreen)));
      await tester.longPress(find.text(contact.name));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.contacts_deleteContact));
      await tester.pumpAndSettle();
      expect(find.text(l10n.contacts_removeAutoAddNote), autoAdd ? findsOneWidget : findsNothing);
      await tester.tap(find.widgetWithText(TextButton, l10n.common_delete));
      await tester.pumpAndSettle();
      expect(find.text(l10n.contacts_removeFailed), findsOneWidget);
      expect(connector.contactData, contains(contact));
      expect(connector.deletionAckChoices, [true]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('CLI precedes favorites and each group keeps the selected sort', (tester) async {
    final names = ['Zulu favorite', 'Beta favorite', 'Alpha regular', 'Gamma regular'];
    final seenDays = [4, 1, 3, 2];
    final messageDays = [1, 3, 2, 4];
    for (var index = 0; index < names.length; index++) {
      final contact = Contact(
        publicKey: Uint8List.fromList(List.filled(32, index + 3)),
        name: names[index], type: advTypeChat,
        flags: index < 2 ? contactFlagFavorite : 0,
        pathLength: -1, path: Uint8List(0),
        lastSeen: DateTime.utc(2026, 1, seenDays[index]),
      );
      connector.contactData.add(contact);
      connector.messagesByContact[contact.publicKeyHex] = [Message(
        senderKey: contact.publicKey, text: 'Synthetic preview',
        timestamp: DateTime.utc(2026, 1, messageDays[index]), isOutgoing: false,
      )];
    }
    // An unread ordinary contact still stays below all matching favorites.
    connector.unreadByContact[connector.contactData.last.publicKeyHex] = 1;
    await show(tester, const ContactsScreen(hideBackButton: true));
    final expected = {
      ContactSortOption.name: [names[1], names[0], names[2], names[3]],
      ContactSortOption.lastSeen: [names[0], names[1], names[2], names[3]],
      ContactSortOption.recentMessages: [names[1], names[0], names[3], names[2]],
    };
    void expectOrder(List<String> order) {
      var previous = cardSurface(tester, find.byType(CompanionCliTile)).bottom;
      for (final name in order) {
        final row = find.text(name);
        expect(row, findsOneWidget);
        final top = tester.getTopLeft(row).dy;
        expect(top, greaterThan(previous));
        previous = top;
      }
    }
    for (final sort in ContactSortOption.values) {
      view.setContactsSortOption(sort);
      await tester.pumpAndSettle();
      expectOrder(expected[sort]!);
    }
    view.setContactsSortOption(ContactSortOption.name);
    connector.contactData[1] = connector.contactData[1].copyWith(flags: 0);
    connector.refreshContactRows();
    await tester.pumpAndSettle();
    expectOrder([names[0], names[2], names[1], names[3]]);
    view.setContactsSearchText('regular');
    await tester.pumpAndSettle();
    expect(find.text(names[0]), findsNothing);
    expect(find.text(names[1]), findsNothing);
    expectOrder([names[2], names[3]]);
    expect(connector.writes, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('CLI scrolls with contacts while filters stay fixed and remains first under every sort', (tester) async {
    for (var i = 0; i < 30; i++) {
      connector.contactData.add(Contact(
        publicKey: Uint8List.fromList(List.filled(32, i + 3)),
        name: 'Scroll contact ${i.toString().padLeft(2, '0')}', type: advTypeChat,
        pathLength: -1, path: Uint8List(0), lastSeen: DateTime.utc(2026, 1, i + 1),
      ));
    }
    await show(tester, const ContactsScreen(hideBackButton: true));
    await tester.pumpAndSettle();
    final cli = find.byType(CompanionCliTile);
    final scroll = find.ancestor(of: cli, matching: find.byType(CustomScrollView));
    expect(scroll, findsOneWidget);
    // Capture the position while the sliver header is still on screen.
    final position = Scrollable.of(tester.element(cli)).position;
    final l10n = AppLocalizations.of(tester.element(find.byType(ContactsScreen)));
    final groupButton = find.ancestor(of: find.text(l10n.listFilter_all),
      matching: find.byType(PopupMenuButton<String>));
    final filterRect = tester.getRect(groupButton);
    expect(cli.hitTestable(), findsOneWidget);
    await tester.drag(scroll, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(cli.hitTestable(), findsNothing);
    expect(tester.getRect(groupButton), filterRect);
    // Return without pulling beyond the top and triggering a real refresh.
    position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(cli.hitTestable(), findsOneWidget);
    for (final sort in ContactSortOption.values) {
      view.setContactsSortOption(sort);
      await tester.pumpAndSettle();
      final cliRect = cardSurface(tester, cli);
      final rows = find.byWidgetPredicate((widget) => widget is Text &&
        (widget.data?.startsWith('Scroll contact ') ?? false));
      expect(rows, findsWidgets);
      for (final row in rows.evaluate()) {
        expect(tester.getRect(find.byWidget(row.widget)).top, greaterThan(cliRect.bottom));
      }
    }
    view.setContactsSearchText('no matching contact');
    await tester.pumpAndSettle();
    expect(cli.hitTestable(), findsOneWidget);
    expect(find.text(l10n.contacts_noContactsFound), findsOneWidget);
    expect(connector.writes, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('contacts keep the service above an empty or loading list under every sort', (tester) async {
    await show(tester, const ContactsScreen(hideBackButton: true));
    for (final sort in ContactSortOption.values) {
      view.setContactsSortOption(sort);
      await tester.pump();
      expect(find.byType(CompanionCliTile), findsOneWidget);
    }
    connector.loaded = false;
    view.setContactsSortOption(ContactSortOption.name);
    await tester.pump();
    expect(find.byType(CompanionCliTile), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('extended quick commands only edit the draft until explicit Send', (tester) async {
    await show(tester, CompanionCliScreen(connector: connector));
    await tester.pumpAndSettle();
    final requested = [
      'ver', 'board', 'get name', 'get radio', 'get tx',
      'set pin <PIN>', 'reboot', 'poweroff', 'shutdown',
      'get cad', 'get radio.rxgain', 'get rxdelay', 'get agc.reset.interval',
      'get multi.acks', 'get txdelay', 'get direct.txdelay',
      'get wifi.ssid', 'get wifi.pwd', 'get wifi.enabled', 'get wifi.status',
      'get wifi.ip', 'set wifi.clear',
    ];
    for (final command in requested) {
      final chip = find.byKey(ValueKey('companion-cli-quick:$command'));
      expect(chip, findsOneWidget);
      // Invoke the callback for offscreen chips without depending on scroll distance.
      tester.widget<ActionChip>(chip).onPressed!();
      await tester.pump();
      final input = tester.widget<TextField>(find.byKey(const ValueKey('companion-cli-input')));
      expect(input.controller!.text, command == 'set pin <PIN>' ? 'set pin ' : command);
      expect(connector.writes, isEmpty);
    }
    // Check a real tap too, then the explicit send action, using the synthetic node.
    final first = find.byKey(const ValueKey('companion-cli-quick:ver'));
    await tester.ensureVisible(first);
    await tester.tap(first);
    await tester.pump();
    expect(connector.writes, isEmpty);
    await tester.tap(find.byKey(const ValueKey('companion-cli-send')));
    await tester.pumpAndSettle();
    expect(connector.writes, hasLength(1));
    expect(connector.writes.single.first, 66);
    expect(connector.history.rows.values.single.command, 'ver');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  Future<void> editGroup(WidgetTester tester, String name) async {
    final l10n = AppLocalizations.of(tester.element(find.byType(ChannelsScreen)));
    await tester.longPress(find.widgetWithText(ListTile, name));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, l10n.contacts_editGroup));
    await tester.pumpAndSettle();
  }

  Future<void> saveGroup(WidgetTester tester) async {
    final l10n = AppLocalizations.of(tester.element(find.byType(ChannelsScreen)));
    await tester.tap(find.widgetWithText(TextButton, l10n.common_save));
    await tester.pumpAndSettle();
  }

  for (final legacy in [true, false]) {
    testWidgets('CLI can enter and leave a folder without duplication, legacy=$legacy', (tester) async {
      connector.channelData.clear();
      await settings.updateSettings(settings.settings.copyWith(
        roomServerShowNotemptyContactsOnChatscreen: true,
        roomServerDisableRoomAndContactsSorting: legacy));
      final store = ChannelGroupStore()..setPublicKeyHex = connector.selfPublicKeyHex;
      await store.saveGroups(const [ChannelGroup(name: 'Tools', channelNames: [])]);
      await store.saveExpandedGroupNames({'Tools'});
      await show(tester, const ChannelsScreen(hideBackButton: true));
      await tester.pumpAndSettle();
      await editGroup(tester, 'Tools');
      final member = find.byKey(const ValueKey('companion-cli-group-member'));
      expect(tester.widget<CheckboxListTile>(member).value, isFalse);
      await tester.tap(member);
      await saveGroup(tester);
      expect((await store.loadGroups()).single.channelNames, [companionCliOrderKey]);
      expect(find.byType(CompanionCliTile), findsOneWidget);
      expect(find.ancestor(of: find.byType(CompanionCliTile),
        matching: find.byType(AnimatedCrossFade)), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'Tools'));
      await tester.pumpAndSettle();
      expect(find.byType(CompanionCliTile).hitTestable(), findsNothing);
      await tester.tap(find.widgetWithText(ListTile, 'Tools'));
      await tester.pumpAndSettle();
      expect(find.byType(CompanionCliTile).hitTestable(), findsOneWidget);
      // Removing and reselecting before saving must keep the checkbox available.
      await editGroup(tester, 'Tools');
      await tester.tap(member);
      await tester.pump();
      expect(member, findsOneWidget);
      await tester.tap(member);
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(member).value, isTrue);
      await tester.tap(member);
      await saveGroup(tester);
      expect((await store.loadGroups()).single.channelNames, isEmpty);
      expect(find.byType(CompanionCliTile), findsOneWidget);
      expect(find.ancestor(of: find.byType(CompanionCliTile),
        matching: find.byType(AnimatedCrossFade)), findsNothing);
      expect(connector.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('folder order survives hidden CLI and reopening, legacy=$legacy', (tester) async {
      await settings.updateSettings(settings.settings.copyWith(
        roomServerShowNotemptyContactsOnChatscreen: true,
        roomServerDisableRoomAndContactsSorting: legacy));
      final store = ChannelGroupStore()..setPublicKeyHex = connector.selfPublicKeyHex;
      await store.saveGroups(const [ChannelGroup(name: 'Tools',
        channelNames: ['Alpha', companionCliOrderKey, 'Beta'], allowOrderingInGroup: true)]);
      await store.saveExpandedGroupNames({'Tools'});
      await show(tester, const ChannelsScreen(hideBackButton: true));
      await tester.pumpAndSettle();
      final nested = tester.widgetList<ReorderableListView>(
        find.byType(ReorderableListView)).singleWhere((list) => list.itemCount == 3);
      nested.onReorderItem!(1, 2);
      await tester.pumpAndSettle();
      expect((await store.loadGroups()).single.channelNames,
        ['Alpha', 'Beta', companionCliOrderKey]);
      connector.supported = false;
      connector.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(CompanionCliTile), findsNothing);
      // A reorder while hidden must retain membership, rather than erase CLI.
      final hidden = tester.widgetList<ReorderableListView>(
        find.byType(ReorderableListView)).singleWhere((list) => list.itemCount == 2);
      hidden.onReorderItem!(0, 1);
      await tester.pumpAndSettle();
      expect((await store.loadGroups()).single.channelNames,
        ['Beta', 'Alpha', companionCliOrderKey]);
      // Saving an ordinary folder edit while unsupported must retain CLI too.
      await editGroup(tester, 'Tools');
      await saveGroup(tester);
      expect((await store.loadGroups()).single.channelNames,
        ['Beta', 'Alpha', companionCliOrderKey]);
      await tester.pumpWidget(const SizedBox.shrink());
      connector.supported = true;
      await show(tester, const ChannelsScreen(hideBackButton: true));
      await tester.pumpAndSettle();
      expect(find.byType(CompanionCliTile), findsOneWidget);
      expect(tester.widget<CompanionCliTile>(find.byType(CompanionCliTile)).dragIndex, 2);
      await settings.updateSettings(settings.settings.copyWith(
        roomServerShowNotemptyContactsOnChatscreen: false));
      await tester.pumpAndSettle();
      expect(find.byType(CompanionCliTile), findsNothing);
      expect((await store.loadGroups()).single.channelNames.last, companionCliOrderKey);
      if (legacy) {
        expect(connector.channelOrders, isNotEmpty);
        expect(connector.channelOrders.every((order) => order.length == 2 &&
          order.toSet().containsAll({1, 2})), isTrue);
      }
      expect(connector.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('CLI remains visible when there are no channels, legacy=$legacy', (tester) async {
      connector.channelData.clear();
      await settings.updateSettings(settings.settings.copyWith(
        roomServerShowNotemptyContactsOnChatscreen: true,
        roomServerDisableRoomAndContactsSorting: legacy));
      await show(tester, const ChannelsScreen(hideBackButton: true));
      await tester.pumpAndSettle();
      expect(find.byType(CompanionCliTile), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('empty CLI is draggable on channels and order persists, legacy=$legacy', (tester) async {
      await settings.updateSettings(settings.settings.copyWith(
        roomServerShowNotemptyContactsOnChatscreen: true,
        roomServerDisableRoomAndContactsSorting: legacy));
      await show(tester, const ChannelsScreen(hideBackButton: true));
      await tester.pumpAndSettle();
      expect(find.byType(CompanionCliTile), findsOneWidget);
      final list = tester.widget<ReorderableListView>(find.byType(ReorderableListView).first);
      expect(list.itemCount, 3);
      final cli = find.byType(CompanionCliTile);
      final channel = find.byKey(const ValueKey('channel_1'));
      final cliRect = cardSurface(tester, cli);
      final channelRect = cardSurface(tester, channel);
      expect(cliRect.left, channelRect.left);
      expect(cliRect.right, channelRect.right);
      final cliHandle = find.descendant(of: cli, matching: find.byIcon(Icons.drag_handle));
      final channelHandle = find.descendant(of: channel, matching: find.byIcon(Icons.drag_handle));
      expect(cliRect.right - tester.getRect(cliHandle).right,
        channelRect.right - tester.getRect(channelHandle).right);
      list.onReorderItem!(0, 2);
      await tester.pumpAndSettle();
      final store = ChannelGroupStore()..setPublicKeyHex = connector.selfPublicKeyHex;
      expect((await store.loadScreenOrder()).last, companionCliOrderKey);
      connector.supported = false;
      connector.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(CompanionCliTile), findsNothing);
      expect((await store.loadScreenOrder()).last, companionCliOrderKey);
      connector.supported = true;
      connector.notifyListeners();
      await tester.pumpAndSettle();
      expect(tester.widget<CompanionCliTile>(find.byType(CompanionCliTile)).dragIndex, 2);
      await settings.updateSettings(settings.settings.copyWith(
        roomServerShowNotemptyContactsOnChatscreen: false));
      await tester.pumpAndSettle();
      expect(find.byType(CompanionCliTile), findsNothing);
      expect((await store.loadScreenOrder()).last, companionCliOrderKey);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('service is absent from contact selection and batch operations', (tester) async {
    await show(tester, const ContactsScreen(hideBackButton: true, selectionMode: true));
    expect(find.byType(CompanionCliTile), findsNothing);
    await show(tester, const ContactsScreen(hideBackButton: true, batchOperationsMode: true));
    expect(find.byType(CompanionCliTile), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shared CLI choice survives reopening, node switches and app view-state restart', (tester) async {
    final nodeA = '01' * 32;
    final nodeB = '02' * 32;
    for (final node in [nodeA, nodeB]) {
      connector.history.rows[node] = CompanionCliEntry(
        id: node, nodeKey: node, nodeName: node == nodeA ? 'Saved node A' : 'Saved node B',
        command: 'ver', response: 'Saved reply', status: CompanionCliStatus.replied,
        createdAt: DateTime.utc(2026));
    }
    final toggle = find.byKey(const ValueKey('companion-cli-shared'));
    await show(tester, CompanionCliScreen(connector: connector));
    expect(tester.widget<IconButton>(toggle).isSelected, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(toggle).isSelected, isTrue);
    expect(find.textContaining('Saved node B'), findsOneWidget);

    // A newly created console for another radio must use the same choice.
    await tester.pumpWidget(const SizedBox.shrink());
    connector.nodeKey = nodeB;
    connector.testSession.connectionChanged();
    await show(tester, CompanionCliScreen(connector: connector));
    expect(tester.widget<IconButton>(toggle).isSelected, isTrue);
    expect(find.textContaining('Saved node A'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(toggle).isSelected, isFalse);
    expect(find.textContaining('Saved node A'), findsNothing);

    // An explicit false must survive even if the general default becomes true.
    await settings.setSharedMessageHistoryMode(SharedMessageHistoryMode.all);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(toggle).isSelected, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    view.dispose();
    final prefs = PrefsManager.instance;
    final persisted = {for (final key in prefs.getKeys()) key: prefs.get(key)!};
    // Desktop initialization may do real backup/repair file I/O. It cannot
    // complete reliably inside testWidgets' fake-async zone; keep only this
    // simulated process restart in the real event loop, outside pump/expect.
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(persisted);
      PrefsManager.reset();
      await PrefsManager.initialize().timeout(const Duration(seconds: 10));
      view = UiViewStateService();
      await view.initialize();
    });
    connector.nodeKey = nodeA;
    connector.testSession.connectionChanged();
    await show(tester, CompanionCliScreen(connector: connector));
    expect(tester.widget<IconButton>(toggle).isSelected, isFalse);
    expect(find.textContaining('Saved node B'), findsNothing);
    expect(connector.writes, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('terminal recall and local clear keep other nodes shared history', (tester) async {
    final otherNode = '02' * 32;
    connector.history.rows['other'] = CompanionCliEntry(id: 'other', nodeKey: otherNode,
      nodeName: 'Synthetic node B', command: 'board', response: 'Other node reply',
      status: CompanionCliStatus.replied, createdAt: DateTime.utc(2026));
    await show(tester, CompanionCliScreen(connector: connector));
    final l10n = AppLocalizations.of(tester.element(find.byType(CompanionCliScreen)));
    await tester.enterText(find.byKey(const ValueKey('companion-cli-input')), 'ver');
    await tester.tap(find.byKey(const ValueKey('companion-cli-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.repeater_previousCommand));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('companion-cli-input'))).controller!.text, 'ver');
    await tester.tap(find.byKey(const ValueKey('companion-cli-shared')));
    await tester.pump();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, l10n.repeater_clearHistory));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.common_clear));
    await tester.pumpAndSettle();
    expect(connector.history.rows.values.single.nodeKey, otherNode);
    expect(find.text('Other node reply'), findsOneWidget);
    expect(connector.writes, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
