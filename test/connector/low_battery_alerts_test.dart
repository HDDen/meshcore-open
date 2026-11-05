import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/models/low_battery_alert_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/notification_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('Synthetic preferences without a directory');
  }
}

class _Plugin {
  static const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  static const badge = MethodChannel('meshcore_open/app_badge');
  final calls = <MethodCall>[];
  final gates = <Completer<void>>[];
  Completer<void>? nextShowGate;

  List<MethodCall> get shown => calls.where((call) => call.method == 'show').toList();
  List<MethodCall> get cancelled => calls.where((call) => call.method == 'cancel').toList();
  Map<Object?, Object?> args(MethodCall call) => call.arguments as Map<Object?, Object?>;

  Completer<void> holdShow() {
    final gate = Completer<void>();
    gates.add(gate);
    nextShowGate = gate;
    return gate;
  }

  void install() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize' || call.method == 'areNotificationsEnabled') {
        return true;
      }
      if (call.method == 'show' || call.method == 'cancel') {
        calls.add(call);
        if (call.method == 'show') {
          final gate = nextShowGate;
          nextShowGate = null;
          await gate?.future;
        }
      }
      return null;
    });
    messenger.setMockMethodCallHandler(badge, (_) async => null);
  }

  void remove() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(badge, null);
  }
}

class _Result {
  _Result(Future<void> future) {
    unawaited(future.then<void>((_) {
      done = true;
    }, onError: (Object failure, StackTrace stack) {
      error = failure;
      done = true;
    }));
  }
  bool done = false;
  Object? error;
}

final _nodeA = Uint8List.fromList(List<int>.filled(32, 0x11));
final _nodeB = Uint8List.fromList(List<int>.filled(32, 0x22));

class _Fixture {
  _Fixture(this.tester, this.connector, this.settings, this.plugin);
  final WidgetTester tester;
  final MeshCoreConnector connector;
  final AppSettingsService settings;
  final _Plugin plugin;

  void identify(Uint8List key, String name) {
    // An unsolicited SELF_INFO updates identity without cold storage/sync.
    final frame = Uint8List(59 + name.length);
    frame[0] = respCodeSelfInfo;
    frame.setRange(4, 36, key);
    frame[47] = 1;
    frame.setRange(58, 58 + name.length, name.codeUnits);
    connector.handleFrameForTest(frame);
  }

  Future<void> reading(int millivolts) async {
    final frame = ByteData(11);
    frame.setUint8(0, respCodeBattAndStorage);
    frame.setUint16(1, millivolts, Endian.little);
    connector.handleFrameForTest(frame.buffer.asUint8List());
    await tester.pump();
  }
}

Future<void> _withAlerts(
  WidgetTester tester,
  Future<void> Function(_Fixture) check, {
  bool identified = true,
}) async {
  final plugin = _Plugin()..install();
  final service = NotificationService()..resetForTest();
  final connector = MeshCoreConnector();
  final settings = AppSettingsService();
  final fixture = _Fixture(tester, connector, settings, plugin);
  try {
    final initialization = _Result(service.initialize());
    await tester.pump();
    expect(initialization.done, isTrue);
    expect(initialization.error, isNull);
    await settings.updateSettings(settings.settings.copyWith(notificationsEnabled: true));
    connector.attachAppSettingsServiceForTest(settings);
    if (identified) {
      fixture.identify(_nodeA, 'Alpha');
    }
    await check(fixture);
  } finally {
    for (final gate in plugin.gates) {
      if (!gate.isCompleted) {
        gate.complete();
      }
    }
    connector.resetConnectionHandshakeForTest();
    await tester.pump(const Duration(seconds: 5));
    connector.dispose();
    settings.dispose();
    service.releaseReplyPort();
    service.resetForTest();
    plugin.remove();
    await tester.pump();
  }
}

