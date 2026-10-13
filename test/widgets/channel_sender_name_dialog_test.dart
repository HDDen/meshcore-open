import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/widgets/channel_sender_name_dialog.dart';

/// Pumps a button that opens the dialog and records what it saves.
Future<List<String?>> _open(
  WidgetTester tester, {
  String? currentName,
  String? nodeName = 'Node',
}) async {
  final saved = <String?>[];
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showChannelSenderNameDialog(
              context,
              currentName: currentName,
              nodeName: nodeName,
              onSave: saved.add,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return saved;
}

TextButton _save(WidgetTester tester) =>
    tester.widget<TextButton>(find.widgetWithText(TextButton, 'Save'));

void main() {
  testWidgets('saves a typed name and counts its bytes', (tester) async {
    final saved = await _open(tester);
    expect(
      find.text('You can change the name for this channel.'),
      findsOneWidget,
    );
    expect(find.text('0 / 31 bytes'), findsOneWidget);
    expect(_save(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'База');
    await tester.pump();
    expect(find.text('8 / 31 bytes'), findsOneWidget);
    expect(_save(tester).onPressed, isNotNull);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, ['База']);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('an emptied name clears the setting', (tester) async {
    final saved = await _open(tester, currentName: 'Base');
    expect(_save(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '  ');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, [null]);
  });

  testWidgets('the node name is the hint and Cancel saves nothing', (
    tester,
  ) async {
    final saved = await _open(tester, nodeName: 'Luchik');
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
      'Luchik',
    );
    await tester.enterText(find.byType(TextField), 'Base');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('the name is held to the bytes a node name may have', (
    tester,
  ) async {
    await _open(tester);
    await tester.enterText(find.byType(TextField), 'x' * 40);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text.length,
      31,
    );
    expect(find.text('31 / 31 bytes'), findsOneWidget);
  });
}
