import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/path_playback.dart';
import 'package:meshcore_open/widgets/path_map_scaffold.dart';
import 'package:meshcore_open/widgets/path_map_ui.dart';

void main() {
  testWidgets('U34: a narrow hop panel expands by swiping its header', (tester) async {
    tester.view.physicalSize = const Size(320, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var mode = PathHopPanelMode.normal;
    const hopListKey = ValueKey('long-hop-list');
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) => Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: mode == PathHopPanelMode.expanded ? 360 : 220,
            child: PathHopPanel(
              mode: mode,
              onModeChanged: (value) => setState(() => mode = value),
              header: const Text('Хопы репитеров'),
              controls: List.generate(20, (index) => Text('Маршрут $index')),
              hopList: ListView.builder(
                key: hopListKey,
                itemCount: 18,
                itemExtent: 52,
                itemBuilder: (_, index) => Text('Hop ${index + 1}'),
              ),
            ),
          ),
        )),
      ),
    ));

    final header = find.byWidgetPredicate(
      (widget) => widget is GestureDetector && widget.onVerticalDragEnd != null,
    );
    await tester.fling(header, const Offset(0, -70), 700);
    await tester.pumpAndSettle();
    expect(mode, PathHopPanelMode.expanded);
    await tester.scrollUntilVisible(
      find.text('Hop 18'),
      95,
      scrollable: find.descendant(of: find.byKey(hopListKey), matching: find.byType(Scrollable)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hop 18').hitTestable(), findsOneWidget);

    await tester.fling(header, const Offset(0, 70), 700);
    await tester.pumpAndSettle();
    expect(mode, PathHopPanelMode.normal);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in [
    (
      name: 'compact portrait',
      size: const Size(320, 568),
      scale: 1.0,
      combined: false,
      collapsed: false,
    ),
    (
      name: 'compact landscape',
      size: const Size(568, 320),
      scale: 1.0,
      combined: false,
      collapsed: false,
    ),
    (
      name: 'large text',
      size: const Size(320, 568),
      scale: 2.0,
      combined: false,
      collapsed: false,
    ),
    (
      name: 'combined paths',
      size: const Size(320, 568),
      scale: 1.0,
      combined: true,
      collapsed: false,
    ),
    (
      name: 'collapsed',
      size: const Size(320, 568),
      scale: 1.0,
      combined: false,
      collapsed: true,
    ),
  ]) {
    testWidgets(
      'path panel fits ${scenario.name} and keeps content accessible',
      (tester) async {
        tester.view.physicalSize = scenario.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final playback = PathPlaybackController(const TestVSync());
        addTearDown(playback.dispose);
        var animationToggles = 0;
        const hopListKey = ValueKey('hop-list');

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scenario.scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Stack(
                children: [
                  PathMapBottomPanel(
                    header: const Text('3 hops (2.00 km)'),
                    combined: scenario.combined,
                    showInferredLegend: true,
                    collapsed: scenario.collapsed,
                    onToggleCollapsed: () {},
                    playback: playback,
                    selected: null,
                    animationEnabled: true,
                    onToggleAnimation: () => animationToggles++,
                    followEnabled: false,
                    onToggleFollow: () {},
                    showNoSelfGpsNote: true,
                    pathCount: scenario.combined ? 3 : 1,
                    hopRowCount: 3,
                    summary: scenario.combined
                        ? Column(
                            children: [
                              for (var i = 1; i <= 3; i++)
                                SizedBox(height: 40, child: Text('Path $i')),
                            ],
                          )
                        : null,
                    hopList: ListView(
                      key: hopListKey,
                      children: [
                        for (var i = 1; i <= 3; i++)
                          SizedBox(height: 60, child: Text('Hop $i')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);

        final animationButton = find.widgetWithIcon(
          IconButton,
          Icons.animation,
        );
        await tester.ensureVisible(animationButton);
        await tester.pumpAndSettle();
        await tester.tap(animationButton);
        expect(animationToggles, 1);

        if (!scenario.collapsed) {
          expect(
            tester.getSize(find.byKey(hopListKey)).height,
            greaterThanOrEqualTo(60),
          );
          final l10n = AppLocalizations.of(
            tester.element(find.byType(PathMapBottomPanel)),
          );
          final gpsNote = find.text(l10n.pathMap_noSelfGpsFix);
          await tester.ensureVisible(gpsNote);
          await tester.pumpAndSettle();
          expect(gpsNote.hitTestable(), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text('Hop 3'),
            60,
            scrollable: find.descendant(
              of: find.byKey(hopListKey),
              matching: find.byType(Scrollable),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Hop 3').hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
