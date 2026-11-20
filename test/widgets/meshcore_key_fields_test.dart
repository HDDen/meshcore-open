import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/widgets/meshcore_key_fields.dart';

void main() {
  testWidgets('stop remains clickable while key editing and generation are disabled', (tester) async {
    final private = TextEditingController();
    final public = TextEditingController();
    final prefix = TextEditingController(text: 'abcd');
    addTearDown(private.dispose);
    addTearDown(public.dispose);
    addTearDown(prefix.dispose);
    var searching = true;
    var stops = 0;
    var generations = 0;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: SingleChildScrollView(child: StatefulBuilder(
        builder: (context, update) => MeshCoreKeyFields(
          privateKey: private, publicKey: public, prefix: prefix,
          searching: searching, editable: false, canGenerate: false,
          onGenerate: () { generations++; },
          onStop: () => update(() { stops++; searching = false; }),
          onPrivateChanged: (_) {}, onPrefixChanged: (_) {},
        ),
      ))),
    ));
    final stop = find.widgetWithIcon(IconButton, Icons.cancel);
    expect(stop, findsOneWidget);
    expect(tester.widget<IconButton>(stop).onPressed, isNotNull);
    await tester.tap(stop);
    await tester.pumpAndSettle();
    expect(stops, 1);
    expect(generations, 0);
    final generate = find.widgetWithIcon(IconButton, Icons.casino_rounded);
    expect(tester.widget<IconButton>(generate).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
