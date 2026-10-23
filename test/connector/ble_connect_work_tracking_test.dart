import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/connector/meshcore_uuids.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/utils/platform_info.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Проверяется Windows-ветвь FlutterBluePlus; Linux bluetoothctl и native iOS
// имеют другой lifecycle. Нативный SDK/радио здесь не вызываются.
final class _BondPlatform extends FlutterBluePlusPlatform {
  @override
  Future<BmBondStateResponse> getBondState(BmBondStateRequest request) async =>
      BmBondStateResponse(
        remoteId: request.remoteId,
        bondState: BmBondStateEnum.bonded,
        prevState: null,
      );
}

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('synthetic preferences without a directory');
  }
}

class _Subscription<T> extends Fake implements StreamSubscription<T> {
  _Subscription(this.detach);
  final void Function() detach;

  @override
  Future<void> cancel() async {
    detach();
  }
}

// Для фикстуры нужен один синхронный listener. Обычный broadcast.cancel()
// возвращает root-Zone Future._nullFuture и может зависнуть внутри FakeAsync.
// Здесь detach и завершение cancel принадлежат зоне самого widget-теста.
class _Events<T> extends Stream<T> {
  void Function(T)? _listener;
  int _generation = 0;
  bool _closed = false;

  bool get hasListener => _listener != null;

  @override
  StreamSubscription<T> listen(
    void Function(T)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (_closed || hasListener) throw StateError('synthetic stream unavailable');
    final generation = ++_generation;
    _listener = onData;
    return _Subscription<T>(() {
      if (_generation == generation) _listener = null;
    });
  }

  void add(T event) {
    if (_closed) throw StateError('synthetic stream closed');
    _listener?.call(event);
  }

  Future<void> close() async {
    _closed = true;
    _listener = null;
  }
}

class _Characteristic extends Fake implements BluetoothCharacteristic {
  _Characteristic(this.id);
  final String id;
  final values = _Events<List<int>>();
  Future<void>? enabling;
  int enables = 0;
  int notifyFailures = 0;

  @override
  Guid get uuid => Guid(id);
  @override
  CharacteristicProperties get properties => const CharacteristicProperties(notify: true);
  @override
  List<BluetoothDescriptor> get descriptors => [];
  @override
  Stream<List<int>> get onValueReceived => values;

  @override
  Future<bool> setNotifyValue(bool notify, {int timeout = 15, bool forceIndications = false}) async {
    enables++;
    await enabling;
    if (notifyFailures > 0) {
      notifyFailures--;
      throw StateError('synthetic CCCD failure');
    }
    return true;
  }
}

class _Service extends Fake implements BluetoothService {
  _Service(this.characteristics);
  @override
  Guid get uuid => Guid(MeshCoreUuids.service);
  @override
  final List<BluetoothCharacteristic> characteristics;
}

class _Device extends Fake implements BluetoothDevice {
  final states = _Events<BluetoothConnectionState>();
  final rx = _Characteristic(MeshCoreUuids.rxCharacteristic);
  final tx = _Characteristic(MeshCoreUuids.txCharacteristic);
  Future<void>? opening;
  Future<void>? discovery;
  Future<void>? closing;
  final failures = <Object>[];
  bool connected = false;
  bool missingService = false;
  bool missingTx = false;
  int opens = 0;
  int closes = 0;
  int discoveries = 0;
  Duration? requestedTimeout;
  int? requestedMtu;
  License? requestedLicense;

  @override
  DeviceIdentifier get remoteId => const DeviceIdentifier('00:00:00:00:00:01');
  @override
  String get platformName => 'synthetic BLE';
  @override
  bool get isConnected => connected;
  @override
  Stream<BluetoothConnectionState> get connectionState => states;

  @override
  Future<void> connect({
    required License license,
    Duration timeout = const Duration(seconds: 35),
    int? mtu = 512,
    bool autoConnect = false,
  }) async {
    opens++;
    requestedTimeout = timeout;
    requestedMtu = mtu;
    requestedLicense = license;
    await opening;
    if (failures.isNotEmpty) throw failures.removeAt(0);
    connected = true;
  }

