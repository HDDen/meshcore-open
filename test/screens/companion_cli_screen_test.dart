import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/companion_cli_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_group.dart';
import 'package:meshcore_open/models/companion_cli_entry.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/screens/companion_cli_screen.dart';
import 'package:meshcore_open/screens/contacts_screen.dart';
import 'package:meshcore_open/screens/channels_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/companion_cli_session.dart';
import 'package:meshcore_open/services/ui_view_state_service.dart';
import 'package:meshcore_open/storage/channel_group_store.dart';
import 'package:meshcore_open/storage/companion_cli_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/utils/contact_filter_types.dart';
import 'package:meshcore_open/utils/platform_info.dart';
import 'package:meshcore_open/widgets/companion_cli_tile.dart';

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
  late final CompanionCliSession testSession;
  bool supported = true;
  bool loaded = true;
  final contactData = <Contact>[];
  final channelData = <Channel>[
    Channel(index: 1, name: 'Alpha', psk: Uint8List.fromList(List.filled(16, 1))),
    Channel(index: 2, name: 'Beta', psk: Uint8List.fromList(List.filled(16, 2))),
  ];
  @override
  bool get isConnected => true;
  @override
  bool get hasReadableSession => true;
  @override
  String get selfPublicKeyHex => '01' * 32;
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
  setUp(() async {
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
  });

  Future<void> show(WidgetTester tester, Widget screen, {String locale = 'en', double textScale = 1}) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<MeshCoreConnector>.value(value: connector),
      ChangeNotifierProvider<AppSettingsService>.value(value: settings),
      ChangeNotifierProvider<UiViewStateService>.value(value: view),
    ], child: MaterialApp(locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!), home: screen)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Rect cardSurface(WidgetTester tester, Finder card) => tester.getRect(
    find.descendant(of: card, matching: find.byType(Material)).first);

  for (final locale in ['ru', 'en']) {
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
