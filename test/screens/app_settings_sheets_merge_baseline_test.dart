import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mco_service/mco_service.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/screens/app_settings_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/translation_service.dart';
import 'package:provider/provider.dart';

import '../support/wrapping_label_expectations.dart';

const _key = 'SYNTHETIC_MAP_KEY_1234';

class _Settings extends AppSettingsService {
  AppSettings value = AppSettings(
    mapRasterSourceId: 'stamen_terrain',
    mapTileApiKey: _key,
  );
  final writes = <(String, Object?)>[];
  @override
  AppSettings get settings => value;

  void _apply(AppSettings next, String key, Object? changed) {
    value = next;
    writes.add((key, changed));
    notifyListeners();
  }

  @override
  Future<void> setMapTimeFilterHours(double hours) async =>
      _apply(value.copyWith(mapTimeFilterHours: hours), 'time', hours);
  @override
  Future<void> setUnitSystem(UnitSystem units) async =>
      _apply(value.copyWith(unitSystem: units), 'units', units);
  @override
  Future<void> setLanguageOverride(String? code) async =>
      _apply(value.copyWith(languageOverride: code), 'language', code);
  @override
  Future<void> setMapTileApiKey(String? key) async =>
      _apply(value.copyWith(mapTileApiKey: key), 'key', key);
}

// Every operation beyond reading idle UI state fails, including any radio IO.
class _Radio extends ChangeNotifier implements MeshCoreConnector {
  @override
  bool get isConnected => false;
  @override
  String? get batteryDeviceKey => null;
  @override
  bool get isLoadingContacts => false;
  @override
  bool get isSyncingChannels => false;
  @override
  bool get isShowingQueuedMessageSyncProgress => false;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected settings radio operation: ${invocation.memberName}');
}

class _Sections extends ChangeNotifier implements SettingsSectionsService {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #batteryChemistryProfilesForDevice) {
      return const <Never>[];
    }
    throw StateError('Unexpected settings section operation: ${invocation.memberName}');
  }
}

Future<void> _withSettings(WidgetTester tester, String locale,
    Future<void> Function(_Settings, AppLocalizations) run, {
  Size size = const Size(1100, 1800),
  double textScale = 1,
}) async {
  final settings = _Settings();
  final radio = _Radio();
  final sections = _Sections();
  // This service's constructor and view getters do not scan/download models;
  // no initialize/refresh/download call or ImageCodecService is registered.
  final translation = TranslationService(settings);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
  try {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppSettingsService>.value(value: settings),
        ChangeNotifierProvider<MeshCoreConnector>.value(value: radio),
        ChangeNotifierProvider<TranslationService>.value(value: translation),
        ChangeNotifierProvider<SettingsSectionsService>.value(value: sections),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const AppSettingsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(settings.writes, isEmpty);
    final l10n = AppLocalizations.of(tester.element(find.byType(AppSettingsScreen)));
    await run(settings, l10n);
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    translation.dispose();
    sections.dispose();
    radio.dispose();
    settings.dispose();
  }
}

Future<void> _open(WidgetTester tester, String title) async {
  final screen = find.byType(AppSettingsScreen);
  final label = find.descendant(of: screen, matching: find.text(title));
  final list = find.descendant(of: screen, matching: find.byType(ListView));
  final scrollable = find.descendant(
    of: list, matching: find.byType(Scrollable),
  ).first;
  // A previous sheet may belong to a section far below this one. Reset the
  // lazy root list before searching forward for a different settings tile.
  final position = tester.state<ScrollableState>(scrollable).position;
  position.jumpTo(0);
  await tester.pumpAndSettle();
  // scrollUntilVisible drags from the viewport's centre, which can land on
  // unrelated interactive settings. Move only this list while locating its
  // lazy child; opening the tile still requires a real, hit-tested tap.
  for (var step = 0; step < 100 && label.evaluate().isEmpty; step++) {
    final next = (position.pixels + position.viewportDimension * 0.75)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (next <= position.pixels) {
      break;
    }
    position.jumpTo(next);
    await tester.pumpAndSettle();
  }
  expect(label, findsOneWidget, reason:
      'Settings tile "$title" was not built: offset=${position.pixels}, '
      'max=${position.maxScrollExtent}, viewport=${position.viewportDimension}');
  await Scrollable.ensureVisible(tester.element(label), alignment: 0.5);
  await tester.pumpAndSettle();
  expect(label.hitTestable(), findsOneWidget);
  await tester.tap(label);
  await tester.pumpAndSettle();
}

