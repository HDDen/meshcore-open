import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CapabilityConnector extends MeshCoreConnector {
  bool connected = true;
  bool supported = true;

  @override
  bool get isConnected => connected;

  @override
  bool get supportsCompanionRadioStats => supported;
}

Future<void> _withSettings(
  WidgetTester tester,
  Future<void> Function(MeshCoreConnector, AppSettingsService) check, {
  PowerSavingProfile profile = PowerSavingProfile.custom,
  MeshCoreConnector? testConnector,
}) async {
  final settings = AppSettingsService();
  final connector = testConnector ?? MeshCoreConnector();
  try {
    await settings.updateSettings(settings.settings.copyWith(
      powerSaving: PowerSavingSettings(
        profile: profile,
        custom: const PowerSavingOptions(uiNotificationIntervalMilliseconds: 750),
      ),
    ));
    connector.attachAppSettingsServiceForTest(settings);
    await check(connector, settings);
  } finally {
    connector.dispose();
    settings.dispose();
    await tester.pump();
  }
}

Uint8List _batteryFrame(int millivolts) {
  final bytes = ByteData(11);
  bytes.setUint8(0, respCodeBattAndStorage);
  bytes.setUint16(1, millivolts, Endian.little);
  return bytes.buffer.asUint8List();
}

