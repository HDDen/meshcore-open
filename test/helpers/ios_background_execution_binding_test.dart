import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mco_service/mco_service.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/ios_background_execution_binding.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/ios_immortalizer_power_options.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'ios_execution_diagnostics_fixture.dart';

// State-only fakes: no license runtime, transport, socket or native backend.
class _Connection extends ChangeNotifier implements MeshCoreConnector {
  MeshCoreTransportType transport = MeshCoreTransportType.bluetooth;
  bool connected = false;
  bool recovering = false;
  bool manual = false;
  @override
  MeshCoreTransportType get activeTransport => transport;
  @override
  bool get isConnected => connected;
  @override
  bool get isRecoveringConnection => recovering;
  @override
  bool get wasManuallyDisconnected => manual;
  void changed() => notifyListeners();
  bool get listening => hasListeners;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends ChangeNotifier implements AppSettingsService {
  bool get listening => hasListeners;
  @override
  AppSettings settings = AppSettings();
  void enable(bool enabled) {
    settings = settings.copyWith(backgroundTcpEnabled: enabled);
    notifyListeners();
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sections extends ChangeNotifier implements SettingsSectionsService {
  bool get listening => hasListeners;
  bool enabled = false;
  bool running = false;
  @override
  bool get companionProxyEnabled => enabled;
  @override
  bool get companionProxyRunning => running;
  void changed() => notifyListeners();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final messenger = TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  const channel = MethodChannel('mco_advanced/ios_execution');
  late _Connection connection;
  late _Settings settings;
  late _Sections sections;
  late List<MethodCall> calls;
  late List<Object> errors;
  late List<String> states;
  late List<String> diagnostics;
  IosBackgroundExecutionBinding? binding;
  List<bool> eligibility() => calls.map((call) => (call.arguments as Map)['eligible'] as bool).toList();
  Future<void> drain() => Future<void>.delayed(Duration.zero);
  void start({bool isIos = true}) {
    binding = IosBackgroundExecutionBinding(
      connector: connection, settings: settings, sections: sections,
      isIos: isIos, onError: errors.add,
      onState: states.add,
      onDiagnostics: diagnostics.add,
    );
  }

  setUp(() {
    connection = _Connection();
    settings = _Settings();
    sections = _Sections();
    calls = <MethodCall>[];
    errors = <Object>[];
    states = <String>[];
    diagnostics = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() async {
    binding?.dispose();
    binding = null;
    await drain();
    messenger.setMockMethodCallHandler(channel, null);
    connection.dispose();
    settings.dispose();
    sections.dispose();
  });

  test('BLE, USB, scanner and initial TCP recovery do not authorize a hold', () async {
    start();
    connection.connected = true;
    connection.changed();
    connection.transport = MeshCoreTransportType.usb;
    connection.changed();
    connection.transport = MeshCoreTransportType.tcp;
    connection.connected = false;
    connection.recovering = true;
    connection.changed();
    await drain();
    expect(eligibility(), <bool>[false]);
  });

  test('custom power is sent before TCP authorization and reset after revocation', () async {
    settings.settings = settings.settings.copyWith(powerSaving: const PowerSavingSettings(
      profile: PowerSavingProfile.custom,
      custom: PowerSavingOptions(iosImmortalizer: IosImmortalizerPowerOptions(
        leanHooks: true, audioBufferMilliseconds: 100,
      )),
    ));
    connection.transport = MeshCoreTransportType.tcp;
    connection.connected = true;
    start();
    await drain();
    expect(calls.map((call) => call.method), ['configurePower', 'configure']);
    expect((calls.first.arguments as Map)['audioBufferMilliseconds'], 100);
    expect(calls.last.arguments, {'eligible': true});
    binding!.dispose();
    await drain();
    expect(calls[calls.length - 2].arguments, {'eligible': false});
    expect((calls.last.arguments as Map)['audioBufferMilliseconds'], 0);
    expect(calls.last.method, 'configurePower');
  });

  test('custom iOS options never open a channel on another platform', () async {
    settings.settings = settings.settings.copyWith(powerSaving: const PowerSavingSettings(
      profile: PowerSavingProfile.custom,
      custom: PowerSavingOptions(iosImmortalizer: IosImmortalizerPowerOptions(withoutAudio: true)),
    ));
    start(isIos: false);
    await drain();
    expect(calls, isEmpty);
  });

  test('TCP authorizes once and retains a previously established recovery', () async {
    start();
    connection.transport = MeshCoreTransportType.tcp;
    connection.connected = true;
    connection.changed();
    connection.changed();
    connection.connected = false;
    connection.recovering = true;
    connection.changed();
    await drain();
    expect(eligibility(), <bool>[false, true]);
    connection.manual = true;
    connection.changed();
    await drain();
    expect(eligibility(), <bool>[false, true, false]);
    connection.manual = false;
    connection.changed();
    await drain();
    expect(eligibility().last, isFalse);
  });

  test('settings off revokes a live TCP reason without erasing the session', () async {
    connection.transport = MeshCoreTransportType.tcp;
    connection.connected = true;
    start();
    settings.enable(false);
    settings.enable(true);
    await drain();
    expect(eligibility(), <bool>[true, false, true]);
    expect(calls.every((call) => call.method == 'configure'), isTrue);
    expect(calls.every((call) => (call.arguments as Map).length == 1), isTrue);
  });

  test('authorized TCP listener is independent of uplink and client count', () async {
    start();
    sections.enabled = true;
    sections.changed(); // Starting is not yet a listener.
    sections.running = true;
    sections.changed();
    connection.manual = true;
    connection.changed(); // Manual uplink disconnect leaves proxy listening.
    sections.enabled = false; // Revoked capability/setting wins over old socket.
    sections.changed();
    await drain();
    expect(eligibility(), <bool>[false, true, false]);
  });

  test('an unauthorized listener and a BLE-only frontend supply no TCP reason', () async {
    // No companionProxyBleEnabled getter is consulted: BLE is not a reason.
    sections.running = true;
    start();
    await drain();
    expect(eligibility(), <bool>[false]);
    sections.enabled = true;
    sections.running = false;
    sections.changed();
    await drain();
    expect(eligibility(), <bool>[false]);
  });

  test('switching from TCP to BLE clears the old recovery authorization', () async {
    connection.transport = MeshCoreTransportType.tcp;
    connection.connected = true;
    start();
    connection.transport = MeshCoreTransportType.bluetooth;
    connection.recovering = true;
    connection.changed();
    connection.transport = MeshCoreTransportType.tcp;
    connection.connected = false;
    connection.changed();
    await drain();
    expect(eligibility(), <bool>[true, false]);
  });

  test('other platforms do not subscribe or send native requests', () async {
    start(isIos: false);
    expect(connection.listening, isFalse);
    expect(settings.listening, isFalse);
    expect(sections.listening, isFalse);
    await drain();
    expect(calls, isEmpty);
  });

  test('late failure cannot invalidate a newer configuration; disposal revokes', () async {
    final oldReply = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (calls.length == 1) {
        await oldReply.future;
      }
      return null;
    });
    start();
    await drain();
    connection.transport = MeshCoreTransportType.tcp;
    connection.connected = true;
    connection.changed();
    await drain();
    oldReply.completeError(PlatformException(code: 'old_request'));
    await drain();
    connection.changed();
    await drain();
    expect(eligibility(), <bool>[false, true]);
    expect(errors, isEmpty);
    binding!.dispose();
    expect(connection.listening, isFalse);
    connection.changed();
    await drain();
    expect(eligibility(), <bool>[false, true, false]);
  });

  test('missing native bridge reports failure without crashing the listener', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => throw MissingPluginException());
    start();
    await drain();
    expect(errors.single, isA<MissingPluginException>());
  });

