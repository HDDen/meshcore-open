import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/quick_action_radio_polling.dart';
import 'package:meshcore_open/models/quick_actions_settings.dart';
import 'package:meshcore_open/models/quick_actions_header_settings.dart';
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

  testWidgets('header starts after connection, firmware info and initial sync', (tester) async {
    final radio = _Radio()..connected = false..ready = false..supported = false;
    final settings = AppSettingsService();
    addTearDown(radio.dispose);
    addTearDown(settings.dispose);
    await _configure(settings, {});
    await settings.updateSettings(settings.settings.copyWith(
      quickActionsHeader: QuickActionsHeaderSettings(display: QuickActionsHeaderDisplay.noise)
          .withInterval(QuickActionsHeaderDisplay.noise, 1000),
    ));
    final polling = QuickActionRadioPolling(radio, settings,
      source: QuickActionPollingSource.header, isVisible: () => true);
    addTearDown(polling.dispose);
    polling.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    expect(radio.noise, 0);
    radio.connected = true;
    radio.notifyListeners();
    await tester.pump(const Duration(seconds: 2));
    expect(radio.noise, 0);
    radio.supported = true;
    radio.notifyListeners();
    await tester.pump(const Duration(seconds: 2));
    expect(radio.noise, 0);
    radio.ready = true;
    radio.notifyListeners();
    await tester.pump(const Duration(milliseconds: 1));
    expect(radio.noise, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(radio.noise, 2);
    radio.ready = false;
    radio.notifyListeners();
    await tester.pump(const Duration(seconds: 2));
    expect(radio.noise, 2);
    radio.ready = true;
    radio.notifyListeners();
    await tester.pump(const Duration(milliseconds: 1));
    expect(radio.noise, 3);
    radio.connected = false;
    radio.notifyListeners();
    await tester.pump(const Duration(seconds: 2));
    expect(radio.noise, 3);
    radio.connected = true;
    radio.notifyListeners();
    await tester.pump(const Duration(milliseconds: 1));
    expect(radio.noise, 4);
    polling.dispose();
  });

  for (final platform in [
    foundation.TargetPlatform.android, foundation.TargetPlatform.iOS,
    foundation.TargetPlatform.windows, foundation.TargetPlatform.linux, foundation.TargetPlatform.macOS,
  ]) {
  testWidgets('header lifecycle polling follows visibility rather than focus ($platform)', (tester) async {
      final mobile = platform == foundation.TargetPlatform.android || platform == foundation.TargetPlatform.iOS;
      final radio = _Radio();
      final settings = AppSettingsService();
      addTearDown(radio.dispose);
      addTearDown(settings.dispose);
      await _configure(settings, {});
      await settings.updateSettings(settings.settings.copyWith(quickActionsHeader:
        QuickActionsHeaderSettings(display: QuickActionsHeaderDisplay.noise)
            .withInterval(QuickActionsHeaderDisplay.noise, 1000)));
      var visible = true;
      final polling = QuickActionRadioPolling(radio, settings,
          source: QuickActionPollingSource.header, isVisible: () => visible);
      addTearDown(polling.dispose);
      polling.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 1));
      expect(radio.noise, 1);
      polling.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.pump(const Duration(seconds: 1));
      expect(radio.noise, 2, reason: 'visible split-screen/unfocused windows must keep polling');
      for (final state in [AppLifecycleState.hidden, AppLifecycleState.paused, AppLifecycleState.detached]) {
        final before = radio.noise;
        polling.didChangeAppLifecycleState(state);
        await tester.pump(const Duration(seconds: 1));
        expect(radio.noise, mobile ? before : before + 1, reason: '$platform / $state');
      }
      final beforeVisible = radio.noise;
      polling.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.pump(const Duration(seconds: 1));
      expect(radio.noise, greaterThan(beforeVisible));
      visible = false;
      polling.update();
      final hidden = radio.noise;
      await tester.pump(const Duration(seconds: 2));
      expect(radio.noise, hidden, reason: 'route/header visibility still matters on desktop');
      polling.dispose();
    }, variant: TargetPlatformVariant({platform}));
  }


  testWidgets('header cadence is independent and never polls while backgrounded', (tester) async {
    final radio = _Radio();
    final settings = AppSettingsService();
    addTearDown(radio.dispose);
    addTearDown(settings.dispose);
    await _configure(settings, {});
    await settings.updateSettings(settings.settings.copyWith(
      quickActionsHeader: QuickActionsHeaderSettings(display: QuickActionsHeaderDisplay.noise)
          .withInterval(QuickActionsHeaderDisplay.noise, 500),
    ));
    final polling = QuickActionRadioPolling(radio, settings,
        source: QuickActionPollingSource.header, isVisible: () => true);
    addTearDown(polling.dispose);
    polling.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 1));
    expect((radio.noise, radio.power), (1, 0));
    await tester.pump(const Duration(milliseconds: 498));
    expect(radio.noise, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(radio.noise, 2);
    polling.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 5));
    expect(radio.noise, 2);
    polling.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 1));
    expect(radio.noise, 3);
    await settings.updateSettings(settings.settings.copyWith(quickActionsHeader:
      settings.settings.quickActionsHeader.withInterval(QuickActionsHeaderDisplay.noise, 2000)));
    await tester.pump(const Duration(milliseconds: 1));
    final changed = radio.noise;
    await tester.pump(const Duration(milliseconds: 1998));
    expect(radio.noise, changed);
    await tester.pump(const Duration(milliseconds: 2));
    expect(radio.noise, changed + 1);
    await settings.updateSettings(settings.settings.copyWith(quickActionsHeader:
      settings.settings.quickActionsHeader.copyWith(display: QuickActionsHeaderDisplay.icon)));
    final stopped = radio.noise;
    await tester.pump(const Duration(seconds: 5));
    expect(radio.noise, stopped);
    polling.dispose();
  }, variant: TargetPlatformVariant({foundation.TargetPlatform.android}));

  testWidgets('popup keeps one-second polling with a half-second header preference', (tester) async {
    final radio = _Radio();
    final settings = AppSettingsService();
    addTearDown(radio.dispose);
    addTearDown(settings.dispose);
    await _configure(settings, {QuickAction.radioNoise});
    await settings.updateSettings(settings.settings.copyWith(quickActionsHeader:
      QuickActionsHeaderSettings(display: QuickActionsHeaderDisplay.noise)
          .withInterval(QuickActionsHeaderDisplay.noise, 500)));
    final polling = QuickActionRadioPolling(radio, settings, isVisible: () => true);
    addTearDown(polling.dispose);
    polling.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 1));
    expect(radio.noise, 1);
    await tester.pump(const Duration(milliseconds: 500));
    expect(radio.noise, 1);
    await tester.pump(const Duration(milliseconds: 500));
    expect(radio.noise, 2);
    polling.dispose();
  });


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
