import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_sender_name.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/widgets/channel_sender_name_line.dart';

Future<void> _pump(
  WidgetTester tester, {
  String? name,
  required ChannelSenderNameLock lock,
  required VoidCallback onEdit,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ChannelSenderNameLine(name: name, lock: lock, onEdit: onEdit),
      ),
    ),
  );
}

TextSpan _valueSpan(WidgetTester tester) {
  final text = tester.widget<Text>(find.byType(Text));
  final span = text.textSpan! as TextSpan;
  return span.children!.last as TextSpan;
}

/// Taps the line and lets the snackbar come up and go again, so no timer of
/// it outlives the test.
Future<void> _tapAndSettle(WidgetTester tester) async {
  await tester.tap(find.byType(ChannelSenderNameLine));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('names the default and opens the editor on a tap', (
    tester,
  ) async {
    var edits = 0;
    await _pump(
      tester,
      lock: ChannelSenderNameLock.none,
      onEdit: () => edits++,
    );
    expect(find.text('Sender: default'), findsOneWidget);
    expect(_valueSpan(tester).style?.decoration, TextDecoration.underline);
    expect(
      _valueSpan(tester).style?.decorationStyle,
      TextDecorationStyle.dotted,
    );

    await tester.tap(find.byType(ChannelSenderNameLine));
    await tester.pump();
    expect(edits, 1);
  });

  testWidgets('shows the name the channel sends under', (tester) async {
    await _pump(
      tester,
      name: 'Base',
      lock: ChannelSenderNameLock.none,
      onEdit: () {},
    );
    expect(find.text('Sender: Base'), findsOneWidget);
  });

  testWidgets('a locked name is not underlined and a tap says why', (
    tester,
  ) async {
    var edits = 0;
    await _pump(
      tester,
      lock: ChannelSenderNameLock.signedMcmp,
      onEdit: () => edits++,
    );
    expect(_valueSpan(tester).style, isNull);

    await _tapAndSettle(tester);
    expect(edits, 0);
    expect(
      find.text("A channel with signed MCMP sends under the node's name."),
      findsOneWidget,
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('old firmware has its own reason', (tester) async {
    await _pump(tester, lock: ChannelSenderNameLock.firmware, onEdit: () {});
    await _tapAndSettle(tester);
    expect(
      find.text('Needs firmware with version code 13 or newer.'),
      findsOneWidget,
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('a private region has its own reason', (tester) async {
    await _pump(
      tester,
      lock: ChannelSenderNameLock.privateRegion,
      onEdit: () {},
    );
    await _tapAndSettle(tester);
    expect(
      find.text(
        "The region's key is on the repeater, so the name cannot be changed.",
      ),
      findsOneWidget,
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}