Future<Finder> _option(WidgetTester tester, String label) async {
  final sheet = find.byType(BottomSheet);
  expect(sheet, findsOneWidget);
  final tile = find.descendant(of: sheet,
      matching: find.widgetWithText(ListTile, label));
  final list = find.descendant(of: sheet, matching: find.byType(ListView));
  if (list.evaluate().isNotEmpty) {
    final scrollable = find.descendant(of: list, matching: find.byType(Scrollable));
    expect(scrollable, findsOneWidget);
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(tile, 160, scrollable: scrollable, maxScrolls: 40);
  } else {
    expect(tile, findsOneWidget);
    await tester.ensureVisible(tile);
  }
  await tester.pumpAndSettle();
  expect(tile.hitTestable(), findsOneWidget);
  return tile;
}

Future<void> _dismiss(WidgetTester tester) async {
  // The sheet can fill a short screen. Use its real Close button, including
  // when a scrollable header has moved above the viewport.
  final close = find.descendant(
    of: find.byType(BottomSheet),
    matching: find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.icon is Icon &&
          (widget.icon as Icon).icon == Icons.close,
    ),
  );
  expect(close, findsOneWidget);
  await tester.ensureVisible(close);
  await tester.pumpAndSettle();
  expect(close.hitTestable(), findsOneWidget);
  await tester.tap(close);
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet), findsNothing);
}

void _selected(WidgetTester tester, Finder tile) {
  expect((tester.widget<ListTile>(tile).leading! as Icon).icon,
      Icons.radio_button_checked);
}

Finder _sheetText(String label) => find.descendant(
  of: find.byType(BottomSheet),
  matching: find.text(label),
);

void _complete(WidgetTester tester, Finder text) {
  expectCompleteWrappingLabel(tester, text, wraps: false);
}

Future<void> _dialogAction(WidgetTester tester, String label) async {
  final action = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(TextButton, label),
  );
  expect(action.hitTestable(), findsOneWidget);
  await tester.tap(action);
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsNothing);
}

