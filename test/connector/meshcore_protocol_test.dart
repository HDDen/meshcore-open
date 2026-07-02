import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';

void main() {
  test('device query advertises companion protocol v14', () {
    expect(buildDeviceQueryFrame(), orderedEquals(<int>[cmdDeviceQuery, 0x0E]));
  });

  test('sync next message frame uses old format without fragment ACK', () {
    expect(buildSyncNextMessageFrame(), orderedEquals(<int>[cmdSyncNextMessage]));
  });

  test('sync next message frame can include queued fragment ACK', () {
    expect(
      buildSyncNextMessageFrame(ackFragmentId: 0x1234, ackFragmentIndex: 1),
      orderedEquals(<int>[cmdSyncNextMessage, 0x01, 0x34, 0x12, 0x01]),
    );
  });
}
