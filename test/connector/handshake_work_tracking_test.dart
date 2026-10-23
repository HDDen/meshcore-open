import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('synthetic preferences without a directory');
  }
}

// Настоящие запросы/SELF_INFO dispatch/wait/retry и физический writer seam.
// Открытие транспорта, первый load БД и cold initial sync здесь не запускаются.
class _HandshakeConnector extends MeshCoreConnector {
  bool connected = true;
  final frames = <List<int>>[];
  final gates = <Completer<void>>[];
  Future<void> Function(int command)? beforeWrite;
  final key = Uint8List.fromList(List.generate(32, (i) => i + 1));

  _HandshakeConnector(MeshCoreTransportType transport) {
    setReconnectContextForTest(transport: transport, state: MeshCoreConnectionState.connected);
    setFrameWriterForTest((frame) {
      frames.add(List<int>.of(frame));
      return beforeWrite?.call(frame.first) ?? Future<void>.value();
    });
  }

  @override
  bool get isConnected => connected;

  List<int> get commands => frames.map((f) => f.first).toList();
  int count(int code) => commands.where((c) => c == code).length;

  Completer<void> holdFirstWrite() {
    final gate = Completer<void>();
    gates.add(gate);
    beforeWrite = (_) {
      beforeWrite = null;
      return gate.future;
    };
    return gate;
  }

  void selfInfo() {
    // Cached-path fixture: stores остаются без привязки к ноде.
    setCachedSelfInfoKeyForTest(key);
    final frame = Uint8List(68);
    frame[0] = respCodeSelfInfo;
    frame.setRange(4, 36, key);
    frame.setRange(58, 67, 'synthetic'.codeUnits);
    handleFrameForTest(frame);
  }

  void loseConnection() {
    connected = false;
    notifyListeners();
  }
}

class _Result<T> {
  _Result(Future<T> operation) {
    unawaited(operation.then<void>((result) {
      value = result;
      completed = true;
    }, onError: (Object failure, StackTrace stack) {
      error = failure;
      completed = true;
    }));
  }
  bool completed = false;
  T? value;
  Object? error;
}

Future<void> _withHandshake(WidgetTester tester,
    Future<void> Function(_HandshakeConnector c) check,
    {MeshCoreTransportType transport = MeshCoreTransportType.tcp}) async {
  final c = _HandshakeConnector(transport);
  try {
    await check(c);
  } finally {
    c.loseConnection();
    c.resetConnectionHandshakeForTest();
    for (final gate in c.gates) {
      if (!gate.isCompleted) gate.complete();
    }
    // Notify завершает локальные waiters; dispose не подменяет reset таймера.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 5));
    c.resetConnectionHandshakeForTest();
    if (!c.backgroundWorkSnapshot.isClosed) c.dispose();
    await tester.pump();
  }
}

void _expectWork(_HandshakeConnector c, int setup, {int writes = 0, int other = 0}) {
  final snapshot = c.backgroundWorkSnapshot;
  expect(snapshot.countFor(BackgroundWorkKind.transportSetup), setup);
  expect(snapshot.countFor(BackgroundWorkKind.transportWrite), writes);
  expect(snapshot.activeCount, setup + writes + other);
  expect(snapshot.isBusy, setup + writes + other > 0);
}

