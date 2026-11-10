import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mco_service/mco_service.dart' show SettingsSectionsService;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/radio_settings.dart';
import 'package:meshcore_open/screens/export_screen.dart';
import 'package:meshcore_open/screens/settings_screen.dart';
import 'package:meshcore_open/services/app_debug_log_service.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/app_update_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';

class _NoDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('Synthetic preferences without a directory');
  }
}

class _Sections extends ChangeNotifier implements SettingsSectionsService {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #licenseManagementTitle) {
      return null;
    }
    return super.noSuchMethod(invocation);
  }
}

Uint8List _selfInfo({int frequency = 869495}) {
  final frame = ByteData(64);
  frame.setUint8(0, respCodeSelfInfo);
  frame.setInt8(2, 14);
  frame.setInt8(3, 22);
  for (var i = 4; i < 36; i++) {
    frame.setUint8(i, 0x11);
  }
  frame.setUint8(47, 1);
  frame.setUint32(48, frequency, Endian.little);
  frame.setUint32(52, 125000, Endian.little);
  frame.setUint8(56, 7);
  frame.setUint8(57, 1); // Firmware's CR 1 must be displayed/saved as UI CR 5.
  frame.buffer.asUint8List().setRange(58, 63, 'Radio'.codeUnits);
  return frame.buffer.asUint8List();
}

// Real command/ACK path. Only physical connectivity and refresh are synthetic;
// unsolicited SELF_INFO does not load databases or start a connection handshake.
class _Connector extends MeshCoreConnector {
  bool reject = false;
  bool mismatch = false;
  int refreshes = 0;
  int? reportedMode;
  Completer<void>? refreshGate;
  final frames = <List<int>>[];

  _Connector({int version = 10}) {
    final info = Uint8List(82);
    info[0] = respCodeDeviceInfo;
    info[1] = version;
    info[81] = 2;
    handleFrameForTest(info);
    handleFrameForTest(_selfInfo());
    setFrameWriterForTest((frame) async {
      frames.add(frame.toList());
      if (frame[0] == cmdSetRadioParams) {
        handleFrameForTest(reject ? [respCodeErr, 1] : [respCodeOk]);
      } else if (frame[0] == cmdSetRadioTxPower ||
          frame[0] == cmdSetPathHashMode) {
        // These setters also reply OK. Leaving them pending would let an
        // earlier setter consume the next save's radio-parameter ACK.
        handleFrameForTest([respCodeOk]);
      }
    });
  }

  @override
  bool get isConnected => true;

  @override
  Future<void> refreshDeviceInfo() async {
    refreshes++;
    handleFrameForTest(_selfInfo(frequency: mismatch ? 868000 : 869495));
    if (reportedMode case final int mode) {
      final info = Uint8List(82);
      info[0] = respCodeDeviceInfo;
      info[1] = 10;
      info[81] = mode;
      handleFrameForTest(info);
    }
    await refreshGate?.future;
  }
}