  @override
  Future<void> disconnect({int timeout = 35, bool queue = true, int androidDelay = 2000}) async {
    closes++;
    connected = false;
    await closing;
  }

  @override
  Future<List<BluetoothService>> discoverServices({bool subscribeToServicesChanged = true, int timeout = 15}) async {
    discoveries++;
    await discovery;
    return missingService ? [] : [_Service([rx, if (!missingTx) tx])];
  }
}

class _Connector extends MeshCoreConnector {
  _Connector(this.ble) {
    setFrameWriterForTest((frame) async {
      commands.add(frame.first);
      await beforeWrite?.call(frame.first);
      if (frame.first == cmdAppStart) {
        appStarts++;
        if (replyAtAppStart == appStarts) selfInfo();
      }
    });
  }
  final _Device ble;
  final commands = <int>[];
  final gates = <Completer<void>>[];
  Future<void>? scanning;
  Future<void> Function(int)? beforeWrite;
  int scansStopped = 0;
  int appStarts = 0;
  int? replyAtAppStart = 1;

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
    ble.tx.values.add(frame);
  }

  Future<void> open({String? displayName}) => connect(
    ble,
    displayName: displayName,
    requestBatteryOptimizationExemption: false,
  );
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

Future<void> _withBle(WidgetTester tester, Future<void> Function(_Connector) check) async {
  final c = _Connector(_Device());
  try {
    await check(c);
  } finally {
    c.ble.failures.clear();
    c.ble.tx.notifyFailures = 0;
    c.replyAtAppStart = 1;
    for (final gate in c.gates) {
      if (!gate.isCompleted) gate.complete();
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    if (c.isOfflineMode) {
      c.setReconnectContextForTest(transport: MeshCoreTransportType.bluetooth, state: c.state);
    }
    if (!c.backgroundWorkSnapshot.isClosed) await c.disconnect(manual: true);
    await tester.pump(const Duration(seconds: 7));
    c.resetConnectionHandshakeForTest();
    if (!c.backgroundWorkSnapshot.isClosed) c.dispose();
    await c.ble.states.close();
    await c.ble.rx.values.close();
    await c.ble.tx.values.close();
    await tester.pump();
  }
}

void _expectWork(_Connector c, int setup, {int writes = 0, int teardown = 0}) {
  final snapshot = c.backgroundWorkSnapshot;
  expect(snapshot.countFor(BackgroundWorkKind.transportSetup), setup);
  expect(snapshot.countFor(BackgroundWorkKind.transportWrite), writes);
  expect(snapshot.countFor(BackgroundWorkKind.transportTeardown), teardown);
  expect(snapshot.activeCount, setup + writes + teardown);
  expect(snapshot.isBusy, setup + writes + teardown > 0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const timeout = Timeout(Duration(seconds: 30));
  group('Windows BLE connect work', () {
    late PathProviderPlatform savedPaths;
    FlutterBluePlusPlatform? savedBle;
    setUpAll(() {
      savedPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _NoPreferencesDirectory();
      try {
        savedBle = FlutterBluePlusPlatform.instance;
      } on UnsupportedError {
        // Тестовый хост может не регистрировать нативный плагин.
      }
      FlutterBluePlusPlatform.instance = _BondPlatform();
    });
    tearDownAll(() {
      PathProviderPlatform.instance = savedPaths;
      final original = savedBle;
      if (original != null) FlutterBluePlusPlatform.instance = original;
    });
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      PrefsManager.reset();
      await PrefsManager.initialize();
    });
    tearDown(PrefsManager.reset);

    for (final boundary in ['scan', 'open', 'discovery', 'cccd']) {
      testWidgets('$boundary wait holds the complete BLE connect Future', (tester) async {
        await _withBle(tester, (c) async {
          final gate = c.gate();
          if (boundary == 'scan') {
            c.scanning = gate.future;
          } else if (boundary == 'open') {
            c.ble.opening = gate.future;
          } else if (boundary == 'discovery') {
            c.ble.discovery = gate.future;
          } else {
            c.ble.tx.enabling = gate.future;
          }
          final open = _Result(c.open());
          await tester.pump();
          if (boundary == 'cccd') {
            await tester.pump(const Duration(milliseconds: 750));
          }
          expect(open.completed, isFalse);
          _expectWork(c, 1);
          gate.complete();
          await tester.pump();
          if (boundary != 'cccd') {
            await tester.pump(const Duration(milliseconds: 750));
          }
          expect(open.completed, isTrue);
          expect(open.error, isNull);
          _expectWork(c, 0);
        });
      }, timeout: timeout);
    }

    testWidgets('the Windows settle delay remains active connection setup', (tester) async {
      await _withBle(tester, (c) async {
        final open = _Result(c.open());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 749));
        expect(c.ble.tx.enables, 0);
        _expectWork(c, 1);
        await tester.pump(const Duration(milliseconds: 1));
        expect(open.completed, isTrue);
        expect(open.error, isNull);
        _expectWork(c, 0);
      });
    }, timeout: timeout);

    testWidgets('SELF_INFO does not release outer connect while time sync writes', (tester) async {
      await _withBle(tester, (c) async {
        final gate = c.gate();
        c.beforeWrite = (code) => code == cmdSetDeviceTime ? gate.future : Future<void>.value();
        final open = _Result(c.open());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
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

    testWidgets('outer connect and logical and actual SELF_INFO waits are independent', (tester) async {
      await _withBle(tester, (c) async {
        c.replyAtAppStart = null;
        final open = _Result(c.open());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
        expect(c.state, MeshCoreConnectionState.connected);
        _expectWork(c, 3);
        c.selfInfo();
        await tester.pump(const Duration(milliseconds: 50));
        expect(open.completed, isTrue);
        expect(open.error, isNull);
        _expectWork(c, 0);
      });
    }, timeout: timeout);

    testWidgets('two missing SELF_INFO windows release outer connect but retain the logical handshake', (tester) async {
      await _withBle(tester, (c) async {
        c.replyAtAppStart = null;
        final open = _Result(c.open());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
        _expectWork(c, 3);
        await tester.pump(const Duration(seconds: 3));
        _expectWork(c, 3);
        await tester.pump(const Duration(seconds: 3));
        expect(open.completed, isTrue);
        expect(open.error, isNull);
        expect(c.hasCompletedSelfInfoHandshake, isFalse);
        _expectWork(c, 1);
        c.resetConnectionHandshakeForTest();
        _expectWork(c, 0);
      });
    }, timeout: timeout);

    testWidgets('caller timeout does not release the actual BLE connect', (tester) async {
      await _withBle(tester, (c) async {
        final gate = c.gate();
        c.ble.opening = gate.future;
        final caller = _Result(c.open().timeout(const Duration(milliseconds: 1)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        expect(caller.error, isA<TimeoutException>());
        _expectWork(c, 1);
        gate.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
        expect(c.hasCompletedSelfInfoHandshake, isTrue);
        _expectWork(c, 0);
      });
    }, timeout: timeout);

    for (final guard in ['connecting', 'connected', 'offline']) {
      testWidgets('$guard guard leaves no persistent setup lease', (tester) async {
        await _withBle(tester, (c) async {
          c.setReconnectContextForTest(
            transport: MeshCoreTransportType.bluetooth,
            state: guard == 'connecting' ? MeshCoreConnectionState.connecting
                : guard == 'connected' ? MeshCoreConnectionState.connected : MeshCoreConnectionState.disconnected,
            offlineMode: guard == 'offline',
          );
          await c.open();
          expect(c.ble.opens, 0);
          _expectWork(c, 0);
          c.setReconnectContextForTest(transport: MeshCoreTransportType.bluetooth);
        });
      }, timeout: timeout);
    }

    testWidgets('duplicate call adds no second persistent connect lease', (tester) async {
      await _withBle(tester, (c) async {
        final gate = c.gate();
        c.ble.opening = gate.future;
        final first = _Result(c.open());
        await tester.pump();
        await c.open();
        expect(c.ble.opens, 1);
        _expectWork(c, 1);
        gate.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
        expect(first.completed, isTrue);
        expect(first.error, isNull);
        _expectWork(c, 0);
      });
    }, timeout: timeout);

    testWidgets('manual cancellation leaves the pending device connect counted until its late error', (tester) async {
      await _withBle(tester, (c) async {
        final gate = c.gate();
        c.ble.opening = gate.future;
        final open = _Result(c.open());
        await tester.pump();
        await c.disconnect(manual: true);
        expect(open.completed, isFalse);
        _expectWork(c, 1);
        final error = StateError('synthetic timed out after cancel');
        gate.completeError(error);
        await tester.pump();
        expect(open.completed, isTrue);
        expect(open.error, same(error));
        expect(c.isAutoReconnectScheduled, isFalse);
        _expectWork(c, 0);
      });
    }, timeout: timeout);

    testWidgets('fast retry delay and its new discovery retain the same outer lease', (tester) async {
      await _withBle(tester, (c) async {
        c.ble.failures.add(StateError('synthetic fast failure'));
        final open = _Result(c.open());
        await tester.pump();
        _expectWork(c, 1);
        await tester.pump(const Duration(milliseconds: 500));
        expect(c.ble.opens, 2);
        _expectWork(c, 1);
        await tester.pump(const Duration(milliseconds: 750));
        expect(open.completed, isTrue);
        expect(open.error, isNull);
        _expectWork(c, 0);
      });
    }, timeout: timeout);

    testWidgets('CCCD retry delays retain setup until notifications and handshake finish', (tester) async {
      await _withBle(tester, (c) async {
        c.ble.tx.notifyFailures = 2;
        final open = _Result(c.open());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
        _expectWork(c, 1);
        await tester.pump(const Duration(seconds: 1));
        expect(c.ble.tx.enables, 2);
        _expectWork(c, 1);
        await tester.pump(const Duration(seconds: 2));
        expect(open.completed, isTrue);
        expect(open.error, isNull);
        _expectWork(c, 0);
      });
    }, timeout: timeout);

    testWidgets('inline stale-link close remains inside the original connect Future', (tester) async {
      await _withBle(tester, (c) async {
        c.ble.connected = true;
        final gate = c.gate();
        c.ble.closing = gate.future;
        final open = _Result(c.open());
        await tester.pump();
        await tester.pump(const Duration(seconds: 8));
        expect(c.ble.opens, 0);
        expect(open.completed, isFalse);
        _expectWork(c, 1);
        gate.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
        expect(open.completed, isTrue);
        expect(open.error, isNull);
        _expectWork(c, 0);
      });
    }, timeout: timeout);

    testWidgets('error cleanup timeout releases connect while actual BLE close remains tracked', (tester) async {
      await _withBle(tester, (c) async {
        c.ble.missingService = true;
        final gate = c.gate();
        c.ble.closing = gate.future;
        final open = _Result(c.open());
        await tester.pump();
        expect(open.completed, isFalse);
        _expectWork(c, 1, teardown: 2);
        await tester.pump(const Duration(seconds: 3));
        expect(open.completed, isTrue);
        expect(open.error, isA<Exception>());
        _expectWork(c, 0, teardown: 1);
        gate.complete();
        await tester.pump();
        _expectWork(c, 0);
      });
    }, timeout: timeout);

    testWidgets('write timeout releases connect but leaves the original writer counted', (tester) async {
      await _withBle(tester, (c) async {
        final gate = c.gate();
        c.beforeWrite = (code) => code == cmdDeviceQuery ? gate.future : Future<void>.value();
        final open = _Result(c.open());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
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

    testWidgets('dispose after manual disconnect retains held connect and time writer until completion', (tester) async {
      await _withBle(tester, (c) async {
        final gate = c.gate();
        c.beforeWrite = (code) => code == cmdSetDeviceTime ? gate.future : Future<void>.value();
        final open = _Result(c.open());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
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

    testWidgets('closed guarded call creates no new setup lease', (tester) async {
      await _withBle(tester, (c) async {
        c.dispose();
        c.setReconnectContextForTest(transport: MeshCoreTransportType.bluetooth, offlineMode: true);
        final revision = c.backgroundWorkSnapshot.revision;
        await c.open();
        expect(c.backgroundWorkSnapshot.revision, revision);
        expect(c.ble.opens, 0);
        _expectWork(c, 0);
      });
    }, timeout: timeout);
  }, skip: !PlatformInfo.isWindows);
}
