import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/quick_action_radio_polling.dart';
import 'package:meshcore_open/models/quick_actions_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Radio extends ChangeNotifier implements MeshCoreConnector {
  bool connected = true;
  bool ready = true;
  bool supported = true;
  int noise = 0;
  int power = 0;
  Future<void>? noisePending;
  Future<void>? powerPending;
  @override
  bool get isConnected => connected;
  @override
  bool get isOfflineMode => false;
  @override
  bool get isSessionReady => ready;
  @override
  bool get supportsCompanionRadioStats => supported;
  @override
  Future<void> requestRadioStats() { noise++; return noisePending ?? Future.value(); }
  @override
  Future<void> refreshRadioPower({Duration timeout = const Duration(seconds: 2)}) {
    power++; return powerPending ?? Future.value();
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _configure(AppSettingsService settings, Set<QuickAction> visible) =>
    settings.updateSettings(settings.settings.copyWith(quickActions: QuickActionsSettings([
      for (final action in QuickAction.values) QuickActionItem(action, visible: visible.contains(action)),
    ])));

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  testWidgets('only enabled and visible readings poll once per second', (tester) async {
    final radio = _Radio();
    final settings = AppSettingsService();
    addTearDown(radio.dispose);
    addTearDown(settings.dispose);
    await _configure(settings, {});
    var visible = true;
    final polling = QuickActionRadioPolling(radio, settings, isVisible: () => visible);
    addTearDown(polling.dispose);
    polling.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
    expect((radio.noise, radio.power), (0, 0));
    await _configure(settings, {QuickAction.radioNoise});
    expect((radio.noise, radio.power), (0, 0),
        reason: 'the first read is deferred until after construction/settings notifications');
    await tester.pump(const Duration(milliseconds: 1));
    expect((radio.noise, radio.power), (1, 0));
    await tester.pump(const Duration(seconds: 1));
    expect((radio.noise, radio.power), (2, 0));
    visible = false;
    polling.update();
    await tester.pump(const Duration(seconds: 3));
    expect((radio.noise, radio.power), (2, 0));
    visible = true;
    polling.update();
    await tester.pump(const Duration(milliseconds: 1));
    expect((radio.noise, radio.power), (3, 0));
    await _configure(settings, {QuickAction.radioTxPower});
    await tester.pump(const Duration(milliseconds: 1));
    expect(radio.power, 1);
    final stoppedNoise = radio.noise;
    await tester.pump(const Duration(seconds: 1));
    expect(radio.noise, stoppedNoise);
    expect(radio.power, 2);
    polling.dispose();
    await tester.pump(const Duration(seconds: 3));
    expect(radio.power, 2);
  });

  testWidgets('slow requests never overlap and hidden completions do not restart polling', (tester) async {
    final radio = _Radio();
    final settings = AppSettingsService();
    addTearDown(radio.dispose);
    addTearDown(settings.dispose);
    await _configure(settings, {QuickAction.radioNoise, QuickAction.radioTxPower});
    final noise = Completer<void>();
    final power = Completer<void>();
    radio.noisePending = noise.future;
    radio.powerPending = power.future;
    var visible = true;
    final polling = QuickActionRadioPolling(radio, settings, isVisible: () => visible);
    addTearDown(polling.dispose);
    polling.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(seconds: 3));
    expect((radio.noise, radio.power), (1, 1));
    visible = false;
    polling.update();
    noise.complete();
    power.complete();
    await tester.pump(const Duration(seconds: 3));
    expect((radio.noise, radio.power), (1, 1));
    polling.dispose();
  });

  testWidgets('background, disconnection and unsupported stats suspend queries', (tester) async {
    final radio = _Radio();
    final settings = AppSettingsService();
    addTearDown(radio.dispose);
    addTearDown(settings.dispose);
    await _configure(settings, {QuickAction.radioNoise, QuickAction.radioTxPower});
    final polling = QuickActionRadioPolling(radio, settings, isVisible: () => true);
    addTearDown(polling.dispose);
    polling.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 1));
    expect((radio.noise, radio.power), (1, 1));
    polling.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 3));
    expect((radio.noise, radio.power), (1, 1));
    polling.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 1));
    expect((radio.noise, radio.power), (2, 2));
    radio.connected = false;
    radio.notifyListeners();
    await tester.pump(const Duration(seconds: 3));
    expect((radio.noise, radio.power), (2, 2));
    radio.connected = true;
    radio.supported = false;
    radio.notifyListeners();
    await tester.pump(const Duration(milliseconds: 1));
    expect((radio.noise, radio.power), (2, 3));
    polling.dispose();
  });
}