Future<void> _withScreen(
  WidgetTester tester,
  Future<void> Function(_Connector, AppLocalizations) check, {
  int version = 10,
  Locale locale = const Locale('en'),
  Size size = const Size(1100, 1800),
  double textScale = 1,
}) async {
  final connector = _Connector(version: version);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  try {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<MeshCoreConnector>.value(value: connector),
        ChangeNotifierProvider(create: (_) => AppSettingsService()),
        ChangeNotifierProvider(create: (_) => AppDebugLogService()),
        ChangeNotifierProvider<SettingsSectionsService>(create: (_) => _Sections()),
        ChangeNotifierProvider(create: (_) => AppUpdateService(
          preferences: PrefsManager.instance,
        )),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const SettingsScreen(),
      ),
    ));
    await tester.pump();
    final l10n = AppLocalizations.of(tester.element(find.byType(SettingsScreen)));
    await check(connector, l10n);
  } finally {
    final gate = connector.refreshGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
    // Drain any response deadlines before disposing an early-failed test.
    await tester.pump(const Duration(seconds: 6));
    // Connected status pulses, so avoid an unbounded pumpAndSettle.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    connector.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

Future<void> _revealSetting(WidgetTester tester, Finder item) async {
  final list = find.descendant(
    of: find.byType(SettingsScreen),
    matching: find.byType(ListView),
  ).first;
  final scrollable = find.descendant(
    of: list,
    matching: find.byType(Scrollable),
  ).first;
  // A small viewport may not have built the node-settings card yet.
  // Start at the top, also when returning to a setting above the previous
  // one, then let bounded scrolling build the target before ensuring it.
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(item, 180,
      scrollable: scrollable, maxScrolls: 40);
  // scrollUntilVisible ends with ensureVisible/jumpTo. Layout still needs
  // a frame before the next tap can use the item's new screen coordinates.
  await tester.pump();
  expect(item.hitTestable(), findsOneWidget,
      reason: 'The setting must be on screen before it is tapped');
}

Future<void> _openRadio(WidgetTester tester, AppLocalizations l10n) async {
  await _revealSetting(tester, find.text(l10n.settings_radioSettings));
  await tester.tap(find.text(l10n.settings_radioSettings));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _save(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.widgetWithText(FilledButton, l10n.common_save));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

DropdownButton<T> _radioDropdown<T>(WidgetTester tester) =>
    tester.widget<DropdownButton<T>>(find.descendant(
      of: find.byType(DropdownButtonFormField<T>),
      matching: find.byType(DropdownButton<T>),
    ));

Future<void> _selectRadioOption<T>(
  WidgetTester tester,
  String label, {
  bool? expectWrapped,
}) async {
  final field = find.byType(DropdownButtonFormField<T>);
  // Wrapping labels can make the decorated field taller than the dialog's
  // viewport. Reveal the small, actual menu trigger instead of requiring
  // the centre of the entire FormField to lie inside the viewport.
  final trigger = find.descendant(
    of: field,
    matching: find.byIcon(Icons.arrow_drop_down),
  );
  expect(trigger, findsOneWidget);
  await tester.ensureVisible(trigger);
  await tester.pump();
  expect(trigger.hitTestable(), findsOneWidget,
      reason: 'The dropdown arrow must be visible and tappable');
  await tester.tap(trigger);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  final option = find.text(label).last;
  await tester.ensureVisible(option);
  await tester.pump();
  expect(option.hitTestable(), findsOneWidget);
  if (expectWrapped != null) {
    _expectCompleteRadioLabel(tester, option, wraps: expectWrapped);
  }
  await tester.tap(option);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void _expectCompleteRadioLabel(
  WidgetTester tester,
  Finder label, {
  required bool wraps,
}) {
  final text = tester.widget<Text>(label).data!;
  final paragraph = tester.renderObject<RenderParagraph>(label);
  expect(paragraph.didExceedMaxLines, isFalse);
  // Merely retaining Text.data would miss a fixed-height field clipping
  // its lower lines. Every glyph box must fit in the rendered paragraph.
  final boxes = paragraph.getBoxesForSelection(TextSelection(
    baseOffset: 0,
    extentOffset: text.length,
  ));
  expect(boxes, isNotEmpty);
  for (final box in boxes) {
    expect(box.top, greaterThanOrEqualTo(-0.01));
    expect(box.bottom, lessThanOrEqualTo(paragraph.size.height + 0.01));
  }
  if (wraps) {
    // One line may have several selection boxes; a later vertical position
    // proves wrapping without relying on TextPainter-only APIs.
    expect(boxes.any((box) => box.top > boxes.first.top + 1), isTrue,
        reason: 'The long radio label must occupy more than one line');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PathProviderPlatform savedPaths;
  setUpAll(() {
    savedPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoDirectory();
  });
  tearDownAll(() => PathProviderPlatform.instance = savedPaths);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    PackageInfo.setMockInitialValues(
      appName: 'Synthetic MCO', packageName: 'example.mco',
      version: '1.0.0', buildNumber: '1', buildSignature: '',
    );
  });
  tearDown(PrefsManager.reset);

  for (final language in ['en', 'ru']) {
    testWidgets('U35: Settings opens the GPX actions ($language)', (tester) async {
      await _withScreen(
        tester,
        (connector, l10n) async {
          final open = find.text(l10n.settings_export);
          await _revealSetting(tester, open);
          await tester.tap(open);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));

          final screen = find.byType(ExportScreen);
          expect(screen, findsOneWidget);
          final messenger = ScaffoldMessenger.of(tester.element(screen));
          for (final label in [
            l10n.settings_gpxExportRepeaters,
            l10n.settings_gpxExportContacts,
            l10n.settings_gpxExportAll,
          ]) {
            final action = find.descendant(
              of: screen,
              matching: find.text(label),
            );
            await tester.ensureVisible(action);
            await tester.pump();
            await tester.tap(action.hitTestable());
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(
              find.widgetWithText(SnackBar, l10n.settings_gpxExportNoContacts),
              findsOneWidget,
            );
            messenger.removeCurrentSnackBar();
            await tester.pump();
          }
          expect(connector.frames, isEmpty);
          expect(tester.takeException(), isNull);
        },
        locale: Locale(language),
        size: const Size(360, 640),
        textScale: 1.5,
      );
    });

    for (final layout in [
      (name: 'phone', size: const Size(320, 568)),
      (name: 'landscape', size: const Size(568, 360)),
    ]) {
      testWidgets('U11b2: radio menus and standalone path width remain usable ($language, ${layout.name}, scale=2)', (tester) async {
        await _withScreen(tester, (connector, l10n) async {
          final pathItem = find.text(l10n.repeater_pathHashMode);
          await _revealSetting(tester, pathItem);
          await tester.tap(pathItem);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          final pathDialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
          expect(pathDialog.scrollable, isTrue);
          expect(_radioDropdown<int>(tester).items!.map((item) => item.value), [0, 1, 2]);
          await _selectRadioOption<int>(tester, l10n.repeater_pathHashModeOption1);
          expect(connector.frames, isEmpty);
          final save = find.widgetWithText(FilledButton, l10n.common_save);
          final cancel = find.widgetWithText(TextButton, l10n.common_cancel);
          expect(save.hitTestable(), findsOneWidget);
          expect(cancel.hitTestable(), findsOneWidget);
          connector.reportedMode = 1;
          await _save(tester, l10n);
          // The refreshed DEVICE_INFO starts the existing one-shot config
          // reads, skipped by this fixture's unsolicited initial SELF_INFO.
          final expectedAfterRefresh = [
            [cmdSetPathHashMode, 0, 1],
            [cmdGetAutoAddConfig],
            [cmdGetAllowedRepeatFreq],
          ];
          expect(connector.frames, expectedAfterRefresh);
          expect(connector.refreshes, 1);
          expect(connector.pathHashByteWidth, 2);

          await _openRadio(tester, l10n);
          // The duplicate upstream path selector must stay hidden, including
          // on narrow screens. The only integer dropdown here is the preset.
          expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
          const presetLabel = 'Australia (Narrow)';
          await _selectRadioOption<int>(tester, presetLabel,
              expectWrapped: layout.name == 'phone');
          _expectCompleteRadioLabel(tester, find.descendant(
            of: find.byType(DropdownButtonFormField<int>),
            matching: find.text(presetLabel),
          ), wraps: layout.name == 'phone');
          await _selectRadioOption<LoRaBandwidth>(tester, '31.25 kHz');
          await _selectRadioOption<LoRaSpreadingFactor>(tester, 'SF8');
          await _selectRadioOption<LoRaCodingRate>(tester, '4/6');
          expect(_radioDropdown<LoRaBandwidth>(tester).value, LoRaBandwidth.bw31_25);
          expect(_radioDropdown<LoRaSpreadingFactor>(tester).value, LoRaSpreadingFactor.sf8);
          expect(_radioDropdown<LoRaCodingRate>(tester).value, LoRaCodingRate.cr4_6);
          expect(save.hitTestable(), findsOneWidget);
          expect(cancel.hitTestable(), findsOneWidget);
          await tester.tap(cancel);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          expect(find.byType(AlertDialog), findsNothing);
          // Opening/editing/cancelling adds no writes or repeated config
          // reads after the explicitly saved width and its refresh.
          expect(connector.frames, expectedAfterRefresh);
          expect(connector.refreshes, 1);
          expect(connector.pathHashByteWidth, 2);
          expect(tester.takeException(), isNull);
        }, locale: Locale(language), size: layout.size, textScale: 2);
      });
    }
  }

  testWidgets('U11b2 baseline: radio dropdown choices remain drafts until save', (tester) async {
    await _withScreen(tester, (connector, l10n) async {
      await _openRadio(tester, l10n);
      expect(_radioDropdown<LoRaBandwidth>(tester).items!.map((item) => item.value), LoRaBandwidth.values);
      expect(_radioDropdown<LoRaSpreadingFactor>(tester).items!.map((item) => item.value), LoRaSpreadingFactor.values);
      expect(_radioDropdown<LoRaCodingRate>(tester).items!.map((item) => item.value), LoRaCodingRate.values);

      // Exercise actual menus, not just onChanged callbacks. Layout changes
      // must retain every option and must not introduce implicit radio writes.
      await _selectRadioOption<LoRaBandwidth>(tester, '250 kHz');
      await _selectRadioOption<LoRaSpreadingFactor>(tester, 'SF8');
      await _selectRadioOption<LoRaCodingRate>(tester, '4/6');
      expect(_radioDropdown<LoRaBandwidth>(tester).value, LoRaBandwidth.bw250);
      expect(_radioDropdown<LoRaSpreadingFactor>(tester).value, LoRaSpreadingFactor.sf8);
      expect(_radioDropdown<LoRaCodingRate>(tester).value, LoRaCodingRate.cr4_6);
      expect(connector.frames, isEmpty);
      expect(connector.pathHashByteWidth, 3);
      await tester.tap(find.widgetWithText(TextButton, l10n.common_cancel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(AlertDialog), findsNothing);
      expect(connector.frames, isEmpty);
      expect(connector.refreshes, 0);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('U11b2 baseline: cancelling standalone path width keeps the node unchanged', (tester) async {
    await _withScreen(tester, (connector, l10n) async {
      final tile = find.text(l10n.repeater_pathHashMode);
      await _revealSetting(tester, tile);
      await tester.tap(tile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await _selectRadioOption<int>(tester, l10n.repeater_pathHashModeOption1);
      expect(_radioDropdown<int>(tester).value, 1);
      expect(connector.frames, isEmpty);
      await tester.tap(find.widgetWithText(TextButton, l10n.common_cancel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(AlertDialog), findsNothing);
      expect(connector.pathHashByteWidth, 3);
      expect(connector.frames, isEmpty);
      expect(connector.refreshes, 0);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('baseline: radio draft and presets do not transmit or reset path width', (tester) async {
    await _withScreen(tester, (connector, l10n) async {
      await _openRadio(tester, l10n);
      expect(tester.widget<TextField>(_field(l10n.settings_frequency)).controller!.text, '869.495');
      expect(tester.widget<TextField>(_field(l10n.settings_txPower)).controller!.text, '14');
      expect(find.text('4/5'), findsWidgets);
      final preset = tester.widget<DropdownButtonFormField<int>>(
        find.byType(DropdownButtonFormField<int>).first,
      );
      preset.onChanged!(0); // Exercise the same callback as selecting Australia.
      await tester.pump();
      expect(tester.widget<TextField>(_field(l10n.settings_frequency)).controller!.text, '915.8');
      expect(connector.pathHashByteWidth, 3);
      expect(connector.frames, isEmpty);
      await tester.tap(find.widgetWithText(TextButton, l10n.common_cancel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsNothing);
      expect(connector.frames, isEmpty);
    });
  });

  testWidgets('baseline: off-grid toggle restores the selected normal preset without sending', (tester) async {
    await _withScreen(tester, (connector, l10n) async {
      await _openRadio(tester, l10n);
      tester.widget<DropdownButtonFormField<int>>(
        find.byType(DropdownButtonFormField<int>).first,
      ).onChanged!(0);
      await tester.pump();
      final toggle = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(SwitchListTile),
      );
      tester.widget<SwitchListTile>(toggle).onChanged!(true);
      await tester.pump();
      expect(tester.widget<TextField>(_field(l10n.settings_frequency)).controller!.text, '918.000');
      tester.widget<SwitchListTile>(toggle).onChanged!(false);
      await tester.pump();
      expect(tester.widget<TextField>(_field(l10n.settings_frequency)).controller!.text, '915.800');
      expect(connector.pathHashByteWidth, 3);
      expect(connector.frames, isEmpty);
    });
  });

  testWidgets('baseline: successful save retains radio values, repeat flag and path mode', (tester) async {
    await _withScreen(tester, (connector, l10n) async {
      await _openRadio(tester, l10n);
      await _save(tester, l10n);
      expect(connector.frames, [
        buildSetRadioParamsFrame(869495, 125000, 7, 5, clientRepeat: false).toList(),
        [cmdSetRadioTxPower, 14],
      ]);
      expect(connector.refreshes, 1);
      expect(connector.pathHashByteWidth, 3);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  testWidgets('baseline: rejected radio settings keep the draft and skip TX power/refresh', (tester) async {
    await _withScreen(tester, (connector, l10n) async {
      connector.reject = true;
      await _openRadio(tester, l10n);
      await _save(tester, l10n);
      expect(connector.frames, hasLength(1));
      expect(connector.frames.single.first, cmdSetRadioParams);
      expect(connector.refreshes, 0);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(l10n.settings_radioSettingsNotApplied), findsOneWidget);
      expect(tester.widget<TextField>(_field(l10n.settings_frequency)).controller!.text, '869.495');
    });
  });

  testWidgets('baseline: SELF_INFO mismatch keeps the radio editor open', (tester) async {
    await _withScreen(tester, (connector, l10n) async {
      connector.mismatch = true;
      await _openRadio(tester, l10n);
      await _save(tester, l10n);
      expect(connector.refreshes, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(l10n.settings_radioSettingsNotApplied), findsOneWidget);
    });
  });

  for (final version in [9, 10]) {
    testWidgets('radio editor hides the upstream path selector (code=$version)', (tester) async {
      await _withScreen(tester, (connector, l10n) async {
        await _openRadio(tester, l10n);
        final fields = find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(DropdownButtonFormField<int>),
        );
        expect(fields, findsOneWidget);
        expect(connector.supportsPathHashMode, version >= 10);
      }, version: version);
    });
  }

  testWidgets('radio save never reverts path width changed outside its hidden selector', (tester) async {
    await _withScreen(tester, (connector, l10n) async {
      await _openRadio(tester, l10n);
      final info = Uint8List(82)
        ..[0] = respCodeDeviceInfo
        ..[1] = 10
        ..[81] = 1;
      connector.handleFrameForTest(info);
      expect(connector.pathHashByteWidth, 2);
      await _save(tester, l10n);
      expect(connector.frames.where((frame) => frame.first == cmdSetPathHashMode), isEmpty);
      expect(connector.pathHashByteWidth, 2);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  // Keep the upstream-specific tests beside its dormant implementation.
  // Standalone selector tests below remain active and exercise real commands.
  group('dormant upstream path selector in the radio editor', () {
    for (final mode in [0, 1]) {
      testWidgets('radio save confirms requested mode $mode from DEVICE_INFO', (tester) async {
        await _withScreen(tester, (connector, l10n) async {
          connector.reportedMode = mode;
          await _openRadio(tester, l10n);
          tester.widget<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>).last,
          ).onChanged!(mode);
          await tester.pump();
          await _save(tester, l10n);
          expect(connector.frames.where((f) => f.first == cmdSetPathHashMode).toList(), [[61, 0, mode]]);
          expect(connector.pathHashByteWidth, mode + 1);
          expect(find.byType(AlertDialog), findsNothing);
        });
      });
    }

    testWidgets('radio keeps the draft on mismatching path confirmation', (tester) async {
      await _withScreen(tester, (connector, l10n) async {
        connector.reportedMode = 2;
        await _openRadio(tester, l10n);
        tester.widget<DropdownButtonFormField<int>>(
          find.byType(DropdownButtonFormField<int>).last,
        ).onChanged!(0);
        await tester.pump();
        await _save(tester, l10n);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text(l10n.settings_pathHashModeNotApplied), findsOneWidget);
        expect(connector.pathHashByteWidth, 3);
      });
    });

    testWidgets('missing DEVICE_INFO times out during held refresh and retry still requires confirmation', (tester) async {
      await _withScreen(tester, (connector, l10n) async {
        final gate = Completer<void>();
        connector.refreshGate = gate;
        await _openRadio(tester, l10n);
        tester.widget<DropdownButtonFormField<int>>(
          find.byType(DropdownButtonFormField<int>).last,
        ).onChanged!(0);
        await tester.pump();
        await _save(tester, l10n);
        expect(connector.pathHashByteWidth, 1); // Optimistic local update only.
        // All setters were acknowledged; only the refreshed DEVICE_INFO is lost.
        expect(connector.pendingCommandReplyCountForTest, 0);
        await tester.pump(const Duration(seconds: 5));
        expect(find.byType(AlertDialog), findsOneWidget);
        gate.complete();
        connector.refreshGate = null;
        await tester.pump();
        expect(find.text(l10n.settings_pathHashModeNotApplied), findsOneWidget);
        // Retrying after timeout must not trust the optimistic width of 1.
        connector.reportedMode = 0;
        await _save(tester, l10n);
        expect(connector.frames.where((f) => f.first == cmdSetPathHashMode), hasLength(2));
        expect(find.byType(AlertDialog), findsNothing);
      });
    });

    testWidgets('applying a radio preset preserves the drafted path hash mode', (tester) async {
      await _withScreen(tester, (connector, l10n) async {
        connector.reportedMode = 0;
        await _openRadio(tester, l10n);
        tester.widget<DropdownButtonFormField<int>>(
          find.byType(DropdownButtonFormField<int>).last,
        ).onChanged!(0);
        tester.widget<DropdownButtonFormField<int>>(
          find.byType(DropdownButtonFormField<int>).first,
        ).onChanged!(0);
        await tester.pump();
        await _save(tester, l10n);
        expect(connector.frames.where((f) => f.first == cmdSetPathHashMode).toList(), [[61, 0, 0]]);
        // This fixture intentionally returns its old radio values, so retain
        // the existing radio-mismatch behavior while checking the path request.
        expect(find.byType(AlertDialog), findsOneWidget);
      });
    });

  }, skip: 'Path width is temporarily managed only by the standalone selector');

  for (final version in [9, 10]) {
    testWidgets('baseline: standalone path selector is gated at protocol code 10 (code=$version)', (tester) async {
      await _withScreen(tester, (connector, l10n) async {
        final tile = find.text(l10n.repeater_pathHashMode);
        await _revealSetting(tester, tile);
        await tester.tap(tile);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        if (version < 10) {
          expect(find.byType(AlertDialog), findsNothing);
          expect(connector.frames, isEmpty);
          return;
        }
        final dropdown = tester.widget<DropdownButtonFormField<int>>(
          find.byType(DropdownButtonFormField<int>),
        );
        // FormField exposes the callback; the rendered button owns items.
        final button = tester.widget<DropdownButton<int>>(find.descendant(
          of: find.byType(DropdownButtonFormField<int>),
          matching: find.byType(DropdownButton<int>),
        ));
        expect(button.items!.map((item) => item.value), [0, 1, 2]);
        dropdown.onChanged!(1);
        await tester.pump();
        await _save(tester, l10n);
        expect(connector.frames, [[61, 0, 1]]);
        expect(connector.refreshes, 1);
        expect(connector.pathHashByteWidth, 2);
      }, version: version);
    });
  }
}
