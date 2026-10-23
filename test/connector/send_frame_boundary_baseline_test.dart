import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mco_service/mco_service.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';

// Fake не вызывает конструктор службы и не включает коммерческие функции.
// Проверяется только публичный контракт mcoX1 -> sendDirect; writer синтетический.
class _Interceptor extends Fake implements SettingsSectionsService {
  Future<void> Function(Uint8List, Future<void> Function())? route;

  @override
  bool get southFrameFragmentsEnabled => false;

  @override
  void mcoX2(Uint8List frame) {}

  @override
  Future<void> mcoX1(Uint8List frame, Future<void> Function() direct) =>
      route?.call(frame, direct) ?? direct();
}

class _Connector extends MeshCoreConnector {
  bool connected = true;
  final frames = <List<int>>[];

  _Connector() {
    setFrameWriterForTest((frame) async {
      frames.add(List<int>.of(frame));
    });
  }

  @override
  bool get isConnected => connected;
}

class _Result {
  _Result(Future<void> operation) {
    unawaited(operation.then<void>((_) {
      completed = true;
    }, onError: (Object value, StackTrace stack) {
      error = value;
      completed = true;
    }));
  }

  bool completed = false;
  Object? error;
}

Future<void> _withBoundary(
  WidgetTester tester,
  Future<void> Function(_Connector c, _Interceptor interceptor,
          Completer<void> gate)
      check,
) async {
  final c = _Connector();
  final interceptor = _Interceptor();
  final gate = Completer<void>();
  c.setFrameInterceptorForTest(interceptor);
  try {
    await check(c, interceptor, gate);
  } finally {
    if (!gate.isCompleted) gate.complete();
    await tester.pump();
    c.setFrameInterceptorForTest(null);
    c.dispose();
    await tester.pump(const Duration(seconds: 5));
  }
}

void main() {
  testWidgets('baseline: interceptor delay precedes writer and keeps frame bytes',
      (tester) async {
    await _withBoundary(tester, (c, interceptor, gate) async {
      Uint8List? intercepted;
      interceptor.route = (frame, direct) async {
        intercepted = frame;
        await gate.future;
        await direct();
      };
      final frame = buildSyncNextMessageFrame();
      final result = _Result(c.sendFrame(frame));
      await tester.pump(const Duration(seconds: 6));
      expect(intercepted, same(frame));
      expect(c.frames, isEmpty);
      expect(result.completed, isFalse);
      gate.complete();
      await tester.pump();
      expect(c.frames, [frame.toList()]);
      expect(result.completed, isTrue);
      expect(result.error, isNull);
    });
  });

  testWidgets('baseline: handled frame awaits interceptor without physical write',
      (tester) async {
    await _withBoundary(tester, (c, interceptor, gate) async {
      interceptor.route = (_, _) => gate.future;
      final result = _Result(c.sendFrame(buildSyncNextMessageFrame()));
      await tester.pump();
      expect(result.completed, isFalse);
      expect(c.frames, isEmpty);
      gate.complete();
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(c.frames, isEmpty);
      expect(c.pendingCommandReplyCountForTest, 0);
    });
  });

  testWidgets('baseline: synchronous interceptor error escapes before writer',
      (tester) async {
    await _withBoundary(tester, (c, interceptor, gate) async {
      final failure = StateError('synthetic interceptor failure');
      interceptor.route = (_, _) => throw failure;
      expect(() => c.sendFrame(buildSyncNextMessageFrame()), throwsA(same(failure)));
      expect(c.frames, isEmpty);
      expect(c.pendingCommandReplyCountForTest, 0);
    });
  });

  testWidgets('baseline: asynchronous interceptor error preserves original error',
      (tester) async {
    await _withBoundary(tester, (c, interceptor, gate) async {
      interceptor.route = (_, _) => gate.future;
      final result = _Result(c.sendFrame(buildSyncNextMessageFrame()));
      final failure = StateError('synthetic async interceptor failure');
      gate.completeError(failure);
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, same(failure));
      expect(c.frames, isEmpty);
    });
  });

  testWidgets('baseline: delayed direct path preserves the awaited specific reply',
      (tester) async {
    await _withBoundary(tester, (c, interceptor, gate) async {
      interceptor.route = (_, direct) async {
        await gate.future;
        await direct();
      };
      final frame = buildGetDeviceTimeFrame();
      final result = _Result(c.sendFrame(frame, waitForGenericAck: true));
      expect(c.pendingCommandReplyCountForTest, 0);
      gate.complete();
      await tester.pump();
      expect(c.frames, [frame.toList()]);
      expect(c.pendingCommandReplyCountForTest, 1);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(result.completed, isFalse);
      c.handleFrameForTest([respCodeCurrTime, 1, 0, 0, 0]);
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
    });
  });

  testWidgets('baseline: connection is checked when delayed direct path starts',
      (tester) async {
    await _withBoundary(tester, (c, interceptor, gate) async {
      interceptor.route = (_, direct) async {
        await gate.future;
        await direct();
      };
      final result = _Result(c.sendFrame(buildSyncNextMessageFrame()));
      c.connected = false;
      gate.complete();
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isA<Exception>());
      expect(c.frames, isEmpty);
      expect(c.pendingCommandReplyCountForTest, 0);
    });
  });
}
