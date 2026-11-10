import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/helpers/ui_notification_batcher.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/models/message_filter.dart';
import 'package:meshcore_open/screens/channel_chat_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/chat_text_scale_service.dart';
import 'package:meshcore_open/services/message_filter/message_filter_service.dart';
import 'package:meshcore_open/services/translation_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/chat_additional_actions_menu.dart';
import 'package:meshcore_open/widgets/chat_bubble_box.dart';
import 'package:meshcore_open/widgets/filtered_channel_message.dart';
import 'package:meshcore_open/widgets/stop_sending_bar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _channel = Channel(index: 0, name: 'synthetic', psk: Uint8List(16));

class _Node extends MeshCoreConnector {
  _Node({super.messageFilterService});

  @override
  bool get isConnected => true;
  @override
  String? get selfName => 'Synthetic';
  @override
  void setActiveChannel(int? channelIndex) {}
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  testWidgets('U27f: a quote can reach a member of a filtered group', (
    tester,
  ) async {
    final filter = MessageFilterService();
    await filter.updateSettings(const MessageFilterSettings(enabled: true));
    final node = _Node(messageFilterService: filter);
    final settings = AppSettingsService();
    final scale = ChatTextScaleService();
    addTearDown(filter.dispose);
    addTearDown(node.dispose);
    addTearDown(settings.dispose);
    addTearDown(scale.dispose);

    final channel = Channel.fromHex(0, 'synthetic', Channel.publicChannelPsk);
    final now = DateTime(2026, 1, 1, 12);
    ChannelMessage post(String id, int seconds, {bool filtered = true}) {
      final at = now.add(Duration(seconds: seconds));
      return ChannelMessage(
        messageId: id,
        senderName: 'Alice',
        text: id,
        timestamp: at,
        receivedAt: at,
        isOutgoing: false,
        status: ChannelMessageStatus.sent,
        filterVerdict: filtered
            ? const FilterVerdict(reason: FilterReason.manual)
            : null,
      );
    }

    final first = post('hidden-first', 0);
    final second = post('hidden-second', 1);
    final reply = post('visible-reply', 2, filtered: false).copyWith(
      replyToMessageId: first.messageId,
      replyToSenderName: first.senderName,
      replyToText: first.text,
    );
    node.setChannelMessagesForTest(channel.index, [first, second, reply]);

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
          home: ChannelChatScreen(channel: channel),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final group = find.byType(FilteredChannelGroup);
    expect(group, findsOneWidget);
    final l10n = AppLocalizations.of(tester.element(group));
    final quote = find.text(l10n.messageFilter_ghostIconTooltip);
    expect(quote, findsOneWidget);
    expect(find.text(l10n.messageFilter_loadOlder), findsOneWidget);
    expect(find.text(first.text), findsNothing);
    await tester.tap(quote);
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text(l10n.chat_originalMessageNotFound), findsNothing);

    await tester.tap(group);
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    Finder body(String id) => find.byWidgetPredicate(
      (widget) => widget is SelectableText && widget.data == 'Alice: $id',
    );
    expect(body(first.messageId), findsOneWidget);
    expect(body(second.messageId), findsOneWidget);
    expect(find.text(l10n.messageFilter_notSpam), findsNWidgets(2));
    expect(find.text(reply.text), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('U27g: channel actions create rules and toggle one channel', (
    tester,
  ) async {
    final filter = MessageFilterService();
    await filter.updateSettings(const MessageFilterSettings(enabled: true));
    final node = _Node(messageFilterService: filter);
    final settings = AppSettingsService();
    final translation = TranslationService(settings);
    final scale = ChatTextScaleService();
    addTearDown(filter.dispose);
    addTearDown(node.dispose);
    addTearDown(settings.dispose);
    addTearDown(translation.dispose);
    addTearDown(scale.dispose);

    final channel = Channel.fromHex(0, 'synthetic', Channel.publicChannelPsk);
    final now = DateTime.utc(2026);
    final message = ChannelMessage(
      senderName: 'Alice',
      text: 'An ordinary message',
      timestamp: now,
      receivedAt: now,
      isOutgoing: false,
      status: ChannelMessageStatus.sent,
    );
    node.setChannelMessagesForTest(channel.index, [message]);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MeshCoreConnector>.value(value: node),
          ChangeNotifierProvider<AppSettingsService>.value(value: settings),
          ChangeNotifierProvider<ChatTextScaleService>.value(value: scale),
          ChangeNotifierProvider<TranslationService>.value(value: translation),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChannelChatScreen(channel: channel),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(AppBar)));
    final filterLike = find.text(l10n.messageFilter_filterLikeThis);
    final filterSender = find.text(l10n.messageFilter_filterSender);

    Future<void> openMessageActions() async {
      final bubble = find.byType(ChatBubbleBox);
      final position = tester.getTopLeft(bubble) + const Offset(12, 6);
      await tester.longPressAt(position);
      await tester.pumpAndSettle();
    }

    await openMessageActions();
    expect(filterLike, findsOneWidget);
    await tester.tap(filterLike);
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(field).controller!.text, message.text);
    await tester.enterText(field, 'Another phrase');
    await tester.tap(find.text(l10n.common_save));
    await tester.pumpAndSettle();
    expect(filter.rules.single.pattern, 'Another phrase');
    expect(filter.rules.single.field, FilterRuleField.text);

    await openMessageActions();
    await tester.tap(filterSender);
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.messageFilter_filterSenderConfirm(message.senderName)),
      findsOneWidget,
    );
    await tester.tap(find.text(l10n.common_cancel));
    await tester.pumpAndSettle();
    expect(filter.rules, hasLength(1));

    await openMessageActions();
    await tester.tap(filterSender);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.common_save));
    await tester.pumpAndSettle();
    expect(filter.rules.last.pattern, message.senderName);
    expect(filter.rules.last.field, FilterRuleField.sender);
    expect(filter.rules.last.match, FilterRuleMatch.exact);
    expect(filter.learningEnabled, isFalse);
    expect(find.byType(FilteredChannelMessage), findsOneWidget);

    final menu = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(PopupMenuButton<String>),
    );
    Future<void> toggleChannel({required bool checked}) async {
      await tester.tap(menu);
      await tester.pumpAndSettle();
      final entry = find.widgetWithText(
        CheckedPopupMenuItem<String>,
        l10n.messageFilter_currentChannelToggle,
      );
      expect(tester.widget<CheckedPopupMenuItem<String>>(entry).checked, checked);
      await tester.tap(entry);
      await tester.pumpAndSettle();
    }

    await toggleChannel(checked: true);
    expect(filter.appliesTo(channel.storageId), isFalse);
    expect(find.byType(FilteredChannelMessage), findsNothing);
    await toggleChannel(checked: false);
    expect(filter.appliesTo(channel.storageId), isTrue);
    expect(filter.rules, hasLength(2));
    expect(find.byType(FilteredChannelMessage), findsOneWidget);
    await node.flushChannelRuleVerdicts();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('U34: channel selection copies loaded messages in chat order', (
    tester,
  ) async {
    final node = _Node();
    final settings = AppSettingsService();
    final translation = TranslationService(settings);
    final scale = ChatTextScaleService();
    addTearDown(node.dispose);
    addTearDown(settings.dispose);
    addTearDown(translation.dispose);
    addTearDown(scale.dispose);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String? clipboard;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    final now = DateTime.utc(2026);
    ChannelMessage post(String text, int seconds) {
      final at = now.add(Duration(seconds: seconds));
      return ChannelMessage(
        messageId: text,
        senderName: 'Alice',
        text: text,
        timestamp: at,
        receivedAt: at,
        isOutgoing: false,
        status: ChannelMessageStatus.sent,
      );
    }
    final posts = [post('First post', 0), post('Second post', 1)];
    node.setChannelMessagesForTest(_channel.index, posts);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MeshCoreConnector>.value(value: node),
          ChangeNotifierProvider<AppSettingsService>.value(value: settings),
          ChangeNotifierProvider<ChatTextScaleService>.value(value: scale),
          ChangeNotifierProvider<TranslationService>.value(value: translation),
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

    final l10n = AppLocalizations.of(tester.element(find.byType(AppBar)));
    final bubble = find.byType(ChatBubbleBox).first;
    await tester.longPressAt(tester.getTopLeft(bubble) + const Offset(12, 6));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.chat_selectMessages));
    await tester.pumpAndSettle();
    expect(find.text(l10n.chat_selectedCount(1)), findsOneWidget);

    final toolbarMenu = find.byTooltip(MaterialLocalizations.of(
      tester.element(find.byType(AppBar)),
    ).showMenuTooltip);
    await tester.tap(toolbarMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.chat_selectAll));
    await tester.pumpAndSettle();
    expect(find.text(l10n.chat_selectedCount(2)), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.common_delete));
    await tester.pumpAndSettle();
    expect(find.text(l10n.chat_confirmDeleteSelected(2)), findsOneWidget);
    await tester.tap(find.text(l10n.common_cancel));
    await tester.pumpAndSettle();
    expect(find.text(l10n.chat_selectedCount(2)), findsOneWidget);
    expect(node.getLoadedChannelMessages(_channel), posts);

    await tester.tap(toolbarMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.common_copy));
    await tester.pumpAndSettle();
    expect(clipboard, 'Alice: First post\nAlice: Second post');
    expect(find.text(l10n.chat_selectedCount(2)), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final locale in ['ru', 'en']) {
    for (final finish in ['tap', 'coverage']) {
      testWidgets('channel bubble stops retries or hides after coverage ($locale, $finish)', (tester) async {
        final node = _Node();
        final settings = AppSettingsService();
        final scale = ChatTextScaleService();
        Future<void>? running;
        var resends = 0;
        try {
          await settings.updateSettings(AppSettings(
            channelMinHopsEnabled: true, channelMinHops: 2,
            channelMinHopsCountRepeaters: true, channelMinHopsRepeaterCount: 3,
            channelMinHopsDelaySeconds: 30, noRetransmissionWarningSeconds: 0,
          ));
          node.attachAppSettingsServiceForTest(settings);
          node.setChannelResendClockForTest(tester.binding.clock.now);
          final now = tester.binding.clock.now();
          final message = ChannelMessage(
            messageId: 'synthetic-stop-bubble', senderName: 'Synthetic', text: 'Hi',
            timestamp: now, sentByRadioAt: now, receivedAt: now,
            isOutgoing: true, status: ChannelMessageStatus.sent,
            repeatCount: 1, pathLength: 1, pathHashWidth: 2,
            pathBytes: Uint8List.fromList([0x81, 0x30]),
          );
          node.setChannelMessagesForTest(_channel.index, [message]);
          running = node.runChannelHopCheckForTest(message.messageId,
            minHops: 2, maxResends: 3, resend: () async { resends++; });
          tester.view.physicalSize = const Size(1000, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(MultiProvider(providers: [
            ChangeNotifierProvider<MeshCoreConnector>.value(value: node),
            ChangeNotifierProvider<AppSettingsService>.value(value: settings),
            ChangeNotifierProvider<ChatTextScaleService>.value(value: scale),
          ], child: MaterialApp(locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ChannelChatScreen(channel: _channel))));
          // The active attempt badge animates: never pumpAndSettle here.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          final bar = find.byKey(ValueKey('channel-stop-sending:${message.messageId}'));
          expect(bar, findsOneWidget);
          expect(find.byType(StopSendingBar), findsOneWidget);
          final l10n = AppLocalizations.of(tester.element(bar));
          expect(find.descendant(of: bar, matching: find.text(l10n.chat_stopSending)), findsOneWidget);
          // U19b layers are placed behind the existing composer and controls.
          final composer = find.byWidgetPredicate(
            (widget) => widget is EditableText && !widget.readOnly,
          ).hitTestable();
          expect(composer, findsOneWidget);
          final send = find.byType(ChatComposerSendButton).hitTestable();
          expect(send, findsOneWidget);
          expect(tester.widget<ChatComposerSendButton>(send).tooltip, l10n.chat_sendMessage);
          // The feature toggle hides the control without falsely completing delivery.
          await settings.updateSettings(settings.settings.copyWith(channelMinHopsEnabled: false));
          await tester.pump();
          expect(bar, findsNothing);
          await settings.updateSettings(settings.settings.copyWith(channelMinHopsEnabled: true));
          await tester.pump();
          expect(bar, findsOneWidget);
          if (finish == 'tap') {
            await tester.tap(bar);
            // ChatZoomWrapper распознаёт double-tap: одиночный onTap
            // проходит gesture arena после штатного kDoubleTapTimeout.
            await tester.pump(kDoubleTapTimeout);
          } else {
            void echo(List<int> path) {
              node.mergeChannelEchoForTest(_channel.index, ChannelMessage(
                messageId: message.messageId, senderName: message.senderName,
                text: message.text, timestamp: message.timestamp,
                receivedAt: tester.binding.clock.now(), isOutgoing: false,
                status: ChannelMessageStatus.sent, pathLength: 1, pathHashWidth: 2,
                pathBytes: Uint8List.fromList(path),
              ));
            }
            echo([0x81, 0x40]);
            await tester.pump(UiNotificationBatcher.minimum);
            expect(bar, findsOneWidget);
            echo([0x81, 0x50]);
          }
          // После распознавания tap/получения эхо состояние меняется сразу;
          // bubble обновляется после штатного окна UI-пакетирования.
          expect(node.canStopChannelSending(message.messageId), isFalse);
          await tester.pump(UiNotificationBatcher.minimum);
          expect(bar, findsNothing);
          expect(node.getChannelMessages(_channel).single.status, ChannelMessageStatus.sent);
          await tester.pump(const Duration(minutes: 2));
          expect(resends, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          node.dispose();
          await tester.pump();
          final pending = running;
          if (pending != null) { await pending; }
          settings.dispose();
          scale.dispose();
        }
      });
    }
  }
}
