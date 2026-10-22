import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Настоящие таймеры и обработчики коннектора; подменены транспорт и teardown.
// Fake time проверяет расписание Dart, а не сон ОС или расход батареи.
class _PollingConnector extends MeshCoreConnector {
  final settings = AppSettingsService();
  final frames = <Uint8List>[];
  bool connected = true;
  bool failBatterySend = false;
  int automaticDisconnects = 0;

  @override
  bool get isConnected => connected;

  int count(int command) => frames.where((f) => f.first == command).length;

  @override
  Future<void> sendFrame(
    Uint8List frame, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {
    frames.add(Uint8List.fromList(frame));
    if (failBatterySend && frame.first == cmdGetBattAndStorage) {
      throw StateError('Synthetic battery transport error');
    }
  }

  @override
  Future<void> disconnect({
    bool manual = true,
    bool skipBleDeviceDisconnect = false,
  }) async {
    if (!manual) {
      automaticDisconnects++;
    }
  }

  void receiveGpsSetting(bool enabled) {
    handleFrameForTest([
      respCodeCustomVars,
      ...utf8.encode('gps:${enabled ? 1 : 0}'),
      0,
    ]);
  }
}

Future<void> _withConnector(
  WidgetTester tester,
  Future<void> Function(_PollingConnector) check, {
  PowerSavingSettings powerSaving = const PowerSavingSettings(),
}) async {
  final connector = _PollingConnector();
  try {
    await connector.settings.updateSettings(
      connector.settings.settings.copyWith(powerSaving: powerSaving),
    );
    connector.attachAppSettingsServiceForTest(connector.settings);
    await check(connector);
  } finally {
    // Очищаем таймеры внутри тела widget test, до проверки его инвариантов.
    connector.dispose();
    connector.settings.dispose();
    await tester.pump();
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  testWidgets('baseline: battery polls every 120 seconds and forces a new request',
      (tester) async {
    await _withConnector(tester, (c) async {
      await c.requestBatteryStatus();
      await c.requestBatteryStatus();
      expect(c.count(cmdGetBattAndStorage), 1);
      c.startBatteryPollingForTest();
      await tester.pump(const Duration(seconds: 119));
      expect(c.count(cmdGetBattAndStorage), 1);
      await tester.pump(const Duration(seconds: 1));
      expect(c.count(cmdGetBattAndStorage), 2);
      await tester.pump(const Duration(seconds: 120));
      expect(c.count(cmdGetBattAndStorage), 3);
    });
  });

  testWidgets('baseline: periodic battery errors do not stop the next poll',
      (tester) async {
    await _withConnector(tester, (c) async {
      c.failBatterySend = true;
      c.startBatteryPollingForTest();
      await tester.pump(const Duration(seconds: 120));
      expect(c.count(cmdGetBattAndStorage), 1);
      c.failBatterySend = false;
      await tester.pump(const Duration(seconds: 120));
      expect(c.count(cmdGetBattAndStorage), 2);
    });
  });

  testWidgets('baseline: battery polling stops on loss and can be started again',
      (tester) async {
    await _withConnector(tester, (c) async {
      c.startBatteryPollingForTest();
      c.connected = false;
      await tester.pump(const Duration(seconds: 240));
      await c.requestBatteryStatus(force: true);
      expect(c.count(cmdGetBattAndStorage), 0);
      c.connected = true;
      c.startBatteryPollingForTest();
      await tester.pump(const Duration(seconds: 120));
      expect(c.count(cmdGetBattAndStorage), 1);
    });
  });

  testWidgets('baseline: GPS polls each minute without duplicate or reset timers',
      (tester) async {
    await _withConnector(tester, (c) async {
      await tester.pump(const Duration(seconds: 120));
      expect(c.count(cmdAppStart), 0);
      c.receiveGpsSetting(true);
      await tester.pump(const Duration(seconds: 59));
      expect(c.count(cmdAppStart), 0);
      c.receiveGpsSetting(true);
      await tester.pump(const Duration(seconds: 1));
      expect(c.count(cmdAppStart), 1);
      await tester.pump(const Duration(seconds: 60));
      expect(c.count(cmdAppStart), 2);
      c.receiveGpsSetting(false);
      await tester.pump(const Duration(seconds: 120));
      expect(c.count(cmdAppStart), 2);
    });
  });

  testWidgets('baseline: GPS skips contact sync and resumes at the next tick',
      (tester) async {
    await _withConnector(tester, (c) async {
      c.receiveGpsSetting(true);
      c.setContactSyncInProgressForTest(true);
      await tester.pump(const Duration(seconds: 60));
      expect(c.count(cmdAppStart), 0);
      c.setContactSyncInProgressForTest(false);
      expect(c.count(cmdAppStart), 0);
      await tester.pump(const Duration(seconds: 60));
      expect(c.count(cmdAppStart), 1);
    });
  });

  testWidgets('baseline: GPS stops on loss and restarts on a new enabled snapshot',
      (tester) async {
    await _withConnector(tester, (c) async {
      c.receiveGpsSetting(true);
      c.connected = false;
      await tester.pump(const Duration(seconds: 60));
      expect(c.count(cmdAppStart), 0);
      c.connected = true;
      c.receiveGpsSetting(true);
      await tester.pump(const Duration(seconds: 60));
      expect(c.count(cmdAppStart), 1);
    });
  });

  testWidgets('baseline: dispose cancels battery and GPS polling', (tester) async {
    late _PollingConnector disposed;
    await _withConnector(tester, (c) async {
      disposed = c;
      c.startBatteryPollingForTest();
      c.receiveGpsSetting(true);
      await tester.pump(const Duration(seconds: 120));
      expect(c.count(cmdGetBattAndStorage), 1);
      expect(c.count(cmdAppStart), 2);
    });
    final before = disposed.frames.length;
    await tester.pump(const Duration(minutes: 5));
    expect(disposed.frames.length, before);
  });

  testWidgets('baseline: watchdog allows recent RX and the original silence window',
      (tester) async {
    await _withConnector(tester, (c) async {
      expect(c.rxWatchdogSilenceForTest, const Duration(seconds: 300));
      final now = DateTime.now();
      c.tickRxWatchdogForTest(
        lastReceivedAt: now.subtract(const Duration(seconds: 240)),
        previousTickAt: now.subtract(const Duration(seconds: 60)),
      );
      expect(c.automaticDisconnects, 0);
      c.tickRxWatchdogForTest(
        lastReceivedAt: now.subtract(const Duration(seconds: 1)),
        silenceAnchor: now.subtract(const Duration(minutes: 10)),
        previousTickAt: now.subtract(const Duration(seconds: 60)),
      );
      expect(c.automaticDisconnects, 0);
      c.tickRxWatchdogForTest(
        lastReceivedAt: now.subtract(const Duration(seconds: 360)),
        previousTickAt: now.subtract(const Duration(seconds: 60)),
      );
      expect(c.automaticDisconnects, 1);
    });
  });

  testWidgets('baseline: watchdog starts a fresh silence window after a timer gap',
      (tester) async {
    await _withConnector(tester, (c) async {
      final before = DateTime.now();
      final fresh = c.tickRxWatchdogForTest(
        lastReceivedAt: before.subtract(const Duration(minutes: 10)),
        previousTickAt: before.subtract(const Duration(seconds: 121)),
      );
      expect(c.automaticDisconnects, 0);
      expect(fresh.isBefore(before), isFalse);
      c.tickRxWatchdogForTest(
        lastReceivedAt: before.subtract(const Duration(minutes: 10)),
        silenceAnchor: fresh,
        previousTickAt: DateTime.now().subtract(const Duration(seconds: 60)),
      );
      expect(c.automaticDisconnects, 0);
    });
  });

  for (final profile in [
    PowerSavingProfile.balanced,
    PowerSavingProfile.economical,
    PowerSavingProfile.maximum,
  ]) {
    testWidgets('${profile.name}: device timers use independent selected intervals',
        (tester) async {
      final selected = PowerSavingSettings(profile: profile);
      await _withConnector(tester, (c) async {
        c.startBatteryPollingForTest();
        c.receiveGpsSetting(true);
        await tester.pump(const Duration(seconds: 1800));
        expect(c.count(cmdGetBattAndStorage),
            1800 ~/ selected.effective.batteryIntervalSeconds);
        expect(c.count(cmdAppStart),
            1800 ~/ selected.effective.gpsIntervalSeconds);
        expect(c.rxWatchdogSilenceForTest.inSeconds,
            selected.effective.batteryIntervalSeconds * 2 + 60);
      }, powerSaving: selected);
    });
  }

  testWidgets('custom polling changes preserve independent and existing deadlines',
      (tester) async {
    await _withConnector(tester, (c) async {
      c.startBatteryPollingForTest();
      c.receiveGpsSetting(true);
      await tester.pump(const Duration(seconds: 59));
      await c.settings.setBatteryPollingIntervalSeconds(300);
      expect(c.rxWatchdogSilenceForTest, const Duration(seconds: 660));
      await tester.pump(const Duration(seconds: 1));
      expect(c.count(cmdAppStart), 1); // GPS по прежнему расписанию, t=60.
      expect(c.count(cmdGetBattAndStorage), 0);
      await c.settings.setGpsPollingIntervalSeconds(180);
      await c.settings.setShowHops(!c.settings.settings.showHops);
      await tester.pump(const Duration(seconds: 179));
      expect(c.count(cmdAppStart), 1);
      await tester.pump(const Duration(seconds: 1));
      expect(c.count(cmdAppStart), 2); // Новый GPS: t=60+180.
      await tester.pump(const Duration(seconds: 118));
      expect(c.count(cmdGetBattAndStorage), 0);
      await tester.pump(const Duration(seconds: 1));
      expect(c.count(cmdGetBattAndStorage), 1); // Батарея: t=59+300.

      await c.settings.setPowerSavingProfile(PowerSavingProfile.disabled);
      expect(c.rxWatchdogSilenceForTest, const Duration(seconds: 300));
      c.frames.clear();
      await tester.pump(const Duration(seconds: 120));
      expect(c.count(cmdGetBattAndStorage), 1);
      expect(c.count(cmdAppStart), 2);
    }, powerSaving: const PowerSavingSettings(profile: PowerSavingProfile.custom));
  });

  testWidgets('off ignores saved device intervals until custom is selected',
      (tester) async {
    await _withConnector(tester, (c) async {
      c.startBatteryPollingForTest();
      c.receiveGpsSetting(true);
      await tester.pump(const Duration(seconds: 59));
      await c.settings.setBatteryPollingIntervalSeconds(600);
      await c.settings.setGpsPollingIntervalSeconds(600);
      await tester.pump(const Duration(seconds: 61));
      expect(c.count(cmdGetBattAndStorage), 1);
      expect(c.count(cmdAppStart), 2);
      expect(c.rxWatchdogSilenceForTest, const Duration(seconds: 300));
      await c.settings.setPowerSavingProfile(PowerSavingProfile.custom);
      expect(c.rxWatchdogSilenceForTest, const Duration(seconds: 1260));
      c.frames.clear();
      await tester.pump(const Duration(seconds: 599));
      expect(c.frames, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(c.count(cmdGetBattAndStorage), 1);
      expect(c.count(cmdAppStart), 1);
    });
  });

  testWidgets('profile changes do not start inactive battery or GPS timers',
      (tester) async {
    await _withConnector(tester, (c) async {
      await c.settings.setPowerSavingProfile(PowerSavingProfile.maximum);
      await tester.pump(const Duration(seconds: 1200));
      expect(c.count(cmdGetBattAndStorage), 0);
      expect(c.count(cmdAppStart), 0);
      c.receiveGpsSetting(false);
      await c.settings.setGpsPollingIntervalSeconds(180);
      await c.settings.setPowerSavingProfile(PowerSavingProfile.custom);
      await tester.pump(const Duration(seconds: 600));
      expect(c.count(cmdGetBattAndStorage), 0);
      expect(c.count(cmdAppStart), 0);
    });
  });

  testWidgets('custom minimum preserves device polling while the app is paused',
      (tester) async {
    final initial = tester.binding.lifecycleState ?? AppLifecycleState.resumed;
    try {
      await _withConnector(tester, (c) async {
        c.startBatteryPollingForTest();
        c.receiveGpsSetting(true);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump(const Duration(seconds: 360));
        expect(c.count(cmdGetBattAndStorage), 3);
        expect(c.count(cmdAppStart), 6);
      }, powerSaving: const PowerSavingSettings(profile: PowerSavingProfile.custom));
    } finally {
      tester.binding.handleAppLifecycleStateChanged(initial);
    }
  });

  testWidgets('custom GPS retains the contact-sync guard and manual battery refresh',
      (tester) async {
    await _withConnector(tester, (c) async {
      c.receiveGpsSetting(true);
      c.setContactSyncInProgressForTest(true);
      await tester.pump(const Duration(seconds: 600));
      expect(c.count(cmdAppStart), 0);
      c.setContactSyncInProgressForTest(false);
      await tester.pump(const Duration(seconds: 600));
      expect(c.count(cmdAppStart), 1);
      await c.requestBatteryStatus(force: true);
      expect(c.count(cmdGetBattAndStorage), 1);
    }, powerSaving: const PowerSavingSettings(profile: PowerSavingProfile.maximum));
  });

  testWidgets('shortening battery polling starts a fresh watchdog silence window',
      (tester) async {
    await _withConnector(tester, (c) async {
      final before = DateTime.now();
      final old = before.subtract(const Duration(minutes: 30));
      c.tickRxWatchdogForTest(
        lastReceivedAt: before.subtract(const Duration(seconds: 1000)),
        silenceAnchor: old,
        previousTickAt: before.subtract(const Duration(seconds: 60)),
      );
      expect(c.automaticDisconnects, 0);
      await c.settings.setPowerSavingProfile(PowerSavingProfile.disabled);
      final fresh = c.rxSilenceAnchorForTest;
      expect(fresh.isBefore(before), isFalse);
      expect(c.rxWatchdogSilenceForTest, const Duration(seconds: 300));
      c.tickRxWatchdogForTest(
        lastReceivedAt: before.subtract(const Duration(seconds: 1000)),
        silenceAnchor: fresh,
        previousTickAt: DateTime.now().subtract(const Duration(seconds: 60)),
      );
      expect(c.automaticDisconnects, 0);
    }, powerSaving: const PowerSavingSettings(profile: PowerSavingProfile.maximum));
  });

  for (final transport in MeshCoreTransportType.values) {
    testWidgets('baseline: watchdog transport gate (${transport.name})',
        (tester) async {
      await _withConnector(tester, (c) async {
        final now = DateTime.now();
        c.tickRxWatchdogForTest(
          lastReceivedAt: now.subtract(const Duration(minutes: 10)),
          previousTickAt: now.subtract(const Duration(seconds: 60)),
          transport: transport,
        );
        final watched = transport == MeshCoreTransportType.bluetooth ||
            transport == MeshCoreTransportType.tcp;
        expect(c.automaticDisconnects, watched ? 1 : 0);
      });
    });
  }

  testWidgets('baseline: watchdog caps automatic recovery at three attempts',
      (tester) async {
    await _withConnector(tester, (c) async {
      for (var i = 0; i < 4; i++) {
        final now = DateTime.now();
        c.tickRxWatchdogForTest(
          lastReceivedAt: now.subtract(const Duration(minutes: 10)),
          previousTickAt: now.subtract(const Duration(seconds: 60)),
        );
      }
      expect(c.automaticDisconnects, 3);
    });
  });
}
