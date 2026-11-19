import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/mcoa_theme_preview_data.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/custom_theme.dart';
import 'package:meshcore_open/screens/channel_chat_screen.dart';
import 'package:meshcore_open/screens/channels_screen.dart';
import 'package:meshcore_open/screens/chat_screen.dart';
import 'package:meshcore_open/screens/contacts_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/contact_chat_composer.dart';
import 'package:meshcore_open/widgets/contact_chat_title.dart';
import 'package:meshcore_open/widgets/mcoa_theme_preview.dart';
import 'package:meshcore_open/widgets/tx_power_boost_badge.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final openedAt = DateTime(2026, 11, 20, 23, 59);
  final theme = CustomTheme(
    id: 'preview',
    name: 'Preview',
    background: const Color(0xFF17112A),
    accent: const Color(0xFFA855F7),
  );

  test('fixtures use two-byte hops and one stable date two days earlier', () {
    final data = McoaThemePreviewData(
      openedAt: openedAt,
      incomingText: 'Incoming',
      outgoingText: 'Outgoing',
      defaultSender: 'default',
    );
    addTearDown(data.dispose);
    for (final message in data.channelMessages) {
      expect(message.timestamp.day, 18);
      expect(message.pathLength, 2);
      expect(message.pathHashWidth, 2);
      expect(message.pathBytes, [0xaa, 0xaa, 0xaa, 0xaa]);
      expect(message.packetRegion, 'any-region');
    }
    for (final message in data.directMessages) {
      expect(message.timestamp.day, 18);
    }
    expect(data.alice.publicKey, hasLength(32));
    expect(data.bob.publicKey, hasLength(32));
    expect(data.alice.publicKeyHex, isNot(data.bob.publicKeyHex));
    expect(data.directMessages.last.tripTimeMs, 1200);
    expect(data.directMessages.last.airtimeMs, 549);
    expect(
      () => data.noSuchMethod(Invocation.method(#sendFrame, [])),
      throwsUnsupportedError,
    );
  });

  for (final locale in ['en', 'ru']) {
    testWidgets('preview reuses chat and list widgets without a live node ($locale)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      PrefsManager.reset();
      final settings = AppSettingsService();
      addTearDown(settings.dispose);
      final before = settings.settings.toJson();
      final prefs = await SharedPreferences.getInstance();
      final initialKeys = prefs.getKeys();

      Widget app(CustomTheme draft) => ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale(locale),
          home: Scaffold(
            body: SingleChildScrollView(
              child: McoaThemePreview(
                theme: draft,
                openedAt: openedAt,
              ),
            ),
          ),
        ),
      );

      Future<void> select(int tab) async {
        final target = find.byKey(ValueKey('theme-preview-tab-$tab'));
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
      }

      await tester.pumpWidget(app(theme));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(McoaThemePreview)),
      );
      final channel = tester.widget<ChannelChatScreen>(
        find.byType(ChannelChatScreen),
      );
      expect(channel.channel.name, '#channel0');
      expect(channel.previewMessages, hasLength(2));
      expect(find.text('senderName'), findsOneWidget);
      expect(find.text(l10n.themes_previewIncoming, findRichText: true), findsOneWidget);
      expect(find.text(l10n.themes_previewOutgoing, findRichText: true), findsOneWidget);
      expect(find.byType(ContactChatComposer), findsOneWidget);
      expect(find.byType(TxPowerBoostBadge), findsOneWidget);
      final timestamp = channel.previewMessages!.first.timestamp;

      await select(1);
      expect(find.byType(ContactMessageBubble), findsNWidgets(2));
      expect(find.byType(ContactChatTitle), findsOneWidget);
      expect(find.byType(ContactChatComposer), findsOneWidget);
      expect(find.byType(TxPowerBoostBadge), findsOneWidget);

      await select(2);
      expect(find.byType(ChannelsScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('channel_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('channel_7')), findsOneWidget);

      await select(3);
      expect(find.byType(ContactThemePreviewTile), findsNWidgets(2));
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      await tester.pumpWidget(app(theme.copyWith(accent: Colors.orange)));
      await tester.pump();
      expect(find.byType(ContactThemePreviewTile), findsNWidgets(2));

      await select(0);
      expect(
        tester.widget<ChannelChatScreen>(find.byType(ChannelChatScreen))
            .previewMessages!.first.timestamp,
        timestamp,
      );
      expect(settings.settings.toJson(), before);
      expect(prefs.getKeys(), initialKeys);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  }
}
