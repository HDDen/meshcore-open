import 'dart:async';

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/services/ble_debug_log_service.dart';

// Контракт установленного плагина до привязки к энергопрофилям.
// Один fake на весь файл: FlutterBluePlus хранит статические подписки.
// Нативного Bluetooth, сканирования и реальных кадров здесь нет.
final class _LogPlatform extends FlutterBluePlusPlatform {
  final requests = <(LogLevel, bool)>[];
  final adapterEvents =
      StreamController<BmBluetoothAdapterState>.broadcast(sync: true);
  Completer<void>? entered;
  Completer<bool>? pending;
  Object? error;
  bool result = true;

  @override
  Stream<BmBluetoothAdapterState> get onAdapterStateChanged =>
      adapterEvents.stream;

  @override
  Future<bool> setLogLevel(BmSetLogLevelRequest request) {
    requests.add((request.logLevel, request.logColor));
    final signal = entered;
    entered = null;
    signal?.complete();
    final failure = error;
    error = null;
    if (failure != null) {
      return Future<bool>.error(failure);
    }
    return pending?.future ?? Future<bool>.value(result);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _LogPlatform platform;
  FlutterBluePlusPlatform? originalPlatform;
  late LogLevel initialLevel;
  late bool initiallyScanning;

  setUpAll(() async {
    initialLevel = FlutterBluePlus.logLevel;
    initiallyScanning = FlutterBluePlus.isScanningNow;
    try {
      originalPlatform = FlutterBluePlusPlatform.instance;
    } on UnsupportedError {
      // На тестовом хосте регистрация нативного плагина может отсутствовать.
    }
    platform = _LogPlatform();
    FlutterBluePlusPlatform.instance = platform;
    await FlutterBluePlus.setLogLevel(initialLevel);
    platform.requests.clear();
  });

  tearDown(() async {
    final pending = platform.pending;
    if (pending != null && !pending.isCompleted) {
      pending.complete(true);
    }
    platform.pending = null;
    platform.entered = null;
    platform.error = null;
    platform.result = true;
    await FlutterBluePlus.setLogLevel(initialLevel);
    platform.requests.clear();
  });

  tearDownAll(() async {
    final original = originalPlatform;
    if (original != null) {
      FlutterBluePlusPlatform.instance = original;
    }
    await platform.adapterEvents.close();
  });

  test('baseline: plugin starts at debug without scanning', () {
    expect(initialLevel, LogLevel.debug);
    expect(initiallyScanning, isFalse);
    expect(FlutterBluePlus.isScanningNow, isFalse);
    expect(platform.requests, isEmpty);
  });

  test('baseline: public log setter forwards levels and color unchanged',
      () async {
    await FlutterBluePlus.setLogLevel(LogLevel.warning, color: false);
    expect(FlutterBluePlus.logLevel, LogLevel.warning);
    await FlutterBluePlus.setLogLevel(LogLevel.error);
    expect(FlutterBluePlus.logLevel, LogLevel.error);
    await FlutterBluePlus.setLogLevel(LogLevel.debug);
    expect(FlutterBluePlus.logLevel, LogLevel.debug);
    expect(platform.requests, [
      (LogLevel.warning, false),
      (LogLevel.error, true),
      (LogLevel.debug, true),
    ]);
    expect(FlutterBluePlus.isScanningNow, isFalse);
  });

  test('baseline: Dart level changes early while platform calls stay ordered',
      () async {
    final entered = Completer<void>();
    final pending = Completer<bool>();
    platform.entered = entered;
    platform.pending = pending;
    var completed = false;
    final first = FlutterBluePlus.setLogLevel(LogLevel.warning)
        .then((_) => completed = true);
    expect(FlutterBluePlus.logLevel, LogLevel.warning);
    try {
      await entered.future;
      expect(completed, isFalse);
      expect(platform.requests, [(LogLevel.warning, true)]);

      final second = FlutterBluePlus.setLogLevel(LogLevel.debug);
      expect(FlutterBluePlus.logLevel, LogLevel.debug);
      // Метод второй операции ещё не вошёл в платформу: первая держит mutex.
      expect(platform.requests, [(LogLevel.warning, true)]);
      platform.pending = null;
      pending.complete(true);
      await first;
      await second;
      expect(completed, isTrue);
      expect(platform.requests, [
        (LogLevel.warning, true),
        (LogLevel.debug, true),
      ]);
    } finally {
      platform.pending = null;
      if (!pending.isCompleted) {
        pending.complete(true);
      }
      await first;
    }
  });

  test('baseline: platform failure leaves Dart level changed and permits retry',
      () async {
    final failure = PlatformException(code: 'synthetic-log-failure');
    platform.error = failure;
    await expectLater(
      FlutterBluePlus.setLogLevel(LogLevel.warning),
      throwsA(same(failure)),
    );
    expect(FlutterBluePlus.logLevel, LogLevel.warning);
    await FlutterBluePlus.setLogLevel(LogLevel.warning);
    expect(platform.requests, [
      (LogLevel.warning, true),
      (LogLevel.warning, true),
    ]);
  });

  test('baseline: public setter does not expose a false platform result',
      () async {
    platform.result = false;
    await FlutterBluePlus.setLogLevel(LogLevel.warning);
    expect(FlutterBluePlus.logLevel, LogLevel.warning);
    expect(platform.requests, [(LogLevel.warning, true)]);
    // Успех Future<void> не доказывает применение уровня нативной стороной.
  });

  test('baseline: quieter logs preserve adapter state event handling', () async {
    await FlutterBluePlus.setLogLevel(LogLevel.warning);
    platform.adapterEvents.add(
      BmBluetoothAdapterState(adapterState: BmAdapterStateEnum.off),
    );
    expect(FlutterBluePlus.adapterStateNow, BluetoothAdapterState.off);
    await FlutterBluePlus.setLogLevel(LogLevel.error);
    platform.adapterEvents.add(
      BmBluetoothAdapterState(adapterState: BmAdapterStateEnum.on),
    );
    expect(FlutterBluePlus.adapterStateNow, BluetoothAdapterState.on);
    expect(FlutterBluePlus.isScanningNow, isFalse);
  });

  test('baseline: plugin log level does not change the app frame journal',
      () async {
    for (final deferred in [false, true]) {
      final log = BleDebugLogService()..setDeferDescriptions(deferred);
      try {
        var notifications = 0;
        log.addListener(() => notifications++);
        for (final level in [LogLevel.debug, LogLevel.warning]) {
          await FlutterBluePlus.setLogLevel(level);
          expect(notifications, log.entries.length);
          final frame = Uint8List.fromList([pushCodeLogRxData, 40, 176, 1, 2]);
          log.logFrame(frame, outgoing: false);
          frame[3] = 99;
          expect(log.entries.last.payload, [pushCodeLogRxData, 40, 176, 1, 2]);
          expect(log.rawLogRxEntries.last.payload, [1, 2]);
          expect(log.entries.last.descriptionResolvedForTest, !deferred);
        }
        expect(log.entries, hasLength(2));
        expect(log.rawLogRxEntries, hasLength(2));
        expect(notifications, 2);
        expect(log.entries[0].description, log.entries[1].description);
      } finally {
        log.dispose();
      }
    }
  });
}
