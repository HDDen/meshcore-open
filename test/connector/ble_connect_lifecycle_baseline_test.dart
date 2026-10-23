import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/connector/meshcore_uuids.dart';
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
    await c.disconnect(manual: true);
    await tester.pump(const Duration(seconds: 7));
    c.resetConnectionHandshakeForTest();
    c.dispose();
    await c.ble.states.close();
    await c.ble.rx.values.close();
    await c.ble.tx.values.close();
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const timeout = Timeout(Duration(seconds: 30));
  group('Windows BLE plugin baseline', () {
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

    testWidgets('baseline: pending scan prevents physical connect', (tester) async {
      await _withBle(tester, (c) async {
        final gate = c.gate();
        c.scanning = gate.future;
        final open = _Result(c.open());
        await tester.pump();
        expect(c.ble.opens, 0);
        expect(open.completed, isFalse);
        gate.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
        expect(open.completed, isTrue);
        expect(open.error, isNull);
      });
    }, timeout: timeout);

    testWidgets('baseline: held device connect precedes discovery and handshake', (tester) async {
      await _withBle(tester, (c) async {
        final gate = c.gate();
        c.ble.opening = gate.future;
        final open = _Result(c.open());
        await tester.pump();
        expect(c.state, MeshCoreConnectionState.connecting);
        expect(c.ble.discoveries, 0);
        expect(c.commands, isEmpty);
        expect(c.ble.requestedTimeout, const Duration(seconds: 15));
        expect(c.ble.requestedMtu, isNull);
        expect(c.ble.requestedLicense, License.nonprofit);
        gate.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
        expect(open.completed, isTrue);
        expect(open.error, isNull);
      });
    }, timeout: timeout);

    testWidgets('baseline: held discovery precedes CCCD and frames', (tester) async {
      await _withBle(tester, (c) async {
        final gate = c.gate();
        c.ble.discovery = gate.future;
        final open = _Result(c.open());
        await tester.pump();
        expect(c.ble.tx.enables, 0);
        expect(c.commands, isEmpty);
        gate.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
        expect(open.completed, isTrue);
        expect(open.error, isNull);
      });
    }, timeout: timeout);

    testWidgets('baseline: Windows waits 750 ms before CCCD', (tester) async {
      await _withBle(tester, (c) async {
        final open = _Result(c.open());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 749));
        expect(c.ble.tx.enables, 0);
        await tester.pump(const Duration(milliseconds: 1));
        expect(c.ble.tx.enables, 1);
        expect(open.completed, isTrue);
        expect(open.error, isNull);
      });
    }, timeout: timeout);

    testWidgets('baseline: CCCD waits before connected and receives an early SELF_INFO', (tester) async {
      await _withBle(tester, (c) async {
        final gate = c.gate();
        c.ble.tx.enabling = gate.future;
        final open = _Result(c.open());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
        expect(c.state, MeshCoreConnectionState.connecting);
        expect(c.commands, isEmpty);
        expect(c.ble.tx.values.hasListener, isTrue);
        gate.complete();
        await tester.pump();
        expect(open.completed, isTrue);
        expect(open.error, isNull);
        expect(c.hasCompletedSelfInfoHandshake, isTrue);
      });
    }, timeout: timeout);

    testWidgets('baseline: connected precedes the late SELF_INFO result', (tester) async {
      await _withBle(tester, (c) async {
        c.replyAtAppStart = null;
        final open = _Result(c.open());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
        expect(c.state, MeshCoreConnectionState.connected);
        expect(c.hasCompletedSelfInfoHandshake, isFalse);
        expect(open.completed, isFalse);
        c.selfInfo();
        await tester.pump(const Duration(milliseconds: 50));
        expect(open.completed, isTrue);
        expect(open.error, isNull);
      });
    }, timeout: timeout);

    testWidgets('baseline: two missing SELF_INFO windows still return without error', (tester) async {
      await _withBle(tester, (c) async {
        c.replyAtAppStart = null;
        final open = _Result(c.open());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
        await tester.pump(const Duration(seconds: 3));
        expect(c.commands.where((code) => code == cmdDeviceQuery).length, 2);
        expect(open.completed, isFalse);
        await tester.pump(const Duration(seconds: 3));
        expect(open.completed, isTrue);
        expect(open.error, isNull);
        expect(c.state, MeshCoreConnectionState.connected);
        expect(c.hasCompletedSelfInfoHandshake, isFalse);
      });
    }, timeout: timeout);

    testWidgets('baseline: time writer is part of the complete connect Future', (tester) async {
      await _withBle(tester, (c) async {
        final gate = c.gate();
        c.beforeWrite = (code) => code == cmdSetDeviceTime ? gate.future : Future<void>.value();
        final open = _Result(c.open());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
        expect(c.hasCompletedSelfInfoHandshake, isTrue);
        expect(open.completed, isFalse);
        gate.complete();
        await tester.pump();
        expect(open.completed, isTrue);
        expect(open.error, isNull);
      });
    }, timeout: timeout);

    for (final missing in ['service', 'characteristic']) {
      testWidgets('baseline: missing $missing tears down and propagates the error', (tester) async {
        await _withBle(tester, (c) async {
          c.ble.missingService = missing == 'service';
          c.ble.missingTx = missing == 'characteristic';
          final open = _Result(c.open());
          await tester.pump();
          expect(open.completed, isTrue);
          expect(open.error, isA<Exception>());
          expect(c.state, MeshCoreConnectionState.disconnected);
          expect(c.ble.closes, 1);
        });
      }, timeout: timeout);
    }

    testWidgets('baseline: fast failure cleans stale link and retries after 500 ms', (tester) async {
      await _withBle(tester, (c) async {
        c.ble.failures.add(StateError('synthetic fast failure'));
        final open = _Result(c.open());
        await tester.pump();
        expect(c.ble.opens, 1);
        expect(c.ble.closes, 1);
        await tester.pump(const Duration(milliseconds: 499));
        expect(c.ble.opens, 1);
        await tester.pump(const Duration(milliseconds: 1));
        expect(c.ble.opens, 2);
        await tester.pump(const Duration(milliseconds: 750));
        expect(open.completed, isTrue);
        expect(open.error, isNull);
      });
    }, timeout: timeout);

    testWidgets('baseline: stale connected device is disconnected before the new attempt', (tester) async {
      await _withBle(tester, (c) async {
        c.ble.connected = true;
        final open = _Result(c.open());
        await tester.pump();
        expect(c.ble.closes, 1);
        expect(c.ble.opens, 1);
        await tester.pump(const Duration(milliseconds: 750));
        expect(open.completed, isTrue);
        expect(open.error, isNull);
      });
    }, timeout: timeout);

    testWidgets('baseline: CCCD retry waits one second after the first failure', (tester) async {
      await _withBle(tester, (c) async {
        c.ble.tx.notifyFailures = 1;
        final open = _Result(c.open());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
        expect(c.ble.tx.enables, 1);
        await tester.pump(const Duration(milliseconds: 999));
        expect(c.ble.tx.enables, 1);
        await tester.pump(const Duration(milliseconds: 1));
        expect(c.ble.tx.enables, 2);
        expect(open.completed, isTrue);
        expect(open.error, isNull);
      });
    }, timeout: timeout);

    testWidgets('baseline: three CCCD failures tear down after separate retry delays', (tester) async {
      await _withBle(tester, (c) async {
        c.ble.tx.notifyFailures = 3;
        final open = _Result(c.open());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
        await tester.pump(const Duration(seconds: 1));
        expect(c.ble.tx.enables, 2);
        expect(open.completed, isFalse);
        await tester.pump(const Duration(seconds: 2));
        expect(c.ble.tx.enables, 3);
        expect(open.completed, isTrue);
        expect(open.error.toString(), contains('synthetic CCCD failure'));
        expect(c.state, MeshCoreConnectionState.disconnected);
      });
    }, timeout: timeout);

    testWidgets('baseline: timeout-text failure skips the immediate retry', (tester) async {
      await _withBle(tester, (c) async {
        final error = StateError('synthetic timed out');
        c.ble.failures.add(error);
        final open = _Result(c.open());
        await tester.pump();
        expect(open.completed, isTrue);
        expect(open.error, same(error));
        expect(c.ble.opens, 1);
        expect(c.state, MeshCoreConnectionState.disconnected);
      });
    }, timeout: timeout);

    for (final guard in ['connecting', 'connected', 'offline']) {
      testWidgets('baseline: $guard prevents a new BLE attempt', (tester) async {
        await _withBle(tester, (c) async {
          c.setReconnectContextForTest(
            transport: MeshCoreTransportType.bluetooth,
            state: guard == 'connecting' ? MeshCoreConnectionState.connecting
                : guard == 'connected' ? MeshCoreConnectionState.connected : MeshCoreConnectionState.disconnected,
            offlineMode: guard == 'offline',
          );
          await c.open();
          expect(c.ble.opens, 0);
          expect(c.scansStopped, 0);
          c.setReconnectContextForTest(transport: MeshCoreTransportType.bluetooth);
        });
      }, timeout: timeout);
    }

    testWidgets('baseline: manual cancellation keeps a late device error from tearing down again', (tester) async {
      await _withBle(tester, (c) async {
        final gate = c.gate();
        c.ble.opening = gate.future;
        final error = StateError('synthetic timed out after cancel');
        final open = _Result(c.open());
        await tester.pump();
        await c.disconnect(manual: true);
        final closes = c.ble.closes;
        gate.completeError(error);
        await tester.pump();
        expect(open.completed, isTrue);
        expect(open.error, same(error));
        expect(c.ble.closes, closes);
        expect(c.wasManuallyDisconnected, isTrue);
        expect(c.isAutoReconnectScheduled, isFalse);
      });
    }, timeout: timeout);

    testWidgets('baseline: caller timeout leaves device connect and handshake running', (tester) async {
      await _withBle(tester, (c) async {
        final gate = c.gate();
        c.ble.opening = gate.future;
        final caller = _Result(c.open().timeout(const Duration(milliseconds: 1)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        expect(caller.error, isA<TimeoutException>());
        gate.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
        expect(c.hasCompletedSelfInfoHandshake, isTrue);
        expect(c.ble.opens, 1);
      });
    }, timeout: timeout);
  }, skip: !PlatformInfo.isWindows);
}
