import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/widgets/chat_additional_actions_menu.dart';
import 'package:meshcore_open/widgets/composer_text_builder.dart';

const _draft = '  Черновик 👩‍💻\nhttps://example.com/photo.png\nконец  ';

void main() {
  Future<AppLocalizations> showComposer(
    WidgetTester tester, {
    required TextEditingController controller,
    required List<String> calls,
    String language = 'en',
    bool offline = false,
    bool canvas = true,
    bool imageEnabled = true,
    bool ipfs = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              ComposerTextBuilder(
                controller: controller,
                builder: (context, text) => TextField(controller: controller),
              ),
              ChatAdditionalActionsButton(
                canvasActive: canvas,
                offlineMode: offline,
                onSendSelfContact: () => calls.add('self'),
                onSendMyLocation: () => calls.add('location'),
                onSendContact: () => calls.add('contact'),
                onPickLocationFromMap: () => calls.add('map'),
                onOpenQuickAnswers: () => calls.add('answers'),
                onSendGif: () => calls.add('gif'),
                onSendImage: () => calls.add('aeic'),
                sendImageEnabled: imageEnabled,
                onSendIpfs: ipfs ? () => calls.add('ipfs') : null,
                onOpenCanvas: () => calls.add('canvas'),
                onOpenMcoImageGallery: () => calls.add('gallery'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(
      tester.element(find.byType(ChatAdditionalActionsButton)),
    );
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byType(ChatAdditionalActionsButton));
    await tester.pumpAndSettle();
  }

  for (final language in ['en', 'ru']) {
    testWidgets('U08 baseline: existing attachments preserve draft ($language)', (
      tester,
    ) async {
      final controller = TextEditingController(text: _draft);
      addTearDown(controller.dispose);
      final calls = <String>[];
      final l10n = await showComposer(
        tester, controller: controller, calls: calls, language: language,
      );
      final actions = <String, String>{
        l10n.chat_sendSelfContact: 'self',
        l10n.chat_sendContact: 'contact',
        l10n.chat_myLocation: 'location',
        l10n.chat_locationFromMap: 'map',
        l10n.settings_quickAnswersTitle: 'answers',
        l10n.chat_sendGif: 'gif',
        l10n.chat_sendImage: 'aeic',
        l10n.chat_canvas: 'canvas',
        l10n.chat_MCOimgOpenGallery: 'gallery',
      };

      // Dismissing the menu must not choose a callback or alter the draft.
      await openMenu(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(controller.text, _draft);

      for (final entry in actions.entries) {
        await openMenu(tester);
        final tile = find.widgetWithText(ListTile, entry.key);
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(calls, [entry.value]);
        expect(find.byType(ChatAdditionalActionsMenu), findsNothing);
        expect(controller.text, _draft);
        calls.clear();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('U08 baseline: offline keeps only local canvas/gallery actions', (
    tester,
  ) async {
    final controller = TextEditingController(text: _draft);
    addTearDown(controller.dispose);
    final calls = <String>[];
    final l10n = await showComposer(
      tester, controller: controller, calls: calls, offline: true, ipfs: true,
    );
    await openMenu(tester);
    expect(find.byType(ListTile), findsNWidgets(2));
    expect(find.text(l10n.chat_sendImage), findsNothing);
    expect(find.text(l10n.chat_sendGif), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, l10n.chat_MCOimgOpenGallery));
    await tester.pumpAndSettle();
    expect(calls, ['gallery']);
    expect(controller.text, _draft);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('IPFS picker callback waits for the sheet to finish closing', (
    tester,
  ) async {
    final controller = TextEditingController(text: _draft);
    addTearDown(controller.dispose);
    final calls = <String>[];
    final l10n = await showComposer(
      tester, controller: controller, calls: calls, ipfs: true,
    );
    await openMenu(tester);
    final tile = find.widgetWithText(ListTile, l10n.chat_sendImageIpfs);
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.tap(tile);
    await tester.pump();
    expect(calls, isEmpty);
    await tester.pumpAndSettle();
    expect(calls, ['ipfs']);
    expect(find.byType(ChatAdditionalActionsMenu), findsNothing);
    expect(controller.text, _draft);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('U08 baseline: unavailable AEIC action does not invoke a picker', (
    tester,
  ) async {
    final controller = TextEditingController(text: _draft);
    addTearDown(controller.dispose);
    final calls = <String>[];
    final l10n = await showComposer(
      tester, controller: controller, calls: calls, imageEnabled: false,
    );
    await openMenu(tester);
    final image = find.widgetWithText(ListTile, l10n.chat_sendImage);
    expect(tester.widget<ListTile>(image).onTap, isNull);
    await tester.ensureVisible(image);
    await tester.pumpAndSettle();
    await tester.tap(image);
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(controller.text, _draft);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