void main() {
  for (final locale in ['en', 'ru']) {
    testWidgets('U11b9 baseline: time filter preserves all five choices and dismissal ($locale)', (tester) async {
      await _withSettings(tester, locale, (settings, l10n) async {
        final initial = settings.value.toJson();
        await _open(tester, l10n.appSettings_timeFilter);
        _selected(tester, await _option(tester, l10n.appSettings_lastWeek));
        await _dismiss(tester);
        expect(settings.value.toJson(), initial);
        expect(settings.writes, isEmpty);
        final options = <(double, String)>[
          (0, l10n.appSettings_allTime), (1, l10n.appSettings_lastHour),
          (6, l10n.appSettings_last6Hours), (24, l10n.appSettings_last24Hours),
          (168, l10n.appSettings_lastWeek),
        ];
        for (final (hours, label) in options) {
          final before = settings.value;
          final count = settings.writes.length;
          await _open(tester, l10n.appSettings_timeFilter);
          await tester.tap(await _option(tester, label));
          await tester.pumpAndSettle();
          expect(find.byType(BottomSheet), findsNothing);
          expect(settings.writes.skip(count), [('time', hours)]);
          expect(settings.value.toJson(), before.copyWith(mapTimeFilterHours: hours).toJson());
          await _open(tester, l10n.appSettings_timeFilter);
          _selected(tester, await _option(tester, label));
          await _dismiss(tester);
          expect(settings.writes, hasLength(count + 1));
        }
      });
    });

    testWidgets('U11b9 baseline: units select and reopen without changing other settings ($locale)', (tester) async {
      await _withSettings(tester, locale, (settings, l10n) async {
        final initial = settings.value.toJson();
        await _open(tester, l10n.appSettings_unitsTitle);
        _selected(tester, await _option(tester, l10n.appSettings_unitsMetric));
        await _dismiss(tester);
        expect(settings.value.toJson(), initial);
        expect(settings.writes, isEmpty);
        for (final (units, label) in [
          (UnitSystem.imperial, l10n.appSettings_unitsImperial),
          (UnitSystem.metric, l10n.appSettings_unitsMetric),
        ]) {
          final before = settings.value;
          final count = settings.writes.length;
          await _open(tester, l10n.appSettings_unitsTitle);
          await tester.tap(await _option(tester, label));
          await tester.pumpAndSettle();
          expect(settings.writes.skip(count), [('units', units)]);
          expect(settings.value.toJson(), before.copyWith(unitSystem: units).toJson());
          await _open(tester, l10n.appSettings_unitsTitle);
          _selected(tester, await _option(tester, label));
          await _dismiss(tester);
          expect(settings.writes, hasLength(count + 1));
        }
      });
    });

    testWidgets('U11b9 baseline: language endpoints and system choice keep their codes ($locale)', (tester) async {
      await _withSettings(tester, locale, (settings, l10n) async {
        for (final (code, label) in <(String?, String)>[
          ('ko', l10n.appSettings_languageKo),
          ('en', l10n.appSettings_languageEn),
          (null, l10n.appSettings_languageSystem),
        ]) {
          final before = settings.value;
          final count = settings.writes.length;
          await _open(tester, l10n.appSettings_language);
          await tester.tap(await _option(tester, label));
          await tester.pumpAndSettle();
          expect(settings.writes.skip(count), [('language', code)]);
          expect(settings.value.toJson(), before.copyWith(languageOverride: code).toJson());
          await _open(tester, l10n.appSettings_language);
          _selected(tester, await _option(tester, label));
          await _dismiss(tester);
          expect(settings.writes, hasLength(count + 1));
        }
      });
    });

    testWidgets('U11b9 baseline: map key mask survives unchanged Save and Cancel ($locale)', (tester) async {
      await _withSettings(tester, locale, (settings, l10n) async {
        for (final action in ['cancel', 'unchanged', 'edited']) {
          final before = settings.value;
          final count = settings.writes.length;
          await _open(tester, l10n.appSettings_stadiaApiKey);
          final dialog = find.byType(AlertDialog);
          final field = find.descendant(of: dialog, matching: find.byType(TextField));
          expect(tester.widget<TextField>(field).obscureText, isTrue);
          final mask = tester.widget<TextField>(field).controller!.text;
          expect(mask, isNotEmpty);
          expect(mask, isNot(_key));
          final toggle = find.descendant(of: dialog, matching: find.byWidgetPredicate(
            (w) => w is IconButton && w.tooltip == l10n.appSettings_showApiKey,
          ));
          await tester.tap(toggle);
          await tester.pump();
          expect(tester.widget<TextField>(field).obscureText, isFalse);
          expect(tester.widget<TextField>(field).controller!.text, mask);
          if (action != 'unchanged') {
            await tester.enterText(field, ' NEW_SYNTHETIC_MAP_KEY ');
          }
          await tester.tap(find.descendant(of: dialog, matching:
              find.widgetWithText(TextButton, action == 'cancel'
                  ? l10n.common_cancel : l10n.common_save)));
          await tester.pumpAndSettle();
          expect(dialog, findsNothing);
          if (action == 'cancel') {
            expect(settings.writes, hasLength(count));
            expect(settings.value.toJson(), before.toJson());
          } else {
            final expected = action == 'unchanged' ? _key : 'NEW_SYNTHETIC_MAP_KEY';
            expect(settings.writes.skip(count), [('key', expected)]);
            expect(settings.value.toJson(), before.copyWith(mapTileApiKey: expected).toJson());
          }
        }
      });
    });

    for (final (orientation, size) in [
      ('phone', const Size(320, 568)),
      ('landscape', const Size(568, 360)),
    ]) {
      testWidgets(
        'U11b9: complete sheet choices remain reachable ($locale, $orientation, scale=2)',
        (tester) async {
          await _withSettings(tester, locale, (settings, l10n) async {
            final initial = settings.value;
            await _open(tester, l10n.appSettings_timeFilter);
            _complete(tester, _sheetText(l10n.appSettings_mapTimeFilter));
            _complete(tester, _sheetText(l10n.appSettings_showNodesDiscoveredWithin));
            _selected(tester, await _option(tester, l10n.appSettings_lastWeek));
            _complete(tester, _sheetText(l10n.appSettings_lastWeek));
            final allTime = await _option(tester, l10n.appSettings_allTime);
            _complete(tester, _sheetText(l10n.appSettings_allTime));
            expect(settings.writes, isEmpty);
            await tester.tap(allTime);
            await tester.pumpAndSettle();
            expect(find.byType(BottomSheet), findsNothing);
            expect(settings.writes, [('time', 0.0)]);
            await _open(tester, l10n.appSettings_timeFilter);
            _selected(tester, await _option(tester, l10n.appSettings_allTime));
            await _dismiss(tester);

            await _open(tester, l10n.appSettings_language);
            _complete(tester, _sheetText(l10n.appSettings_language));
            final korean = await _option(tester, l10n.appSettings_languageKo);
            _complete(tester, _sheetText(l10n.appSettings_languageKo));
            final languageList = find.descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(ListView),
            );
            final height = tester.getSize(languageList).height;
            expect(height, lessThanOrEqualTo(400));
            expect(height, lessThan(size.height));
            expect(height, greaterThan(0));
            await tester.tap(korean);
            await tester.pumpAndSettle();
            expect(find.byType(BottomSheet), findsNothing);
            await _open(tester, l10n.appSettings_language);
            _selected(tester, await _option(tester, l10n.appSettings_languageKo));
            await _option(tester, l10n.appSettings_languageSystem);
            _complete(tester, _sheetText(l10n.appSettings_languageSystem));
            await _dismiss(tester);

            await _open(tester, l10n.appSettings_unitsTitle);
            _complete(tester, _sheetText(l10n.appSettings_unitsTitle));
            final imperial = await _option(tester, l10n.appSettings_unitsImperial);
            _complete(tester, _sheetText(l10n.appSettings_unitsImperial));
            await tester.tap(imperial);
            await tester.pumpAndSettle();
            expect(find.byType(BottomSheet), findsNothing);
            await _open(tester, l10n.appSettings_unitsTitle);
            _selected(tester, await _option(tester, l10n.appSettings_unitsImperial));
            await _dismiss(tester);

            expect(settings.writes, [
              ('time', 0.0), ('language', 'ko'), ('units', UnitSystem.imperial),
            ]);
            expect(settings.value.toJson(), initial.copyWith(
              mapTimeFilterHours: 0,
              languageOverride: 'ko',
              unitSystem: UnitSystem.imperial,
            ).toJson());
          }, size: size, textScale: 2);
        },
      );

      testWidgets(
        'U11b9: keyboard leaves map key editing and actions accessible ($locale, $orientation, scale=2)',
        (tester) async {
          await _withSettings(tester, locale, (settings, l10n) async {
            for (final action in ['cancel', 'unchanged', 'edited']) {
              final before = settings.value;
              final count = settings.writes.length;
              await _open(tester, l10n.appSettings_stadiaApiKey);
              // Exercise the actual dialog after a keyboard consumes height.
              tester.view.viewInsets = FakeViewPadding(
                bottom: orientation == 'phone' ? 180 : 100,
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              final dialog = find.byType(AlertDialog);
              final description = find.descendant(of: dialog, matching:
                  find.text(l10n.appSettings_stadiaApiKeyDialogDescription));
              _complete(tester, description);
              final scrollable = find.descendant(of: dialog, matching:
                  find.byWidgetPredicate((widget) => widget is Scrollable &&
                      widget.axisDirection == AxisDirection.down));
              expect(scrollable, findsOneWidget);
              expect(tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
                  greaterThan(0));

              final field = find.descendant(of: dialog, matching: find.byType(TextField));
              expect(tester.widget<TextField>(field).obscureText, isTrue);
              final mask = tester.widget<TextField>(field).controller!.text;
              expect(mask, isNotEmpty);
              expect(mask, isNot(_key));
              final toggle = find.descendant(of: dialog, matching:
                  find.byWidgetPredicate((widget) => widget is IconButton &&
                      widget.tooltip == l10n.appSettings_showApiKey));
              await tester.ensureVisible(toggle);
              await tester.pumpAndSettle();
              expect(toggle.hitTestable(), findsOneWidget);
              await tester.tap(toggle);
              await tester.pump();
              expect(tester.widget<TextField>(field).obscureText, isFalse);
              expect(tester.widget<TextField>(field).controller!.text, mask);
              if (action != 'unchanged') {
                await tester.enterText(field, ' NEW_SYNTHETIC_MAP_KEY ');
              }
              await _dialogAction(tester, action == 'cancel'
                  ? l10n.common_cancel : l10n.common_save);
              if (action == 'cancel') {
                expect(settings.writes, hasLength(count));
                expect(settings.value.toJson(), before.toJson());
              } else {
                final expected = action == 'unchanged' ? _key : 'NEW_SYNTHETIC_MAP_KEY';
                expect(settings.writes.skip(count), [('key', expected)]);
                expect(settings.value.toJson(), before.copyWith(mapTileApiKey: expected).toJson());
              }
              tester.view.resetViewInsets();
              await tester.pumpAndSettle();
            }
          }, size: size, textScale: 2);
        },
      );
    }
  }
}
