import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mco_service/mco_service.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';

// Отдельные регрессии: принятый baseline остаётся без изменений.
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
  bool disposed = false;
  final frames = <List<int>>[];
  final held = <Completer<void>>[];
  Future<void> Function()? write;

  _Connector() {
    setFrameWriterForTest((frame) {
      frames.add(List<int>.of(frame));
      return write?.call() ?? Future<void>.value();
    });
  }

  @override
  bool get isConnected => connected;

  Completer<void> hold() {
    final gate = Completer<void>();
    held.add(gate);
    return gate;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
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

void _expectWork(_Connector c, {
  int dispatch = 0, int writes = 0, int replies = 0, bool closed = false,
}) {
  final snapshot = c.backgroundWorkSnapshot;
  expect(snapshot.countFor(BackgroundWorkKind.frameDispatch), dispatch);
  expect(snapshot.countFor(BackgroundWorkKind.transportWrite), writes);
  expect(snapshot.countFor(BackgroundWorkKind.commandReply), replies);
  expect(snapshot.activeCount, dispatch + writes + replies);
  expect(snapshot.isClosed, closed);
}

Future<void> _withBoundary(WidgetTester tester,
    Future<void> Function(_Connector, _Interceptor) check) async {
  final c = _Connector();
  final interceptor = _Interceptor();
  c.setFrameInterceptorForTest(interceptor);
  try {
    await check(c, interceptor);
  } finally {
    for (final gate in c.held) {
      if (!gate.isCompleted) gate.complete();
    }
    await tester.pump();
    c.setFrameInterceptorForTest(null);
    if (!c.disposed) c.dispose();
    await tester.pump(const Duration(seconds: 5));
  }
}

void main() {
  testWidgets('dispatch begins before interceptor and stays held before writer', (tester) async {
    await _withBoundary(tester, (c, interceptor) async {
      final gate = c.hold();
      BackgroundWorkSnapshot? atEntry;
      interceptor.route = (_, direct) async {
        atEntry = c.backgroundWorkSnapshot;
        await gate.future;
        await direct();
      };
      final result = _Result(c.sendFrame(buildSyncNextMessageFrame()));
      _expectWork(c, dispatch: 1);
      expect(atEntry!.countFor(BackgroundWorkKind.frameDispatch), 1);
      await tester.pump(const Duration(seconds: 6));
      expect(c.frames, isEmpty);
      _expectWork(c, dispatch: 1);
      gate.complete();
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      _expectWork(c);
      expect(atEntry!.activeCount, 1);
    });
  });

  testWidgets('handled dispatch survives caller timeout and needs no physical writer', (tester) async {
    await _withBoundary(tester, (c, interceptor) async {
      final gate = c.hold();
      interceptor.route = (_, _) => gate.future;
      final original = c.sendFrame(buildSyncNextMessageFrame());
      final result = _Result(original);
      final timed = _Result(original.timeout(const Duration(seconds: 1)));
      await tester.pump(const Duration(seconds: 1));
      expect(timed.error, isA<TimeoutException>());
      expect(result.completed, isFalse);
      _expectWork(c, dispatch: 1);
      gate.complete();
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(c.frames, isEmpty);
      _expectWork(c);
    });
  });

  for (final synchronous in [true, false]) {
    testWidgets('dispatch releases on original error, synchronous=$synchronous', (tester) async {
      await _withBoundary(tester, (c, interceptor) async {
        final failure = StateError('synthetic interceptor failure');
        if (synchronous) {
          interceptor.route = (_, _) => throw failure;
          expect(() => c.sendFrame(buildSyncNextMessageFrame()), throwsA(same(failure)));
        } else {
          final gate = c.hold();
          interceptor.route = (_, _) => gate.future;
          final result = _Result(c.sendFrame(buildSyncNextMessageFrame()));
          gate.completeError(failure);
          await tester.pump();
          expect(result.error, same(failure));
        }
        _expectWork(c);
        expect(c.frames, isEmpty);
      });
    });
  }

  testWidgets('dispatch, physical writer and awaited reply have independent lifetimes', (tester) async {
    await _withBoundary(tester, (c, interceptor) async {
      final gate = c.hold();
      c.write = () => gate.future;
      final result = _Result(c.sendFrame(buildGetDeviceTimeFrame(), waitForGenericAck: true));
      _expectWork(c, dispatch: 1, writes: 1, replies: 1);
      c.handleFrameForTest([respCodeCurrTime, 1, 0, 0, 0]);
      await tester.pump();
      expect(result.completed, isFalse);
      _expectWork(c, dispatch: 1, writes: 1, replies: 1);
      gate.complete();
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      _expectWork(c);
    });
  });

  testWidgets('write timeout ends dispatch while underlying writer remains held', (tester) async {
    await _withBoundary(tester, (c, interceptor) async {
      final gate = c.hold();
      c.write = () => gate.future;
      final result = _Result(c.sendFrame(buildSetAdvertNameFrame('synthetic'), waitForGenericAck: true));
      _expectWork(c, dispatch: 1, writes: 1, replies: 1);
      await tester.pump(const Duration(seconds: 5));
      expect(result.error, isA<TimeoutException>());
      _expectWork(c, writes: 1);
      gate.completeError(StateError('synthetic late writer failure'));
      await tester.pump();
      expect(result.error, isA<TimeoutException>());
      _expectWork(c);
    });
  });

  testWidgets('dispose retains concurrent dispatch and late callback creates no lease', (tester) async {
    await _withBoundary(tester, (c, interceptor) async {
      final first = c.hold();
      final second = c.hold();
      var calls = 0;
      interceptor.route = (_, _) => calls++ == 0 ? first.future : second.future;
      final a = _Result(c.sendFrame(buildSyncNextMessageFrame()));
      final b = _Result(c.sendFrame(buildSyncNextMessageFrame()));
      _expectWork(c, dispatch: 2);
      c.dispose();
      _expectWork(c, dispatch: 2, closed: true);
      final revision = c.backgroundWorkSnapshot.revision;
      // Перехватчик обрабатывает кадр сам, не обращаясь к закрытому транспорту.
      interceptor.route = (_, _) async {};
      await c.sendFrame(buildSyncNextMessageFrame());
      expect(c.backgroundWorkSnapshot.revision, revision);
      first.complete();
      await tester.pump();
      expect(a.completed, isTrue);
      expect(b.completed, isFalse);
      _expectWork(c, dispatch: 1, closed: true);
      second.complete();
      await tester.pump();
      _expectWork(c, closed: true);
    });
  });

  testWidgets('without interceptor the existing writer accounting is sufficient', (tester) async {
    await _withBoundary(tester, (c, interceptor) async {
      c.setFrameInterceptorForTest(null);
      final gate = c.hold();
      c.write = () => gate.future;
      final result = _Result(c.sendFrame(buildSyncNextMessageFrame()));
      _expectWork(c, writes: 1);
      gate.complete();
      await tester.pump();
      expect(result.completed, isTrue);
      _expectWork(c);
    });
  });
}
