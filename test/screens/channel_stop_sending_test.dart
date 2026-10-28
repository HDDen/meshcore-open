import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/helpers/ui_notification_batcher.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/screens/channel_chat_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/chat_text_scale_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/stop_sending_bar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _channel = Channel(index: 0, name: 'synthetic', psk: Uint8List(16));

class _Node extends MeshCoreConnector {
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
