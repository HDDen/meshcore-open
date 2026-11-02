import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mco_service/mco_service.dart' show McoBatteryChemistryProfile;
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('Synthetic preferences without a directory');
  }
}

final _nodeA = Uint8List.fromList(List<int>.filled(32, 0x11));
final _nodeB = Uint8List.fromList(List<int>.filled(32, 0x22));

Uint8List _batteryFrame(int millivolts, {int usedKb = 12, int totalKb = 1024}) {
  final data = ByteData(11);
  data.setUint8(0, respCodeBattAndStorage);
  data.setUint16(1, millivolts, Endian.little);
  data.setUint32(3, usedKb, Endian.little);
  data.setUint32(7, totalKb, Endian.little);
  return data.buffer.asUint8List();
}

Future<void> _withBattery(
  WidgetTester tester,
  Future<void> Function(MeshCoreConnector, AppSettingsService) check,
) async {
  final connector = MeshCoreConnector();
  final settings = AppSettingsService();
  try {
    // Freeze battery state/calculation independently of the new OS alerts.
    // Existing fixture APIs set the key without transport, stores or sync.
    await settings.updateSettings(
      settings.settings.copyWith(notificationsEnabled: false),
    );
    connector.attachAppSettingsServiceForTest(settings);
    await check(connector, settings);
  } finally {
    connector.dispose();
    settings.dispose();
    await tester.pump();
  }
}

