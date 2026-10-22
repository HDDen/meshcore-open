import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';

// Отдельные регрессии счётчиков; принятый queued processing baseline сохранён.
class _QueueConnector extends MeshCoreConnector {
  bool connected = true;
  bool disposed = false;
  final held = <Completer<void>>[];
  final frames = <List<int>>[];
  Future<void> Function()? write;

  _QueueConnector() {
    setFrameWriterForTest((frame) {
      frames.add(List<int>.of(frame));
      return write?.call() ?? Future<void>.value();
    });
  }

  @override
  bool get isConnected => connected;

  Completer<void> hold() {
    final completion = Completer<void>();
    held.add(completion);
    return completion;
  }

  void finishQueue() => handleFrameForTest([respCodeNoMoreMessages]);

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

void _expectWork(
  _QueueConnector c, {
  int processing = 0,
  int writes = 0,
  int requests = 0,
  bool closed = false,
}) => _expectSnapshot(
  c.backgroundWorkSnapshot,
  processing: processing,
  writes: writes,
  requests: requests,
  closed: closed,
);

void _expectSnapshot(
  BackgroundWorkSnapshot snapshot, {
  int processing = 0,
  int writes = 0,
  int requests = 0,
  bool closed = false,
}) {
  expect(snapshot.countFor(BackgroundWorkKind.messageSync), processing);
  expect(snapshot.countFor(BackgroundWorkKind.transportWrite), writes);
  expect(snapshot.countFor(BackgroundWorkKind.queuedMessageRequest), requests);
  expect(snapshot.activeCount, processing + writes + requests);
  expect(snapshot.isBusy, processing + writes + requests > 0);
  expect(snapshot.isClosed, closed);
}

Future<void> _withQueue(
  WidgetTester tester,
  Future<void> Function(_QueueConnector c) check,
) async {
  final c = _QueueConnector();
  try {
    await check(c);
  } finally {
    c.connected = false;
    for (final completion in c.held) {
      if (!completion.isCompleted) {
        completion.complete();
      }
    }
    await tester.pump();
    if (!c.disposed) {
      c.finishQueue();
      c.dispose();
    }
    await tester.pump(const Duration(seconds: 5));
  }
}

void main() {
  const timeout = Timeout(Duration(seconds: 30));

  testWidgets(
    'processing spans parsing and persistence and hands off to the next write',
    (tester) async {
      await _withQueue(tester, (c) async {
        await c.syncQueuedMessages();
        final parsed = c.hold();
        final saved = c.hold();
        final nextWrite = c.hold();
        var persistenceStarted = false;
        var persisted = false;
        bool? persistedAtWrite;
        BackgroundWorkSnapshot? workAtWrite;
        c.write = () {
          // Только наблюдения: callback может выполняться внутри tester.pump.
          persistedAtWrite = persisted;
          workAtWrite = c.backgroundWorkSnapshot;
          return nextWrite.future;
        };
        final result = _Result(c.processQueuedMessageForTest(process: () async {
          await parsed.future;
          persistenceStarted = true;
          await saved.future;
          persisted = true;
        }));
        _expectWork(c, processing: 1);
        final snapshot = c.backgroundWorkSnapshot;

        await tester.pump(const Duration(seconds: 6));
        expect(c.isSyncingQueuedMessages, isTrue);
        expect(persistenceStarted, isFalse);
        _expectWork(c, processing: 1);
        parsed.complete();
        await tester.pump();
        expect(persistenceStarted, isTrue);
        _expectWork(c, processing: 1);
        c.handleFrameForTest([pushCodeMsgWaiting]);
        await tester.pump();
        expect(c.frames, [[cmdSyncNextMessage]]);

        saved.complete();
        await tester.pump();
        expect(result.completed, isTrue);
        expect(result.error, isNull);
        expect(c.frames, [[cmdSyncNextMessage], [cmdSyncNextMessage]]);
        expect(persistedAtWrite, isTrue);
        expect(workAtWrite, isNotNull);
        // Снимок из callback доказывает перекрытие удержаний до handoff.
        // Прежние processing/write ожидания сохранены; добавлен новый wait kind.
        _expectSnapshot(workAtWrite!, processing: 1, writes: 1, requests: 1);
        _expectWork(c, writes: 1, requests: 1);
        expect(snapshot.countFor(BackgroundWorkKind.messageSync), 1);
        nextWrite.complete();
        await tester.pump();
        _expectWork(c, requests: 1);
        c.finishQueue();
        _expectWork(c);
      });
    },
    timeout: timeout,
  );

  for (final synchronous in [true, false]) {
    testWidgets(
      'queued error releases processing and stops sync, synchronous=$synchronous',
      (tester) async {
        await _withQueue(tester, (c) async {
          await c.syncQueuedMessages();
          final completion = c.hold();
          final failure = StateError('synthetic persistence failure');
          BackgroundWorkSnapshot? duringProcessing;
          final result = _Result(c.processQueuedMessageForTest(process: () {
            duringProcessing = c.backgroundWorkSnapshot;
            if (synchronous) {
              throw failure;
            }
            return completion.future;
          }));
          if (!synchronous) {
            _expectWork(c, processing: 1);
            completion.completeError(failure);
          }
          await tester.pump();
          expect(duringProcessing?.countFor(BackgroundWorkKind.messageSync), 1);
          expect(result.completed, isTrue);
          expect(result.error, isNull);
          expect(c.isSyncingQueuedMessages, isFalse);
          expect(c.frames, [[cmdSyncNextMessage]]);
          _expectWork(c);
        });
      },
      timeout: timeout,
    );

    testWidgets(
      'outside a queue the original error survives, synchronous=$synchronous',
      (tester) async {
        await _withQueue(tester, (c) async {
          final failure = StateError('synthetic receive failure');
          BackgroundWorkSnapshot? duringProcessing;
          final result = _Result(c.processQueuedMessageForTest(process: () {
            duringProcessing = c.backgroundWorkSnapshot;
            if (synchronous) {
              throw failure;
            }
            return Future<void>.error(failure);
          }));
          await tester.pump();
          expect(duringProcessing, isNotNull);
          _expectSnapshot(duringProcessing!, processing: 1);
          expect(result.completed, isTrue);
          expect(result.error, same(failure));
          expect(c.frames, isEmpty);
          _expectWork(c);
        });
      },
      timeout: timeout,
    );
  }

  testWidgets(
    'local processing remains held when the unrelated queue request times out',
    (tester) async {
      await _withQueue(tester, (c) async {
        await c.syncQueuedMessages();
        final completion = c.hold();
        final result = _Result(c.processQueuedMessageForTest(
          localSourceLabel: 'synthetic local source',
          process: () => completion.future,
        ));
        await tester.pump(const Duration(seconds: 5));
        expect(c.isSyncingQueuedMessages, isFalse);
        expect(result.completed, isFalse);
        _expectWork(c, processing: 1);
        completion.complete();
        await tester.pump();
        expect(result.completed, isTrue);
        expect(result.error, isNull);
        expect(c.frames, [[cmdSyncNextMessage]]);
        _expectWork(c);
      });
    },
    timeout: timeout,
  );

  testWidgets(
    'caller timeout and another completion cannot release pending processing',
    (tester) async {
      await _withQueue(tester, (c) async {
        final first = c.hold();
        final second = c.hold();
        final firstResult = _Result(c.processQueuedMessageForTest(
          process: () => first.future,
        ).timeout(const Duration(seconds: 1)));
        final secondResult = _Result(c.processQueuedMessageForTest(
          process: () => second.future,
        ));
        _expectWork(c, processing: 2);
        await tester.pump(const Duration(seconds: 1));
        expect(firstResult.error, isA<TimeoutException>());
        _expectWork(c, processing: 2);
        second.complete();
        await tester.pump();
        expect(secondResult.completed, isTrue);
        expect(secondResult.error, isNull);
        _expectWork(c, processing: 1);
        first.complete();
        await tester.pump();
        _expectWork(c);
        expect(c.frames, isEmpty);
      });
    },
    timeout: timeout,
  );

  testWidgets('connection loss does not release unfinished processing', (tester) async {
    await _withQueue(tester, (c) async {
      await c.syncQueuedMessages();
      final completion = c.hold();
      final result = _Result(c.processQueuedMessageForTest(
        process: () => completion.future,
      ));
      c.connected = false;
      await tester.pump(const Duration(seconds: 6));
      _expectWork(c, processing: 1);
      completion.complete();
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(c.frames, [[cmdSyncNextMessage]]);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('dispose closes tracking but preserves the pending operation', (tester) async {
    await _withQueue(tester, (c) async {
      final completion = c.hold();
      final result = _Result(c.processQueuedMessageForTest(
        process: () => completion.future,
      ));
      c.dispose();
      _expectWork(c, processing: 1, closed: true);
      completion.complete();
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      _expectWork(c, closed: true);
    });
  }, timeout: timeout);

  testWidgets('late processing after close runs with its original error', (tester) async {
    await _withQueue(tester, (c) async {
      c.dispose();
      final revision = c.backgroundWorkSnapshot.revision;
      final failure = StateError('synthetic late callback');
      var called = false;
      final result = _Result(c.processQueuedMessageForTest(process: () async {
        called = true;
        throw failure;
      }));
      await tester.pump();
      expect(called, isTrue);
      expect(result.error, same(failure));
      expect(c.backgroundWorkSnapshot.revision, revision);
      _expectWork(c, closed: true);
    });
  }, timeout: timeout);

  testWidgets('node response wait is tracked separately from processing', (tester) async {
    await _withQueue(tester, (c) async {
      await c.syncQueuedMessages();
      expect(c.isSyncingQueuedMessages, isTrue);
      _expectWork(c, requests: 1);
      c.finishQueue();
      _expectWork(c);
    });
  }, timeout: timeout);
}