bool _linuxWithoutSession() {
  if (!Platform.isLinux) {
    return false;
  }
  if ((Platform.environment['DBUS_SESSION_BUS_ADDRESS'] ?? '').isNotEmpty) {
    return false;
  }
  final uid = Platform.environment['UID'] ?? Platform.environment['EUID'] ?? '1000';
  return !File('/run/user/$uid/bus').existsSync();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const timeout = Timeout(Duration(seconds: 20));
  late PathProviderPlatform savedPaths;
  setUpAll(() {
    savedPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferencesDirectory();
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  });
  tearDownAll(() => PathProviderPlatform.instance = savedPaths);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  group('low battery alerts', () {
    for (final level in LowBatteryAlertSettings.supportedThresholds) {
      testWidgets('configured $level percent reaches the native notification backend', (tester) async {
        await _withAlerts(tester, (h) async {
          final key = pubKeyToHex(_nodeA);
          await h.settings.setBatteryCustomRangeForDevice(key, 3.0, 4.0);
          await h.settings.setBatteryChemistryForDevice(key, 'custom');
          await h.settings.updateSettings(h.settings.settings.copyWith(
            lowBatteryAlerts: LowBatteryAlertSettings(thresholds: [level]),
          ));
          await h.reading(3000 + level * 10);
          expect(h.plugin.shown, isEmpty);
          await h.reading(3000 + level * 10);
          expect(h.plugin.shown, hasLength(1));
          expect(h.plugin.args(h.plugin.shown.single)['body'], contains('$level%'));
        });
      }, timeout: timeout);
    }

    testWidgets('battery toggle suppresses alerts and cancels an existing one', (tester) async {
      await _withAlerts(tester, (h) async {
        await h.settings.setLowBatteryAlertsEnabled(false);
        await h.reading(3240);
        await h.reading(3240);
        expect(h.plugin.shown, isEmpty);
        await h.settings.setLowBatteryAlertsEnabled(true);
        await h.reading(3240);
        expect(h.plugin.shown, isEmpty);
        await h.reading(3240);
        expect(h.plugin.shown, hasLength(1));
        await h.settings.setLowBatteryAlertsEnabled(false);
        await tester.pump();
        expect(h.plugin.cancelled, hasLength(1));
      });
    }, timeout: timeout);

    testWidgets('unselected thresholds and rising voltage with a plateau stay silent', (tester) async {
      await _withAlerts(tester, (h) async {
        await h.settings.updateSettings(h.settings.settings.copyWith(
          lowBatteryAlerts: const LowBatteryAlertSettings(thresholds: [10]),
        ));
        await h.reading(3240);
        await h.reading(3240);
        expect(h.plugin.shown, isEmpty); // 25% is no longer selected.
        await h.reading(3072);
        await h.reading(3084);
        await h.reading(3084);
        expect(h.plugin.shown, isEmpty);
        await h.reading(3072);
        await h.reading(3072);
        expect(h.plugin.shown, hasLength(1));
      });
    }, timeout: timeout);

    testWidgets('deselecting a level cancels its queued show before native delivery', (tester) async {
      await _withAlerts(tester, (h) async {
        final gate = h.plugin.holdShow();
        await h.reading(3240);
        await h.reading(3240);
        await h.reading(3108);
        await h.reading(3108);
        expect(h.plugin.shown, hasLength(1));
        await h.settings.setLowBatteryAlertThreshold(10, false);
        gate.complete();
        await tester.pump();
        expect(h.plugin.shown, hasLength(1));
        expect(h.plugin.cancelled, hasLength(1));
      });
    }, timeout: timeout);

    testWidgets('25 percent needs two readings and does not repeat', (tester) async {
      await _withAlerts(tester, (h) async {
        await h.reading(3300);
        expect(h.plugin.shown, isEmpty);
        await h.reading(3300);
        expect(h.plugin.shown, hasLength(1));
        final shown = h.plugin.args(h.plugin.shown.single);
        expect(shown['payload'], 'low_battery');
        expect(shown['body'], contains('Alpha'));
        expect(shown['body'], contains('25%'));
        await h.reading(3240);
        await h.reading(3240);
        expect(h.plugin.shown, hasLength(1));
      });
    }, timeout: timeout);

    testWidgets('a confirmed critical reading posts only the lowest threshold', (tester) async {
      await _withAlerts(tester, (h) async {
        await h.reading(3120);
        await h.reading(3120);
        expect(h.plugin.shown, hasLength(1));
        expect(h.plugin.args(h.plugin.shown.single)['body'], contains('10%'));
        await h.reading(3240);
        await h.reading(3240);
        expect(h.plugin.shown, hasLength(1));
      });
    }, timeout: timeout);

    testWidgets('ordinary battery requests preserve consecutive readings', (tester) async {
      await _withAlerts(tester, (h) async {
        h.connector.setReconnectContextForTest(
          transport: MeshCoreTransportType.tcp,
          state: MeshCoreConnectionState.connected,
        );
        h.connector.setFrameWriterForTest((_) async {});
        for (var i = 0; i < 2; i++) {
          final request = _Result(h.connector.requestBatteryStatus(force: true));
          await tester.pump();
          expect(request.done, isTrue);
          expect(request.error, isNull);
          await h.reading(3240);
        }
        expect(h.plugin.shown, hasLength(1));
      });
    }, timeout: timeout);

    testWidgets('one reading below 10 percent cannot reuse the 25 percent streak', (tester) async {
      await _withAlerts(tester, (h) async {
        await h.reading(3240);
        await h.reading(3108);
        expect(h.plugin.shown, hasLength(1));
        final first = h.plugin.args(h.plugin.shown.single)['id'];
        await h.reading(3108);
        expect(h.plugin.shown, hasLength(2));
        expect(h.plugin.args(h.plugin.shown.last)['id'], isNot(first));
      });
    }, timeout: timeout);

    for (final invalid in [0, 1999]) {
      testWidgets('$invalid mV breaks confirmation without changing raw state', (tester) async {
        await _withAlerts(tester, (h) async {
          await h.reading(3240);
          await h.reading(invalid);
          expect(h.connector.batteryMillivolts, invalid);
          await h.reading(3240);
          expect(h.plugin.shown, isEmpty);
          await h.reading(3240);
          expect(h.plugin.shown, hasLength(1));
        });
      }, timeout: timeout);
    }

    testWidgets('unknown identity does not consume low readings', (tester) async {
      await _withAlerts(tester, (h) async {
        await h.reading(3240);
        await h.reading(3240);
        expect(h.plugin.shown, isEmpty);
        h.identify(_nodeA, 'Alpha');
        await h.reading(3240);
        expect(h.plugin.shown, isEmpty);
        await h.reading(3240);
        expect(h.plugin.shown, hasLength(1));
      }, identified: false);
    }, timeout: timeout);

    testWidgets('disabled application notifications do not consume thresholds', (tester) async {
      await _withAlerts(tester, (h) async {
        await h.settings.setNotificationsEnabled(false);
        await h.reading(3240);
        await h.reading(3240);
        expect(h.plugin.shown, isEmpty);
        await h.settings.setNotificationsEnabled(true);
        await h.reading(3240);
        expect(h.plugin.shown, isEmpty);
        await h.reading(3240);
        expect(h.plugin.shown, hasLength(1));
      });
    }, timeout: timeout);

    testWidgets('rearm is strictly above five points and uses the same id', (tester) async {
      await _withAlerts(tester, (h) async {
        await h.reading(3240);
        await h.reading(3240);
        final id = h.plugin.args(h.plugin.shown.single)['id'];
        await h.reading(3360);
        expect(h.plugin.cancelled, isEmpty);
        await h.reading(3372);
        expect(h.plugin.cancelled, hasLength(1));
        expect(h.plugin.args(h.plugin.cancelled.single)['id'], id);
        await h.reading(3240);
        expect(h.plugin.shown, hasLength(1));
        await h.reading(3240);
        expect(h.plugin.shown, hasLength(2));
        expect(h.plugin.args(h.plugin.shown.last)['id'], id);
      });
    }, timeout: timeout);

    testWidgets('reset clears the old device after its held native show', (tester) async {
      await _withAlerts(tester, (h) async {
        final gate = h.plugin.holdShow();
        await h.reading(3240);
        await h.reading(3240);
        final oldId = h.plugin.args(h.plugin.shown.single)['id'];
        h.connector.resetConnectionHandshakeForTest();
        h.identify(_nodeB, 'Beta');
        await h.reading(3240);
        await h.reading(3240);
        expect(h.plugin.calls.map((call) => call.method), ['show']);
        expect(h.connector.backgroundWorkSnapshot.countFor(BackgroundWorkKind.notification), 3);
        gate.complete();
        await tester.pump();
        expect(h.plugin.calls.map((call) => call.method), ['show', 'cancel', 'show']);
        expect(h.plugin.args(h.plugin.cancelled.single)['id'], oldId);
        expect(h.plugin.args(h.plugin.shown.last)['id'], isNot(oldId));
        expect(h.plugin.args(h.plugin.shown.last)['body'], contains('Beta'));
        expect(h.connector.backgroundWorkSnapshot.countFor(BackgroundWorkKind.notification), 0);
      });
    }, timeout: timeout);

    testWidgets('a different identity cannot inherit an unconfirmed reading', (tester) async {
      await _withAlerts(tester, (h) async {
        await h.reading(3240);
        h.identify(_nodeB, 'Beta');
        await h.reading(3240);
        expect(h.plugin.shown, isEmpty);
        await h.reading(3240);
        expect(h.plugin.shown, hasLength(1));
        expect(h.plugin.args(h.plugin.shown.single)['body'], contains('Beta'));
      });
    }, timeout: timeout);

    testWidgets('a held battery show does not block ordinary message notifications', (tester) async {
      await _withAlerts(tester, (h) async {
        h.plugin.holdShow();
        await h.reading(3240);
        await h.reading(3240);
        final message = _Result(NotificationService().showMessageNotification(
          contactName: 'Sender',
          contactId: 'synthetic-contact',
          message: 'hello',
          urlImagesEnabled: false,
        ));
        await tester.pump();
        expect(message.done, isTrue);
        expect(message.error, isNull);
        expect(h.plugin.shown, hasLength(2));
        expect(h.plugin.args(h.plugin.shown.last)['payload'], 'message:synthetic-contact');
      });
    }, timeout: timeout);

    testWidgets('explicit low-voltage custom profile can still notify', (tester) async {
      await _withAlerts(tester, (h) async {
        final key = pubKeyToHex(_nodeA);
        await h.settings.setBatteryCustomRangeForDevice(key, 1.0, 2.0);
        await h.settings.setBatteryChemistryForDevice(key, 'custom');
        await h.reading(1250);
        await h.reading(1250);
        expect(h.connector.batteryPercent, 25);
        expect(h.plugin.shown, hasLength(1));
      });
    }, timeout: timeout);
  }, skip: _linuxWithoutSession()
      ? 'NotificationService skips initialization without a Linux D-Bus session'
      : null);
}
