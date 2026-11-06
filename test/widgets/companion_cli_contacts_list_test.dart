import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/widgets/companion_cli_contacts_list.dart';
import 'package:meshcore_open/widgets/companion_cli_tile.dart';
import 'package:meshcore_open/widgets/empty_state.dart';

// Rendering the tile must not access the radio. No connector initialization,
// native database, notification plugin or network requests in this fixture.
class _NoRadio implements MeshCoreConnector {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected connector access: ${invocation.memberName}');
}

void main() {
  for (final language in ['en', 'ru']) {
    for (final showCli in [false, true]) {
      for (final short in [false, true]) {
        testWidgets('scrollable contacts placeholder ($language, CLI=$showCli, short=$short)', (tester) async {
          tester.view.physicalSize = short ? const Size(320, 360) : const Size(800, 600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var taps = 0;
          final action = language == 'ru' ? 'Добавить запись' : 'Add item';
          try {
            await tester.pumpWidget(MaterialApp(
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(short ? 2 : 1),
                ),
                child: child!,
              ),
              home: Scaffold(body: Column(children: [
                const SizedBox(height: 52, child: Center(child: Text('Synthetic filters'))),
                Expanded(child: CompanionCliContactsList.placeholder(
                  connector: _NoRadio(), showCli: showCli,
                  hasScrollBody: true,
                  child: EmptyState(
                    icon: Icons.people_outline,
                    title: language == 'ru' ? 'Контактов пока нет' : 'No contacts yet',
                    subtitle: language == 'ru'
                        ? 'После синхронизации здесь появятся новые контакты. Можно добавить первый контакт самостоятельно.'
                        : 'New contacts appear here after synchronization. You can add the first contact yourself.',
                    action: FilledButton(onPressed: () => taps++, child: Text(action)),
                  ),
                )),
              ])),
            ));
            await tester.pump(const Duration(milliseconds: 500));
            expect(tester.takeException(), isNull);
            final cli = find.byType(CompanionCliTile);
            expect(cli, showCli ? findsOneWidget : findsNothing);
            if (showCli) {
              expect(tester.getRect(cli).bottom,
                  lessThanOrEqualTo(tester.getRect(find.byType(EmptyState)).top + 0.1));
            }
            if (short) {
              final inner = find.descendant(
                of: find.byType(EmptyState), matching: find.byType(Scrollable),
              );
              expect(tester.state<ScrollableState>(inner).position.maxScrollExtent, greaterThan(0));
              if (showCli) {
                final oldTop = tester.getTopLeft(cli).dy;
                final outer = tester.state<ScrollableState>(find.descendant(
                  of: find.byType(CustomScrollView), matching: find.byType(Scrollable),
                ).first).position;
                expect(outer.maxScrollExtent, greaterThan(0));
                outer.jumpTo(outer.maxScrollExtent);
                await tester.pump();
                // Once the sliver leaves the viewport, the default finder
                // skips it. Verify visibility and return, not offstage bounds.
                expect(outer.pixels, greaterThan(0));
                expect(cli.hitTestable(), findsNothing);
                outer.jumpTo(0);
                await tester.pump();
                expect(cli, findsOneWidget);
                expect(tester.getTopLeft(cli).dy, closeTo(oldTop, 0.1));
              }
              await tester.ensureVisible(find.text(action));
              await tester.pumpAndSettle();
            }
            expect(taps, 0);
            await tester.tap(find.text(action));
            await tester.pump();
            expect(taps, 1);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
          }
        });
      }
    }
  }

  testWidgets('plain loading placeholder keeps the non-scroll-body contract', (tester) async {
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: CompanionCliContactsList.placeholder(
          connector: _NoRadio(),
          child: const Center(child: Text('Synthetic loading')),
        )),
      ));
      await tester.pump();
      final sliver = tester.widget<SliverFillRemaining>(find.byType(SliverFillRemaining));
      expect(sliver.hasScrollBody, isFalse);
      expect(find.text('Synthetic loading'), findsOneWidget);
      expect(find.byType(CompanionCliTile), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}
