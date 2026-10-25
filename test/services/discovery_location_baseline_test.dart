import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/map_location_helper.dart';
import 'package:meshcore_open/helpers/zero_hop_device_discovery.dart';
import 'package:meshcore_open/services/wardrive_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Исходные девять контрактов сохранены; отдельная группа ниже проверяет
// исправление утечки разового запроса и позднего запуска GPS после stop.
class _Subscription<T> extends Fake implements StreamSubscription<T> {
  _Subscription(this.detach, this.waitForCancel);
  final void Function() detach;
  final Future<void>? waitForCancel;
  bool cancelled = false;

  @override
  Future<void> cancel() async {
    if (cancelled) return;
    cancelled = true;
    detach();
    if (waitForCancel != null) await waitForCancel;
  }
}

// broadcast.cancel() может вернуть root-Zone Future._nullFuture, который
// не завершается под FakeAsync. Как в BLE baseline, cancel принадлежит
// зоне widget-теста. Несколько слушателей допустимы; каждый отменяется отдельно.
class _Events<T> extends Stream<T> {
  _Events({this.onCancel, this.waitForCancel});
  final void Function()? onCancel;
  final Future<void>? waitForCancel;
  final _listeners = <Object, void Function(T)?>{};
  bool closed = false;

  bool get hasListener => _listeners.isNotEmpty;

  @override
  StreamSubscription<T> listen(
    void Function(T)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (closed) throw StateError('synthetic stream closed');
    final token = Object();
    _listeners[token] = onData;
    return _Subscription<T>(() {
      if (_listeners.containsKey(token)) {
        _listeners.remove(token);
        onCancel?.call();
      }
    }, waitForCancel);
  }

  void add(T event) {
    if (closed) throw StateError('synthetic stream closed');
    for (final listener in List.of(_listeners.values)) {
      listener?.call(event);
    }
  }

  Future<void> close() async {
    closed = true;
    _listeners.clear();
  }
}

class _Location extends GeolocatorPlatform {
  final streams = <_Events<Position>>[];
  final settings = <LocationSettings?>[];
  int singleRequests = 0;
  int cancelled = 0;
  bool available = true;
  Completer<LocationPermission>? permissionGate;
  Completer<Position>? positionGate;
  Object? positionError;
  Completer<void>? cancellationGate;

  Position get fix => Position(
    longitude: 38,
    latitude: 45,
    timestamp: DateTime.now(),
    accuracy: 3,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  @override
  Future<bool> isLocationServiceEnabled() async => available;

  @override
  Future<LocationPermission> checkPermission() async => permissionGate == null
      ? LocationPermission.whileInUse
      : await permissionGate!.future;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    singleRequests++;
    settings.add(locationSettings);
    final error = positionError;
    if (error != null) throw error;
    final gate = positionGate;
    if (gate != null) return gate.future;
    return fix;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    settings.add(locationSettings);
    final stream = _Events<Position>(
      onCancel: () { cancelled++; },
      waitForCancel: cancellationGate?.future,
    );
    streams.add(stream);
    return stream;
  }
}

class _Connector extends Fake implements MeshCoreConnector {
  final frames = _Events<Uint8List>();
  int writes = 0;
  bool failWrite = false;
  int nodeLocationRequests = 0;

  @override
  bool get isConnected => true;

  @override
  Stream<Uint8List> get receivedFrames => frames;

