import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/path_selection.dart';
import 'package:meshcore_open/screens/repeater_status_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/widgets/mesh_ui.dart';
import 'package:provider/provider.dart';

import '../support/wrapping_label_expectations.dart'
    show expectCompleteWrappingLabel;

// Do not construct the real connector or open preferences/history. The real
// screen and both status parsers operate on synthetic transport frames.
class _Radio extends ChangeNotifier implements MeshCoreConnector {
  _Radio(int type) : target = Contact(
    publicKey: Uint8List.fromList(List.generate(32, (i) => i + 1)),
    name: 'Synthetic managed node',
    type: type,
    pathLength: -1,
    path: Uint8List(0),
    lastSeen: DateTime.utc(2026, 1, 1),
  );

  final Contact target;
  final incoming = StreamController<Uint8List>.broadcast(sync: true);
  final writes = <Uint8List>[];
  final outcomes = <bool>[];
  final batterySources = <String>[];
  int? batteryMv;
  bool connected = true;
  int preparations = 0;

  @override
  bool get isConnected => connected;
  @override
  List<Contact> get contacts => [target];
  @override
  Stream<Uint8List> get receivedFrames => incoming.stream;
  @override
  DateTime? repeaterClockAtLogin(Uint8List publicKey) => null;
  @override
  int? getRepeaterBatteryMillivolts(String contactKeyHex) => batteryMv;

  @override
  void updateRepeaterBatterySnapshot(String contactKeyHex, int millivolts, {
    String source = 'unknown',
  }) {
    expect(contactKeyHex, target.publicKeyHex);
    batteryMv = millivolts;
    batterySources.add(source);
    notifyListeners();
  }

  @override
  Future<PathSelection> preparePathForContactSend(Contact contact) async {
    expect(contact.publicKeyHex, target.publicKeyHex);
    preparations++;
    return const PathSelection(pathBytes: [], hopCount: -1, useFlood: true);
  }

  @override
  Future<void> sendContactFrame(Contact contact, Uint8List frame, {
    required bool useFlood,
    bool Function()? canSend,
    VoidCallback? onSending,
  }) async {
    expect(contact.publicKeyHex, target.publicKeyHex);
    expect(useFlood, isTrue);
    if (canSend?.call() == false) {
      return;
    }
    onSending?.call();
    writes.add(Uint8List.fromList(frame));
  }

  @override
  int calculateTimeout({
    required int pathLength,
    int messageBytes = 100,
    String? contactKey,
    int? deviceTimeoutMs,
  }) {
    expect(pathLength, -1);
    expect(messageBytes, greaterThanOrEqualTo(176));
    return 1000;
  }

  @override
  void recordRepeaterPathResult(Contact contact, PathSelection selection,
      bool success, int? tripTimeMs) {
    expect(contact.publicKeyHex, target.publicKeyHex);
    expect(selection.useFlood, isTrue);
    outcomes.add(success);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected status operation: ${invocation.memberName}');

  @override
  void dispose() {
    unawaited(incoming.close());
    super.dispose();
  }
}

Uint8List _binaryStatus(_Radio radio, {bool wrongSender = false}) {
  final room = radio.target.type == advTypeRoom;
  // Independent literal wire offsets: shared 48-byte body, then the
  // repeater's two uint32 fields or the room's two uint16 counters.
  final body = ByteData(room ? 52 : 56)
    ..setUint16(0, 4200, Endian.little)
    ..setUint16(2, 3, Endian.little)
    ..setInt16(4, -120, Endian.little)
    ..setInt16(6, -81, Endian.little)
    ..setUint32(8, 100, Endian.little)
    ..setUint32(12, 80, Endian.little)
    ..setUint32(16, 61, Endian.little)
    ..setUint32(20, 90061, Endian.little)
    ..setUint32(24, 50, Endian.little)
    ..setUint32(28, 30, Endian.little)
    ..setUint32(32, 60, Endian.little)
    ..setUint32(36, 25, Endian.little)
    ..setUint16(40, 2, Endian.little)
    ..setInt16(42, 29, Endian.little)
    ..setUint16(44, 2, Endian.little)
    ..setUint16(46, 3, Endian.little);
  if (room) {
    body.setUint16(48, 7, Endian.little);
    body.setUint16(50, 9, Endian.little);
  } else {
    body.setUint32(48, 120, Endian.little);
    body.setUint32(52, 4, Endian.little);
  }
  return Uint8List.fromList([
    pushCodeStatusResponse, 0,
    if (wrongSender) ...List.filled(6, 0xff)
    else ...radio.target.publicKey.take(6),
    ...body.buffer.asUint8List(),
  ]);
}

void _textReply(_Radio radio, String text) {
  radio.incoming.add(Uint8List.fromList([
    respCodeContactMsgRecv, ...radio.target.publicKey.take(6),
    0, txtTypePlain, 0, 0, 0, 0, ...utf8.encode(text), 0,
  ]));
}

Future<void> _withStatus(WidgetTester tester, String locale, int type,
    Future<void> Function(_Radio, AppLocalizations) run, {
  Size size = const Size(1100, 1800),
  double textScale = 1,
}) async {
  final radio = _Radio(type);
  final settings = AppSettingsService();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  try {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<MeshCoreConnector>.value(value: radio),
        ChangeNotifierProvider<AppSettingsService>.value(value: settings),
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
        home: RepeaterStatusScreen(repeater: radio.target, password: ''),
      ),
    ));
    // The response is injected after the asynchronous send has armed its
    // timeout. Do not settle the indeterminate loading indicator.
    await tester.pump();
    await tester.pump();
    expect(radio.writes, [<int>[cmdSendStatusReq, ...radio.target.publicKey]]);
    expect(radio.preparations, 1);
    expect(radio.incoming.hasListener, isTrue);
    final l10n = AppLocalizations.of(tester.element(find.byType(RepeaterStatusScreen)));
    await run(radio, l10n);
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    expect(radio.incoming.hasListener, isFalse);
    radio.dispose();
    settings.dispose();
  }
}

