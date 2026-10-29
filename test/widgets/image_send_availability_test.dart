import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshcore_open/helpers/image_send_availability.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/widgets/chat_additional_actions_menu.dart';
import 'package:meshcore_open/widgets/image_send_codec_binding.dart';

void main() {
  Future<void> showActions(
    WidgetTester tester, {
    required ImageSendCodec? Function() codec,
    String? reason,
    required VoidCallback onSelection,
  }) async {
    void noAction() {}
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Builder(builder: (context) => ChatAdditionalActionsButton(
        canvasActive: false,
        onSendSelfContact: noAction,
        onSendMyLocation: noAction,
        onSendContact: noAction,
        onPickLocationFromMap: noAction,
        onOpenQuickAnswers: noAction,
        onSendGif: noAction,
        onSendImage: () async {
          if (await ensureImageSendAvailable(context, codec: codec(), statusReason: reason)) {
            onSelection();
          }
        },
        onOpenCanvas: noAction,
        onOpenMcoImageGallery: noAction,
      ))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
  }

  Future<void> chooseImage(WidgetTester tester) async {
    final context = tester.element(find.byType(ChatAdditionalActionsMenu));
    final label = AppLocalizations.of(context).chat_sendImage;
    await tester.tap(find.widgetWithText(ListTile, label));
    await tester.pumpAndSettle();
    expect(find.byType(ChatAdditionalActionsMenu), findsNothing);
  }

  testWidgets('a visible image action closes its menu and explains a missing model', (tester) async {
    var selections = 0;
    const reason = 'The model is not installed. Download it in Settings.';
    await showActions(tester,
      codec: () => const FakeImageSendCodec(availability: ImageCodecAvailability.disabled),
      reason: reason, onSelection: () => selections++);
    await chooseImage(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(reason), findsOneWidget);
    expect(selections, 0);
    final context = tester.element(find.byType(AlertDialog));
    await tester.tap(find.text(AppLocalizations.of(context).common_close));
    await tester.pumpAndSettle();
    // It remains an actionable explanation, rather than an inert menu entry.
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    await chooseImage(tester);
    expect(find.text(reason), findsOneWidget);
    expect(selections, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a backend failure explains why without starting selection or inference', (tester) async {
    var selections = 0;
    await showActions(tester, codec: () => const FakeImageSendCodec(
      availability: ImageCodecAvailability.unavailable,
      unavailableReason: 'Synthetic backend failure'),
      onSelection: () => selections++);
    await chooseImage(tester);
    expect(find.text('Synthetic backend failure'), findsOneWidget);
    expect(selections, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a ready codec continues to image selection', (tester) async {
    var selections = 0;
    await showActions(tester, codec: () => const FakeImageSendCodec(),
      onSelection: () => selections++);
    await chooseImage(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(selections, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('readiness is rechecked after the action menu has opened', (tester) async {
    var selections = 0;
    ImageSendCodec? codec = const FakeImageSendCodec();
    await showActions(tester, codec: () => codec, onSelection: () => selections++);
    codec = null;
    await chooseImage(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    final context = tester.element(find.byType(AlertDialog));
    expect(find.text(AppLocalizations.of(context).imageSend_codecUnavailable), findsOneWidget);
    expect(selections, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