Uint8List _statsFrame(int txAirSecs) {
  final bytes = ByteData(14);
  bytes.setUint8(0, respCodeStats);
  bytes.setUint8(1, statsTypeRadio);
  bytes.setInt16(2, -110, Endian.little);
  bytes.setInt8(4, -80);
  bytes.setInt8(5, 30);
  bytes.setUint32(6, txAirSecs, Endian.little);
  bytes.setUint32(10, 20, Endian.little);
  return bytes.buffer.asUint8List();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  const intervals = {
    PowerSavingProfile.disabled: 50,
    PowerSavingProfile.balanced: 100,
    PowerSavingProfile.economical: 250,
    PowerSavingProfile.maximum: 500,
    PowerSavingProfile.custom: 750,
  };
  for (final entry in intervals.entries) {
    testWidgets('${entry.key.name}: ordinary updates follow the effective interval',
        (tester) async {
      await _withSettings(tester, (connector, settings) async {
        var calls = 0;
        connector.addListener(() => calls++);
        connector.markNotifyDirty();
        await tester.pump(Duration(milliseconds: entry.value - 1));
        expect(calls, 0);
        connector.markNotifyDirty();
        await tester.pump(const Duration(milliseconds: 1));
        expect(calls, 1);
        expect(settings.settings.powerSaving.custom.uiNotificationIntervalMilliseconds, 750);
      }, profile: entry.key);
    });
  }

  testWidgets('a slow UI window preserves immediate state and every raw frame',
      (tester) async {
    await _withSettings(tester, (connector, settings) async {
      final raw = <Uint8List>[];
      final seen = <int?>[];
      final subscription = connector.receivedFrames.listen(raw.add);
      try {
        connector.addListener(() => seen.add(connector.batteryMillivolts));
        final first = _batteryFrame(4100);
        final second = _batteryFrame(4200);
        connector.handleFrameForTest(first);
        expect(connector.batteryMillivolts, 4100);
        connector.handleFrameForTest(second);
        expect(connector.batteryMillivolts, 4200);
        await tester.pump();
        expect(raw, [first, second]);
        await tester.pump(const Duration(milliseconds: 749));
        expect(seen, isEmpty);
        await tester.pump(const Duration(milliseconds: 1));
        expect(seen, [4200]);
      } finally {
        // Broadcast без onCancel снимает listener синхронно (см. baseline).
        unawaited(subscription.cancel());
        await tester.pump();
      }
    });
  });

  testWidgets('radio stats reach their notifier without waiting for the slow UI window',
      (tester) async {
    await _withSettings(tester, (connector, settings) async {
      final tx = <int>[];
      var calls = 0;
      connector.addListener(() => calls++);
      connector.radioStatsNotifier.addListener(() {
        tx.add(connector.radioStatsNotifier.value!.txAirSecs);
      });
      connector.markNotifyDirty();
      connector.handleFrameForTest(_statsFrame(10));
      connector.handleFrameForTest(_statsFrame(12));
      expect(tx, [10, 12]);
      expect(connector.radioStatsAirActivityPulse, isTrue);
      expect(calls, 0);
      await tester.pump(const Duration(milliseconds: 750));
      expect(calls, 1);
      expect(tx, [10, 12]);
    });
  });

  testWidgets('connection transitions keep 50 ms and ordinary updates return to the selected interval',
      (tester) async {
    await _withSettings(tester, (connector, settings) async {
      final states = <MeshCoreConnectionState>[];
      connector.addListener(() => states.add(connector.state));
      connector.markNotifyDirty();
      await tester.pump(const Duration(milliseconds: 100));
      connector.setConnectionStateForTest(MeshCoreConnectionState.scanning);
      await tester.pump(const Duration(milliseconds: 49));
      expect(states, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(states, [MeshCoreConnectionState.scanning]);
      connector.markNotifyDirty();
      await tester.pump(const Duration(milliseconds: 749));
      expect(states, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(states, hasLength(2));
      connector.setConnectionStateForTest(MeshCoreConnectionState.disconnected);
      await tester.pump(const Duration(milliseconds: 50));
      expect(states.last, MeshCoreConnectionState.disconnected);
      expect(states, hasLength(3));
    });
  });

  testWidgets('changing an unrelated setting preserves the active deadline',
      (tester) async {
    await _withSettings(tester, (connector, settings) async {
      var calls = 0;
      connector.addListener(() => calls++);
      connector.markNotifyDirty();
      await tester.pump(const Duration(milliseconds: 400));
      await settings.setPauseHiddenGifs(true);
      await tester.pump();
      expect(calls, 0);
      await tester.pump(const Duration(milliseconds: 349));
      expect(calls, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 1);
    });
  });

  testWidgets('switching to Off releases accumulated updates without waiting for the old interval',
      (tester) async {
    await _withSettings(tester, (connector, settings) async {
      var calls = 0;
      connector.addListener(() => calls++);
      connector.markNotifyDirty();
      await tester.pump(const Duration(milliseconds: 200));
      await settings.setPowerSavingProfile(PowerSavingProfile.disabled);
      await tester.pump(Duration.zero);
      expect(calls, 1);
      connector.markNotifyDirty();
      await tester.pump(const Duration(milliseconds: 49));
      expect(calls, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 2);
    });
  });

  testWidgets('public connection and radio capabilities keep the 50 ms window',
      (tester) async {
    final capability = _CapabilityConnector();
    await _withSettings(tester, (connector, settings) async {
      final seen = <(bool, bool)>[];
      connector.addListener(() {
        seen.add((connector.isConnected, connector.supportsCompanionRadioStats));
      });
      expect(connector.state, MeshCoreConnectionState.disconnected);
      connector.markNotifyDirty();
      await tester.pump(const Duration(milliseconds: 100));
      capability.connected = false;
      connector.notifyListeners();
      await tester.pump(const Duration(milliseconds: 49));
      expect(seen, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(seen, [(false, true)]);
      capability.connected = true;
      capability.supported = false;
      connector.notifyListeners();
      await tester.pump(const Duration(milliseconds: 50));
      expect(seen, [(false, true), (true, false)]);
      capability.supported = true;
      connector.notifyListeners();
      await tester.pump(const Duration(milliseconds: 49));
      expect(seen, hasLength(2));
      await tester.pump(const Duration(milliseconds: 1));
      expect(seen, [(false, true), (true, false), (true, true)]);
      // Без нового перехода обычное уведомление снова ждёт свои 750 мс.
      connector.markNotifyDirty();
      await tester.pump(const Duration(milliseconds: 749));
      expect(seen, hasLength(3));
      await tester.pump(const Duration(milliseconds: 1));
      expect(seen, hasLength(4));
    }, testConnector: capability);
  });
}