  @override
  Future<void> sendFrame(
    Uint8List frame, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {
    writes++;
    if (failWrite) throw StateError('synthetic write failure');
  }

  @override
  Future<({double latitude, double longitude})?> refreshSelfLocation({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    nodeLocationRequests++;
    return (latitude: 46.0, longitude: 39.0);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GeolocatorPlatform previous;
  late _Location location;
  late _Connector connector;
  WardriveService? wardrive;

  setUp(() async {
    previous = GeolocatorPlatform.instance;
    location = _Location();
    GeolocatorPlatform.instance = location;
    connector = _Connector();
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(() async {
    wardrive?.dispose();
    wardrive = null;
    await connector.frames.close();
    for (final stream in location.streams) {
      await stream.close();
    }
    GeolocatorPlatform.instance = previous;
    PrefsManager.reset();
  });

  Future<WardriveService> service(WidgetTester tester) async {
    final value = WardriveService(connector);
    wardrive = value;
    // Завершить первоначальную загрузку preferences до dispose.
    await tester.pump();
    return value;
  }

  Future<void> finishService(WidgetTester tester) async {
    wardrive?.dispose();
    wardrive = null;
    await tester.pump();
  }

  for (final ending in ['timeout', 'cancel', 'write error']) {
    testWidgets('contacts discovery uses no GPS: $ending', (tester) async {
      // Даже сохранённая опция wardrive не должна влиять на поиск контактов.
      await PrefsManager.instance.setBool(
        'wardrive_continuous_gps_enabled_v1', true,
      );
      await service(tester);
      connector.failWrite = ending == 'write error';
      final discovery = ZeroHopDeviceDiscovery(connector);
      final operation = discovery.run();
      if (connector.failWrite) {
        await expectLater(operation, throwsStateError);
      } else {
        var completed = false;
        unawaited(operation.then((_) { completed = true; }));
        await tester.pump();
        if (ending == 'cancel') discovery.cancel();
        await tester.pump(
          ending == 'timeout' ? ZeroHopDeviceDiscovery.responseWindow : Duration.zero,
        );
        expect(completed, isTrue, reason: 'discovery must finish after $ending');
        await operation;
      }
      expect(connector.writes, 1);
      expect(connector.frames.hasListener, isFalse);
      expect(location.singleRequests, 0);
      expect(location.streams, isEmpty);
      await finishService(tester);
    });
  }

  for (final failWrite in [false, true]) {
    testWidgets('one-shot map discovery, continuous off, write error=$failWrite',
        (tester) async {
      final value = await service(tester);
      connector.failWrite = failWrite;
      final operation = value.sendZeroHopDiscoveryRequest(startWardrive: false);
      if (failWrite) {
        await expectLater(operation, throwsStateError);
      } else {
        await operation;
        await tester.pump(value.autoDiscoveryInterval);
        expect(value.isAwaitingDiscoveryResponse, isFalse);
      }
      expect(value.isRunning, isFalse);
      expect(location.singleRequests, 1);
      expect(location.settings.single?.accuracy, LocationAccuracy.high);
      expect(location.settings.single?.timeLimit, const Duration(seconds: 15));
      expect(location.streams, isEmpty);
      await finishService(tester);
    });
  }

  testWidgets('map discovery can fall back to node coordinates without phone GPS',
      (tester) async {
    final value = await service(tester);
    location.available = false;
    await value.sendZeroHopDiscoveryRequest(startWardrive: false);
    expect(connector.nodeLocationRequests, 1);
    expect(connector.writes, 1);
    expect(location.singleRequests, 0);
    expect(location.streams, isEmpty);
    expect(value.usesPhoneLocationForDisplay, isFalse);
    await finishService(tester);
  });

  for (final finish in ['stop', 'toggle off', 'dispose']) {
    testWidgets('active wardrive releases continuous GPS on $finish',
        (tester) async {
      final value = await service(tester);
      await value.setContinuousGpsEnabled(true);
      expect(location.streams, isEmpty);
      value.start();
      await tester.pump();
      expect(location.streams, hasLength(1));
      expect(location.settings.single?.distanceFilter, 0);
      location.streams.single.add(location.fix);
      expect(value.lastPhoneLatitude, 45);
      if (finish == 'stop') {
        value.stop();
      } else if (finish == 'toggle off') {
        await value.setContinuousGpsEnabled(false);
      } else {
        value.dispose();
        wardrive = null;
      }
      await tester.pump();
      expect(location.cancelled, 1);
      expect(location.streams.single.hasListener, isFalse);
      if (finish == 'toggle off') value.stop();
      await finishService(tester);
    });
  }

  group('GPS lifetime regressions', () {
    for (final outcome in ['success', 'write error', 'GPS timeout']) {
      testWidgets('one-shot with saved continuous=true: $outcome', (tester) async {
        await PrefsManager.instance.setBool(
          'wardrive_continuous_gps_enabled_v1', true,
        );
        final value = await service(tester);
        connector.failWrite = outcome == 'write error';
        if (outcome == 'GPS timeout') {
          location.positionError = TimeoutException('synthetic GPS timeout');
        }
        final operation = value.sendZeroHopDiscoveryRequest(startWardrive: false);
        if (connector.failWrite) {
          await expectLater(operation, throwsStateError);
        } else {
          await operation;
          await tester.pump(value.autoDiscoveryInterval);
        }
        expect(value.isRunning, isFalse);
        expect(location.singleRequests, 1);
        expect(location.streams, isEmpty);
        expect(connector.nodeLocationRequests, outcome == 'GPS timeout' ? 1 : 0);
        await finishService(tester);
      });
    }

    testWidgets('map phone position does not acquire continuous GPS outside wardrive',
        (tester) async {
      final value = await service(tester);
      await value.setContinuousGpsEnabled(true);
      final point = await MapLocationHelper.resolve(
        enabled: true, wardrive: value, connector: connector,
      );
      expect(point?.latitude, 45);
      expect(location.singleRequests, 1);
      expect(location.streams, isEmpty);
      await finishService(tester);
    });

    for (final ending in ['stop', 'toggle off', 'dispose']) {
      testWidgets('pending permission cannot attach GPS after $ending', (tester) async {
        final value = await service(tester);
        await value.setContinuousGpsEnabled(true);
        final gate = Completer<LocationPermission>();
        location.permissionGate = gate;
        value.start();
        await tester.pump();
        expect(location.streams, isEmpty);
        if (ending == 'stop') {
          value.stop();
        } else if (ending == 'toggle off') {
          await value.setContinuousGpsEnabled(false);
        } else {
          value.dispose();
          wardrive = null;
        }
        gate.complete(LocationPermission.whileInUse);
        await tester.pump();
        expect(location.streams, isEmpty);
        if (ending == 'toggle off') value.stop();
        await finishService(tester);
      });
    }

    testWidgets('concurrent location requests share pending stream startup', (tester) async {
      final value = await service(tester);
      await value.setContinuousGpsEnabled(true);
      final permission = Completer<LocationPermission>();
      location.permissionGate = permission;
      value.start();
      final first = value.requestPhoneLocation();
      final second = value.requestPhoneLocation();
      await tester.pump();
      permission.complete(LocationPermission.whileInUse);
      await tester.pump();
      expect(location.streams, hasLength(1));
      expect(await first, (latitude: 45.0, longitude: 38.0));
      expect(await second, (latitude: 45.0, longitude: 38.0));
      value.stop();
      await tester.pump();
      expect(location.cancelled, 1);
      await finishService(tester);
    });

    testWidgets('stop and restart while permission is pending owns one new stream',
        (tester) async {
      final value = await service(tester);
      await value.setContinuousGpsEnabled(true);
      final permission = Completer<LocationPermission>();
      location.permissionGate = permission;
      value.start();
      await tester.pump();
      value.stop();
      value.start();
      permission.complete(LocationPermission.whileInUse);
      await tester.pump();
      expect(location.streams, hasLength(1));
      value.stop();
      await tester.pump();
      expect(location.cancelled, 1);
      await finishService(tester);
    });

    testWidgets('one-shot completion preserves GPS owned by active wardrive',
        (tester) async {
      final value = await service(tester);
      await value.setContinuousGpsEnabled(true);
      value.start();
      await tester.pump();
      location.streams.single.add(location.fix);
      await value.sendZeroHopDiscoveryRequest(startWardrive: false);
      expect(value.isRunning, isTrue);
      expect(location.streams, hasLength(1));
      expect(location.streams.single.hasListener, isTrue);
      expect(location.singleRequests, 0);
      expect(location.cancelled, 0);
      value.stop();
      await tester.pump();
      expect(location.cancelled, 1);
      await finishService(tester);
    });

    testWidgets('restart waits for old native GPS cancellation', (tester) async {
      final value = await service(tester);
      await value.setContinuousGpsEnabled(true);
      final cancellation = Completer<void>();
      location.cancellationGate = cancellation;
      value.start();
      await tester.pump();
      expect(location.streams, hasLength(1));
      value.stop();
      value.start();
      await tester.pump();
      expect(location.cancelled, 1);
      expect(location.streams, hasLength(1));
      cancellation.complete();
      await tester.pump();
      expect(location.streams, hasLength(2));
      expect(location.streams.last.hasListener, isTrue);
      value.stop();
      await tester.pump();
      expect(location.cancelled, 2);
      await finishService(tester);
    });

    for (final ending in ['stop', 'dispose']) {
      testWidgets('late initial discovery GPS fix cannot start wardrive after $ending',
          (tester) async {
        final value = await service(tester);
        await value.setContinuousGpsEnabled(true);
        final fix = Completer<Position>();
        location.positionGate = fix;
        final operation = value.sendZeroHopDiscoveryRequest();
        await tester.pump();
        expect(location.singleRequests, 1);
        if (ending == 'stop') {
          value.stop();
        } else {
          value.dispose();
          wardrive = null;
        }
        fix.complete(location.fix);
        await tester.pump();
        await operation;
        expect(connector.writes, 0);
        expect(location.streams, isEmpty);
        expect(value.isRunning, isFalse);
        await finishService(tester);
      });
    }
  });
}
