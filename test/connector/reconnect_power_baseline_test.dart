import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/ios_presentation_guard.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../tool/simulate_reconnect_backoff.dart' as simulation;

const _deviceId = '00:00:00:00:00:01';
const _host = '192.0.2.1';
const _port = 5000;

// Настоящие scheduler/backoff/teardown, заменено только физическое подключение.
// Fake time проверяет Dart-таймеры, а не исполнение в фоне или расход батареи.
class _ReconnectConnector extends MeshCoreConnector {
  final attempts = <({MeshCoreTransportType transport, String target, bool automatic})>[];
  Completer<void>? heldAttempt;
  bool closed = false;

  Future<void> _failAttempt() async {
    final held = heldAttempt;
    if (held != null) {
      setConnectionStateForTest(MeshCoreConnectionState.connecting);
      await held.future;
    }
    throw StateError('synthetic connect failure');
  }

  @override
  Future<void> connect(
    BluetoothDevice device, {
    String? displayName,
    Future<String?> Function()? linuxPairingPinProvider,
    bool requestBatteryOptimizationExemption = true,
  }) async {
    attempts.add((transport: MeshCoreTransportType.bluetooth,
        target: device.remoteId.toString(), automatic: !requestBatteryOptimizationExemption));
    await _failAttempt();
  }

  @override
  Future<void> connectTcp({
    required String host,
    required int port,
    bool automaticReconnect = false,
  }) async {
    attempts.add((transport: MeshCoreTransportType.tcp,
        target: '$host:$port', automatic: automaticReconnect));
    await _failAttempt();
  }

  @override
  void dispose() {
    if (closed) {
      return;
    }
    closed = true;
    super.dispose();
  }
}

_ReconnectConnector _connector({
  List<_ReconnectConnector>? cleanup,
  MeshCoreTransportType? transport = MeshCoreTransportType.bluetooth,
  bool manual = false,
  bool offline = false,
  MeshCoreConnectionState state = MeshCoreConnectionState.disconnected,
}) {
  final connector = _ReconnectConnector();
  cleanup?.add(connector);
  addTearDown(connector.dispose);
  connector.setReconnectContextForTest(
    transport: transport, deviceId: _deviceId, tcpHost: _host, tcpPort: _port,
    manualDisconnect: manual, offlineMode: offline, state: state,
  );
  return connector;
}

