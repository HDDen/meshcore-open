import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/chat_text_scale_service.dart';
import 'package:meshcore_open/widgets/formatted_message_text.dart';
import 'package:meshcore_open/widgets/reply_quote_box.dart';
import 'package:meshcore_open/widgets/translated_message_content.dart';
import 'package:provider/provider.dart';

// A right-click on a message opens its action menu once. Both chat screens
// catch the click on the bubble (onSecondaryTapUp) and hand the same menu to
// the body (onSecondaryTap) for a body that swallows the click itself: plain
// text is a SelectableText on a desktop. The last two tests are the change:
// a formatted body, text with a mention or a reply drawn as a mention, used
// to answer the click from a listener of its own as well and opened the menu
// twice.

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: Center(child: child)),
);

/// [_app] with the services a formatted body reads.
Widget _appWithServices(Widget child) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => ChatTextScaleService()),
    ChangeNotifierProvider(create: (_) => AppSettingsService()),
  ],
  child: _app(child),
);

/// A chat bubble as the chat screens build it on a desktop: the menu on the
/// bubble's right-click, and the same menu handed to its body.
Widget _bubble(Widget body, VoidCallback openMenu) => GestureDetector(
  key: const Key('bubble'),
  onSecondaryTapUp: (_) => openMenu(),
  child: Container(
    padding: const EdgeInsets.all(24),
    color: Colors.grey,
    child: body,
  ),
);

void main() {
  testWidgets(
    'a right-click on plain text opens the menu once',
    (tester) async {
      var menus = 0;
      void openMenu() => menus++;
      await tester.pumpWidget(
        _app(
          _bubble(
            TranslatedMessageContent(
              displayText: 'hello there',
              style: const TextStyle(),
              onSecondaryTap: openMenu,
            ),
            openMenu,
          ),
        ),
      );

      await tester.tap(
        find.text('hello there'),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(menus, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'a right-click on the bubble around the text opens the menu once',
    (tester) async {
      var menus = 0;
      void openMenu() => menus++;
      await tester.pumpWidget(
        _app(
          _bubble(
            TranslatedMessageContent(
              displayText: 'hello there',
              style: const TextStyle(),
              onSecondaryTap: openMenu,
            ),
            openMenu,
          ),
        ),
      );

      await tester.tapAt(
        tester.getTopLeft(find.byKey(const Key('bubble'))) +
            const Offset(8, 8),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(menus, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'a right-click on text with a mention opens the menu once',
    (tester) async {
      var menus = 0;
      void openMenu() => menus++;
      await tester.pumpWidget(
        _appWithServices(
          _bubble(
            TranslatedMessageContent(
              displayText: 'hi @[Bob] there',
              style: const TextStyle(),
              onSecondaryTap: openMenu,
            ),
            openMenu,
          ),
        ),
      );

      await tester.tapAt(
        tester.getTopLeft(find.byType(FormattedMessageText)) +
            const Offset(4, 6),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(menus, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'a right-click on a reply drawn as a mention opens the menu once',
    (tester) async {
      var menus = 0;
      void openMenu() => menus++;
      await tester.pumpWidget(
        _app(
          _bubble(
            const ReplyMentionText(
              mentionName: 'Bob',
              text: 'sure thing',
              style: TextStyle(),
              originalStyle: TextStyle(),
              textScale: 1,
              simplified: false,
            ),
            openMenu,
          ),
        ),
      );

      await tester.tap(
        find.byType(ReplyMentionText),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(menus, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
