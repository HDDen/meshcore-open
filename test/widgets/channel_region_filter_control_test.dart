import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_region_filter.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/widgets/channel_region_filter_control.dart';

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  for (final save in [false, true]) {
    testWidgets('region dialog stores a denylist only, save=$save', (tester) async {
      Set<String>? result;
      final original = <String>{'north'};
      await tester.pumpWidget(_app(Builder(builder: (context) => TextButton(
        onPressed: () async {
          result = await showChannelRegionFilterDialog(context,
            knownRegions: ['north', 'south', 'new-region'], hidden: original);
        }, child: const Text('Open'),
      ))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(AlertDialog));
      final l10n = AppLocalizations.of(context);
      final toggles = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).toList();
      expect((toggles[0].title as Text).data, l10n.chat_floodRegionNone);
      expect((toggles[1].title as Text).data, l10n.channelRegionFilter_unknown);
      expect(toggles[0].value, isTrue);
      expect(toggles[1].value, isTrue);
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('region-filter:north'))).value, isFalse);
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('region-filter:new-region'))).value, isTrue);
      toggles[1].onChanged!(false);
      await tester.pump();
      final action = find.text(save ? l10n.common_save : l10n.common_cancel);
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(result, save ? {'north', ChannelRegionFilter.unknown} : isNull);
      expect(original, {'north'});
    });
  }

  testWidgets('region and filter stay on one line without unread text', (tester) async {
    var opened = 0;
    for (final width in [360.0, 135.0, 90.0]) {
      await tester.pumpWidget(_app(Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: ChannelRegionFilterLine(
          regionHeader: 'Region: north',
          knownRegions: const ['north', 'south'],
          hidden: const {'', ChannelRegionFilter.unknown},
          onConfigure: () => opened++,
        )),
      )));
      final region = tester.renderObject<RenderParagraph>(
        find.byKey(const ValueKey('channel-header-region')),
      );
      expect(region.didExceedMaxLines, isFalse);
      expect(find.byKey(const ValueKey('channel-header-unread')), findsNothing);
      if (width == 360) {
        expect(tester.renderObject<RenderParagraph>(find.text('north +1'))
            .didExceedMaxLines, isFalse);
      }
      await tester.ensureVisible(find.byKey(const ValueKey('channel-region-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('channel-region-filter')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    expect(opened, 3);
  });

  testWidgets('no-filter label truncates while the region stays visible', (tester) async {
    await tester.pumpWidget(_app(const SizedBox(width: 135,
      child: ChannelRegionFilterLine(
        regionHeader: 'Region: north', knownRegions: [], hidden: {},
        onConfigure: _noop,
      ),
    )));
    final label = tester.renderObject<RenderParagraph>(find.text('No filter'));
    expect(label.overflow, TextOverflow.ellipsis);
    expect(label.didExceedMaxLines, isTrue);
    final region = tester.renderObject<RenderParagraph>(
      find.byKey(const ValueKey('channel-header-region')),
    );
    expect(region.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a region wider than the header keeps its natural single-line width', (tester) async {
    await tester.pumpWidget(_app(const SizedBox(width: 80,
      child: ChannelRegionFilterLine(
        regionHeader: 'Region: very-long-region-name',
        knownRegions: [], hidden: {}, onConfigure: _noop,
      ),
    )));
    final region = tester.renderObject<RenderParagraph>(
      find.byKey(const ValueKey('channel-header-region')),
    );
    expect(region.didExceedMaxLines, isFalse);
    expect(region.size.width, greaterThan(80));
    expect(region.maxLines, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header has a clickable empty or filled filter and allowed-region summary', (tester) async {
    var opened = 0;
    Widget line(Set<String> hidden) => Builder(builder: (context) => ChannelRegionFilterLine(
      regionHeader: 'Region: north',
      knownRegions: const ['north', 'south'], hidden: hidden,
      onConfigure: () => opened++,
    ));
    await tester.pumpWidget(_app(line({})));
    expect(find.byIcon(Icons.filter_alt_outlined), findsOneWidget);
    expect(find.text('No filter'), findsOneWidget);
    expect(find.textContaining('•'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('channel-region-filter')));
    expect(opened, 1);
    await tester.pumpWidget(_app(line({'', ChannelRegionFilter.unknown})));
    expect(find.byIcon(Icons.filter_alt), findsOneWidget);
    expect(find.text('north +1'), findsOneWidget);
    await tester.pumpWidget(_app(line({'', ChannelRegionFilter.unknown, 'north', 'south'})));
    final l10n = AppLocalizations.of(tester.element(find.byType(ChannelRegionFilterLine)));
    expect(find.text(l10n.channelRegionFilter_noneAllowed), findsOneWidget);
  });
}

void _noop() {}
