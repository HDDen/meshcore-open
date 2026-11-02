import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';

// Real parser, command builders and sendFrame; no platform transport or stores.
class _Connector extends MeshCoreConnector {
  bool connected = true;
  bool rejectRadio = false;
  final frames = <List<int>>[];

  _Connector() {
    setFrameWriterForTest((frame) async {
      frames.add(frame.toList());
      if (frame[0] == cmdSetRadioParams) {
        handleFrameForTest(rejectRadio ? [respCodeErr, 1] : [respCodeOk]);
      }
    });
  }

  @override
  bool get isConnected => connected;
}

Uint8List _deviceInfo({int version = 10, int? mode = 0}) {
  final frame = Uint8List(mode == null ? 80 : 82);
  frame[0] = respCodeDeviceInfo;
  frame[1] = version;
  // Zero capacities keep the existing limits and avoid history reloads.
  if (mode != null) {
    frame[81] = mode;
  }
  return frame;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Connector connector;
  setUp(() => connector = _Connector());
  tearDown(() {
    if (!connector.backgroundWorkSnapshot.isClosed) {
      connector.dispose();
    }
  });

  for (final mode in [0, 1, 2]) {
    test('baseline: DEVICE_INFO mode $mode means ${mode + 1} bytes per hop', () {
      connector.handleFrameForTest(_deviceInfo(mode: mode));
      expect(connector.firmwareVerCode, 10);
      expect(connector.pathHashByteWidth, mode + 1);
    });
  }

  test('baseline: legacy DEVICE_INFO restores one byte and clamps invalid mode', () {
    connector.handleFrameForTest(_deviceInfo(mode: 2));
    connector.handleFrameForTest(_deviceInfo(version: 9, mode: null));
    expect(connector.pathHashByteWidth, 1);
    connector.handleFrameForTest(_deviceInfo(mode: 255));
    expect(connector.pathHashByteWidth, 3);
  });

  testWidgets('baseline: set mode is optimistic until refreshed DEVICE_INFO', (tester) async {
    try {
      for (final sample in [(input: -1, mode: 0), (input: 1, mode: 1), (input: 99, mode: 2)]) {
        await connector.setPathHashMode(sample.input);
        expect(connector.frames.last, [61, 0, sample.mode]);
        expect(connector.pathHashByteWidth, sample.mode + 1);
      }
      connector.handleFrameForTest(_deviceInfo(mode: 0));
      expect(connector.pathHashByteWidth, 1);
      connector.connected = false;
      final count = connector.frames.length;
      await connector.setPathHashMode(2);
      expect(connector.frames, hasLength(count));
      expect(connector.pathHashByteWidth, 1);
    } finally {
      // Cancel batched UI notifications before widget-test invariants.
      connector.dispose();
    }
  });

  testWidgets('baseline: radio command preserves optional repeat byte and ACK outcome', (tester) async {
    try {
      for (final repeat in <bool?>[null, false, true]) {
        expect(await connector.setRadioParams(869495, 250000, 11, 5, clientRepeat: repeat), isTrue);
        final frame = connector.frames.last;
        expect(frame.take(11), [11, 0x77, 0x44, 0x0d, 0, 0x90, 0xd0, 3, 0, 11, 5]);
        expect(frame.length, repeat == null ? 11 : 12);
        if (repeat != null) {
          expect(frame.last, repeat ? 1 : 0);
        }
      }
      connector.rejectRadio = true;
      expect(await connector.setRadioParams(869495, 250000, 11, 5), isFalse);
      connector.connected = false;
      final count = connector.frames.length;
      expect(await connector.setRadioParams(869495, 250000, 11, 5), isFalse);
      expect(connector.frames, hasLength(count));
    } finally {
      // Cancel batched UI notifications before widget-test invariants.
      connector.dispose();
    }
  });
}