void main() {
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

  testWidgets('baseline: battery and storage retain their little-endian values', (
    tester,
  ) async {
    await _withBattery(tester, (connector, settings) async {
      expect(connector.batteryMillivolts, isNull);
      expect(connector.batteryPercent, isNull);
      connector.handleFrameForTest(
        _batteryFrame(3300, usedKb: 0x010203, totalKb: 0x02030405),
      );
      expect(connector.batteryMillivolts, 3300);
      expect(connector.batteryPercent, 25);
      expect(connector.storageUsedKb, 0x010203);
      expect(connector.storageTotalKb, 0x02030405);
    });
  });

  testWidgets('baseline: identity selects the saved chemistry for a reading', (
    tester,
  ) async {
    await _withBattery(tester, (connector, settings) async {
      final key = pubKeyToHex(_nodeA);
      await settings.setBatteryChemistryForDevice(key, 'lifepo4');
      connector.handleFrameForTest(_batteryFrame(3200));
      expect(connector.batteryDeviceKey, isNull);
      expect(connector.batteryPercent, 17);

      connector.setPacketReplayFixtureForTest(selfKey: _nodeA);
      expect(connector.batteryDeviceKey, key);
      expect(connector.batteryMillivolts, 3200);
      expect(connector.batteryPercent, 57);
    });
  });

  for (final sample in [
    (chemistry: 'nmc', empty: 3000, full: 4200, quarter: 3300),
    (chemistry: 'lipo', empty: 3000, full: 4200, quarter: 3300),
    (chemistry: 'lifepo4', empty: 2600, full: 3650, quarter: 2863),
    (chemistry: 'lipo_hv', empty: 3000, full: 4350, quarter: 3338),
  ]) {
    testWidgets('baseline: ${sample.chemistry} keeps its voltage range', (
      tester,
    ) async {
      await _withBattery(tester, (connector, settings) async {
        connector.setPacketReplayFixtureForTest(selfKey: _nodeA);
        await settings.setBatteryChemistryForDevice(
          pubKeyToHex(_nodeA),
          sample.chemistry,
        );
        for (final reading in [
          (millivolts: sample.empty - 1, percent: 0),
          (millivolts: sample.empty, percent: 0),
          (millivolts: sample.quarter, percent: 25),
          (millivolts: sample.full, percent: 100),
          (millivolts: sample.full + 1, percent: 100),
        ]) {
          connector.handleFrameForTest(_batteryFrame(reading.millivolts));
          expect(connector.batteryPercent, reading.percent);
          expect(connector.batteryMillivolts, reading.millivolts);
        }
      });
    });
  }

  testWidgets('baseline: custom range survives reload and remains per node', (
    tester,
  ) async {
    await _withBattery(tester, (connector, settings) async {
      final keyA = pubKeyToHex(_nodeA);
      final keyB = pubKeyToHex(_nodeB);
      await settings.setBatteryCustomRangeForDevice(keyA, 2.8, 4.4);
      await settings.setBatteryChemistryForDevice(keyA, 'custom');
      await settings.setBatteryChemistryForDevice(keyB, 'nmc');
      final reloaded = AppSettingsService();
      try {
        await reloaded.loadSettings();
        connector.attachAppSettingsServiceForTest(reloaded);
        connector.setPacketReplayFixtureForTest(selfKey: _nodeA);
        connector.handleFrameForTest(_batteryFrame(3200));
        expect(
          reloaded.batteryVoltageRangeForDevice(keyA),
          (minMv: 2800, maxMv: 4400),
        );
        expect(connector.batteryPercent, 25);

        connector.setPacketReplayFixtureForTest(selfKey: _nodeB);
        connector.handleFrameForTest(_batteryFrame(3300));
        expect(connector.batteryPercent, 25);
        expect(reloaded.batteryVoltageRangeForDevice(keyB), isNull);
        connector.setPacketReplayFixtureForTest(selfKey: _nodeA);
        connector.handleFrameForTest(_batteryFrame(3200));
        expect(connector.batteryPercent, 25);
      } finally {
        connector.attachAppSettingsServiceForTest(settings);
        reloaded.dispose();
      }
    });
  });

  testWidgets('baseline: additional profiles follow the active node', (
    tester,
  ) async {
    await _withBattery(tester, (connector, settings) async {
      final keyA = pubKeyToHex(_nodeA);
      final keyB = pubKeyToHex(_nodeB);
      settings.setExtraBatteryProfilesProvider((deviceId) => [
        McoBatteryChemistryProfile(
          id: 'synthetic-profile',
          label: 'Synthetic battery',
          minVolts: deviceId == keyA ? 2.7 : 3.0,
          maxVolts: deviceId == keyA ? 4.3 : 4.0,
        ),
      ]);
      await settings.setBatteryChemistryForDevice(keyA, 'synthetic-profile');
      await settings.setBatteryChemistryForDevice(keyB, 'synthetic-profile');
      connector.setPacketReplayFixtureForTest(selfKey: _nodeA);
      connector.handleFrameForTest(_batteryFrame(3100));
      expect(connector.batteryPercent, 25);
      connector.setPacketReplayFixtureForTest(selfKey: _nodeB);
      expect(connector.batteryPercent, 10);
      connector.setPacketReplayFixtureForTest(selfKey: _nodeA);
      expect(connector.batteryPercent, 25);
    });
  });

  testWidgets('baseline: legacy chemistry and invalid custom range use NMC', (
    tester,
  ) async {
    await _withBattery(tester, (connector, settings) async {
      final key = pubKeyToHex(_nodeA);
      connector.setPacketReplayFixtureForTest(selfKey: _nodeA);
      connector.handleFrameForTest(_batteryFrame(3300));
      await settings.setBatteryChemistryForDevice(key, 'liion');
      expect(settings.batteryChemistryForDevice(key), 'nmc');
      expect(connector.batteryPercent, 25);
      await settings.updateSettings(
        settings.settings.copyWith(
          batteryChemistryByDeviceId: {key: 'custom'},
          batteryCustomMinVoltsByDeviceId: {key: 4.2},
          batteryCustomMaxVoltsByDeviceId: {key: 3.0},
        ),
      );
      expect(settings.batteryVoltageRangeForDevice(key), isNull);
      expect(connector.batteryPercent, 25);
      connector.handleFrameForTest(_batteryFrame(0));
      expect(connector.batteryMillivolts, 0);
      expect(connector.batteryPercent, 0);
    });
  });
}