void main() {
  const timeout = Timeout(Duration(seconds: 30));
  late PathProviderPlatform savedPaths;
  setUpAll(() {
    savedPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferencesDirectory();
  });
  tearDownAll(() => PathProviderPlatform.instance = savedPaths);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  testWidgets('logical SELF_INFO wait survives the completed request and ends on reply', (tester) async {
    await _withHandshake(tester, (c) async {
      final request = _Result(c.requestDeviceInfoForTest());
      await tester.pump();
      expect(request.completed, isTrue);
      expect(request.error, isNull);
      _expectWork(c, 1);
      c.selfInfo();
      await tester.pump();
      _expectWork(c, 0);
      expect(c.awaitingSelfInfoForTest, isFalse);
      expect(c.hasCompletedSelfInfoHandshake, isTrue);
    });
  }, timeout: timeout);

  testWidgets('reset and loss release the logical wait but retain the actual request and writer', (tester) async {
    await _withHandshake(tester, (c) async {
      final gate = c.holdFirstWrite();
      final request = _Result(c.requestDeviceInfoForTest());
      await tester.pump();
      _expectWork(c, 2, writes: 1);
      c.resetConnectionHandshakeForTest();
      c.loseConnection();
      _expectWork(c, 1, writes: 1);
      expect(request.completed, isFalse);
      gate.complete();
      await tester.pump();
      expect(request.completed, isTrue);
      expect(request.error, isNotNull);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('duplicate query creates no additional persistent handshake wait', (tester) async {
    await _withHandshake(tester, (c) async {
      final gate = c.holdFirstWrite();
      final first = _Result(c.requestDeviceInfoForTest());
      await tester.pump();
      final duplicate = _Result(c.requestDeviceInfoForTest());
      await tester.pump();
      expect(duplicate.completed, isTrue);
      expect(first.completed, isFalse);
      _expectWork(c, 2, writes: 1);
      gate.complete();
      await tester.pump();
      _expectWork(c, 1);
      c.selfInfo();
      await tester.pump();
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('overlapping refresh shares the logical flag while requests remain independent', (tester) async {
    await _withHandshake(tester, (c) async {
      final gate = c.holdFirstWrite();
      final initial = _Result(c.requestDeviceInfoForTest());
      await tester.pump();
      final refresh = _Result(c.refreshDeviceInfo());
      await tester.pump();
      expect(refresh.completed, isTrue);
      expect(refresh.error, isNull);
      expect(initial.completed, isFalse);
      _expectWork(c, 2, writes: 1);
      gate.complete();
      await tester.pump();
      expect(initial.completed, isTrue);
      _expectWork(c, 1);
      c.selfInfo();
      await tester.pump();
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('a known key does not release the pending refresh flag', (tester) async {
    await _withHandshake(tester, (c) async {
      c.selfInfo();
      await c.refreshDeviceInfo();
      expect(await c.waitForSelfInfoForTest(const Duration(seconds: 3)), isTrue);
      _expectWork(c, 1);
      c.selfInfo();
      await tester.pump();
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('SELF_INFO listener timeout releases only its own wait', (tester) async {
    await _withHandshake(tester, (c) async {
      await c.requestDeviceInfoForTest();
      final wait = _Result(c.waitForSelfInfoForTest(const Duration(seconds: 3)));
      await tester.pump();
      _expectWork(c, 2);
      await tester.pump(const Duration(seconds: 3));
      expect(wait.completed, isTrue);
      expect(wait.value, isFalse);
      _expectWork(c, 1);
      c.resetConnectionHandshakeForTest();
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('independent SELF_INFO listeners release at their existing deadlines', (tester) async {
    await _withHandshake(tester, (c) async {
      final first = _Result(c.waitForSelfInfoForTest(const Duration(seconds: 1)));
      final second = _Result(c.waitForSelfInfoForTest(const Duration(seconds: 3)));
      await tester.pump();
      _expectWork(c, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(first.value, isFalse);
      expect(second.completed, isFalse);
      _expectWork(c, 1);
      c.selfInfo();
      await tester.pump(const Duration(milliseconds: 50));
      expect(second.value, isTrue);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('fast disconnected and known-key paths leave no persistent hold', (tester) async {
    await _withHandshake(tester, (c) async {
      c.connected = false;
      expect(await c.waitForSelfInfoForTest(const Duration(seconds: 3)), isFalse);
      await c.requestDeviceInfoForTest();
      await c.refreshDeviceInfo();
      expect(await c.refreshSelfLocation(), isNull);
      _expectWork(c, 0);
      c.connected = true;
      c.selfInfo();
      expect(await c.waitForSelfInfoForTest(const Duration(seconds: 3)), isTrue);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('early SELF_INFO releases only the flag while writes continue', (tester) async {
    await _withHandshake(tester, (c) async {
      final gate = c.holdFirstWrite();
      final request = _Result(c.requestDeviceInfoForTest());
      await tester.pump();
      _expectWork(c, 2, writes: 1);
      c.selfInfo();
      _expectWork(c, 1, writes: 1);
      gate.complete();
      await tester.pump();
      expect(request.completed, isTrue);
      _expectWork(c, 0);
      expect(c.selfInfoRetryActiveForTest, isTrue);
      await tester.pump(const Duration(milliseconds: 3500));
      expect(c.selfInfoRetryActiveForTest, isFalse);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('writer error releases actual work but keeps the original guard hold until reset', (tester) async {
    await _withHandshake(tester, (c) async {
      final error = StateError('synthetic handshake writer failure');
      c.beforeWrite = (_) async => throw error;
      final request = _Result(c.requestDeviceInfoForTest());
      await tester.pump();
      expect(request.error, same(error));
      expect(c.awaitingSelfInfoForTest, isTrue);
      _expectWork(c, 1);
      c.resetConnectionHandshakeForTest();
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('retry detects loss and releases its logical phase while the writer remains active', (tester) async {
    await _withHandshake(tester, (c) async {
      await c.requestDeviceInfoForTest();
      final gate = c.holdFirstWrite();
      await tester.pump(const Duration(milliseconds: 3500));
      _expectWork(c, 1, writes: 1);
      c.loseConnection();
      await tester.pump(const Duration(milliseconds: 3500));
      expect(c.selfInfoRetryActiveForTest, isFalse);
      _expectWork(c, 0, writes: 1);
      gate.complete();
      await tester.pump();
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('a reset replacement phase survives completion of the old actual request', (tester) async {
    await _withHandshake(tester, (c) async {
      final gate = c.holdFirstWrite();
      final old = _Result(c.requestDeviceInfoForTest());
      await tester.pump();
      c.resetConnectionHandshakeForTest();
      await c.requestDeviceInfoForTest();
      _expectWork(c, 2, writes: 1);
      gate.complete();
      await tester.pump();
      expect(old.completed, isTrue);
      expect(old.error, isNull);
      _expectWork(c, 1);
      c.selfInfo();
      await tester.pump();
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('location refreshes hold independent Futures without creating a logical handshake flag', (tester) async {
    await _withHandshake(tester, (c) async {
      final first = _Result(c.refreshSelfLocation());
      final second = _Result(c.refreshSelfLocation());
      await tester.pump();
      expect(c.awaitingSelfInfoForTest, isFalse);
      expect(c.selfLocationWaiterCountForTest, 2);
      _expectWork(c, 2);
      c.selfInfo();
      await tester.pump();
      expect(first.completed && second.completed, isTrue);
      expect(first.error, isNull);
      expect(second.error, isNull);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('an early location reply does not finish its held writer', (tester) async {
    await _withHandshake(tester, (c) async {
      final gate = c.holdFirstWrite();
      final location = _Result(c.refreshSelfLocation());
      await tester.pump();
      _expectWork(c, 1, writes: 1);
      c.selfInfo();
      await tester.pump();
      expect(c.selfLocationWaiterCountForTest, 0);
      expect(location.completed, isFalse);
      _expectWork(c, 1, writes: 1);
      gate.complete();
      await tester.pump();
      expect(location.completed, isTrue);
      expect(location.error, isNull);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('location timeout releases its actual wait without changing the result', (tester) async {
    await _withHandshake(tester, (c) async {
      final location = _Result(c.refreshSelfLocation());
      await tester.pump();
      _expectWork(c, 1);
      await tester.pump(const Duration(seconds: 3));
      expect(location.completed, isTrue);
      expect(location.error, isNull);
      expect(location.value, isNull);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  for (final mode in ['malformed', 'writer error']) {
    testWidgets('location $mode retains the original caught result and releases actual work', (tester) async {
      await _withHandshake(tester, (c) async {
        if (mode == 'writer error') {
          c.beforeWrite = (_) async => throw StateError('synthetic location writer failure');
        }
        final location = _Result(c.refreshSelfLocation());
        await tester.pump();
        if (mode == 'malformed') {
          _expectWork(c, 1);
          c.handleFrameForTest([respCodeSelfInfo]);
          await tester.pump();
        }
        expect(location.completed, isTrue);
        expect(location.error, isNull);
        expect(location.value, isNull);
        _expectWork(c, 0);
      });
    }, timeout: timeout);
  }

  testWidgets('caller timeout does not release the underlying location refresh', (tester) async {
    await _withHandshake(tester, (c) async {
      final caller = _Result(c.refreshSelfLocation().timeout(const Duration(milliseconds: 1)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(caller.error, isA<TimeoutException>());
      _expectWork(c, 1);
      c.selfInfo();
      await tester.pump();
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('dispose releases the logical wait but retains actual request and writer', (tester) async {
    await _withHandshake(tester, (c) async {
      final gate = c.holdFirstWrite();
      final request = _Result(c.requestDeviceInfoForTest());
      await tester.pump();
      c.loseConnection();
      c.dispose();
      expect(c.backgroundWorkSnapshot.isClosed, isTrue);
      _expectWork(c, 1, writes: 1);
      gate.complete();
      await tester.pump();
      expect(request.completed, isTrue);
      expect(request.error, isNotNull);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('dispose preserves existing local waiter deadlines and their leases', (tester) async {
    await _withHandshake(tester, (c) async {
      await c.requestDeviceInfoForTest();
      final wait = _Result(c.waitForSelfInfoForTest(const Duration(seconds: 3)));
      final location = _Result(c.refreshSelfLocation());
      await tester.pump();
      _expectWork(c, 3);
      c.loseConnection();
      c.dispose();
      _expectWork(c, 2);
      await tester.pump(const Duration(seconds: 3));
      expect(wait.value, isFalse);
      expect(location.completed, isTrue);
      expect(location.error, isNull);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('late closed calls add no setup lease or revision', (tester) async {
    await _withHandshake(tester, (c) async {
      c.loseConnection();
      c.dispose();
      final revision = c.backgroundWorkSnapshot.revision;
      await c.requestDeviceInfoForTest();
      await c.refreshDeviceInfo();
      expect(await c.waitForSelfInfoForTest(const Duration(seconds: 3)), isFalse);
      expect(await c.refreshSelfLocation(), isNull);
      expect(c.backgroundWorkSnapshot.revision, revision);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('deferred APP_START leaves one handshake hold beside the contact sync', (tester) async {
    await _withHandshake(tester, (c) async {
      await c.getContacts();
      await c.requestDeviceInfoForTest();
      expect(c.count(cmdAppStart), 0);
      _expectWork(c, 1, other: 1);
      c.handleFrameForTest([respCodeEndOfContacts]);
      await tester.pump();
      expect(c.count(cmdAppStart), 1);
      _expectWork(c, 1);
      c.selfInfo();
      await tester.pump();
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('SELF_INFO ends the logical wait without releasing an active retry writer', (tester) async {
    await _withHandshake(tester, (c) async {
      await c.requestDeviceInfoForTest();
      final gate = c.holdFirstWrite();
      await tester.pump(const Duration(milliseconds: 3500));
      _expectWork(c, 1, writes: 1);
      c.selfInfo();
      _expectWork(c, 0, writes: 1);
      gate.complete();
      await tester.pump();
      _expectWork(c, 0);
    });
  }, timeout: timeout);
}