Map<String, String> _values(WidgetTester tester) => {
  for (final tile in tester.widgetList<StatTile>(find.byType(StatTile)))
    tile.label: tile.value,
};

// byTooltip locates a tooltip widget, which is not itself an IconButton.
Finder _refreshButton(AppLocalizations l10n) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == l10n.repeater_refresh,
  description: 'status refresh IconButton',
);

Finder _tile(String label) => find.byWidgetPredicate(
  (widget) => widget is StatTile && widget.label == label,
  description: 'statistic tile: $label',
);

void _expectCompleteValue(WidgetTester tester, Finder tile, String value) {
  final text = find.descendant(of: tile, matching: find.byWidgetPredicate(
    (widget) => widget is Text && widget.textSpan?.toPlainText() == value,
  ));
  expect(text, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(text);
  expect(paragraph.didExceedMaxLines, isFalse);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: value.length),
  );
  expect(boxes, isNotEmpty);
  for (final box in boxes) {
    expect(box.top, greaterThanOrEqualTo(-0.01));
    expect(box.bottom, lessThanOrEqualTo(paragraph.size.height + 0.01));
  }
  final card = tester.getRect(tile);
  final content = tester.getRect(text);
  expect(content.top, greaterThanOrEqualTo(card.top));
  expect(content.bottom, lessThanOrEqualTo(card.bottom + 0.01));
}

Map<String, String> _expected(AppLocalizations l10n, {required bool room}) => {
  l10n.repeater_battery: '100% / 4.20V',
  l10n.repeater_uptime: l10n.repeater_daysHoursMinsSecs(1, 1, 1, 1),
  l10n.repeater_clockAtLogin: '—',
  l10n.repeater_queueLength: '3',
  l10n.repeater_debugFlags: '2',
  l10n.repeater_lastRssi: '-81 dBm',
  l10n.repeater_lastSnr: '7.25',
  l10n.repeater_noiseFloor: '-120 dBm',
  l10n.repeater_txAirtime: l10n.repeater_hoursMinsSecs(0, 1, 1),
  if (!room) l10n.repeater_rxAirtime: l10n.repeater_hoursMinsSecs(0, 2, 0),
  l10n.repeater_sent:
      l10n.repeater_packetTxTotal(80, '50', '30').replaceAll(', ', '\n'),
  l10n.repeater_received:
      l10n.repeater_packetRxTotal(100, '60', '25').replaceAll(', ', '\n'),
  l10n.repeater_duplicates:
      l10n.repeater_duplicatesFloodDirect('3', '2').replaceAll(', ', '\n'),
  if (room) ...{
    l10n.room_postsStored: '7',
    l10n.room_postsPushed: '9',
  } else ...{
    l10n.repeater_packetErrors: '4',
    l10n.repeater_chanUtil: '0.20%',
  },
};

