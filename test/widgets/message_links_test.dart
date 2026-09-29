import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/widgets/formatted_message_text.dart';
import 'package:meshcore_open/widgets/translated_message_content.dart';

// What a tap on a link in a message body does, pinned before a channel link
// (meshcore://channel/add?...) became a link of its own: a web link, in plain
// text or among formatted runs, asks before it opens the browser.

const _webLink = 'https://example.com/page';

Widget _app(Widget body) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: body),
);

/// Taps the span showing [text], whatever the body was built with: a
/// RichText, or the SelectableText linkify gives a desktop.
void _tapSpan(WidgetTester tester, String text) {
  final roots = <InlineSpan>[
    for (final rich in tester.widgetList<RichText>(find.byType(RichText)))
      rich.text,
    for (final selectable in tester.widgetList<SelectableText>(
      find.byType(SelectableText),
    ))
      if (selectable.textSpan != null) selectable.textSpan!,
  ];
  for (final root in roots) {
    TapGestureRecognizer? tap;
    root.visitChildren((span) {
      if (span is TextSpan &&
          span.text == text &&
          span.recognizer is TapGestureRecognizer) {
        tap = span.recognizer! as TapGestureRecognizer;
        return false;
      }
      return true;
    });
    if (tap != null) {
      tap!.onTap!();
      return;
    }
  }
  fail('No tappable span shows "$text"');
}

void main() {
  testWidgets('a web link in a plain message asks before it opens', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const TranslatedMessageContent(
          displayText: 'see $_webLink now',
          style: TextStyle(),
        ),
      ),
    );

    _tapSpan(tester, _webLink);
    await tester.pumpAndSettle();

    expect(find.text('Open Link?'), findsOneWidget);
    expect(
      find.text('Do you want to open this link in your browser?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Open Link?'), findsNothing);
  });

  testWidgets('a web link among formatted runs asks the same', (tester) async {
    await tester.pumpWidget(
      _app(
        const FormattedMessageText(
          text: '**look** $_webLink',
          style: TextStyle(),
          textScale: 1,
          simplified: false,
        ),
      ),
    );

    _tapSpan(tester, _webLink);
    await tester.pumpAndSettle();

    expect(find.text('Open Link?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Open Link?'), findsNothing);
  });
}
