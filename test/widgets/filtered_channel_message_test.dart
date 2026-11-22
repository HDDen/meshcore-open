import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/models/message_filter.dart';
import 'package:meshcore_open/services/message_filter/message_filter_service.dart';
import 'package:meshcore_open/storage/message_filter_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/filtered_channel_message.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _manual = FilterVerdict(reason: FilterReason.manual);
const _action = ValueKey('spam-action');

class _Store extends MessageFilterStore {
  MessageFilterSettings settings = const MessageFilterSettings(enabled: true);
  Completer<void>? holdSave;
  int saves = 0;
  List<FilterRule> rules = const [];

  @override
  MessageFilterSettings loadSettings() => settings;

  @override
  List<FilterRule> loadRules() => rules;

  @override
  Future<void> saveRules(List<FilterRule> value) async {
    rules = List.of(value);
  }

  @override
  Future<({int spam, int notSpam})> loadTrainingLabelCounts() async =>
      (spam: 0, notSpam: 0);

  @override
  Future<void> saveSettings(MessageFilterSettings next) async {
    saves++;
    await holdSave?.future;
    settings = next;
  }
}

class _Connector extends MeshCoreConnector {
  _Connector({required super.messageFilterService});

  final marks = <({bool learningEnabled, FilterVerdict? verdict})>[];
  final markedPosts = <ChannelMessage>[];

  @override
  Future<bool> setChannelMessageFilterVerdict(
    Channel channel,
    ChannelMessage message,
    FilterVerdict? verdict,
  ) async {
    markedPosts.add(message);
    marks.add((
      learningEnabled: messageFilterService!.learningEnabled,
      verdict: verdict,
    ));
    return true;
  }
}

class _ReviewConnector extends _Connector {
  _ReviewConnector({required super.messageFilterService, required this.posts});

  final List<ChannelMessage> posts;

  @override
  List<ChannelMessage> getChannelMergedMessages(Channel channel) => posts;
}

