import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/path_selection.dart';
import 'package:meshcore_open/screens/repeater_settings_screen.dart';
import 'package:meshcore_open/storage/node_state.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/wrapping_label_expectations.dart'
    show revealDropdownOption, expectCompleteWrappingLabel;

class _NoPreferenceDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async =>
      throw MissingPluginException('Synthetic repeater settings');
}

// Exercise the actual screen, dirty tracking and CLI parser/service. No real
// connector constructor, radio, preferences directory or database is opened.
class _Radio extends ChangeNotifier implements MeshCoreConnector {
  final target = Contact(
    publicKey: Uint8List.fromList(List.generate(32, (i) => i + 1)),
    name: 'Synthetic settings node',
    type: advTypeRepeater,
    pathLength: -1,
    path: Uint8List(0),
    lastSeen: DateTime.utc(2026, 1, 1),
  );
  final incoming = StreamController<Uint8List>.broadcast(sync: true);
  final writes = <Uint8List>[];
  final tracked = <String>[];
  bool connected = true;

  @override
  bool get isConnected => connected;
  @override
  List<Contact> get contacts => [target];
  @override
  Stream<Uint8List> get receivedFrames => incoming.stream;

  List<String> get commands => [
    for (final frame in writes) _text(frame).substring(3),
  ];
  String _text(Uint8List frame) => utf8.decode(
    frame.sublist(13).takeWhile((byte) => byte != 0).toList(),
  );

  @override
  Future<PathSelection> preparePathForContactSend(Contact contact) async {
    expect(contact.publicKeyHex, target.publicKeyHex);
    return const PathSelection(pathBytes: [], hopCount: -1, useFlood: true);
  }

  @override
  void trackRepeaterAck({required Contact contact,
    required PathSelection selection, required String text,
    required int timestampSeconds, int attempt = 0}) {
    expect(contact.publicKeyHex, target.publicKeyHex);
    expect(selection.useFlood, isTrue);
    expect(attempt, 0);
    tracked.add(text);
  }

  @override
  Future<void> sendContactFrame(Contact contact, Uint8List frame, {
    required bool useFlood,
    bool Function()? canSend,
    VoidCallback? onSending,
  }) async {
    expect(contact.publicKeyHex, target.publicKeyHex);
    expect(useFlood, isTrue);
    expect(frame.take(3), [cmdSendTxtMsg, txtTypeCliData, 0]);
    expect(frame.sublist(7, 13), target.publicKey.take(6));
    expect(_text(frame), matches(RegExp(r'^[0-9A-F]{2}\|')));
    onSending?.call();
    writes.add(Uint8List.fromList(frame));
  }

  @override
  int calculateTimeout({required int pathLength, int messageBytes = 100,
    String? contactKey, int? deviceTimeoutMs}) => 3000;

  void reply(String response) {
    final prefix = _text(writes.last).substring(0, 3);
    incoming.add(Uint8List.fromList([
      respCodeContactMsgRecv, ...target.publicKey.take(6),
      0, txtTypeCliData, 0, 0, 0, 0, ...utf8.encode('$prefix$response'), 0,
    ]));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected settings operation: ${invocation.memberName}');

  @override
  void dispose() {
    unawaited(incoming.close());
    super.dispose();
  }
}

Future<void> _withSettings(WidgetTester tester, String locale,
    Future<void> Function(_Radio, AppLocalizations) run, {
  Size size = const Size(1100, 1800),
  double textScale = 1,
}) async {
  final radio = _Radio();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  try {
    await tester.pumpWidget(ChangeNotifierProvider<MeshCoreConnector>.value(
      value: radio,
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
        home: RepeaterSettingsScreen(repeater: radio.target, password: ''),
      ),
    ));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(RepeaterSettingsScreen)));
    expect(radio.writes, isEmpty);
    expect(radio.incoming.hasListener, isTrue);
    await run(radio, l10n);
    expect(tester.takeException(), isNull);
    expect(PrefsManager.instance.getKeys(), isEmpty);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(radio.incoming.hasListener, isFalse);
    expect(radio.tracked, hasLength(radio.writes.length));
    radio.dispose();
  }
}

