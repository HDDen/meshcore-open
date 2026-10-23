import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_connector_tcp.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
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
    await c.disconnect(manual: true);
    await tester.pump(const Duration(seconds: 7));
    c.resetConnectionHandshakeForTest();
    c.dispose();
    await tester.pump();
  }
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

  testWidgets('baseline: open remains pending while the transport manager is opening', (tester) async {
    await _withTcp(tester, (c) async {
      final gate = c.gate();
      c.tcp.opening = gate.future;
      final open = _Result(c.open());
      await tester.pump();
      expect(c.state, MeshCoreConnectionState.connecting);
      expect(open.completed, isFalse);
      expect(c.tcp.events, ['cancel', 'open']);
      expect(c.commands, isEmpty);
      gate.complete();
      await tester.pump();
      expect(open.completed, isFalse);
      await tester.pump(const Duration(milliseconds: 200));
      expect(open.completed, isTrue);
      expect(open.error, isNull);
    });
  }, timeout: timeout);

  testWidgets('baseline: frame listening and handshake start after exactly the existing 200 ms delay', (tester) async {
    await _withTcp(tester, (c) async {
      final open = _Result(c.open());
      await tester.pump();
      expect(c.tcp.connected, isTrue);
      await tester.pump(const Duration(milliseconds: 199));
      expect(c.tcp.listens, 0);
      expect(c.commands, isEmpty);
      expect(open.completed, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      expect(c.tcp.listens, 1);
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      expect(c.state, MeshCoreConnectionState.connected);
      expect(c.hasCompletedSelfInfoHandshake, isTrue);
      expect(c.isSessionReady, isFalse);
      expect(c.commands, [cmdDeviceQuery, cmdAppStart, buildGetCustomVarsFrame().first, cmdGetBattAndStorage, cmdSetDeviceTime]);
      expect(c.regionQueries, 1);
    });
  }, timeout: timeout);

  testWidgets('baseline: connected state can precede completed SELF_INFO and connect Future', (tester) async {
    await _withTcp(tester, (c) async {
      c.replyAtAppStart = null;
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.state, MeshCoreConnectionState.connected);
      expect(c.hasCompletedSelfInfoHandshake, isFalse);
      expect(open.completed, isFalse);
      c.selfInfo();
      await tester.pump(const Duration(milliseconds: 50));
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      expect(c.count(cmdSetDeviceTime), 1);
    });
  }, timeout: timeout);

  testWidgets('baseline: the second SELF_INFO window follows a full explicit refresh', (tester) async {
    await _withTcp(tester, (c) async {
      c.replyAtAppStart = 2;
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 2999));
      expect(c.count(cmdAppStart), 1);
      expect(open.completed, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      expect(c.count(cmdAppStart), 2);
      expect(c.count(cmdDeviceQuery), 2);
      expect(c.count(cmdGetBattAndStorage), 2);
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      expect(c.count(cmdSetDeviceTime), 1);
    });
  }, timeout: timeout);

  testWidgets('baseline: two missing SELF_INFO windows fail and disconnect without time sync', (tester) async {
    await _withTcp(tester, (c) async {
      c.replyAtAppStart = null;
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 3));
      expect(open.completed, isFalse);
      await tester.pump(const Duration(seconds: 3));
      expect(open.completed, isTrue);
      expect(open.error, isA<StateError>());
      expect(c.state, MeshCoreConnectionState.disconnected);
      expect(c.tcp.closes, 1);
      expect(c.count(cmdDeviceQuery), 2);
      expect(c.count(cmdSetDeviceTime), 0);
      expect(c.regionQueries, 0);
    });
  }, timeout: timeout);

  testWidgets('baseline: handshake writer failure tears down TCP and keeps the original error', (tester) async {
    await _withTcp(tester, (c) async {
      final error = StateError('synthetic handshake TX failure');
      c.beforeWrite = (command) async {
        if (command == cmdDeviceQuery) throw error;
      };
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(open.completed, isTrue);
      expect(open.error, same(error));
      expect(c.state, MeshCoreConnectionState.disconnected);
      expect(c.tcp.closes, 1);
      expect(c.count(cmdAppStart), 0);
    });
  }, timeout: timeout);

  testWidgets('baseline: successful SELF_INFO does not finish connect before time synchronization writes', (tester) async {
    await _withTcp(tester, (c) async {
      final gate = c.gate();
      c.beforeWrite = (command) => command == cmdSetDeviceTime ? gate.future : Future<void>.value();
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.hasCompletedSelfInfoHandshake, isTrue);
      expect(c.state, MeshCoreConnectionState.connected);
      expect(open.completed, isFalse);
      gate.complete();
      await tester.pump();
      expect(open.completed, isTrue);
      expect(open.error, isNull);
    });
  }, timeout: timeout);

  testWidgets('baseline: prior frame cancellation finishes before opening starts', (tester) async {
    await _withTcp(tester, (c) async {
      final gate = c.gate();
      c.tcp.cancelling = gate.future;
      final open = _Result(c.open());
      await tester.pump();
      expect(c.tcp.events, ['cancel']);
      expect(c.tcp.opens, 0);
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(open.completed, isTrue);
      expect(open.error, isNull);
    });
  }, timeout: timeout);

  testWidgets('baseline: scan stop is awaited before the transport is claimed or opened', (tester) async {
    await _withTcp(tester, (c) async {
      final gate = c.gate();
      c.scanning = gate.future;
      final open = _Result(c.open());
      await tester.pump();
      expect(c.scansStopped, 1);
      expect(c.tcp.opens, 0);
      expect(c.state, MeshCoreConnectionState.disconnected);
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(open.completed, isTrue);
      expect(open.error, isNull);
    });
  }, timeout: timeout);

  testWidgets('baseline: a new connect waits for the active teardown before scan or dial', (tester) async {
    await _withTcp(tester, (c) async {
      c.setReconnectContextForTest(transport: MeshCoreTransportType.tcp, state: MeshCoreConnectionState.connected);
      c.tcp.connected = true;
      final gate = c.gate();
      c.tcp.closing = gate.future;
      final close = _Result(c.disconnect(manual: true));
      await tester.pump();
      final open = _Result(c.open());
      await tester.pump();
      expect(close.completed, isFalse);
      expect(c.scansStopped, 0);
      expect(c.tcp.opens, 0);
      gate.complete();
      await tester.pump();
      expect(close.completed, isTrue);
      expect(c.tcp.opens, 1);
      await tester.pump(const Duration(milliseconds: 200));
      expect(open.completed, isTrue);
      expect(open.error, isNull);
    });
  }, timeout: timeout);

  for (final state in [MeshCoreConnectionState.connecting, MeshCoreConnectionState.connected]) {
    testWidgets('baseline: occupied $state connector ignores another connect', (tester) async {
      await _withTcp(tester, (c) async {
        c.setReconnectContextForTest(transport: MeshCoreTransportType.tcp, state: state);
        await c.open();
        expect(c.tcp.opens, 0);
        expect(c.scansStopped, 0);
      });
    }, timeout: timeout);
  }

  testWidgets('baseline: offline history ignores TCP connect before scan or dial', (tester) async {
    await _withTcp(tester, (c) async {
      c.setReconnectContextForTest(transport: MeshCoreTransportType.tcp, offlineMode: true);
      await c.open();
      expect(c.tcp.opens, 0);
      expect(c.scansStopped, 0);
      // Не запускать exitOfflineHistory: настоящая offline история не открывалась.
      c.setReconnectContextForTest(transport: MeshCoreTransportType.tcp);
    });
  }, timeout: timeout);

  testWidgets('baseline: open failure is rethrown after automatic teardown', (tester) async {
    await _withTcp(tester, (c) async {
      final gate = c.gate();
      c.tcp.opening = gate.future;
      final error = StateError('synthetic dial failure');
      final open = _Result(c.open());
      await tester.pump();
      gate.completeError(error);
      await tester.pump();
      expect(open.completed, isTrue);
      expect(open.error, same(error));
      expect(c.state, MeshCoreConnectionState.disconnected);
      expect(c.tcp.closes, 1);
      expect(c.commands, isEmpty);
    });
  }, timeout: timeout);

  testWidgets('baseline: late dial failure after manual cancel is ignored', (tester) async {
    await _withTcp(tester, (c) async {
      final gate = c.gate();
      c.tcp.opening = gate.future;
      final open = _Result(c.open());
      await tester.pump();
      await c.disconnect(manual: true);
      gate.completeError(StateError('synthetic late dial failure'));
      await tester.pump();
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      expect(c.tcp.closes, 1);
      expect(c.state, MeshCoreConnectionState.disconnected);
      expect(c.commands, isEmpty);
    });
  }, timeout: timeout);

  testWidgets('baseline: late dial success after manual cancel closes the abandoned TCP transport', (tester) async {
    await _withTcp(tester, (c) async {
      final gate = c.gate();
      c.tcp.opening = gate.future;
      final open = _Result(c.open());
      await tester.pump();
      await c.disconnect(manual: true);
      expect(open.completed, isFalse);
      gate.complete();
      await tester.pump();
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      expect(c.tcp.closes, 2);
      expect(c.tcp.listens, 0);
      expect(c.tcp.connected, isFalse);
      expect(c.commands, isEmpty);
    });
  }, timeout: timeout);

  testWidgets('baseline: manual cancellation during the 200 ms delay prevents listening and queries', (tester) async {
    await _withTcp(tester, (c) async {
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await c.disconnect(manual: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      expect(c.tcp.listens, 0);
      expect(c.commands, isEmpty);
    });
  }, timeout: timeout);

  testWidgets('baseline: a missing connected transport at dial completion aborts and resets connecting', (tester) async {
    await _withTcp(tester, (c) async {
      c.tcp.connectedAfterOpen = false;
      final open = _Result(c.open());
      await tester.pump();
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      expect(c.state, MeshCoreConnectionState.disconnected);
      expect(c.tcp.closes, 1);
      expect(c.commands, isEmpty);
    });
  }, timeout: timeout);

  testWidgets('baseline: cancellation on transport switch preserves the replacement connection state', (tester) async {
    await _withTcp(tester, (c) async {
      final gate = c.gate();
      c.tcp.opening = gate.future;
      final open = _Result(c.open());
      await tester.pump();
      c.setReconnectContextForTest(transport: MeshCoreTransportType.bluetooth, state: MeshCoreConnectionState.connected);
      gate.complete();
      await tester.pump();
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      expect(c.activeTransport, MeshCoreTransportType.bluetooth);
      expect(c.state, MeshCoreConnectionState.connected);
      expect(c.tcp.closes, 1);
      expect(c.commands, isEmpty);
    });
  }, timeout: timeout);

  testWidgets('baseline: caller timeout leaves the underlying dial and handshake running', (tester) async {
    await _withTcp(tester, (c) async {
      final gate = c.gate();
      c.tcp.opening = gate.future;
      final caller = _Result(c.open().timeout(const Duration(milliseconds: 1)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(caller.error, isA<TimeoutException>());
      expect(c.tcp.closes, 0);
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.state, MeshCoreConnectionState.connected);
      expect(c.hasCompletedSelfInfoHandshake, isTrue);
      expect(c.count(cmdSetDeviceTime), 1);
    });
  }, timeout: timeout);
}