Future<AppLocalizations> _open(
  WidgetTester tester,
  _Connector connector, {
  required FilterVerdict? verdict,
}) async {
  final channel = Channel.fromHex(0, 'Test', Channel.publicChannelPsk);
  final now = DateTime.utc(2026);
  final message = ChannelMessage(
    channelIndex: channel.index,
    senderName: 'Alice',
    text: 'Example post',
    timestamp: now,
    receivedAt: now,
    isOutgoing: false,
    filterVerdict: verdict == null ? _manual : null,
  );
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: verdict == null
            ? FilteredChannelMessage(
                key: _action,
                connector: connector,
                channel: channel,
                message: message,
              )
            : Builder(
                builder: (context) => TextButton(
                  key: _action,
                  onPressed: () => saveChannelMessageVerdict(
                    context,
                    connector,
                    channel,
                    message,
                    verdict,
                  ),
                  child: const Text('Test'),
                ),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final l10n = AppLocalizations.of(tester.element(find.byKey(_action)));
  if (verdict == null) {
    await tester.tap(find.text(l10n.messageFilter_ghostSingle));
    await tester.pumpAndSettle();
  }
  return l10n;
}

void main() {
  testWidgets('sender unblock preserves and disables rules without marking posts', (tester) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(PrefsManager.reset);
    await tester.runAsync(PrefsManager.initialize);
    const rule = FilterRule(id: 'name', pattern: 'Alice',
      field: FilterRuleField.sender, match: FilterRuleMatch.exact);
    final store = _Store()..rules = [rule];
    final service = MessageFilterService(store: store)..load();
    final connector = _Connector(messageFilterService: service);
    addTearDown(service.dispose);
    addTearDown(connector.dispose);
    final l10n = await _open(tester, connector, verdict: null);
    expect(find.text(l10n.messageFilter_notSpam), findsOneWidget);
    await tester.tap(find.text(l10n.messageFilter_unblockSender));
    await tester.pumpAndSettle();
    expect(service.rules, [rule.withEnabled(false)]);
    expect(store.rules, service.rules);
    expect(connector.marks, isEmpty);
    // Complete the debounced history write inside the widget test zone.
    // addTearDown runs after the pending-timer invariant is checked.
    await connector.flushChannelRuleVerdicts();
  });

  testWidgets('filtered placeholder shows sender with compact typography', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(PrefsManager.reset);
    await tester.runAsync(PrefsManager.initialize);
    final service = MessageFilterService(store: _Store())..load();
    final connector = _Connector(messageFilterService: service);
    addTearDown(service.dispose);
    addTearDown(connector.dispose);

    final l10n = await _open(tester, connector, verdict: null);
    final tile = tester.widget<ExpansionTile>(find.byType(ExpansionTile));
    final compactStyle = Theme.of(
      tester.element(find.byType(FilteredChannelMessage)),
    ).textTheme.bodySmall;
    expect((tile.title as Text).style, compactStyle);
    expect((tile.subtitle as Text).data, 'Alice');
    expect((tile.subtitle as Text).style, compactStyle);
    expect(find.text(l10n.messageFilter_reasonManual), findsOneWidget);
    expect(find.text('Alice: Example post'), findsOneWidget);

    await tester.tap(find.text(l10n.messageFilter_ghostSingle));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text(l10n.messageFilter_reasonManual), findsNothing);
    expect(find.text('Alice: Example post'), findsNothing);
  });

  testWidgets('U34 baseline: review keeps a shared post separate and read-only', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(PrefsManager.reset);
    await tester.runAsync(PrefsManager.initialize);
    final channel = Channel.fromHex(0, 'Test', Channel.publicChannelPsk);
    final now = DateTime.utc(2026);
    final shared = ChannelMessage(
      channelIndex: channel.index,
      messageId: 'same-id',
      senderName: 'Alice',
      text: 'Shared post',
      timestamp: now,
      receivedAt: now,
      isOutgoing: false,
      filterVerdict: _manual,
      sharedHistorySourceName: 'Another node',
    );
    final local = shared.copyWith(sharedHistorySourceName: null);
    final service = MessageFilterService(store: _Store())..load();
    final connector = _ReviewConnector(
      messageFilterService: service,
      posts: [shared, local],
    );
    addTearDown(service.dispose);
    addTearDown(connector.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MeshCoreConnector>.value(
        value: connector,
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: FilteredChannelGroup(messages: [shared], channel: channel),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(FilteredChannelGroup));
    await tester.pumpAndSettle();

    final tile = find.byType(FilteredChannelMessage);
    expect(tester.widget<FilteredChannelMessage>(tile).message, same(shared));
    final l10n = AppLocalizations.of(tester.element(tile));
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      'Alice: Shared post',
    );
    expect(find.text(l10n.messageFilter_notSpam), findsNothing);
    expect(connector.marks, isEmpty);

    expect(find.byType(ExpansionTile), findsNothing);
    expect(tester.getSize(tile).width, tester.getSize(find.byType(ListView)).width);
    expect(find.text('Alice'), findsNothing);
    expect(find.text(l10n.messageFilter_reasonManual), findsNothing);
    await tester.longPressAt(tester.getTopLeft(tile) + const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text(l10n.chat_selectedCount(1)), findsOneWidget);
    expect(find.byTooltip(l10n.messageFilter_notSpam), findsNothing);
    expect(find.byTooltip(l10n.common_delete), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(l10n.messageFilter_displayTitle), findsOneWidget);
    expect(tile, findsOneWidget);
  });

  testWidgets('U34: bulk restore asks once and skips shared posts', (tester) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(PrefsManager.reset);
    await tester.runAsync(PrefsManager.initialize);
    final channel = Channel.fromHex(0, 'Test', Channel.publicChannelPsk);
    final now = DateTime.utc(2026);
    ChannelMessage post(String text, {String? source}) => ChannelMessage(
      channelIndex: channel.index,
      messageId: text,
      senderName: 'Alice',
      text: text,
      timestamp: now,
      receivedAt: now,
      isOutgoing: false,
      filterVerdict: _manual,
      sharedHistorySourceName: source,
    );
    final posts = [post('First'), post('Second'), post('Shared', source: 'Node')];
    final store = _Store();
    final service = MessageFilterService(store: store)..load();
    final connector = _ReviewConnector(messageFilterService: service, posts: posts);
    addTearDown(service.dispose);
    addTearDown(connector.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MeshCoreConnector>.value(
        value: connector,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: FilteredChannelGroup(messages: posts, channel: channel)),
        ),
      ),
    );
    await tester.tap(find.byType(FilteredChannelGroup));
    await tester.pumpAndSettle();
    final appBar = find.byType(AppBar);
    final l10n = AppLocalizations.of(tester.element(appBar));
    expect(find.byType(ExpansionTile), findsNothing);
    await tester.longPressAt(
      tester.getTopLeft(find.byType(FilteredChannelMessage).first) + const Offset(4, 4),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(MaterialLocalizations.of(
      tester.element(appBar),
    ).showMenuTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.chat_selectAll));
    await tester.pumpAndSettle();
    expect(find.text(l10n.chat_selectedCount(3)), findsOneWidget);

    final notSpam = find.byTooltip(l10n.messageFilter_notSpam);
    await tester.tap(notSpam);
    await tester.pumpAndSettle();
    expect(find.text(l10n.messageFilter_enableLearningPrompt), findsOneWidget);
    await tester.tap(find.text(l10n.common_cancel));
    await tester.pumpAndSettle();
    expect(connector.marks, isEmpty);
    expect(store.saves, 0);
    expect(find.text(l10n.chat_selectedCount(3)), findsOneWidget);

    await tester.tap(notSpam);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.common_ok));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(store.saves, 1);
    expect(connector.markedPosts, posts.take(2));
    expect(connector.marks, List.filled(2, (learningEnabled: true, verdict: null)));
  });

  for (final (name, verdict) in [('spam', _manual), ('restore', null)]) {
    testWidgets('cancel does not apply the $name action', (
      tester,
    ) async {
      final store = _Store();
      final service = MessageFilterService(store: store)..load();
      final connector = _Connector(messageFilterService: service);
      addTearDown(service.dispose);
      addTearDown(connector.dispose);
      final l10n = await _open(tester, connector, verdict: verdict);
      final action = verdict == null
          ? find.text(l10n.messageFilter_notSpam)
          : find.byKey(_action);

      await tester.tap(action);
      await tester.pumpAndSettle();
      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(dialog.title, isNull);
      expect((dialog.content! as Text).data, l10n.messageFilter_enableLearningPrompt);
      expect(connector.marks, isEmpty);

      await tester.tap(find.text(l10n.common_cancel));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(connector.marks, isEmpty);
      expect(store.saves, 0);
      expect(service.learningEnabled, isFalse);
      if (verdict == null) {
        final tile = tester.widget<FilteredChannelMessage>(find.byKey(_action));
        expect(tile.message.filterVerdict, _manual);
        expect(find.text(l10n.messageFilter_reasonManual), findsOneWidget);
        final body = tester.widget<SelectableText>(find.byType(SelectableText));
        expect(body.data, 'Alice: Example post');
      }
    });

    testWidgets('OK saves learning before applying the $name action', (tester) async {
      final store = _Store()..holdSave = Completer<void>();
      final service = MessageFilterService(store: store)..load();
      final connector = _Connector(messageFilterService: service);
      addTearDown(service.dispose);
      addTearDown(connector.dispose);
      final l10n = await _open(tester, connector, verdict: verdict);
      final action = verdict == null
          ? find.text(l10n.messageFilter_notSpam)
          : find.byKey(_action);

      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.common_ok));
      await tester.pumpAndSettle();
      expect(store.saves, 1);
      expect(store.settings.learning, isFalse);
      expect(connector.marks, isEmpty);

      store.holdSave!.complete();
      await tester.pumpAndSettle();
      expect(store.settings.learning, isTrue);
      expect(connector.marks, [(learningEnabled: true, verdict: verdict)]);

      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(connector.marks, hasLength(2));
      expect(store.saves, 1);
    });
  }
}