Finder _icon(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final scrollable = find.descendant(of: find.byType(ListView),
      matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(finder, 180,
      scrollable: scrollable, maxScrolls: 80);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
}

Finder _field<T>(String label) => find.ancestor(
  of: find.text(label), matching: find.byType(DropdownButtonFormField<T>),
);

DropdownButton<T> _dropdown<T>(WidgetTester tester, String label) =>
    tester.widget<DropdownButton<T>>(find.descendant(
      of: _field<T>(label), matching: find.byType(DropdownButton<T>),
    ));

Future<void> _choose<T>(WidgetTester tester, String field, String option, {
  bool checkCompleteLabel = false,
  bool wraps = false,
}) async {
  final arrow = find.descendant(of: _field<T>(field),
      matching: find.byIcon(Icons.arrow_drop_down));
  // Once loaded, InputDecorator floats the label and ignores its pointer
  // events. Reveal and hit-test the actual dropdown arrow instead; the field
  // may still be unbuilt in the lazy list when this finder is created.
  await _reveal(tester, arrow);
  await tester.tap(arrow);
  await tester.pumpAndSettle();
  final item = await revealDropdownOption(tester, option);
  if (checkCompleteLabel) {
    expectCompleteWrappingLabel(tester, item, wraps: false);
  }
  await tester.tap(item);
  await tester.pumpAndSettle();
  if (checkCompleteLabel) {
    expectCompleteWrappingLabel(tester,
        find.descendant(of: _field<T>(field), matching: find.text(option)),
        wraps: wraps);
  }
}

// The screen deliberately spaces commands by 200 ms. Let that existing
// delay complete without settling an indeterminate spinner for a next SET.
Future<void> _answer(WidgetTester tester, _Radio radio, String response) async {
  radio.reply(response);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

Future<void> _read(WidgetTester tester, _Radio radio,
    String tooltip, String command, String response) async {
  final count = radio.writes.length;
  await _reveal(tester, _icon(tooltip));
  await tester.tap(_icon(tooltip));
  await tester.pump();
  expect(radio.commands.skip(count), [command]);
  await _answer(tester, radio, '> $response');
  await tester.pumpAndSettle();
}

Finder _textInput(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _editText(WidgetTester tester, String label, String value) async {
  final field = _textInput(label);
  await _reveal(tester, field);
  expect(tester.widget<TextField>(field).enabled, isTrue);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Future<void> _openAdvanced(WidgetTester tester, AppLocalizations l10n) async {
  final heading = find.text(l10n.repeater_advancedSettings);
  await _reveal(tester, heading);
  await tester.tap(heading);
  await tester.pumpAndSettle();
}

void main() {
  late PathProviderPlatform previousPaths;
  setUp(() async {
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferenceDirectory();
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    expect(NodeState.usesDatabase, isFalse);
  });
  tearDown(() {
    PrefsManager.reset();
    PathProviderPlatform.instance = previousPaths;
  });

  for (final locale in ['en', 'ru']) {
    for (final layout in [
      (name: 'phone', size: const Size(320, 568)),
      (name: 'landscape', size: const Size(568, 360)),
    ]) {
      testWidgets('U11b8: unloaded notice and refresh remain readable '
          '($locale, ${layout.name}, scale=2)', (tester) async {
        await _withSettings(tester, locale, (radio, l10n) async {
          final notice = find.text(l10n.repeater_settingsNotLoaded);
          final refresh = find.widgetWithText(TextButton, l10n.repeater_refreshAll);
          await _reveal(tester, refresh);
          expectCompleteWrappingLabel(tester, notice, wraps: false);
          expectCompleteWrappingLabel(tester,
              find.descendant(of: refresh, matching: find.text(l10n.repeater_refreshAll)),
              wraps: false);
          expect(tester.getRect(refresh).top,
              greaterThanOrEqualTo(tester.getRect(notice).bottom));
          expect(tester.getRect(refresh).right, lessThanOrEqualTo(layout.size.width));
          expect(tester.widget<TextButton>(refresh).onPressed, isNotNull);
          expect(radio.commands, isEmpty);
          radio.connected = false;
          radio.notifyListeners();
          await tester.pumpAndSettle();
          await _reveal(tester, refresh);
          expect(tester.widget<TextButton>(refresh).onPressed, isNull);
          await tester.pump(const Duration(seconds: 5));
          expect(radio.commands, isEmpty);
        }, size: layout.size, textScale: 2);
      });

      testWidgets('U11b8: all five menus wrap and Save sends only edited fields '
          '($locale, ${layout.name}, scale=2)', (tester) async {
        await _withSettings(tester, locale, (radio, l10n) async {
          await _read(tester, radio, l10n.repeater_refreshRadioSettings,
              'get radio', '869.495,137.5,7,5');
          await _choose<int>(tester, l10n.repeater_bandwidth, '125 kHz',
              checkCompleteLabel: true);
          expect(_dropdown<int>(tester, l10n.repeater_bandwidth).value, 125000);
          await _choose<int>(tester, l10n.repeater_spreadingFactor, 'SF8',
              checkCompleteLabel: true);
          expect(_dropdown<int>(tester, l10n.repeater_spreadingFactor).value, 8);
          await _choose<int>(tester, l10n.repeater_codingRate, '4/6',
              checkCompleteLabel: true);
          expect(_dropdown<int>(tester, l10n.repeater_codingRate).value, 6);

          await _read(tester, radio, l10n.repeater_loopDetect, 'get loop.detect', 'moderate');
          await _choose<String>(tester, l10n.repeater_loopDetect, l10n.repeater_loopDetectStrict,
              checkCompleteLabel: true);
          expect(_dropdown<String>(tester, l10n.repeater_loopDetect).value, 'strict');
          await _reveal(tester, find.text(l10n.repeater_advancedSettings));
          await tester.tap(find.text(l10n.repeater_advancedSettings));
          await tester.pumpAndSettle();
          await _read(tester, radio, l10n.repeater_pathHashMode, 'get path.hash.mode', '1');
          await _choose<int>(tester, l10n.repeater_pathHashMode, l10n.repeater_pathHashModeOption2,
              checkCompleteLabel: true, wraps: layout.name == 'phone');
          expect(_dropdown<int>(tester, l10n.repeater_pathHashMode).value, 2);
          expect(radio.commands, ['get radio', 'get loop.detect', 'get path.hash.mode']);

          final save = _icon(l10n.common_save);
          expect(save.hitTestable(), findsOneWidget);
          expect(tester.widget<IconButton>(save).onPressed, isNotNull);
          await tester.tap(save);
          await tester.pump();
          expect(radio.commands, [
            'get radio', 'get loop.detect', 'get path.hash.mode',
            'set radio 869.495,125.0,8,6',
          ]);
          await _answer(tester, radio, 'OK');
          expect(radio.commands.last, 'set loop.detect strict');
          await _answer(tester, radio, 'OK');
          expect(radio.commands.last, 'set path.hash.mode 2');
          await _answer(tester, radio, 'OK');
          await tester.pumpAndSettle();
          expect(radio.commands, [
            'get radio', 'get loop.detect', 'get path.hash.mode',
            'set radio 869.495,125.0,8,6', 'set loop.detect strict', 'set path.hash.mode 2',
          ]);
          expect(save, findsNothing);
        }, size: layout.size, textScale: 2);
      });
    }

    testWidgets('U13b baseline: delays require GET and retry only the rejected '
        'field ($locale)', (tester) async {
      await _withSettings(tester, locale, (radio, l10n) async {
        // Before the U13b fix, the first successful GET removed the
        // unloaded hint and collapsed Advanced by shifting its list slot.
        // Load only the name before opening Advanced so this baseline can
        // isolate each delay's GET guard and partial-save behavior. Preserve
        // expansion across the first GET in a separate U13b regression.
        await _read(tester, radio, l10n.repeater_refreshBasicSettings,
            'get name', 'Remote name');
        await _openAdvanced(tester, l10n);
        final tx = _textInput(l10n.repeater_txDelay);
        final direct = _textInput(l10n.repeater_directTxDelay);
        await _reveal(tester, tx);
        expect(tester.widget<TextField>(tx).enabled, isFalse);
        await _reveal(tester, direct);
        expect(tester.widget<TextField>(direct).enabled, isFalse);
        expect(radio.commands, ['get name']);

        // An older firmware's unsupported response is not a loaded value.
        await _reveal(tester, _icon(l10n.repeater_txDelay));
        await tester.tap(_icon(l10n.repeater_txDelay));
        await tester.pump();
        await _answer(tester, radio, 'Error: unknown command');
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(tx).enabled, isFalse);
        await _read(tester, radio, l10n.repeater_txDelay, 'get txdelay', '0');
        expect(tester.widget<TextField>(direct).enabled, isFalse);
        await _editText(tester, l10n.repeater_txDelay, '0,25');
        await _read(tester, radio, l10n.repeater_directTxDelay,
            'get direct.txdelay', '1');
        await _editText(tester, l10n.repeater_directTxDelay, '2');
        expect(radio.commands,
            ['get name', 'get txdelay', 'get txdelay', 'get direct.txdelay']);

        final save = find.widgetWithText(TextButton, l10n.common_save);
        final beforeSave = radio.commands.length;
        await tester.tap(save);
        await tester.pump();
        expect(radio.commands.skip(beforeSave), ['set txdelay 0.25']);
        await _answer(tester, radio, 'OK');
        expect(radio.commands.last, 'set direct.txdelay 2.0');
        await _answer(tester, radio, 'Error rejected');
        await tester.pumpAndSettle();
        expect(save, findsOneWidget);
        expect(tester.widget<TextField>(tx).controller!.text, '0,25');
        expect(tester.widget<TextField>(direct).controller!.text, '2');

        await tester.tap(save);
        await tester.pump();
        expect(radio.commands.skip(beforeSave), [
          'set txdelay 0.25', 'set direct.txdelay 2.0',
          'set direct.txdelay 2.0',
        ]);
        await _answer(tester, radio, 'OK');
        await tester.pumpAndSettle();
        expect(save, findsNothing);
      });
    });

    testWidgets('U13b baseline: malformed delay stays dirty while a valid '
        'field is saved ($locale)', (tester) async {
      await _withSettings(tester, locale, (radio, l10n) async {
        // Stabilize the list before expansion, as in the GET-guard case.
        await _read(tester, radio, l10n.repeater_refreshBasicSettings,
            'get name', 'Remote name');
        await _openAdvanced(tester, l10n);
        await _read(tester, radio, l10n.repeater_txDelay, 'get txdelay', '1');
        await _read(tester, radio, l10n.repeater_directTxDelay,
            'get direct.txdelay', '1');
        await _editText(tester, l10n.repeater_txDelay, 'invalid');
        await _editText(tester, l10n.repeater_directTxDelay, '1.5');
        final save = find.widgetWithText(TextButton, l10n.common_save);
        final beforeSave = radio.commands.length;
        await tester.tap(save);
        await tester.pump();
        expect(radio.commands.skip(beforeSave), ['set direct.txdelay 1.5']);
        await _answer(tester, radio, 'OK');
        await tester.pumpAndSettle();
        expect(save, findsOneWidget);
        expect(tester.widget<TextField>(
          _textInput(l10n.repeater_txDelay),
        ).controller!.text, 'invalid');

        await _editText(tester, l10n.repeater_txDelay, '0');
        await tester.tap(save);
        await tester.pump();
        expect(radio.commands.skip(beforeSave),
            ['set direct.txdelay 1.5', 'set txdelay 0.0']);
        await _answer(tester, radio, 'OK');
        await tester.pumpAndSettle();
        expect(save, findsNothing);
      });
    });

    testWidgets('U13b baseline: incomplete radio GET does not write defaults '
        'and a complete refresh supplies the bundle ($locale)', (tester) async {
      await _withSettings(tester, locale, (radio, l10n) async {
        await _read(tester, radio, l10n.repeater_refreshRadioSettings,
            'get radio', '869.495');
        for (final label in [l10n.repeater_bandwidth,
          l10n.repeater_spreadingFactor, l10n.repeater_codingRate]) {
          expect(_dropdown<int>(tester, label).value, isNull);
        }
        expect(find.widgetWithText(TextButton, l10n.common_save), findsNothing);
        expect(radio.commands, ['get radio']);
        await _read(tester, radio, l10n.repeater_refreshRadioSettings,
            'get radio', '869.495,137.5,8,2');
        // CR 1..4 returned by some firmware is normalized to UI 5..8.
        expect(_dropdown<int>(tester, l10n.repeater_codingRate).value, 6);
        await _editText(tester, l10n.repeater_frequencyMhz, '868,3');
        final save = find.widgetWithText(TextButton, l10n.common_save);
        await tester.tap(save);
        await tester.pump();
        expect(radio.commands,
            ['get radio', 'get radio', 'set radio 868.3,137.5,8,6']);
        await _answer(tester, radio, 'OK');
        await tester.pumpAndSettle();
        expect(save, findsNothing);
      });
    });

    testWidgets('U13b baseline: manual batch reads serially and continues '
        'past an unsupported setting ($locale)', (tester) async {
      await _withSettings(tester, locale, (radio, l10n) async {
        // This is the accepted pre-U13c GET list, not an automatic query.
        const replies = <(String, String)>[
          ('get name', '> Remote name'),
          ('get radio', '> 869.495,125,7,5'),
          ('get tx', '> 14'),
          ('get radio.rxgain', '> on'),
          ('get lat', '> 55.75'),
          ('get lon', '> 37.625'),
          ('get repeat', '> on'),
          ('get allow.read.only', '> on'),
          ('get multi.acks', '> 1'),
          ('get loop.detect', '> moderate'),
          ('get dutycycle', '> 50.0%'),
          ('get advert.interval', '> 120'),
          ('get flood.advert.interval', '> 12'),
          ('get flood.max', '> 64'),
          ('get owner.info', '> Owner|Second line'),
          ('get path.hash.mode', '> 1'),
          ('get txdelay', 'Error: unknown command'),
          ('get direct.txdelay', '> 0.5'),
          ('get int.thresh', '> 0'),
          ('get agc.reset.interval', '> 60'),
        ];
        final refresh = _icon(l10n.repeater_refreshAll);
        await tester.tap(refresh);
        await tester.pump();
        expect(tester.widget<IconButton>(refresh).onPressed, isNull);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        for (var i = 0; i < replies.length; i++) {
          expect(radio.commands, [
            for (final item in replies.take(i + 1)) item.$1,
          ]);
          // No second request may start while this one awaits its reply.
          await tester.pump(const Duration(milliseconds: 25));
          expect(radio.commands, hasLength(i + 1));
          await _answer(tester, radio, replies[i].$2);
        }
        await tester.pumpAndSettle();
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(tester.widget<IconButton>(refresh).onPressed, isNotNull);
        expect(find.widgetWithText(TextButton, l10n.common_save), findsNothing);
        await _openAdvanced(tester, l10n);
        final tx = _textInput(l10n.repeater_txDelay);
        await _reveal(tester, tx);
        expect(tester.widget<TextField>(tx).enabled, isFalse);
        final direct = _textInput(l10n.repeater_directTxDelay);
        await _reveal(tester, direct);
        expect(tester.widget<TextField>(direct).enabled, isTrue);
        expect(tester.widget<TextField>(direct).controller!.text, '0.5');
        await tester.pump(const Duration(seconds: 5));
        expect(radio.commands, [for (final item in replies) item.$1]);
      });
    });

    testWidgets('U13b: Advanced stays open after the first successful GET '
        '($locale)', (tester) async {
      await _withSettings(tester, locale, (radio, l10n) async {
        await _openAdvanced(tester, l10n);
        await _read(tester, radio, l10n.repeater_txDelay, 'get txdelay', '0.5');
        // No second tap on the Advanced heading: its state must survive
        // removal of the unloaded notice above the settings cards.
        final tx = _textInput(l10n.repeater_txDelay);
        final direct = _textInput(l10n.repeater_directTxDelay);
        expect(tx, findsOneWidget);
        expect(direct, findsOneWidget);
        expect(tester.widget<TextField>(tx).enabled, isTrue);
        expect(tester.widget<TextField>(tx).controller!.text, '0.5');
        expect(tester.widget<TextField>(direct).enabled, isFalse);
        await _read(tester, radio, l10n.repeater_directTxDelay,
            'get direct.txdelay', '1');
        await tester.pump(const Duration(seconds: 1));
        expect(radio.commands, ['get txdelay', 'get direct.txdelay']);
        expect(find.widgetWithText(TextButton, l10n.common_save), findsNothing);
      });
    });

    testWidgets('U13b: both delays reject out-of-range and non-finite values '
        'and preserve valid boundaries ($locale)', (tester) async {
      await _withSettings(tester, locale, (radio, l10n) async {
        await _openAdvanced(tester, l10n);
        await _read(tester, radio, l10n.repeater_txDelay, 'get txdelay', '1');
        await _read(tester, radio, l10n.repeater_directTxDelay,
            'get direct.txdelay', '1');
        final save = find.widgetWithText(TextButton, l10n.common_save);
        final beforeSave = radio.commands.length;
        for (final invalid in ['-0.1', '2.1', 'NaN', 'Infinity', '-Infinity']) {
          await _editText(tester, l10n.repeater_txDelay, invalid);
          await _editText(tester, l10n.repeater_directTxDelay, invalid);
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(radio.commands, hasLength(beforeSave), reason: invalid);
          expect(save, findsOneWidget);
          expect(tester.widget<TextField>(
            _textInput(l10n.repeater_txDelay),
          ).controller!.text, invalid);
          expect(tester.widget<TextField>(
            _textInput(l10n.repeater_directTxDelay),
          ).controller!.text, invalid);
        }
        await _editText(tester, l10n.repeater_txDelay, '0');
        await _editText(tester, l10n.repeater_directTxDelay, '2');
        await tester.tap(save);
        await tester.pump();
        expect(radio.commands.skip(beforeSave), ['set txdelay 0.0']);
        await _answer(tester, radio, 'OK');
        expect(radio.commands.last, 'set direct.txdelay 2.0');
        await _answer(tester, radio, 'OK');
        await tester.pumpAndSettle();
        expect(save, findsNothing);
      });
    });

    for (final partial in ['869.495', '869.495,125,7', ',125,7,5']) {
      testWidgets('U13b: incomplete radio save stays dirty and sends no SET '
          '($locale, reply=$partial)', (tester) async {
        await _withSettings(tester, locale, (radio, l10n) async {
          await _read(tester, radio, l10n.repeater_refreshRadioSettings,
              'get radio', partial);
          if (partial.startsWith(',')) {
            // Mark the bundle dirty while its required frequency is empty.
            await _choose<int>(tester, l10n.repeater_spreadingFactor, 'SF8');
          } else {
            await _editText(tester, l10n.repeater_frequencyMhz, '868,3');
          }
          // Let the preceding refresh snackbar expire so validation is shown.
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
          final save = find.widgetWithText(TextButton, l10n.common_save);
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(radio.commands, ['get radio']);
          expect(save, findsOneWidget);
          final missingLabel = partial.startsWith(',')
              ? l10n.repeater_frequencyMhz
              : l10n.repeater_codingRate;
          expect(find.textContaining(l10n.repeater_valueRequired(missingLabel)),
              findsOneWidget);

          await _read(tester, radio, l10n.repeater_refreshRadioSettings,
              'get radio', '869.495,125,7,5');
          await _editText(tester, l10n.repeater_frequencyMhz, '868,3');
          await tester.tap(save);
          await tester.pump();
          expect(radio.commands,
              ['get radio', 'get radio', 'set radio 868.3,125.0,7,5']);
          await _answer(tester, radio, 'OK');
          await tester.pumpAndSettle();
          expect(save, findsNothing);
        });
      });
    }

    testWidgets('U11b8 baseline: open and disconnected state never fetch settings ($locale)', (tester) async {
      await _withSettings(tester, locale, (radio, l10n) async {
        expect(find.text(l10n.repeater_settingsNotLoaded), findsOneWidget);
        expect(tester.widget<IconButton>(_icon(l10n.repeater_refreshAll)).onPressed, isNotNull);
        for (final label in [l10n.repeater_bandwidth,
          l10n.repeater_spreadingFactor, l10n.repeater_codingRate]) {
          await _reveal(tester, find.text(label));
          expect(_dropdown<int>(tester, label).onChanged, isNull);
        }
        await _reveal(tester, find.text(l10n.repeater_loopDetect));
        expect(_dropdown<String>(tester, l10n.repeater_loopDetect).onChanged, isNull);
        await _reveal(tester, find.text(l10n.repeater_advancedSettings));
        await tester.tap(find.text(l10n.repeater_advancedSettings));
        await tester.pumpAndSettle();
        await _reveal(tester, find.text(l10n.repeater_pathHashMode));
        expect(_dropdown<int>(tester, l10n.repeater_pathHashMode).onChanged, isNull);
        expect(radio.commands, isEmpty);
        radio.connected = false;
        radio.notifyListeners();
        await tester.pumpAndSettle();
        expect(tester.widget<IconButton>(_icon(l10n.repeater_refreshAll)).onPressed, isNull);
        await tester.pump(const Duration(seconds: 5));
        expect(radio.commands, isEmpty);
      });
    });

    testWidgets('U11b8 baseline: radio selections stay local until Save and rejection keeps the draft ($locale)', (tester) async {
      await _withSettings(tester, locale, (radio, l10n) async {
        await _read(tester, radio, l10n.repeater_refreshRadioSettings,
            'get radio', '869.495,137.5,7,5');
        expect(_dropdown<int>(tester, l10n.repeater_bandwidth).value, 137500);
        expect(_dropdown<int>(tester, l10n.repeater_bandwidth).items!
            .map((item) => item.value), contains(137500));
        await _choose<int>(tester, l10n.repeater_bandwidth, '125 kHz');
        await _choose<int>(tester, l10n.repeater_spreadingFactor, 'SF8');
        await _choose<int>(tester, l10n.repeater_codingRate, '4/6');
        expect(radio.commands, ['get radio']);
        final save = find.widgetWithText(TextButton, l10n.common_save);
        await tester.tap(save);
        await tester.pump();
        expect(radio.commands, ['get radio', 'set radio 869.495,125.0,8,6']);
        await _answer(tester, radio, 'Error rejected');
        await tester.pumpAndSettle();
        expect(save, findsOneWidget);
        expect(_dropdown<int>(tester, l10n.repeater_bandwidth).value, 125000);
        expect(_dropdown<int>(tester, l10n.repeater_spreadingFactor).value, 8);
        expect(_dropdown<int>(tester, l10n.repeater_codingRate).value, 6);
        await tester.tap(save);
        await tester.pump();
        expect(radio.commands, [
          'get radio', 'set radio 869.495,125.0,8,6', 'set radio 869.495,125.0,8,6',
        ]);
        await _answer(tester, radio, 'OK');
        await tester.pumpAndSettle();
        expect(save, findsNothing);
      });
    });

    testWidgets('U11b8 baseline: loop and path width use explicit GET and dirty SET only ($locale)', (tester) async {
      await _withSettings(tester, locale, (radio, l10n) async {
        await _read(tester, radio, l10n.repeater_loopDetect, 'get loop.detect', 'moderate');
        expect(_dropdown<String>(tester, l10n.repeater_loopDetect).value, 'moderate');
        await _choose<String>(tester, l10n.repeater_loopDetect, l10n.repeater_loopDetectStrict);
        expect(_dropdown<String>(tester, l10n.repeater_loopDetect).value, 'strict');
        await _reveal(tester, find.text(l10n.repeater_advancedSettings));
        await tester.tap(find.text(l10n.repeater_advancedSettings));
        await tester.pumpAndSettle();
        await _read(tester, radio, l10n.repeater_pathHashMode, 'get path.hash.mode', '1');
        expect(_dropdown<int>(tester, l10n.repeater_pathHashMode).value, 1);
        await _choose<int>(tester, l10n.repeater_pathHashMode, l10n.repeater_pathHashModeOption2);
        expect(radio.commands, ['get loop.detect', 'get path.hash.mode']);
        final save = find.widgetWithText(TextButton, l10n.common_save);
        await tester.tap(save);
        await tester.pump();
        expect(radio.commands, ['get loop.detect', 'get path.hash.mode', 'set loop.detect strict']);
        await _answer(tester, radio, 'OK');
        expect(radio.commands, [
          'get loop.detect', 'get path.hash.mode', 'set loop.detect strict', 'set path.hash.mode 2',
        ]);
        await _answer(tester, radio, 'OK');
        await tester.pumpAndSettle();
        expect(save, findsNothing);
        expect(_dropdown<int>(tester, l10n.repeater_pathHashMode).value, 2);
      });
    });
  }
}
