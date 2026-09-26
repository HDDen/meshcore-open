import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/remote_node_stats.dart';

Uint8List _frame(int statsSize, void Function(ByteData stats) fill) {
  final frame = Uint8List(RemoteNodeStats.payloadOffset + statsSize);
  fill(ByteData.sublistView(frame, RemoteNodeStats.payloadOffset));
  return frame;
}

void _fillCommon(ByteData d) {
  d.setUint16(0, 4100, Endian.little);
  d.setInt16(4, -110, Endian.little);
  d.setUint32(16, 300, Endian.little);
  d.setUint32(20, 3600, Endian.little);
  d.setInt16(42, -22, Endian.little);
  d.setUint16(46, 9, Endian.little);
}

void main() {
  test('decodes repeater stats with rx airtime and recv errors', () {
    final frame = _frame(56, (d) {
      _fillCommon(d);
      d.setUint32(48, 120, Endian.little);
      d.setUint32(52, 7, Endian.little);
    });
    final stats = RemoteNodeStats.tryParse(frame, isRoom: false)!;
    expect(stats.batteryMv, 4100);
    expect(stats.noiseFloor, -110);
    expect(stats.txAirSecs, 300);
    expect(stats.uptimeSecs, 3600);
    expect(stats.lastSnr, -5.5);
    expect(stats.floodDups, 9);
    expect(stats.rxAirSecs, 120);
    expect(stats.recvErrors, 7);
    expect(stats.posted, isNull);
  });

  test('older repeater frame without recv errors', () {
    final frame = _frame(52, (d) {
      _fillCommon(d);
      d.setUint32(48, 120, Endian.little);
    });
    final stats = RemoteNodeStats.tryParse(frame, isRoom: false)!;
    expect(stats.rxAirSecs, 120);
    expect(stats.recvErrors, isNull);
  });

  test('decodes room server posted / pushed counters', () {
    final frame = _frame(52, (d) {
      _fillCommon(d);
      d.setUint16(48, 42, Endian.little);
      d.setUint16(50, 17, Endian.little);
    });
    final stats = RemoteNodeStats.tryParse(frame, isRoom: true)!;
    expect(stats.posted, 42);
    expect(stats.postPushes, 17);
    expect(stats.rxAirSecs, isNull);
    expect(stats.recvErrors, isNull);
  });

  test('rejects frames shorter than the common layout', () {
    expect(RemoteNodeStats.tryParse(Uint8List(50), isRoom: false), isNull);
  });
}
