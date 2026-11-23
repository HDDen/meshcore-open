import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/widgets/path_trace_controls.dart';

void main() {
  for (final locale in ['en', 'ru']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'trace actions stay in two rows at 280px ($locale, scale=$scale)',
        (tester) async {
          final calls = <String>[];
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(locale),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: SizedBox(
                    width: 280,
                    child: PathTraceControls(
                      onRemove: () => calls.add('remove'),
                      onClear: () => calls.add('clear'),
                      onClose: () => calls.add('close'),
                      onRegions: () => calls.add('regions'),
                      onLastResult: () => calls.add('last'),
                      onRun: () => calls.add('run'),
                      onRoundTrip: () => calls.add('roundTrip'),
                      onAsEntered: () => calls.add('asEntered'),
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          final edits = find.descendant(
            of: find.byKey(const ValueKey('path-trace-edit-actions')),
            matching: find.byType(TextButton),
          );
          expect(edits, findsNWidgets(5));
          final editY = tester.getTopLeft(edits.first).dy;
          for (var i = 0; i < 5; i++) {
            expect(tester.getTopLeft(edits.at(i)).dy, editY);
            expect(
              tester.getSize(edits.at(i)).height,
              tester.getSize(edits.first).height,
            );
            final text = tester.widget<Text>(
              find.descendant(of: edits.at(i), matching: find.byType(Text)),
            );
            expect(text.maxLines, 2);
            expect(text.overflow, TextOverflow.ellipsis);
            final icon = find.descendant(
              of: edits.at(i),
              matching: find.byType(Icon),
            );
            final label = find.descendant(
              of: edits.at(i),
              matching: find.byType(Text),
            );
            final firstIcon = find.descendant(
              of: edits.first,
              matching: find.byType(Icon),
            );
            expect(tester.getTopLeft(icon).dy, tester.getTopLeft(firstIcon).dy);
            expect(
              tester.getBottomLeft(icon).dy,
              lessThan(tester.getTopLeft(label).dy),
            );
            await tester.tap(edits.at(i));
          }
          final mainButtons = find.descendant(
            of: find.byKey(const ValueKey('path-trace-main-actions')),
            matching: find.byType(TextButton),
          );
          final main = [
            mainButtons.at(0),
            mainButtons.at(1),
            mainButtons.at(2),
          ];
          final mainY = tester.getTopLeft(main.first).dy;
          expect(mainY, greaterThan(editY));
          for (final button in main) {
            expect(tester.getTopLeft(button).dy, mainY);
            final icon = find.descendant(
              of: button,
              matching: find.byType(Icon),
            );
            final label = find.descendant(
              of: button,
              matching: find.byType(Text),
            );
            expect(
              tester.getBottomLeft(icon).dy,
              lessThan(tester.getTopLeft(label).dy),
            );
            await tester.tap(button);
          }
          expect(calls, [
            'roundTrip',
            'asEntered',
            'remove',
            'clear',
            'close',
            'regions',
            'last',
            'run',
          ]);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('main actions use natural centered widths and 6px corners', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: PathTraceControls(
              onClose: () {},
              onRegions: () {},
              onRun: () {},
            ),
          ),
        ),
      ),
    );
    final buttons = find.descendant(
      of: find.byKey(const ValueKey('path-trace-main-actions')),
      matching: find.byType(TextButton),
    );
    final regions = buttons.at(0);
    final trace = buttons.at(1);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(tester.getSize(regions).width, lessThan(300));
    expect(
      tester.getSize(trace).width,
      lessThan(tester.getSize(regions).width),
    );
    expect(
      (tester.getTopLeft(regions).dx + tester.getTopRight(trace).dx) / 2,
      closeTo(300, 0.1),
    );
    expect(
      find.descendant(of: trace, matching: find.text('Trace')),
      findsOneWidget,
    );
    for (final button in [regions, trace]) {
      final widget = tester.widget<ButtonStyleButton>(button);
      final shape = widget.style!.shape!.resolve({})! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(6));
    }
    expect(tester.takeException(), isNull);
  });
}