void main() {
  for (final locale in ['en', 'ru']) {
    for (final type in [advTypeRepeater, advTypeRoom]) {
      for (final layout in [
        (name: 'phone', size: const Size(430, 740), singleColumn: true, scale: 1.0),
        (name: 'phone', size: const Size(320, 568), singleColumn: true, scale: 2.0),
        (name: 'landscape', size: const Size(568, 360), singleColumn: true, scale: 2.0),
        (name: 'desktop', size: const Size(1000, 800), singleColumn: false, scale: 2.0),
      ]) {
        testWidgets(
          'U11b7: responsive status keeps complete fields without new requests '
          '($locale, type=$type, ${layout.name}, scale=${layout.scale})',
          (tester) async {
            await _withStatus(tester, locale, type, (radio, l10n) async {
              radio.incoming.add(_binaryStatus(radio));
              await tester.pumpAndSettle();
              final battery = _tile(l10n.repeater_battery);
              final uptime = _tile(l10n.repeater_uptime);
              if (layout.singleColumn) {
                expect(tester.getRect(battery).left, tester.getRect(uptime).left);
                expect(tester.getRect(battery).width, tester.getRect(uptime).width);
                expect(tester.getRect(uptime).top,
                    greaterThanOrEqualTo(tester.getRect(battery).bottom + 7));
                // Unlike paired rows, a single full-width tile needs no
                // IntrinsicHeight pass or empty placeholder beside it.
                expect(find.ancestor(of: battery,
                    matching: find.byType(IntrinsicHeight)), findsNothing);
              } else {
                expect(tester.getRect(battery).top, tester.getRect(uptime).top);
                expect(tester.getRect(battery).height, tester.getRect(uptime).height);
                expect(tester.getRect(battery).right,
                    lessThan(tester.getRect(uptime).left));
              }

              final list = find.byType(ListView);
              final scrollable = find.descendant(
                of: list, matching: find.byType(Scrollable),
              );
              expect(scrollable, findsOneWidget);
              final seen = <String, String>{};
              final expected = _expected(l10n, room: type == advTypeRoom);
              for (final entry in expected.entries) {
                final tile = _tile(entry.key);
                // Each section is built lazily; reveal it before asking for
                // a widget or RenderObject, preserving the real list behavior.
                await tester.scrollUntilVisible(tile, 160,
                    scrollable: scrollable, maxScrolls: 60);
                await tester.pumpAndSettle();
                expect(tile.hitTestable(), findsOneWidget);
                final card = tester.getRect(tile);
                expect(card.left, greaterThanOrEqualTo(0));
                expect(card.right, lessThanOrEqualTo(layout.size.width));
                seen[entry.key] = tester.widget<StatTile>(tile).value;
                expectCompleteWrappingLabel(tester,
                    find.descendant(of: tile,
                        matching: find.text(entry.key.toUpperCase())),
                    wraps: false);
                _expectCompleteValue(tester, tile, entry.value);
              }
              expect(seen, expected);
              await tester.pump(const Duration(seconds: 2));
              expect(radio.writes,
                  [<int>[cmdSendStatusReq, ...radio.target.publicKey]]);
              expect(radio.preparations, 1);
              expect(radio.outcomes, [true]);
              expect(radio.batterySources, ['status_binary']);

              // Returning to a wide window changes layout without resetting
              // the screen or requesting status again.
              tester.state<ScrollableState>(scrollable).position.jumpTo(0);
              tester.view.physicalSize = const Size(1100, 1800);
              await tester.pumpAndSettle();
              expect(tester.getRect(battery).top, tester.getRect(uptime).top);
              expect(tester.widget<StatTile>(battery).value, expected[l10n.repeater_battery]);
              expect(radio.writes, hasLength(1));
              expect(radio.outcomes, [true]);
              expect(tester.takeException(), isNull);
            }, size: layout.size, textScale: layout.scale);
          },
        );
      }

      testWidgets('U11b7 baseline: binary status keeps values and two-column rows ($locale, type=$type)', (tester) async {
        await _withStatus(tester, locale, type, (radio, l10n) async {
          radio.incoming.add(_binaryStatus(radio, wrongSender: true));
          _textReply(radio, 'unrelated CLI response');
          await tester.pump();
          expect(radio.outcomes, isEmpty);
          expect(radio.batterySources, isEmpty);
          expect(find.byType(StatTile), findsNothing);
          expect(tester.widget<IconButton>(
            _refreshButton(l10n),
          ).onPressed, isNull);

          radio.incoming.add(_binaryStatus(radio));
          await tester.pumpAndSettle();
          expect(find.byType(StatTile), findsNWidgets(type == advTypeRoom ? 14 : 15));
          expect(_values(tester), _expected(l10n, room: type == advTypeRoom));
          expect(radio.outcomes, [true]);
          expect(radio.batterySources, ['status_binary']);
          final battery = find.byWidgetPredicate((w) =>
              w is StatTile && w.label == l10n.repeater_battery);
          final uptime = find.byWidgetPredicate((w) =>
              w is StatTile && w.label == l10n.repeater_uptime);
          expect(tester.getRect(battery).top, tester.getRect(uptime).top);
          expect(tester.getRect(battery).height, tester.getRect(uptime).height);
          expect(tester.getRect(battery).right, lessThan(tester.getRect(uptime).left));
          await tester.pump(const Duration(seconds: 2));
          expect(radio.writes, hasLength(1));
          expect(radio.outcomes, [true]);

          await tester.tap(_refreshButton(l10n));
          await tester.pump();
          expect(radio.writes, [
            <int>[cmdSendStatusReq, ...radio.target.publicKey],
            <int>[cmdSendStatusReq, ...radio.target.publicKey],
          ]);
          radio.incoming.add(_binaryStatus(radio));
          await tester.pumpAndSettle();
          expect(_values(tester), _expected(l10n, room: type == advTypeRoom));
          expect(radio.outcomes, [true, true]);
          expect(radio.preparations, 2);
        });
      });
    }

    testWidgets('U11b7 baseline: legacy JSON status retains its fields ($locale)', (tester) async {
      await _withStatus(tester, locale, advTypeRepeater, (radio, l10n) async {
        _textReply(radio, jsonEncode({
          'battery_mv': 4200, 'uptime_secs': 90061, 'queue_len': 3, 'errors': 2,
        }));
        _textReply(radio, jsonEncode({
          'noise_floor': -120, 'last_rssi': -81, 'last_snr': 7.25,
          'tx_air_secs': 61, 'rx_air_secs': 120,
        }));
        _textReply(radio, jsonEncode({
          'recv': 100, 'sent': 80, 'recv_errors': 4, 'flood_tx': 50,
          'direct_tx': 30, 'flood_rx': 60, 'direct_rx': 25,
          'dup_flood': 3, 'dup_direct': 2,
        }));
        await tester.pumpAndSettle();
        expect(_values(tester), {
          ..._expected(l10n, room: false),
          // Legacy JSON currently does not derive utilization from uptime.
          l10n.repeater_chanUtil: '—',
        });
        expect(radio.outcomes, [true]);
        expect(radio.batterySources, ['status_text']);
        await tester.pump(const Duration(seconds: 2));
        expect(radio.writes, hasLength(1));
        expect(radio.outcomes, [true]);
      });
    });

    testWidgets('U11b7 baseline: timeout waits for an explicit retry and disconnect disables refresh ($locale)', (tester) async {
      await _withStatus(tester, locale, advTypeRepeater, (radio, l10n) async {
        await tester.pump(const Duration(milliseconds: 1100));
        await tester.pumpAndSettle();
        expect(find.text(l10n.repeater_statusRequestTimeout), findsOneWidget);
        expect(radio.outcomes, [false]);
        await tester.pump(const Duration(seconds: 2));
        expect(radio.writes, hasLength(1));
        await tester.tap(find.widgetWithText(FilledButton, l10n.common_retry));
        await tester.pump();
        expect(radio.writes, hasLength(2));
        radio.incoming.add(_binaryStatus(radio));
        await tester.pumpAndSettle();
        expect(radio.outcomes, [false, true]);
        radio.connected = false;
        radio.notifyListeners();
        await tester.pumpAndSettle();
        final refresh = _refreshButton(l10n);
        expect(tester.widget<IconButton>(refresh).onPressed, isNull);
        expect(find.text(l10n.repeater_radioDisconnected), findsOneWidget);
        expect(radio.writes, hasLength(2));
      });
    });
  }
}
