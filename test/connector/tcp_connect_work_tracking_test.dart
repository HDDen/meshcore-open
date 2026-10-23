import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_connector_tcp.dart';
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

class _Subscription extends Fake implements StreamSubscription<Uint8List> {
  @override
  Future<void> cancel() async {}
}

// Только граница transport manager. Ни Socket.connect, ни настоящий stream
// не создаются; frame callbacks передаются обычному dispatch коннектора.
class _Tcp extends MeshCoreTcpConnector {
  bool connected = false;
  bool connectedAfterOpen = true;
  int opens = 0;
  int closes = 0;
  int listens = 0;
  final events = <String>[];
  Future<void>? opening;
  Future<void>? cancelling;
  Future<void>? closing;
  void Function(Uint8List)? onFrame;
  void Function(Object, StackTrace?)? onError;
  void Function()? onDone;

  @override
  bool get isConnected => connected;

  @override
  Future<void> cancelFrameSubscription() async {
    events.add('cancel');
    await cancelling;
  }

  @override
  Future<void> connect({required String host, required int port}) async {
    opens++;
    events.add('open');
    await opening;
    connected = connectedAfterOpen;
    events.add('opened');
  }

  @override
  StreamSubscription<Uint8List> listenFrames({
    required void Function(Uint8List) onFrame,
    required void Function(Object, StackTrace?) onError,
    required void Function() onDone,
  }) {
    listens++;
    events.add('listen');
    this.onFrame = onFrame;
    this.onError = onError;
    this.onDone = onDone;
    return _Subscription();
  }

  @override
  Future<void> disconnect() async {
    closes++;
    events.add('close');
    connected = false;
    onFrame = null;
    onError = null;
    onDone = null;
    await closing;
  }

  @override
  void dispose() {
    connected = false;
    super.dispose();
  }
}

// Настоящий connectTcp/disconnect/request/wait/таймеры. stopScan и запрос
// региона изолированы: их механизмы проверяются соседними пакетами отдельно.
class _Connector extends MeshCoreConnector {
  _Connector(_Tcp manager) : tcp = manager, super(tcpConnector: manager) {
    setFrameWriterForTest((frame) async {
      frames.add(List<int>.of(frame));
      await beforeWrite?.call(frame.first);
      if (frame.first == cmdAppStart) {
        appStarts++;
        if (replyAtAppStart == appStarts && tcp.onFrame != null) selfInfo();
      }
    });
  }
  final _Tcp tcp;
  final frames = <List<int>>[];
  final gates = <Completer<void>>[];
  Future<void>? scanning;
  Future<void> Function(int command)? beforeWrite;
  int scansStopped = 0;
  int appStarts = 0;
  int? replyAtAppStart = 1;
  int regionQueries = 0;

  List<int> get commands => frames.map((f) => f.first).toList();
  int count(int code) => commands.where((c) => c == code).length;

  @override
  Future<void> stopScan() async {
    scansStopped++;
    await scanning;
  }

  @override
  Future<String?> getDefaultRegionScope() async {
    regionQueries++;
    return null;
  }

  Completer<void> gate() {
    final gate = Completer<void>();
    gates.add(gate);
    return gate;
  }

  void selfInfo() {
    final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
    setCachedSelfInfoKeyForTest(key);
    final frame = Uint8List(68);
    frame[0] = respCodeSelfInfo;
    frame.setRange(4, 36, key);
    frame.setRange(58, 67, 'synthetic'.codeUnits);
    tcp.onFrame!(frame);
  }

