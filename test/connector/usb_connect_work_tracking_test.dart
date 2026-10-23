import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_connector_usb.dart';
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

  for (final boundary in ['scan', 'open']) {
    testWidgets('$boundary wait holds the complete connect Future', (tester) async {
      await _withUsb(tester, (c) async {
        final gate = c.gate();
        if (boundary == 'scan') {
          c.scanning = gate.future;
        } else {
          c.usb.opening = gate.future;
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

  testWidgets('the 200 ms delay remains active USB setup work', (tester) async {
    await _withUsb(tester, (c) async {
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

  testWidgets('SELF_INFO completion does not release connect during time sync', (tester) async {
    await _withUsb(tester, (c) async {
      final gate = c.gate();
      c.beforeWrite = (code) => code == cmdSetDeviceTime ? gate.future : Future<void>.value();
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

  testWidgets('time writer failure retains setup through its error cleanup', (tester) async {
    await _withUsb(tester, (c) async {
      final close = c.gate();
      final error = StateError('synthetic time TX failure');
      c.usb.closing = close.future;
      c.beforeWrite = (code) async {
        if (code == cmdSetDeviceTime) throw error;
      };
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(open.completed, isFalse);
      expect(c.state, MeshCoreConnectionState.disconnecting);
      _expectWork(c, 1);
      close.complete();
      await tester.pump();
      expect(open.completed, isTrue);
      expect(open.error, same(error));
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('outer connect, logical SELF_INFO and actual wait are independent', (tester) async {
    await _withUsb(tester, (c) async {
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

  testWidgets('reset drops logical SELF_INFO without releasing actual wait or connect', (tester) async {
    await _withUsb(tester, (c) async {
      c.replyAtAppStart = null;
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      _expectWork(c, 3);
      c.resetConnectionHandshakeForTest();
      _expectWork(c, 2);
      c.selfInfo();
      await tester.pump(const Duration(milliseconds: 50));
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('both missing SELF_INFO windows retain setup until failure cleanup', (tester) async {
    await _withUsb(tester, (c) async {
      c.replyAtAppStart = null;
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      _expectWork(c, 3);
      await tester.pump(const Duration(seconds: 3));
      expect(c.commands.where((code) => code == cmdDeviceQuery).length, 2);
      _expectWork(c, 3);
      await tester.pump(const Duration(seconds: 3));
      expect(open.completed, isTrue);
      expect(open.error, isA<StateError>());
      expect(c.state, MeshCoreConnectionState.disconnected);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('manual disconnect keeps the held request writer and outer USB connect', (tester) async {
    await _withUsb(tester, (c) async {
      final gate = c.gate();
      c.beforeWrite = (code) => code == cmdDeviceQuery ? gate.future : Future<void>.value();
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
      expect(open.error, isA<Exception>());
      expect(open.error.toString(), contains('Not connected to a MeshCore device'));
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('manual cancellation during the delay does not release the original connect early', (tester) async {
    await _withUsb(tester, (c) async {
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await c.disconnect(manual: true);
      expect(open.completed, isFalse);
      _expectWork(c, 1);
      await tester.pump(const Duration(milliseconds: 100));
      expect(open.completed, isTrue);
      expect(open.error, isA<StateError>());
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('open failure retains setup throughout the existing unbounded manager close', (tester) async {
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
      _expectWork(c, 1);
      close.complete();
      await tester.pump();
      expect(open.completed, isTrue);
      expect(open.error, same(error));
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('waiting for a pre-existing USB close holds setup without a new deadline', (tester) async {
    await _withUsb(tester, (c) async {
      c.setReconnectContextForTest(transport: MeshCoreTransportType.usb, state: MeshCoreConnectionState.connected);
      c.usb.connected = true;
      final gate = c.gate();
      c.usb.closing = gate.future;
      final close = _Result(c.disconnect(manual: true));
      await tester.pump();
      final open = _Result(c.open());
      await tester.pump(const Duration(seconds: 8));
      expect(c.usb.opens, 0);
      expect(close.completed, isFalse);
      expect(open.completed, isFalse);
      _expectWork(c, 1);
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('a port lost during the delay releases setup after the original failure cleanup', (tester) async {
    await _withUsb(tester, (c) async {
      c.usb.connectedAfterOpen = false;
      final open = _Result(c.open());
      await tester.pump();
      _expectWork(c, 1);
      await tester.pump(const Duration(milliseconds: 200));
      expect(open.completed, isTrue);
      expect(open.error, isA<StateError>());
      expect(c.usb.listens, 0);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('write timeout finishes connect but leaves the actual writer counted', (tester) async {
    await _withUsb(tester, (c) async {
      final gate = c.gate();
      c.beforeWrite = (code) => code == cmdDeviceQuery ? gate.future : Future<void>.value();
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

  testWidgets('caller timeout does not release the actual USB connect', (tester) async {
    await _withUsb(tester, (c) async {
      final gate = c.gate();
      c.usb.opening = gate.future;
      final caller = _Result(c.open().timeout(const Duration(milliseconds: 1)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(caller.error, isA<TimeoutException>());
      _expectWork(c, 1);
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.hasCompletedSelfInfoHandshake, isTrue);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  for (final guard in ['connecting', 'connected', 'offline']) {
    testWidgets('$guard guard leaves no persistent USB setup lease', (tester) async {
      await _withUsb(tester, (c) async {
        c.setReconnectContextForTest(
          transport: MeshCoreTransportType.usb,
          state: guard == 'connecting' ? MeshCoreConnectionState.connecting
              : guard == 'connected' ? MeshCoreConnectionState.connected : MeshCoreConnectionState.disconnected,
          offlineMode: guard == 'offline',
        );
        await c.open();
        expect(c.usb.opens, 0);
        _expectWork(c, 0);
        c.setReconnectContextForTest(transport: MeshCoreTransportType.usb);
      });
    }, timeout: timeout);
  }

  testWidgets('duplicate while opening does not add another persistent connect lease', (tester) async {
    await _withUsb(tester, (c) async {
      final gate = c.gate();
      c.usb.opening = gate.future;
      final first = _Result(c.open());
      await tester.pump();
      await c.open();
      expect(c.usb.opens, 1);
      _expectWork(c, 1);
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(first.completed, isTrue);
      expect(first.error, isNull);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('dispose after manual cancel retains the held time writer and connect', (tester) async {
    await _withUsb(tester, (c) async {
      final gate = c.gate();
      c.beforeWrite = (code) => code == cmdSetDeviceTime ? gate.future : Future<void>.value();
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await c.disconnect(manual: true);
      c.dispose();
      expect(c.backgroundWorkSnapshot.isClosed, isTrue);
      _expectWork(c, 1, writes: 1);
      gate.complete();
      await tester.pump();
      expect(open.completed, isTrue);
      expect(open.error, isNull);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('late closed guarded call registers no new USB setup lease', (tester) async {
    await _withUsb(tester, (c) async {
      c.dispose();
      c.setReconnectContextForTest(transport: MeshCoreTransportType.usb, offlineMode: true);
      final revision = c.backgroundWorkSnapshot.revision;
      await c.open();
      expect(c.backgroundWorkSnapshot.revision, revision);
      expect(c.usb.opens, 0);
      _expectWork(c, 0);
    });
  }, timeout: timeout);

  testWidgets('completed connect leaves no setup lease while later stream failure closes USB', (tester) async {
    await _withUsb(tester, (c) async {
      final open = _Result(c.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(open.completed, isTrue);
      _expectWork(c, 0);
      final gate = c.gate();
      c.usb.closing = gate.future;
      final onError = c.usb.onError! as void Function(Object, StackTrace);
      onError(StateError('synthetic RX failure'), StackTrace.current);
      await tester.pump();
      expect(c.state, MeshCoreConnectionState.disconnecting);
      // Закрытие после уже завершённого connect — отдельный путь, не новый connect.
      _expectWork(c, 0);
      expect(c.backgroundWorkSnapshot.countFor(BackgroundWorkKind.transportTeardown), 1);
      gate.complete();
      await tester.pump();
      expect(c.state, MeshCoreConnectionState.disconnected);
      _expectWork(c, 0);
    });
  }, timeout: timeout);
}
