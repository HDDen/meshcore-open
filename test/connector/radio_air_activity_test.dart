import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/theme/mesh_theme.dart';
import 'package:meshcore_open/widgets/mesh_ui.dart';
import 'package:meshcore_open/widgets/radio_stats_entry.dart';
import 'package:provider/provider.dart';

// What the connector promises about the air activity the stats poll reports,
// pinned before the flag the air-activity dot reads moves from a two-second
// window to the poll window. A radio-stats frame whose airtime grew over the
// frame before it lights the activity, the stats reach the notifier the
// screens listen to, and a frame that does not parse changes nothing. The
// last two groups are the change: the activity holds for the poll window,
// the first frame of a polling run lights nothing, and a dot built on a
// screen opened after the frame blinks as the one that saw it did.

/// RESP_CODE_STATS with STATS_TYPE_RADIO: the noise floor, the last RSSI,
/// the last SNR in quarters of a dB, then the TX and RX airtime in seconds.
Uint8List _statsFrame({required int txAirSecs, required int rxAirSecs}) {
  final data = ByteData(14);
  data.setUint8(0, respCodeStats);
  data.setUint8(1, statsTypeRadio);
  data.setInt16(2, -110, Endian.little);
  data.setInt8(4, -80);
  data.setInt8(5, 30); // 7.5 dB
  data.setUint32(6, txAirSecs, Endian.little);
  data.setUint32(10, rxAirSecs, Endian.little);
  return data.buffer.asUint8List();
}

void main() {
  test('a stats frame whose airtime grew over the one before lights the air '
      'activity', () {
    final connector = MeshCoreConnector();

    connector.handleFrameForTest(_statsFrame(txAirSecs: 10, rxAirSecs: 20));
    connector.handleFrameForTest(_statsFrame(txAirSecs: 12, rxAirSecs: 20));

    expect(connector.radioStatsAirActivityPulse, isTrue);
  });

  test('the stats reach the notifier the screens listen to', () {
    final connector = MeshCoreConnector();
    final seen = <int>[];
    connector.radioStatsNotifier.addListener(() {
      final stats = connector.radioStatsNotifier.value;
      if (stats != null) seen.add(stats.txAirSecs);
    });

    connector.handleFrameForTest(_statsFrame(txAirSecs: 10, rxAirSecs: 20));
    connector.handleFrameForTest(_statsFrame(txAirSecs: 12, rxAirSecs: 20));

    expect(seen, [10, 12]);
    final stats = connector.latestRadioStats!;
    expect(stats.rxAirSecs, 20);
    expect(stats.lastSnrDb, 7.5);
    expect(stats.noiseFloorDbm, -110);
  });

  test('a frame that does not parse changes nothing', () {
    final connector = MeshCoreConnector();
    connector.handleFrameForTest(_statsFrame(txAirSecs: 10, rxAirSecs: 20));
    connector.handleFrameForTest(_statsFrame(txAirSecs: 12, rxAirSecs: 20));
    final before = connector.latestRadioStats;

    connector.handleFrameForTest(
      Uint8List.fromList([respCodeStats, statsTypeRadio, 0, 0]),
    );

    expect(connector.latestRadioStats, same(before));
    expect(connector.radioStatsAirActivityPulse, isTrue);
  });

  group('the poll window', () {
    test('the activity holds until the next frame, however long that takes',
        () async {
      final connector = MeshCoreConnector();
      connector.handleFrameForTest(_statsFrame(txAirSecs: 10, rxAirSecs: 20));
      connector.handleFrameForTest(_statsFrame(txAirSecs: 12, rxAirSecs: 20));

      await Future<void>.delayed(const Duration(milliseconds: 2200));

      expect(connector.radioStatsAirActivityPulse, isTrue);
    });

    test('a frame with no growth puts it out', () {
      final connector = MeshCoreConnector();
      connector.handleFrameForTest(_statsFrame(txAirSecs: 10, rxAirSecs: 20));
      connector.handleFrameForTest(_statsFrame(txAirSecs: 12, rxAirSecs: 20));
      expect(connector.radioStatsAirActivityPulse, isTrue);

      connector.handleFrameForTest(_statsFrame(txAirSecs: 12, rxAirSecs: 20));

      expect(connector.radioStatsAirActivityPulse, isFalse);
    });

    test('the first frame of a polling run lights nothing', () {
      final connector = MeshCoreConnector();

      connector.handleFrameForTest(
        _statsFrame(txAirSecs: 5000, rxAirSecs: 9000),
      );

      expect(connector.radioStatsAirActivityPulse, isFalse);
    });

    test('stopping the poll puts it out and starts the next run afresh', () {
      final connector = MeshCoreConnector();
      connector.handleFrameForTest(_statsFrame(txAirSecs: 10, rxAirSecs: 20));
      connector.handleFrameForTest(_statsFrame(txAirSecs: 12, rxAirSecs: 20));
      expect(connector.radioStatsAirActivityPulse, isTrue);

      // The last screen with a dot goes: the poll stops.
      connector.acquireRadioStatsPolling();
      connector.releaseRadioStatsPolling();
      expect(connector.radioStatsAirActivityPulse, isFalse);

      connector.handleFrameForTest(_statsFrame(txAirSecs: 40, rxAirSecs: 60));
      expect(
        connector.radioStatsAirActivityPulse,
        isFalse,
        reason: 'the growth since the last run is not this window\'s',
      );
      connector.handleFrameForTest(_statsFrame(txAirSecs: 41, rxAirSecs: 60));
      expect(connector.radioStatsAirActivityPulse, isTrue);
    });
  });

  group('a new screen', () {
    testWidgets('a dot built after the frame, on a screen opened later, '
        'blinks as the one that saw it did', (tester) async {
      final connector = _ConnectedConnector();
      final settings = AppSettingsService();
      addTearDown(settings.dispose);
      connector.handleFrameForTest(_statsFrame(txAirSecs: 10, rxAirSecs: 20));
      connector.handleFrameForTest(_statsFrame(txAirSecs: 12, rxAirSecs: 20));
      // Past the two seconds the flag used to last: the screen switch comes
      // well after the frame.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2200)),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MeshCoreConnector>.value(value: connector),
            ChangeNotifierProvider<AppSettingsService>.value(value: settings),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              appBar: AppBar(actions: const [RadioStatsIconButton()]),
            ),
          ),
        ),
      );

      final colours = <Color>{};
      for (var i = 0; i < 4; i++) {
        colours.add(tester.widget<PulseDot>(find.byType(PulseDot)).color);
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(colours, contains(MeshPalette.blue));
      expect(colours, hasLength(2), reason: 'blue and out, a blink');

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

/// A connector on a node that reports radio stats.
class _ConnectedConnector extends MeshCoreConnector {
  @override
  bool get isConnected => true;

  @override
  bool get supportsCompanionRadioStats => true;

  @override
  Future<void> sendFrame(
    Uint8List frame, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {}
}
