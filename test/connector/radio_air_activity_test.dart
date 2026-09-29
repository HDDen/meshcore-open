import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';

// What the connector promises about the air activity the stats poll reports,
// pinned before the flag the air-activity dot reads moves from a two-second
// window to the poll window. A radio-stats frame whose airtime grew over the
// frame before it lights the activity, the stats reach the notifier the
// screens listen to, and a frame that does not parse changes nothing.

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
}