  test('ordered native diagnostics neither authorize a hold nor accept late states', () async {
    start();
    await drain();
    const codec = StandardMethodCodec();
    Future<void> emit(Map<String, Object> data) async {
      await messenger.handlePlatformMessage(channel.name,
          codec.encodeMethodCall(MethodCall('state', data)), null);
    }
    final state = <String, Object>{
      'schema': 1, 'revision': 2, 'eligible': false, 'manualAllowed': false,
      'background': true, 'armed': false, 'audioRunning': false, 'legacyInjection': false,
    };
    await emit(state);
    await emit({...state, 'revision': 1, 'armed': true});
    await emit({...state, 'revision': 3, 'armed': 'bad'});
    expect(states, hasLength(1));
    expect(states.single, contains('manual=false'));
    expect(eligibility(), <bool>[false]);
    binding!.dispose();
    await emit({...state, 'revision': 4});
    expect(states, hasLength(1));
  });

  test('audio diagnostics are independently ordered and never authorize or reconfigure a hold', () async {
    start();
    await drain();
    const codec = StandardMethodCodec();
    Future<void> emit(Map<String, Object> raw) async {
      await messenger.handlePlatformMessage(channel.name,
          codec.encodeMethodCall(MethodCall('diagnostics', raw)), null);
    }
    await emit(iosExecutionDiagnosticsFixture(revision: 2));
    await emit(iosExecutionDiagnosticsFixture(revision: 1));
    await emit({...iosExecutionDiagnosticsFixture(revision: 3), 'audio': 'invalid'});
    await emit(iosExecutionDiagnosticsFixture(revision: 3));
    expect(diagnostics, hasLength(2));
    expect(states, isEmpty);
    expect(eligibility(), [false]);
    binding!.dispose();
    await drain();
    await emit(iosExecutionDiagnosticsFixture(revision: 4));
    expect(diagnostics, hasLength(2));
  });
}