void _reconnectWidgetTest(
  String description,
  Future<void> Function(WidgetTester, List<_ReconnectConnector>) body,
) {
  testWidgets(description, (tester) async {
    final connectors = <_ReconnectConnector>[];
    try {
      await body(tester, connectors);
    } finally {
      // Flutter проверяет fake timers до addTearDown: закрываем внутри callback.
      for (final connector in connectors.reversed) {
        connector.dispose();
        final held = connector.heldAttempt;
        if (held != null && !held.isCompleted) {
          held.complete();
        }
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    }
  });
}

Future<({_ReconnectConnector connector, AppSettingsService settings})> _powerConnector(
  WidgetTester tester,
  List<_ReconnectConnector> cleanup, {
  MeshCoreTransportType transport = MeshCoreTransportType.bluetooth,
  PowerSavingProfile profile = PowerSavingProfile.custom,
  int seconds = 180,
}) async {
  final settings = AppSettingsService();
  addTearDown(settings.dispose);
  await settings.setBackgroundReconnectIntervalSeconds(seconds);
  await settings.setPowerSavingProfile(profile);
  final connector = _connector(cleanup: cleanup, transport: transport);
  connector.setReconnectClockForTest(() => tester.binding.clock.now()
      .difference(DateTime.utc(2026)));
  connector.attachAppSettingsServiceForTest(settings);
  return (connector: connector, settings: settings);
}

void _consumeFastPrefix(_ReconnectConnector connector) {
  for (final milliseconds in [1000, 2000, 4000, 8000, 16000, 30000]) {
    expect(connector.nextReconnectDelayMsForTest(), milliseconds);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  test('legacy delay is 1/2/4/8/16/30 seconds and stays capped without a retry limit', () {
    final connector = _connector();
    final initial = List<int>.generate(8, (_) => connector.nextReconnectDelayMsForTest());
    expect(initial, [1000, 2000, 4000, 8000, 16000, 30000, 30000, 30000]);
    expect(initial, List<int>.generate(8, simulation.legacyReconnectDelayMs));
    for (var i = 0; i < 1000; i++) {
      expect(connector.nextReconnectDelayMsForTest(),
          simulation.legacyReconnectDelayMs(i + 8));
    }
    expect(connector.reconnectAttemptsForTest, 1008);
  });

  test('the proposed model keeps all six fast delays and the foreground/minimum baseline', () {
    for (var attempt = 0; attempt < 20; attempt++) {
      for (final seconds in [30, 60, 180, 600]) {
        expect(simulation.proposedReconnectDelayMs(attempt,
            background: false, backgroundIntervalSeconds: seconds),
            simulation.legacyReconnectDelayMs(attempt));
        expect(simulation.proposedReconnectDelayMs(attempt,
            background: true, backgroundIntervalSeconds: seconds),
            attempt < 6 ? simulation.legacyReconnectDelayMs(attempt) : seconds * 1000);
      }
    }
  });

  for (final transport in [MeshCoreTransportType.bluetooth, MeshCoreTransportType.tcp]) {
    _reconnectWidgetTest('real timer retries $transport with the legacy cadence and same target', (tester, cleanup) async {
      final connector = _connector(cleanup: cleanup, transport: transport);
      connector.scheduleReconnectForTest();
      expect(connector.attempts, isEmpty);
      for (final seconds in [1, 2, 4, 8, 16, 30, 30]) {
        final before = connector.attempts.length;
        await tester.pump(Duration(milliseconds: seconds * 1000 - 1));
        expect(connector.attempts, hasLength(before));
        await tester.pump(const Duration(milliseconds: 1));
        expect(connector.attempts, hasLength(before + 1));
        expect(connector.attempts.last, (
          transport: transport,
          target: transport == MeshCoreTransportType.bluetooth ? _deviceId : '$_host:$_port',
          automatic: true,
        ));
        expect(connector.isAutoReconnectScheduled, isTrue);
      }
    });
  }

  _reconnectWidgetTest('repeated scheduling joins the pending timer without consuming another delay', (tester, cleanup) async {
    final connector = _connector(cleanup: cleanup);
    connector.scheduleReconnectForTest();
    await tester.pump(const Duration(milliseconds: 400));
    connector.scheduleReconnectForTest();
    connector.scheduleReconnectForTest();
    expect(connector.reconnectAttemptsForTest, 1);
    await tester.pump(const Duration(milliseconds: 599));
    expect(connector.attempts, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(connector.attempts, hasLength(1));
    expect(connector.reconnectAttemptsForTest, 2);
  });

  for (final activity in [AppLifecycleState.resumed, AppLifecycleState.paused]) {
    _reconnectWidgetTest('legacy scheduler retains its cadence while app is $activity', (tester, cleanup) async {
      tester.binding.handleAppLifecycleStateChanged(activity);
      final connector = _connector(cleanup: cleanup);
      connector.scheduleReconnectForTest();
      await tester.pump(const Duration(seconds: 1));
      expect(connector.attempts, hasLength(1));
      expect(connector.isAutoReconnectScheduled, isTrue);
    });
  }

  _reconnectWidgetTest('missing identity or endpoint, USB, review, manual and offline never schedule', (tester, cleanup) async {
    final contexts = <({MeshCoreTransportType? transport, String? deviceId,
        String? host, int? port, bool manual, bool offline})>[
      (transport: null, deviceId: _deviceId, host: _host, port: _port, manual: false, offline: false),
      (transport: MeshCoreTransportType.bluetooth, deviceId: null, host: _host, port: _port, manual: false, offline: false),
      (transport: MeshCoreTransportType.tcp, deviceId: _deviceId, host: null, port: _port, manual: false, offline: false),
      (transport: MeshCoreTransportType.tcp, deviceId: _deviceId, host: _host, port: null, manual: false, offline: false),
      (transport: MeshCoreTransportType.usb, deviceId: _deviceId, host: _host, port: _port, manual: false, offline: false),
      (transport: MeshCoreTransportType.review, deviceId: _deviceId, host: _host, port: _port, manual: false, offline: false),
      (transport: MeshCoreTransportType.bluetooth, deviceId: _deviceId, host: _host, port: _port, manual: true, offline: false),
      (transport: MeshCoreTransportType.tcp, deviceId: _deviceId, host: _host, port: _port, manual: false, offline: true),
    ];
    for (final context in contexts) {
      final connector = _connector(cleanup: cleanup);
      connector.setReconnectContextForTest(
        transport: context.transport, deviceId: context.deviceId,
        tcpHost: context.host, tcpPort: context.port,
        manualDisconnect: context.manual, offlineMode: context.offline,
      );
      connector.scheduleReconnectForTest();
      expect(connector.reconnectTimerActiveForTest, isFalse);
      expect(connector.reconnectAttemptsForTest, 0);
      await tester.pump(const Duration(minutes: 1));
      expect(connector.attempts, isEmpty);
      connector.dispose();
    }
  });

  for (final state in [MeshCoreConnectionState.connecting, MeshCoreConnectionState.connected]) {
    _reconnectWidgetTest('timer expiry does not start a parallel attempt while $state', (tester, cleanup) async {
      final connector = _connector(cleanup: cleanup, state: state);
      connector.scheduleReconnectForTest();
      await tester.pump(const Duration(seconds: 1));
      expect(connector.attempts, isEmpty);
      expect(connector.reconnectTimerActiveForTest, isFalse);
    });
  }

  _reconnectWidgetTest('a pending timer cannot reconnect a replaced transport', (tester, cleanup) async {
    final connector = _connector(cleanup: cleanup);
    connector.scheduleReconnectForTest();
    connector.setReconnectContextForTest(
      transport: MeshCoreTransportType.tcp, tcpHost: _host, tcpPort: _port,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(connector.attempts, isEmpty);
    expect(connector.reconnectTimerActiveForTest, isFalse);
  });

  _reconnectWidgetTest('manual disconnect cancels the real timer and resets the backoff', (tester, cleanup) async {
    final connector = _connector(cleanup: cleanup);
    connector.scheduleReconnectForTest();
    expect(connector.reconnectTimerActiveForTest, isTrue);
    await connector.disconnect(manual: true);
    expect(connector.wasManuallyDisconnected, isTrue);
    expect(connector.reconnectTimerActiveForTest, isFalse);
    expect(connector.reconnectAttemptsForTest, 0);
    await tester.pump(const Duration(minutes: 2));
    expect(connector.attempts, isEmpty);
    expect(connector.nextReconnectDelayMsForTest(), 1000);
  });

  _reconnectWidgetTest('a late failure after manual disconnect cannot restart the timer', (tester, cleanup) async {
    final connector = _connector(cleanup: cleanup);
    final held = Completer<void>();
    connector.heldAttempt = held;
    connector.scheduleReconnectForTest();
    await tester.pump(const Duration(seconds: 1));
    expect(connector.attempts, hasLength(1));
    expect(connector.state, MeshCoreConnectionState.connecting);
    await connector.disconnect(manual: true);
    held.complete();
    await tester.pump();
    await tester.pump(const Duration(minutes: 2));
    expect(connector.attempts, hasLength(1));
    expect(connector.reconnectTimerActiveForTest, isFalse);
  });

  _reconnectWidgetTest('dispose cancels the pending timer and forbids new scheduling', (tester, cleanup) async {
    final connector = _connector(cleanup: cleanup);
    connector.scheduleReconnectForTest();
    connector.dispose();
    expect(connector.reconnectTimerActiveForTest, isFalse);
    connector.scheduleReconnectForTest();
    await tester.pump(const Duration(hours: 1));
    expect(connector.attempts, isEmpty);
    expect(connector.reconnectTimerActiveForTest, isFalse);
  });

  group('power saving regressions', () {
    _reconnectWidgetTest('custom minimum keeps every baseline delay in the background', (tester, cleanup) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final h = await _powerConnector(tester, cleanup, seconds: 30);
      for (var attempt = 0; attempt < 1008; attempt++) {
        expect(h.connector.nextReconnectDelayMsForTest(), simulation.legacyReconnectDelayMs(attempt));
      }
    });

    for (final transport in [MeshCoreTransportType.bluetooth, MeshCoreTransportType.tcp]) {
      _reconnectWidgetTest('$transport keeps six fast pauses then uses the background pause', (tester, cleanup) async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        final h = await _powerConnector(tester, cleanup, transport: transport);
        h.connector.scheduleReconnectForTest();
        for (final seconds in [1, 2, 4, 8, 16, 30, 180]) {
          final count = h.connector.attempts.length;
          await tester.pump(Duration(milliseconds: seconds * 1000 - 1));
          expect(h.connector.attempts, hasLength(count));
          await tester.pump(const Duration(milliseconds: 1));
          expect(h.connector.attempts, hasLength(count + 1));
          expect(h.connector.attempts.last.automatic, isTrue);
          expect(h.connector.attempts.last.target,
              transport == MeshCoreTransportType.bluetooth ? _deviceId : '$_host:$_port');
        }
      });
    }

    for (final entry in {
      PowerSavingProfile.disabled: 30,
      PowerSavingProfile.balanced: 60,
      PowerSavingProfile.economical: 180,
      PowerSavingProfile.maximum: 600,
      PowerSavingProfile.custom: 90,
    }.entries) {
      _reconnectWidgetTest('${entry.key} selects its background interval and retains foreground baseline', (tester, cleanup) async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        final h = await _powerConnector(tester, cleanup, profile: entry.key, seconds: 90);
        _consumeFastPrefix(h.connector);
        expect(h.connector.nextReconnectDelayMsForTest(), entry.value * 1000);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        expect(h.connector.nextReconnectDelayMsForTest(), 30000);
      });
    }

    _reconnectWidgetTest('returning to foreground retains elapsed time and does not spend another attempt', (tester, cleanup) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final h = await _powerConnector(tester, cleanup, seconds: 600);
      _consumeFastPrefix(h.connector);
      h.connector.scheduleReconnectForTest();
      await tester.pump(const Duration(seconds: 10));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(h.connector.reconnectAttemptsForTest, 7);
      await tester.pump(const Duration(milliseconds: 19999));
      expect(h.connector.attempts, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.connector.attempts, hasLength(1));
      expect(h.connector.reconnectAttemptsForTest, 8);
      await tester.pump(const Duration(seconds: 30));
      expect(h.connector.attempts, hasLength(2));
    });

    _reconnectWidgetTest('entering background extends only the late phase from the original anchor', (tester, cleanup) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final h = await _powerConnector(tester, cleanup);
      _consumeFastPrefix(h.connector);
      h.connector.scheduleReconnectForTest();
      await tester.pump(const Duration(seconds: 10));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(h.connector.reconnectAttemptsForTest, 7);
      await tester.pump(const Duration(milliseconds: 169999));
      expect(h.connector.attempts, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.connector.attempts, hasLength(1));
    });

    _reconnectWidgetTest('activity changes cannot extend a fast pause or consume another delay', (tester, cleanup) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final h = await _powerConnector(tester, cleanup, seconds: 600);
      h.connector.scheduleReconnectForTest();
      await tester.pump(const Duration(milliseconds: 400));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await h.settings.setPowerSavingProfile(PowerSavingProfile.economical);
      h.connector.scheduleReconnectForTest();
      expect(h.connector.reconnectAttemptsForTest, 1);
      await tester.pump(const Duration(milliseconds: 599));
      expect(h.connector.attempts, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.connector.attempts, hasLength(1));
      expect(h.connector.reconnectAttemptsForTest, 2);
    });

    _reconnectWidgetTest('long waits still reject USB, review and an old transport callback', (tester, cleanup) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      for (final transport in [MeshCoreTransportType.usb, MeshCoreTransportType.review]) {
        final h = await _powerConnector(tester, cleanup, transport: transport);
        _consumeFastPrefix(h.connector);
        h.connector.scheduleReconnectForTest();
        expect(h.connector.reconnectTimerActiveForTest, isFalse);
        expect(h.connector.reconnectAttemptsForTest, 6);
        h.connector.dispose();
      }
      final h = await _powerConnector(tester, cleanup);
      _consumeFastPrefix(h.connector);
      h.connector.scheduleReconnectForTest();
      h.connector.setReconnectContextForTest(
        transport: MeshCoreTransportType.tcp, tcpHost: _host, tcpPort: _port,
      );
      await tester.pump(const Duration(seconds: 180));
      expect(h.connector.attempts, isEmpty);
      expect(h.connector.reconnectTimerActiveForTest, isFalse);
    });

    _reconnectWidgetTest('profile, custom and unrelated settings preserve the wait anchor', (tester, cleanup) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final h = await _powerConnector(tester, cleanup, seconds: 600);
      _consumeFastPrefix(h.connector);
      h.connector.scheduleReconnectForTest();
      await tester.pump(const Duration(seconds: 10));
      await h.settings.setPowerSavingProfile(PowerSavingProfile.economical);
      await tester.pump(const Duration(seconds: 10));
      await h.settings.setPowerSavingProfile(PowerSavingProfile.balanced);
      await h.settings.setBackgroundReconnectIntervalSeconds(90);
      await h.settings.setHideRadioStatsButton(true);
      expect(h.connector.reconnectAttemptsForTest, 7);
      await tester.pump(const Duration(milliseconds: 39999));
      expect(h.connector.attempts, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.connector.attempts, hasLength(1));
      await h.settings.setPowerSavingProfile(PowerSavingProfile.custom);
      expect(h.settings.settings.powerSaving.custom.backgroundReconnectIntervalSeconds, 90);
      await tester.pump(const Duration(milliseconds: 89999));
      expect(h.connector.attempts, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.connector.attempts, hasLength(2));
    });

    _reconnectWidgetTest('Off releases an overdue background wait asynchronously and custom is retained', (tester, cleanup) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final h = await _powerConnector(tester, cleanup, seconds: 600);
      _consumeFastPrefix(h.connector);
      h.connector.scheduleReconnectForTest();
      await tester.pump(const Duration(seconds: 40));
      await h.settings.setPowerSavingProfile(PowerSavingProfile.disabled);
      expect(h.connector.attempts, isEmpty);
      expect(h.connector.reconnectAttemptsForTest, 7);
      // pump() без длительности не исполняет Timer.zero на fake clock.
      await tester.pump(Duration.zero);
      expect(h.connector.attempts, hasLength(1));
      expect(h.settings.settings.powerSaving.custom.backgroundReconnectIntervalSeconds, 600);
    });

    _reconnectWidgetTest('native inactivity uses background timing while Flutter remains resumed', (tester, cleanup) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final h = await _powerConnector(tester, cleanup, seconds: 600);
      _consumeFastPrefix(h.connector);
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(IosPresentationBridge.platformChannel,
          (call) async => call.method == 'watch' ? {
            'schema': 1, 'enabled': false, 'active': false, 'revision': 0,
          } : null);
      final bridge = IosPresentationBridge(onPresentationChanged: (_) {});
      try {
        await bridge.start();
        expect(tester.binding.lifecycleState, AppLifecycleState.resumed);
        h.connector.scheduleReconnectForTest();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump(const Duration(seconds: 40));
        expect(h.connector.attempts, isEmpty);
        await bridge.dispose();
        expect(h.connector.attempts, isEmpty);
        // Следующее событие таймера без продвижения виртуального времени.
        await tester.pump(Duration.zero);
        expect(h.connector.attempts, hasLength(1));
      } finally {
        h.connector.dispose();
        await bridge.dispose();
        messenger.setMockMethodCallHandler(IosPresentationBridge.platformChannel, null);
      }
    });

    _reconnectWidgetTest('lifecycle and settings cannot restart a held or manually stopped attempt', (tester, cleanup) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final h = await _powerConnector(tester, cleanup);
      _consumeFastPrefix(h.connector);
      final held = Completer<void>();
      h.connector.heldAttempt = held;
      h.connector.scheduleReconnectForTest();
      await tester.pump(const Duration(seconds: 180));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await h.settings.setPowerSavingProfile(PowerSavingProfile.maximum);
      await tester.pump(const Duration(minutes: 20));
      expect(h.connector.attempts, hasLength(1));
      await h.connector.disconnect(manual: true);
      held.complete();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await h.settings.setPowerSavingProfile(PowerSavingProfile.economical);
      await tester.pump();
      await tester.pump(const Duration(minutes: 20));
      expect(h.connector.attempts, hasLength(1));
      expect(h.connector.reconnectTimerActiveForTest, isFalse);
      expect(h.connector.reconnectAttemptsForTest, 0);
    });

    _reconnectWidgetTest('manual disconnect cancels a long pending wait before any connection', (tester, cleanup) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final h = await _powerConnector(tester, cleanup, seconds: 600);
      _consumeFastPrefix(h.connector);
      h.connector.scheduleReconnectForTest();
      await tester.pump(const Duration(seconds: 10));
      await h.connector.disconnect(manual: true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await h.settings.setPowerSavingProfile(PowerSavingProfile.disabled);
      await tester.pump(const Duration(minutes: 20));
      expect(h.connector.attempts, isEmpty);
      expect(h.connector.reconnectTimerActiveForTest, isFalse);
      expect(h.connector.reconnectAttemptsForTest, 0);
    });

    _reconnectWidgetTest('disposal cancels an extended wait and releases activity and settings', (tester, cleanup) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final h = await _powerConnector(tester, cleanup, seconds: 600);
      _consumeFastPrefix(h.connector);
      h.connector.scheduleReconnectForTest();
      h.connector.dispose();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await h.settings.setPowerSavingProfile(PowerSavingProfile.disabled);
      await tester.pump(const Duration(hours: 1));
      expect(h.connector.attempts, isEmpty);
      expect(h.connector.reconnectTimerActiveForTest, isFalse);
    });
  });
}
