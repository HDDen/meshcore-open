import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/mcoa_theme_preview_data.dart';
import 'package:meshcore_open/helpers/mcoa_theme_options.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/custom_theme.dart';
import 'package:meshcore_open/models/bookmarked_message.dart';
import 'package:meshcore_open/screens/channel_chat_screen.dart';
import 'package:meshcore_open/screens/channels_screen.dart';
import 'package:meshcore_open/screens/chat_screen.dart';
import 'package:meshcore_open/screens/contacts_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/contact_chat_composer.dart';
import 'package:meshcore_open/widgets/contact_chat_title.dart';
import 'package:meshcore_open/widgets/mcoa_theme_preview.dart';
import 'package:meshcore_open/widgets/mention_chip.dart';
import 'package:meshcore_open/widgets/tx_power_boost_badge.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Iterable<TextSpan> _textSpans(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    for (final child in span.children ?? const <InlineSpan>[]) {
      yield* _textSpans(child);
    }
  }
}

Iterable<TextSpan> _messageSpans(WidgetTester tester, Finder root) sync* {
  for (final rich in tester.widgetList<RichText>(find.descendant(
    of: root, matching: find.byType(RichText),
  ))) {
    yield* _textSpans(rich.text);
  }
  for (final selectable in tester.widgetList<SelectableText>(find.descendant(
    of: root, matching: find.byType(SelectableText),
  ))) {
    final span = selectable.textSpan;
    if (span != null) yield* _textSpans(span);
  }
}

void main() {
  final openedAt = DateTime(2026, 11, 20, 23, 59);
  final theme = CustomTheme(
    id: 'preview',
    name: 'Preview',
    background: const Color(0xFF17112A),
    accent: const Color(0xFFA855F7),
    mcoa: const McoaThemeOptions(colors: {
      'incoming_sender_name': Color(0xFFAA55BB),
      'incoming_text': Color(0xFF556677),
      'outgoing_text': Color(0xFF336677),
      'incoming_mention_text': Color(0xFFAA2233),
      'outgoing_mention_text': Color(0xFFCC7733),
      'incoming_link': Color(0xFF11AA77),
      'outgoing_link': Color(0xFFAA7711),
      'incoming_signal': Color(0xFF3355BB),
      'outgoing_signal': Color(0xFFBB5533),
    }),
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
      expect(message.text, endsWith('\nhttps://localhost'));
    }
    for (final message in data.directMessages) {
      expect(message.timestamp.day, 18);
      expect(message.text, endsWith('\nhttps://localhost'));
    }
    expect(data.alice.publicKey, hasLength(32));
    expect(data.bob.publicKey, hasLength(32));
    expect(data.alice.publicKeyHex, isNot(data.bob.publicKeyHex));
    expect(data.directMessages.last.tripTimeMs, 1200);
    expect(data.directMessages.last.airtimeMs, 549);
    expect(data.bookmarkRevision, 0);
    for (final message in data.channelMessages) {
      expect(data.isMessageBookmarked(
        BookmarkSourceType.channel,
        data.chatChannel.storageId!,
        message.messageId,
      ), isFalse);
    }
    for (final message in data.directMessages) {
      expect(data.isMessageBookmarked(
        BookmarkSourceType.contact,
        data.alice.publicKeyHex,
        message.messageId,
      ), isFalse);
    }
    expect(
      () => data.loadBookmarkedMessages(),
      throwsUnsupportedError,
    );
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
        find.byType(ChannelChatScreen).first,
      );
      expect(channel.channel.name, '#channel0');
      expect(channel.previewMessages, hasLength(2));
      expect(find.byType(ChannelChatScreen), findsOneWidget);
      for (final message in channel.previewMessages!) {
        expect(message.replyToSenderName, isNotEmpty);
        expect(message.replyToText, isNotEmpty);
        expect(message.replyIsExact, isTrue);
      }
      for (final direction in ['incoming', 'outgoing']) {
        final body = find.byKey(ValueKey('theme-preview-$direction-body'));
        expect(body, findsOneWidget);
        final links = _messageSpans(tester, body)
            .where((span) => span.text == 'https://localhost').toList();
        expect(links, isNotEmpty);
        for (final link in links) {
          expect(link.style!.color, theme.mcoa.colors['${direction}_link']);
          expect(link.style!.decorationColor, theme.mcoa.colors['${direction}_link']);
        }
        final mentions = tester.widgetList<MentionChip>(find.descendant(
          of: body,
          matching: find.byType(MentionChip),
        ));
        expect(mentions, hasLength(2));
        expect(mentions.map((chip) => chip.simplified), [false, true]);
        for (final chip in mentions) {
          final label = tester.widget<Text>(find.descendant(
            of: find.byWidget(chip), matching: find.text('@senderName'),
          ));
          final key = direction + (chip.simplified ? '_text' : '_mention_text');
          expect(label.style!.color, theme.mcoa.colors[key]);
        }
      }

      for (final entry in {
        '4.8dB': 'incoming_signal', '-89dBm': 'incoming_signal',
        '-1.3dB': 'outgoing_signal', '-98dBm': 'outgoing_signal',
      }.entries) {
        final readings = tester.widgetList<RichText>(find.byType(RichText))
            .expand((rich) => _textSpans(rich.text))
            .where((span) => span.text?.contains(entry.key) ?? false).toList();
        expect(readings, isNotEmpty);
        for (final reading in readings) {
          expect(reading.style!.color, theme.mcoa.colors[entry.value]);
        }
      }
      expect(find.text('senderName'), findsWidgets);
      expect(tester.widget<Text>(find.text('senderName')).style!.color,
          const Color(0xFFAA55BB));
      expect(find.text(l10n.themes_previewIncoming, findRichText: true), findsWidgets);
      expect(find.text(l10n.themes_previewOutgoing, findRichText: true), findsWidgets);
      expect(find.byType(ContactChatComposer), findsOneWidget);
      expect(find.byType(TxPowerBoostBadge), findsOneWidget);
      final timestamp = channel.previewMessages!.first.timestamp;

      await select(1);
      expect(find.byType(ContactMessageBubble), findsNWidgets(2));
      for (final outgoing in [false, true]) {
        final bubbles = find.byType(ContactMessageBubble);
        final root = outgoing ? bubbles.last : bubbles.first;
        final links = _messageSpans(tester, root)
            .where((span) => span.text == 'https://localhost').toList();
        expect(links, isNotEmpty);
        final key = outgoing ? 'outgoing_link' : 'incoming_link';
        for (final link in links) {
          expect(link.style!.color, theme.mcoa.colors[key]);
          expect(link.style!.decorationColor, theme.mcoa.colors[key]);
        }
      }
      expect(tester.widget<Text>(find.descendant(
        of: find.byType(ContactMessageBubble).first, matching: find.text('Alice'),
      )).style!.color, const Color(0xFFAA55BB));
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
        tester.widget<ChannelChatScreen>(find.byType(ChannelChatScreen).first)
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
