import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_connector_usb.dart';
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
  _Subscription(this.usb);
  final _Usb usb;

  @override
  Future<void> cancel() async {
    usb.events.add('cancel');
    await usb.cancelling;
  }
}

class _Frames extends Stream<Uint8List> {
  _Frames(this.usb);
  final _Usb usb;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    usb.events.add('listen');
    usb.onFrame = onData;
    usb.onError = onError;
    usb.onDone = onDone;
    usb.listens++;
    return _Subscription(usb);
  }
}

// Fake вместо наследования: UsbSerialService, flserial и FFI не создаются.
class _Usb extends Fake implements MeshCoreUsbManager {
  bool connected = false;
  bool connectedAfterOpen = true;
  Object? error;
  Future<void>? opening;
  Future<void>? closing;
  Future<void>? cancelling;
  int opens = 0;
  int closes = 0;
  int listens = 0;
  int? baud;
  String? port;
  String? label;
  final events = <String>[];
  void Function(Uint8List)? onFrame;
  Function? onError;
  void Function()? onDone;

  @override
  bool get isConnected => connected;
  @override
  Object? get lastError => error;
  @override
  String? get activePortKey => port;
  @override
  String? get activePortDisplayLabel => label ?? port;
  @override
  Stream<Uint8List> get frameStream => _Frames(this);

  @override
  Future<void> connect({required String portName, int baudRate = 115200}) async {
    events.add('open');
    opens++;
    port = portName;
    baud = baudRate;
    await opening;
    connected = connectedAfterOpen;
    events.add('opened');
  }

  @override
  Future<void> disconnect() async {
    events.add('close');
    closes++;
    connected = false;
    onFrame = null;
    await closing;
    port = null;
  }

  @override
  void updateConnectedLabel(String selfName) => label = selfName;
  @override
  void dispose() {}
}

// Настоящие connectUsb/disconnect/request/wait. Изолированы поиск BLE,
// default-region query и cold storage; публичная USB-ветвь не переопределяется.
class _Connector extends MeshCoreConnector {
  _Connector(_Usb manager) : usb = manager, super(usbManager: manager) {
    setFrameWriterForTest((frame) async {
      commands.add(frame.first);
      await beforeWrite?.call(frame.first);
      if (frame.first == cmdAppStart) {
        appStarts++;
        if (appStarts == replyAtAppStart && usb.onFrame != null) selfInfo();
      }
    });
  }

  final _Usb usb;
  final commands = <int>[];
  final gates = <Completer<void>>[];
  Future<void>? scanning;
  Future<void> Function(int)? beforeWrite;
  int appStarts = 0;
  int? replyAtAppStart = 1;
  int scansStopped = 0;

  @override
  Future<void> stopScan() async {
    scansStopped++;
    await scanning;
  }

  @override
  Future<String?> getDefaultRegionScope() async => null;

  Completer<void> gate() {
    final result = Completer<void>();
    gates.add(result);
    return result;
  }

  void selfInfo() {
    final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
    setCachedSelfInfoKeyForTest(key);
    final frame = Uint8List(68);
    frame[0] = respCodeSelfInfo;
    frame.setRange(4, 36, key);
    frame.setRange(58, 67, 'synthetic'.codeUnits);
    usb.onFrame!(frame);
  }

  Future<void> open({int baud = 115200}) =>
      connectUsb(portName: 'synthetic-port', baudRate: baud);
}

class _Result<T> {
  _Result(Future<T> operation) {
    unawaited(operation.then<void>((value) {
      completed = true;
    }, onError: (Object failure, StackTrace stack) {
      error = failure;
      completed = true;
    }));
  }
  bool completed = false;
  Object? error;
}