  Future<void> open({bool automatic = false}) => connectTcp(
    host: 'synthetic.invalid', port: 5000, automaticReconnect: automatic,
  );
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

Future<void> _withTcp(WidgetTester tester, Future<void> Function(_Connector c) check) async {
  final c = _Connector(_Tcp());
  try {
    await check(c);
  } finally {
    c.replyAtAppStart = null;
    for (final gate in c.gates) {
      if (!gate.isCompleted) gate.complete();
    }
    await tester.pump();
    // Завершить delayed connect до финального manual teardown и dispose.
    await tester.pump(const Duration(milliseconds: 200));
    if (c.isOfflineMode) {
      c.setReconnectContextForTest(transport: MeshCoreTransportType.tcp, state: c.state);
    }
    if (!c.backgroundWorkSnapshot.isClosed) await c.disconnect(manual: true);
    await tester.pump(const Duration(seconds: 7));
    c.resetConnectionHandshakeForTest();
    if (!c.backgroundWorkSnapshot.isClosed) c.dispose();
    await tester.pump();
  }
}

void _expectWork(_Connector c, int setup, {int writes = 0}) {
  final snapshot = c.backgroundWorkSnapshot;
  expect(snapshot.countFor(BackgroundWorkKind.transportSetup), setup);
  expect(snapshot.countFor(BackgroundWorkKind.transportWrite), writes);
  // Самостоятельный teardown теперь учитывается отдельно от подключения.
  final teardown = snapshot.countFor(BackgroundWorkKind.transportTeardown);
  expect(snapshot.activeCount, setup + writes + teardown);
  expect(snapshot.isBusy, setup + writes + teardown > 0);
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

  for (final boundary in ['scan', 'subscription', 'dial']) {
    testWidgets('$boundary wait holds the complete connect Future', (tester) async {
      await _withTcp(tester, (c) async {
        final gate = c.gate();
        if (boundary == 'scan') {
          c.scanning = gate.future;
        } else if (boundary == 'subscription') {
          c.tcp.cancelling = gate.future;
        } else {
          c.tcp.opening = gate.future;
        }
        final open = _Result(c.open());
        await tester.pump();
        expect(open.completed, isFalse);
        _expectWork(c, 1);
        gate.complete();
        await tester.pump();
        _expectWork(c, 1);
        await tester.pump(const Duration(milliseconds: 200));
        expect(open.completed, isTrue);
        expect(open.error, isNull);
        _expectWork(c, 0);
      });
    }, timeout: timeout);
  }

  testWidgets('the 200 ms pre-handshake delay remains active setup work', (tester) async {
    await _withTcp(tester, (c) async {
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 199));
      expect(c.commands, isEmpty);
      _expectWork(c, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('completed SELF_INFO does not release connect while time sync is writing', (tester) async {
    await _withTcp(tester, (c) async {
      final gate = c.gate();
      c.beforeWrite = (command) => command == cmdSetDeviceTime ? gate.future : Future<void>.value();
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.hasCompletedSelfInfoHandshake, isTrue);
      expect(open.completed, isFalse);
      _expectWork(c, 1, writes: 1);
      gate.complete();
      await tester.pump();
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('outer connect, logical SELF_INFO and local wait have independent leases', (tester) async {
    await _withTcp(tester, (c) async {
      c.replyAtAppStart = null;
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.state, MeshCoreConnectionState.connected);
      expect(open.completed, isFalse);
      _expectWork(c, 3);
      c.selfInfo();
      await tester.pump(const Duration(milliseconds: 50));
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('both missing SELF_INFO windows retain setup until the original failure teardown finishes', (tester) async {
    await _withTcp(tester, (c) async {
      c.replyAtAppStart = null;
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      _expectWork(c, 3);
      await tester.pump(const Duration(seconds: 3));
      expect(c.count(cmdDeviceQuery), 2);
      _expectWork(c, 3);
      await tester.pump(const Duration(seconds: 3));
      expect(open.completed, isTrue);
      expect(open.error, isA<StateError>());
      expect(c.state, MeshCoreConnectionState.disconnected);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('manual disconnect does not release outer connect or its held request writer', (tester) async {
    await _withTcp(tester, (c) async {
      final gate = c.gate();
      c.beforeWrite = (command) => command == cmdDeviceQuery ? gate.future : Future<void>.value();
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      _expectWork(c, 3, writes: 1);
      await c.disconnect(manual: true);
      expect(open.completed, isFalse);
      _expectWork(c, 2, writes: 1);
      gate.complete();
      await tester.pump();
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('ignored late dial error releases only when the original dial actually completes', (tester) async {
    await _withTcp(tester, (c) async {
      final gate = c.gate();
      c.tcp.opening = gate.future;
      final open = _Result(c.open());
      await tester.pump();
      await c.disconnect(manual: true);
      _expectWork(c, 1);
      gate.completeError(StateError('synthetic cancelled dial failure'));
      await tester.pump();
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('late dial success keeps setup held while the abandoned TCP transport closes', (tester) async {
    await _withTcp(tester, (c) async {
      final dial = c.gate();
      c.tcp.opening = dial.future;
      final open = _Result(c.open());
      await tester.pump();
      await c.disconnect(manual: true);
      final close = c.gate();
      c.tcp.closing = close.future;
      dial.complete();
      await tester.pump();
      expect(c.tcp.closes, 2);
      expect(open.completed, isFalse);
      _expectWork(c, 1);
      close.complete();
      await tester.pump();
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('dial failure retains outer setup while the error teardown is pending', (tester) async {
    await _withTcp(tester, (c) async {
      final dial = c.gate();
      final close = c.gate();
      c.tcp.opening = dial.future;
      c.tcp.closing = close.future;
      final error = StateError('synthetic dial failure');
      final open = _Result(c.open());
      await tester.pump();
      dial.completeError(error);
      await tester.pump();
      expect(c.state, MeshCoreConnectionState.disconnecting);
      expect(open.completed, isFalse);
      _expectWork(c, 1);
      close.complete();
      await tester.pump();
      expect(open.completed, isTrue);
      expect(open.error, same(error));
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('write timeout can finish connect while the actual writer remains separately held', (tester) async {
    await _withTcp(tester, (c) async {
      final gate = c.gate();
      c.beforeWrite = (command) => command == cmdDeviceQuery ? gate.future : Future<void>.value();
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      _expectWork(c, 3, writes: 1);
      await tester.pump(const Duration(seconds: 5));
      expect(open.completed, isTrue);
      expect(open.error, isA<TimeoutException>());
      _expectWork(c, 0, writes: 1);
      gate.complete();
      await tester.pump();
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('caller timeout does not release the actual connect Future', (tester) async {
    await _withTcp(tester, (c) async {
      final dial = c.gate();
      c.tcp.opening = dial.future;
      final caller = _Result(c.open().timeout(const Duration(milliseconds: 1)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(caller.error, isA<TimeoutException>());
      _expectWork(c, 1);
      dial.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.hasCompletedSelfInfoHandshake, isTrue);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  for (final guard in ['connecting', 'connected', 'offline']) {
    testWidgets('$guard guard leaves no persistent setup or dial', (tester) async {
      await _withTcp(tester, (c) async {
        c.setReconnectContextForTest(
          transport: MeshCoreTransportType.tcp,
          state: guard == 'connected' ? MeshCoreConnectionState.connected
              : guard == 'connecting' ? MeshCoreConnectionState.connecting : MeshCoreConnectionState.disconnected,
          offlineMode: guard == 'offline',
        );
        await c.open();
        expect(c.tcp.opens, 0);
        _expectWork(c, 0);
        c.setReconnectContextForTest(transport: MeshCoreTransportType.tcp);
      });
    }, timeout: timeout);
  }

  testWidgets('duplicate while dialling does not add another persistent connect lease', (tester) async {
    await _withTcp(tester, (c) async {
      final dial = c.gate();
      c.tcp.opening = dial.future;
      final first = _Result(c.open());
      await tester.pump();
      await c.open();
      expect(c.tcp.opens, 1);
      _expectWork(c, 1);
      dial.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(first.completed, isTrue);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('transport switch ends old connect only after its abandoned TCP transport closes', (tester) async {
    await _withTcp(tester, (c) async {
      final dial = c.gate();
      final close = c.gate();
      c.tcp.opening = dial.future;
      c.tcp.closing = close.future;
      final open = _Result(c.open());
      await tester.pump();
      c.setReconnectContextForTest(transport: MeshCoreTransportType.bluetooth, state: MeshCoreConnectionState.connected);
      dial.complete();
      await tester.pump();
      expect(open.completed, isFalse);
      _expectWork(c, 1);
      close.complete();
      await tester.pump();
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      expect(c.activeTransport, MeshCoreTransportType.bluetooth);
      expect(c.state, MeshCoreConnectionState.connected);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('waiting for an already active teardown is part of connect setup', (tester) async {
    await _withTcp(tester, (c) async {
      c.setReconnectContextForTest(transport: MeshCoreTransportType.tcp, state: MeshCoreConnectionState.connected);
      c.tcp.connected = true;
      final closeGate = c.gate();
      c.tcp.closing = closeGate.future;
      final close = _Result(c.disconnect(manual: true));
      await tester.pump();
      final open = _Result(c.open());
      await tester.pump();
      expect(close.completed, isFalse);
      expect(c.tcp.opens, 0);
      _expectWork(c, 1);
      closeGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('dispose after manual cancel preserves the old pending dial lease until completion', (tester) async {
    await _withTcp(tester, (c) async {
      final dial = c.gate();
      c.tcp.opening = dial.future;
      final open = _Result(c.open());
      await tester.pump();
      await c.disconnect(manual: true);
      c.dispose();
      expect(c.backgroundWorkSnapshot.isClosed, isTrue);
      _expectWork(c, 1);
      dial.complete();
      await tester.pump();
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('late closed guarded call does not register a new setup lease', (tester) async {
    await _withTcp(tester, (c) async {
      c.dispose();
      c.setReconnectContextForTest(transport: MeshCoreTransportType.tcp, offlineMode: true);
      final revision = c.backgroundWorkSnapshot.revision;
      await c.open();
      expect(c.backgroundWorkSnapshot.revision, revision);
      expect(c.tcp.opens, 0);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('an unconnected dial result releases setup after the existing abort cleanup', (tester) async {
    await _withTcp(tester, (c) async {
      c.tcp.connectedAfterOpen = false;
      final open = _Result(c.open());
      await tester.pump();
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      expect(c.state, MeshCoreConnectionState.disconnected);
      _expectWork(c, 0);
    });
  }, timeout: timeout);
}

