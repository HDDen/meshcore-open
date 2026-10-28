import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/companion_cli_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/channel.dart';
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
  late final CompanionCliSession testSession;
  bool supported = true;
  bool loaded = true;
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
  List<Contact> get contacts => const [];
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

  Future<void> show(WidgetTester tester, Widget screen, {String locale = 'en'}) async {
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
      supportedLocales: AppLocalizations.supportedLocales, home: screen)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final locale in ['ru', 'en']) {
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

  for (final legacy in [true, false]) {
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
      list.onReorderItem!(0, 2);
      await tester.pumpAndSettle();
      final store = ChannelGroupStore()..setPublicKeyHex = connector.selfPublicKeyHex;
      expect((await store.loadScreenOrder()).last, companionCliOrderKey);
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
    await tester.tap(find.byTooltip(l10n.repeater_clearHistory));
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