Future<void> _withUsb(
  WidgetTester tester,
  Future<void> Function(_Connector) check,
) async {
  final c = _Connector(_Usb());
  try {
    await check(c);
  } finally {
    c.replyAtAppStart = null;
    for (final gate in c.gates) {
      if (!gate.isCompleted) gate.complete();
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    if (c.isOfflineMode) {
      c.setReconnectContextForTest(transport: MeshCoreTransportType.usb, state: c.state);
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

  testWidgets('baseline: held open precedes the delay, listener and queries', (tester) async {
    await _withUsb(tester, (c) async {
      final gate = c.gate();
      c.usb.opening = gate.future;
      final open = _Result(c.open(baud: 57600));
      await tester.pump();
      expect(c.state, MeshCoreConnectionState.connecting);
      expect(c.usb.port, 'synthetic-port');
      expect(c.usb.baud, 57600);
      expect(c.commands, isEmpty);
      expect(c.usb.listens, 0);
      expect(open.completed, isFalse);
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      expect(c.hasCompletedSelfInfoHandshake, isTrue);
    });
  }, timeout: timeout);

  testWidgets('baseline: the pre-handshake delay is 200 ms', (tester) async {
    await _withUsb(tester, (c) async {
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 199));
      expect(c.usb.listens, 0);
      expect(c.commands, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      expect(c.usb.listens, 1);
      expect(c.commands, containsAllInOrder([cmdDeviceQuery, cmdAppStart, cmdSetDeviceTime]));
    });
  }, timeout: timeout);

  testWidgets('baseline: connected state precedes SELF_INFO and the connect result', (tester) async {
    await _withUsb(tester, (c) async {
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
    });
  }, timeout: timeout);

  testWidgets('baseline: first SELF_INFO timeout refreshes before the second window', (tester) async {
    await _withUsb(tester, (c) async {
      c.replyAtAppStart = 2;
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 3));
      expect(c.commands.where((code) => code == cmdDeviceQuery).length, 2);
      expect(open.completed, isTrue);
      expect(open.error, isNull);
    });
  }, timeout: timeout);

  testWidgets('baseline: both missing SELF_INFO windows fail and tear down', (tester) async {
    await _withUsb(tester, (c) async {
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
      expect(c.usb.closes, 1);
    });
  }, timeout: timeout);

  testWidgets('baseline: initial request writer failure preserves the error', (tester) async {
    await _withUsb(tester, (c) async {
      final error = StateError('synthetic request failure');
      c.beforeWrite = (code) async {
        if (code == cmdDeviceQuery) throw error;
      };
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(open.completed, isTrue);
      expect(open.error, same(error));
      expect(c.state, MeshCoreConnectionState.disconnected);
    });
  }, timeout: timeout);

  testWidgets('baseline: successful SELF_INFO still waits for the time writer', (tester) async {
    await _withUsb(tester, (c) async {
      final gate = c.gate();
      c.beforeWrite = (code) => code == cmdSetDeviceTime ? gate.future : Future<void>.value();
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.hasCompletedSelfInfoHandshake, isTrue);
      expect(open.completed, isFalse);
      gate.complete();
      await tester.pump();
      expect(open.completed, isTrue);
      expect(open.error, isNull);
    });
  }, timeout: timeout);

  testWidgets('baseline: pending stopScan prevents opening the port', (tester) async {
    await _withUsb(tester, (c) async {
      final gate = c.gate();
      c.scanning = gate.future;
      final open = _Result(c.open());
      await tester.pump();
      expect(c.usb.opens, 0);
      expect(open.completed, isFalse);
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(open.completed, isTrue);
      expect(open.error, isNull);
    });
  }, timeout: timeout);

  testWidgets('baseline: port open failure waits for close and preserves the error', (tester) async {
    await _withUsb(tester, (c) async {
      final dial = c.gate();
      final close = c.gate();
      final error = StateError('synthetic open failure');
      c.usb.opening = dial.future;
      c.usb.closing = close.future;
      final open = _Result(c.open());
      await tester.pump();
      dial.completeError(error);
      await tester.pump();
      await tester.pump(const Duration(seconds: 8));
      expect(c.state, MeshCoreConnectionState.disconnecting);
      expect(open.completed, isFalse);
      close.complete();
      await tester.pump();
      expect(open.completed, isTrue);
      expect(open.error, same(error));
    });
  }, timeout: timeout);

  testWidgets('baseline: lost port after opening fails with the recorded cause', (tester) async {
    await _withUsb(tester, (c) async {
      c.usb.connectedAfterOpen = false;
      c.usb.error = StateError('synthetic detached port');
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(open.completed, isTrue);
      expect(open.error, isA<StateError>());
      expect(open.error.toString(), contains('synthetic detached port'));
      expect(c.usb.listens, 0);
      expect(c.commands, isEmpty);
      expect(c.state, MeshCoreConnectionState.disconnected);
    });
  }, timeout: timeout);

  testWidgets('baseline: manual disconnect during the delay fails USB liveness', (tester) async {
    await _withUsb(tester, (c) async {
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await c.disconnect(manual: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(open.completed, isTrue);
      expect(open.error, isA<StateError>());
      expect(c.usb.listens, 0);
      expect(c.commands, isEmpty);
    });
  }, timeout: timeout);

  for (final guard in ['connecting', 'connected', 'offline']) {
    testWidgets('baseline: $guard guard prevents USB opening', (tester) async {
      await _withUsb(tester, (c) async {
        c.setReconnectContextForTest(
          transport: MeshCoreTransportType.usb,
          state: guard == 'connecting' ? MeshCoreConnectionState.connecting
              : guard == 'connected' ? MeshCoreConnectionState.connected : MeshCoreConnectionState.disconnected,
          offlineMode: guard == 'offline',
        );
        await c.open();
        expect(c.usb.opens, 0);
        expect(c.scansStopped, 0);
        c.setReconnectContextForTest(transport: MeshCoreTransportType.usb);
      });
    }, timeout: timeout);
  }

  testWidgets('baseline: a duplicate call does not replace the pending open', (tester) async {
    await _withUsb(tester, (c) async {
      final gate = c.gate();
      c.usb.opening = gate.future;
      final first = _Result(c.open());
      await tester.pump();
      await c.open();
      expect(c.usb.opens, 1);
      expect(first.completed, isFalse);
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(first.completed, isTrue);
      expect(first.error, isNull);
    });
  }, timeout: timeout);

  testWidgets('baseline: caller timeout leaves the actual USB open running', (tester) async {
    await _withUsb(tester, (c) async {
      final gate = c.gate();
      c.usb.opening = gate.future;
      final caller = _Result(c.open().timeout(const Duration(milliseconds: 1)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(caller.error, isA<TimeoutException>());
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.hasCompletedSelfInfoHandshake, isTrue);
      expect(c.state, MeshCoreConnectionState.connected);
    });
  }, timeout: timeout);

  testWidgets('baseline: connect waits for the existing USB close without an outer deadline', (tester) async {
    await _withUsb(tester, (c) async {
      c.setReconnectContextForTest(transport: MeshCoreTransportType.usb, state: MeshCoreConnectionState.connected);
      c.usb.connected = true;
      final gate = c.gate();
      c.usb.closing = gate.future;
      final close = _Result(c.disconnect(manual: true));
      await tester.pump();
      final open = _Result(c.open());
      await tester.pump(const Duration(seconds: 8));
      expect(close.completed, isFalse);
      expect(open.completed, isFalse);
      expect(c.usb.opens, 0);
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      expect(c.usb.events, containsAllInOrder(['close', 'open', 'opened', 'listen']));
    });
  }, timeout: timeout);

  testWidgets('baseline: USB stream error disconnects without automatic reconnect', (tester) async {
    await _withUsb(tester, (c) async {
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(open.error, isNull);
      final onError = c.usb.onError! as void Function(Object, StackTrace);
      onError(StateError('synthetic RX failure'), StackTrace.current);
      await tester.pump();
      expect(c.state, MeshCoreConnectionState.disconnected);
      expect(c.isAutoReconnectScheduled, isFalse);
      expect(c.usb.events, containsAllInOrder(['listen', 'cancel', 'close']));
    });
  }, timeout: timeout);

  testWidgets('baseline: USB subscription cancellation precedes manager close', (tester) async {
    await _withUsb(tester, (c) async {
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(open.error, isNull);
      final gate = c.gate();
      c.usb.cancelling = gate.future;
      final close = _Result(c.disconnect(manual: true));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(close.completed, isFalse);
      expect(c.usb.closes, 0);
      gate.complete();
      await tester.pump();
      expect(close.completed, isTrue);
      expect(close.error, isNull);
      expect(c.usb.events, containsAllInOrder(['cancel', 'close']));
    });
  }, timeout: timeout);

  testWidgets('baseline: stream completion disconnects USB', (tester) async {
    await _withUsb(tester, (c) async {
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(open.error, isNull);
      c.usb.onDone!();
      await tester.pump();
      expect(c.state, MeshCoreConnectionState.disconnected);
      expect(c.isAutoReconnectScheduled, isFalse);
    });
  }, timeout: timeout);
}
