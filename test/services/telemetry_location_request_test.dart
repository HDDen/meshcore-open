import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/path_selection.dart';
import 'package:meshcore_open/services/telemetry_location_request.dart';

final _key = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
const _gps = [6, 136, 0, 39, 16, 255, 177, 224, 0, 4, 210]; // 1, -2, 12.34m
const _path = PathSelection(pathBytes: [], hopCount: -1, useFlood: true);

// Service-only fixture; command locks/scopes are exercised separately through
// the real connector in telemetry_contact_send_baseline_test.dart.
class _Connector extends ChangeNotifier implements MeshCoreConnector {
  final frames = StreamController<Uint8List>.broadcast(sync: true);
  final writes = <Uint8List>[];
  final results = <bool>[];
  String node = 'synthetic-node-a';
  bool connected = true;
  int applied = 0;
  Completer<PathSelection>? prepareGate;
  Completer<void>? sendGate;
  VoidCallback? onWrite;
  Contact? target = Contact(
    publicKey: _key, name: 'Synthetic GPS contact', type: advTypeChat,
    pathLength: -1, path: Uint8List(0), lastSeen: DateTime.utc(2026),
  );

  @override
  bool get isConnected => connected;
  @override
  String get selfPublicKeyHex => node;
  @override
  Stream<Uint8List> get receivedFrames => frames.stream;
  @override
  Contact? getContactByPubKeyHex(String key) => target?.publicKeyHex == key ? target : null;
  @override
  Future<PathSelection> preparePathForContactSend(Contact contact) async =>
      prepareGate == null ? _path : await prepareGate!.future;
  @override
  Future<void> sendContactFrame(Contact contact, Uint8List frame, {
    required bool useFlood,
    bool Function()? canSend,
    VoidCallback? onSending,
  }) async {
    final gate = sendGate;
    if (gate != null) await gate.future;
    if (canSend?.call() == false) return;
    onSending?.call();
    writes.add(frame);
    onWrite?.call();
  }
  @override
  void recordRepeaterPathResult(Contact contact, PathSelection path, bool success, int? tripTimeMs) {
    results.add(success);
  }
  @override
  bool updateContactLocationFromTelemetry(String key, double latitude, double longitude, {
    required String expectedNodeKey,
  }) {
    if (expectedNodeKey != node || target?.publicKeyHex != key) return false;
    applied++;
    target = target!.copyWith(latitude: latitude, longitude: longitude);
    return true;
  }
  void emit(List<int> bytes) => frames.add(Uint8List.fromList(bytes));
  void connectionChanged() => notifyListeners();
  void sent(int tag, {int milliseconds = 5000}) {
    final bytes = ByteData(10)
      ..setUint8(0, respCodeSent)
      ..setUint32(2, tag, Endian.little)
      ..setUint32(6, milliseconds, Endian.little);
    frames.add(bytes.buffer.asUint8List());
  }
  void binary(int tag, [List<int> payload = _gps]) {
    final bytes = ByteData(6)
      ..setUint8(0, pushCodeBinaryResponse)
      ..setUint32(2, tag, Endian.little);
    emit([...bytes.buffer.asUint8List(), ...payload]);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Outcome {
  _Outcome(Future<TelemetryLocationResult> future) {
    unawaited(future.then<void>((value) {
      result = value;
    }));
  }
  TelemetryLocationResult? result;
}

// StreamSubscription.cancel may return the SDK's already-completed root-zone
// Future. A fake-clock pump alone cannot deliver that continuation. Give the
// real event loop one zero-delay turn, then flush the test zone again. This
// advances no request deadline and never uses pumpAndSettle on pending work.
Future<void> _pumpRequest(WidgetTester tester, [Duration? elapsed]) async {
  await tester.pump(elapsed);
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

Future<void> _withRequest(WidgetTester tester,
    Future<void> Function(_Connector, TelemetryLocationRequest) check) async {
  final c = _Connector();
  final request = TelemetryLocationRequest();
  try {
    await check(c, request);
  } finally {
    request.cancel();
    if (c.prepareGate != null && !c.prepareGate!.isCompleted) c.prepareGate!.complete(_path);
    if (c.sendGate != null && !c.sendGate!.isCompleted) c.sendGate!.complete();
    await _pumpRequest(tester);
    await c.frames.close();
    c.dispose();
    await _pumpRequest(tester);
  }
}

void main() {
  for (final phase in ['prepare', 'queue']) {
    testWidgets('ignores SENT and replies before actual send during $phase', (tester) async {
      await _withRequest(tester, (c, request) async {
        if (phase == 'prepare') c.prepareGate = Completer<PathSelection>();
        if (phase == 'queue') c.sendGate = Completer<void>();
        final outcome = _Outcome(request.run(c, c.target!));
        await _pumpRequest(tester);
        c.sent(111, milliseconds: 1);
        c.binary(111);
        c.emit([pushCodeTelemetryResponse, 0, ..._key.take(6), ..._gps]);
        await _pumpRequest(tester, const Duration(seconds: 20));
        expect(outcome.result, isNull);
        expect(c.writes, isEmpty);
        c.prepareGate?.complete(_path);
        c.sendGate?.complete();
        await _pumpRequest(tester);
        c.sent(222);
        c.sent(333); // Another command's SENT must not replace our tag.
        c.binary(222);
        await _pumpRequest(tester);
        expect(outcome.result, TelemetryLocationResult.located);
        expect(c.writes.single, buildSendTelemetryReq(_key));
        expect(c.target!.latitude, 1);
        expect(c.target!.longitude, -2);
        expect(c.applied, 1);
        expect(c.results, [true]);
      });
    });
    testWidgets('cancellation during $phase completes promptly and prevents a late send', (tester) async {
      await _withRequest(tester, (c, request) async {
        if (phase == 'prepare') c.prepareGate = Completer<PathSelection>();
        if (phase == 'queue') c.sendGate = Completer<void>();
        final outcome = _Outcome(request.run(c, c.target!));
        await _pumpRequest(tester);
        request.cancel();
        await _pumpRequest(tester);
        expect(outcome.result, TelemetryLocationResult.cancelled);
        c.prepareGate?.complete(_path);
        c.sendGate?.complete();
        await _pumpRequest(tester);
        expect(c.writes, isEmpty);
        expect(c.applied, 0);
        expect(c.results, isEmpty);
      });
    });
  }

  testWidgets('chat checks the reply prefix; sensor uses binary telemetry', (tester) async {
    await _withRequest(tester, (c, request) async {
      final outcome = _Outcome(request.run(c, c.target!));
      await _pumpRequest(tester);
      c.emit([pushCodeTelemetryResponse, 0, ...List<int>.filled(6, 99), ..._gps]);
      c.binary(123); // No matching SENT.
      await _pumpRequest(tester);
      expect(outcome.result, isNull);
      c.emit([pushCodeTelemetryResponse, 0, ..._key.take(6), ..._gps]);
      await _pumpRequest(tester);
      expect(outcome.result, TelemetryLocationResult.located);
    });
    await _withRequest(tester, (c, request) async {
      c.target = c.target!.copyWith(type: advTypeSensor);
      final outcome = _Outcome(request.run(c, c.target!));
      await _pumpRequest(tester);
      expect(c.writes.single, buildSendBinaryReq(_key, payload: buildTelemetryBinaryPayload()));
      c.sent(456);
      c.binary(456, [2, 103, 1, 28]); // Valid temperature, no GPS.
      await _pumpRequest(tester);
      expect(outcome.result, TelemetryLocationResult.noLocation);
      expect(c.applied, 0);
      expect(c.results, [true]);
    });
  });

  for (final action in ['node', 'disconnect', 'removed', 'cancel']) {
    testWidgets('$action invalidates a sent request and ignores late GPS', (tester) async {
      await _withRequest(tester, (c, request) async {
        final outcome = _Outcome(request.run(c, c.target!));
        await _pumpRequest(tester);
        if (action == 'node') c.node = 'synthetic-node-b';
        if (action == 'disconnect') c.connected = false;
        if (action == 'removed') c.target = null;
        if (action == 'cancel') request.cancel();
        c.connectionChanged();
        await _pumpRequest(tester);
        c.sent(1);
        c.binary(1);
        await _pumpRequest(tester);
        expect(outcome.result, TelemetryLocationResult.cancelled);
        expect(c.applied, 0);
        expect(c.results, isEmpty);
      });
    });
  }

  for (final error in ['timeout', 'ERR', 'malformed']) {
    testWidgets('$error cannot apply a location', (tester) async {
      await _withRequest(tester, (c, request) async {
        final outcome = _Outcome(request.run(c, c.target!));
        await _pumpRequest(tester);
        if (error == 'ERR') c.emit([respCodeErr, errCodeUnsupportedCmd]);
        if (error == 'malformed') c.emit([pushCodeBinaryResponse, 0, 1]);
        await _pumpRequest(tester, const Duration(seconds: 11));
        expect(outcome.result, TelemetryLocationResult.failed);
        expect(c.applied, 0);
        expect(c.results, [false]);
      });
    });
  }

  testWidgets('a synchronous reply during the writer is not lost', (tester) async {
    await _withRequest(tester, (c, request) async {
      c.onWrite = () {
        c.sent(77);
        c.binary(77);
      };
      final outcome = _Outcome(request.run(c, c.target!));
      await _pumpRequest(tester);
      expect(outcome.result, TelemetryLocationResult.located);
      expect(c.applied, 1);
    });
  });

  testWidgets('writer failure reports failure and cancels its fallback timer', (tester) async {
    await _withRequest(tester, (c, request) async {
      c.onWrite = () => throw StateError('synthetic writer failure');
      final outcome = _Outcome(request.run(c, c.target!));
      await _pumpRequest(tester);
      expect(outcome.result, TelemetryLocationResult.failed);
      expect(c.applied, 0);
      expect(c.results, [false]);
    });
  });
}
