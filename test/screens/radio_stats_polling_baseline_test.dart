import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/helpers/ios_presentation_guard.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/screens/companion_radio_stats_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/message_retry_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/utils/app_route_observer.dart';
import 'package:meshcore_open/widgets/radio_stats_entry.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Count commands from the real connector polling timers, replacing only the
// physical connection. The baseline cases preserve Off/legacy behavior;
// separate opt-in cases check the profile-driven cadence. Fake time exercises
// Dart scheduling, not OS suspension or device energy consumption.
class _RadioStatsConnector extends MeshCoreConnector {
  final sentFrames = <Uint8List>[];
  bool sending = false;
  bool connected = true;
  bool supported = true;

  @override
  bool get hasPendingRadioStatsWork => sending || super.hasPendingRadioStatsWork;

  @override
  bool get isConnected => connected;

  @override
  bool get supportsCompanionRadioStats => supported;

  int get polls => sentFrames.where(
    (frame) => listEquals(frame, buildGetStatsFrame(statsTypeRadio)),
  ).length;

  @override
  Future<void> sendFrame(
    Uint8List frame, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {
    sentFrames.add(Uint8List.fromList(frame));
  }
}

Uint8List _statsFrame({int snrRaw = 30}) {
  final data = ByteData(14);
  data.setUint8(0, respCodeStats);
  data.setUint8(1, statsTypeRadio);
  data.setInt16(2, -110, Endian.little);
  data.setInt8(4, -80);
  data.setInt8(5, snrRaw);
  data.setUint32(6, 10, Endian.little);
  data.setUint32(10, 20, Endian.little);
  return data.buffer.asUint8List();
}

class _Harness {
  final connector = _RadioStatsConnector();
  final settings = AppSettingsService();
  final navigator = GlobalKey<NavigatorState>();
  final retryServices = <MessageRetryService>[];
}

Future<_Harness> _open(
  WidgetTester tester, {
  required Widget home,
  bool hidden = false,
  PowerSavingSettings powerSaving = const PowerSavingSettings(),
}) async {
  final harness = _Harness();
  addTearDown(() async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    harness.connector.dispose();
    for (final service in harness.retryServices) {
      service.dispose();
    }
    harness.settings.dispose();
  });
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await harness.settings.updateSettings(harness.settings.settings.copyWith(
    powerSaving: powerSaving,
  ));
  harness.connector.attachAppSettingsServiceForTest(harness.settings);
  if (hidden) {
    await harness.settings.setHideRadioStatsButton(true);
  }
  // Avoid a perpetual progress animation in tests of route visibility.
  harness.connector.handleFrameForTest(_statsFrame());
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<MeshCoreConnector>.value(
          value: harness.connector,
        ),
        ChangeNotifierProvider<AppSettingsService>.value(
          value: harness.settings,
        ),
      ],
      child: MaterialApp(
        navigatorKey: harness.navigator,
        navigatorObservers: [appRouteObserver],
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  return harness;
}

Future<void> _push(_Harness harness, WidgetTester tester, Widget screen) async {
  // Do not await the route future: it completes only when the route is popped.
  harness.navigator.currentState!.push<void>(
    MaterialPageRoute<void>(builder: (_) => screen),
  );
  await _settleRoute(tester);
}

Future<void> _settleRoute(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 2),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  testWidgets('polling owners share the timer and the last release stops it', (
    tester,
  ) async {
    final harness = await _open(tester, home: const Scaffold());
    final connector = harness.connector;
    connector.acquireRadioStatsPolling();
    await tester.pump(const Duration(seconds: 29));
    expect(connector.polls, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(connector.polls, 1);

    connector.acquireRadioStatsPolling();
    connector.releaseRadioStatsPolling();
    await tester.pump(const Duration(seconds: 30));
    expect(connector.polls, 2);
    connector.releaseRadioStatsPolling();
    await tester.pump(const Duration(seconds: 60));
    expect(connector.polls, 2);

    // Releasing automatic polling must not disable an explicit request.
    await connector.requestRadioStats();
    expect(connector.polls, 3);
  });

  testWidgets('visible statistics poll each second and display fresh readings', (
    tester,
  ) async {
    final harness = await _open(
      tester,
      home: const CompanionRadioStatsScreen(),
    );
    expect(find.text('Last SNR: 7.5 dB'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(harness.connector.polls, 3);

    harness.connector.handleFrameForTest(_statsFrame(snrRaw: -4));
    await tester.pump();
    expect(find.text('Last SNR: -1.0 dB'), findsOneWidget);
    expect(find.text('Last SNR: 7.5 dB'), findsNothing);
  });

  testWidgets('closing statistics restores normal polling for another owner', (
    tester,
  ) async {
    final harness = await _open(
      tester,
      home: const Scaffold(body: RadioStatsIconButton()),
    );
    await _push(harness, tester, const CompanionRadioStatsScreen());
    final statisticsState = tester.state(
      find.byType(CompanionRadioStatsScreen),
    );
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 3));
    expect(harness.connector.polls, 3);

    harness.navigator.currentState!.pop();
    // The interval changes in dispose, after overlay removal, not at pop().
    await _settleRoute(tester);
    expect(statisticsState.mounted, isFalse);
    expect(
      find.byType(CompanionRadioStatsScreen, skipOffstage: false),
      findsNothing,
    );
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 31));
    expect(harness.connector.polls, 1);
  });

  testWidgets('baseline: a covered statistics screen keeps polling each second', (
    tester,
  ) async {
    final harness = await _open(
      tester,
      home: const CompanionRadioStatsScreen(),
    );
    await _push(harness, tester, const Scaffold(body: Text('cover')));
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 3));
    expect(harness.connector.polls, 3);

    harness.connector.handleFrameForTest(_statsFrame(snrRaw: -4));
    await tester.pump();
    harness.navigator.currentState!.pop();
    await _settleRoute(tester);
    expect(find.text('Last SNR: -1.0 dB'), findsOneWidget);
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 2));
    expect(harness.connector.polls, 2);
  });

  testWidgets('baseline: paused lifecycle leaves the one-second poll running', (
    tester,
  ) async {
    final harness = await _open(
      tester,
      home: const CompanionRadioStatsScreen(),
    );
    await tester.pump(const Duration(seconds: 1));
    harness.connector.sentFrames.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.binding.lifecycleState, AppLifecycleState.paused);
    expect(harness.connector.polls, 3);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 2));
    expect(harness.connector.polls, 2);
  });

  testWidgets('baseline: hiding the statistics button retains its polling owner', (
    tester,
  ) async {
    final harness = await _open(
      tester,
      home: const Scaffold(body: RadioStatsIconButton()),
      hidden: true,
    );
    expect(find.byType(AirActivityDot), findsNothing);
    await tester.pump(const Duration(seconds: 60));
    expect(harness.connector.polls, 2);

    await harness.settings.setHideRadioStatsButton(false);
    await tester.pump();
    expect(find.byType(AirActivityDot), findsOneWidget);
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 30));
    expect(harness.connector.polls, 1);
  });

  for (final profile in [
    PowerSavingProfile.disabled,
    PowerSavingProfile.maximum,
  ]) {
    testWidgets(
      '${profile.name}: indicator polling follows route visibility',
      (tester) async {
        final harness = await _open(
          tester,
          home: const Scaffold(body: RadioStatsIconButton()),
          powerSaving: PowerSavingSettings(profile: profile),
        );
        expect(harness.connector.radioStatsPollingOwners.value, 1);
        await _push(harness, tester, const Scaffold(body: Text('cover')));
        harness.connector.sentFrames.clear();
        await tester.pump(const Duration(seconds: 60));
        expect(harness.connector.polls,
            profile == PowerSavingProfile.disabled ? 2 : 0);
        expect(harness.connector.radioStatsPollingOwners.value,
            profile == PowerSavingProfile.disabled ? 1 : 0);

        harness.navigator.currentState!.pop();
        await _settleRoute(tester);
        harness.connector.sentFrames.clear();
        await tester.pump(const Duration(seconds: 30));
        expect(harness.connector.polls, 1);
        expect(find.byType(AirActivityDot), findsOneWidget);
      },
    );

    testWidgets(
      '${profile.name}: indicator polling follows application activity',
      (tester) async {
        final harness = await _open(
          tester,
          home: const Scaffold(body: RadioStatsIconButton()),
          powerSaving: PowerSavingSettings(profile: profile),
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        harness.connector.sentFrames.clear();
        await tester.pump(const Duration(seconds: 60));
        expect(harness.connector.polls,
            profile == PowerSavingProfile.disabled ? 2 : 0);
        expect(harness.connector.radioStatsPollingOwners.value,
            profile == PowerSavingProfile.disabled ? 1 : 0);

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        harness.connector.sentFrames.clear();
        await tester.pump(const Duration(seconds: 30));
        expect(harness.connector.polls, 1);
      },
    );
  }

  testWidgets('baseline: stacked indicators share polling across route disposal',
      (tester) async {
    final harness = await _open(
      tester,
      home: const Scaffold(body: RadioStatsIconButton()),
    );
    await _push(
      harness,
      tester,
      const Scaffold(body: RadioStatsIconButton()),
    );
    expect(harness.connector.radioStatsPollingOwners.value, 2);
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 60));
    expect(harness.connector.polls, 2);

    harness.navigator.currentState!.pop();
    await _settleRoute(tester);
    expect(harness.connector.radioStatsPollingOwners.value, 1);
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 30));
    expect(harness.connector.polls, 1);
  });

  testWidgets('baseline: pending-work signal alone does not own polling',
      (tester) async {
    final harness = await _open(tester, home: const Scaffold());
    await _push(
      harness,
      tester,
      const Scaffold(body: RadioStatsIconButton()),
    );
    // Подменён только сигнал работы: это проверка владения таймером,
    // а не имитация полной отправки или подтверждения сообщения.
    harness.connector.sending = true;
    harness.connector.notifyListeners();
    await tester.pump(const Duration(milliseconds: 50));
    expect(harness.connector.radioStatsPollingOwners.value, 1);
    harness.navigator.currentState!.pop();
    await _settleRoute(tester);
    expect(harness.connector.hasPendingRadioStatsWork, isTrue);
    expect(harness.connector.radioStatsPollingOwners.value, 0);
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 60));
    expect(harness.connector.polls, 0);
    await harness.connector.requestRadioStats();
    expect(harness.connector.polls, 1);
  });

  testWidgets('hidden indicator option changes live and preserves manual requests',
      (tester) async {
    final harness = await _open(
      tester,
      home: const Scaffold(body: RadioStatsIconButton()),
      hidden: true,
      powerSaving: const PowerSavingSettings(profile: PowerSavingProfile.custom),
    );
    expect(harness.connector.radioStatsPollingOwners.value, 1);
    await harness.settings.setPauseHiddenRadioIndicator(true);
    expect(harness.connector.radioStatsPollingOwners.value, 0);
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 60));
    expect(harness.connector.polls, 0);
    await harness.connector.requestRadioStats();
    expect(harness.connector.polls, 1);

    await harness.settings.setPowerSavingProfile(PowerSavingProfile.disabled);
    expect(harness.connector.radioStatsPollingOwners.value, 1);
    await harness.settings.setPowerSavingProfile(PowerSavingProfile.custom);
    expect(harness.connector.radioStatsPollingOwners.value, 0);
    await harness.settings.setHideRadioStatsButton(false);
    await tester.pump();
    expect(harness.connector.radioStatsPollingOwners.value, 1);
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 30));
    expect(harness.connector.polls, 1);
  });

  testWidgets('muted indicator releases polling when the option is enabled',
      (tester) async {
    final harness = await _open(
      tester,
      home: const Scaffold(
        body: TickerMode(enabled: false, child: RadioStatsIconButton()),
      ),
      powerSaving: const PowerSavingSettings(profile: PowerSavingProfile.maximum),
    );
    expect(harness.connector.radioStatsPollingOwners.value, 0);
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 60));
    expect(harness.connector.polls, 0);
  });

  testWidgets('opted-in stacked indicators keep just the visible polling owner',
      (tester) async {
    final harness = await _open(
      tester,
      home: const Scaffold(body: RadioStatsIconButton()),
      powerSaving: const PowerSavingSettings(profile: PowerSavingProfile.maximum),
    );
    await _push(harness, tester,
        const Scaffold(body: RadioStatsIconButton()));
    expect(harness.connector.radioStatsPollingOwners.value, 1);
    harness.navigator.currentState!.pop();
    await _settleRoute(tester);
    expect(harness.connector.radioStatsPollingOwners.value, 1);
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 30));
    expect(harness.connector.polls, 1);
  });

  testWidgets('opted-in polling waits for a supported connection', (tester) async {
    final harness = await _open(
      tester,
      home: const Scaffold(body: RadioStatsIconButton()),
      powerSaving: const PowerSavingSettings(profile: PowerSavingProfile.maximum),
    );
    harness.connector.connected = false;
    harness.connector.sending = true;
    harness.connector.notifyListeners();
    await tester.pump(const Duration(milliseconds: 50));
    expect(harness.connector.radioStatsPollingOwners.value, 0);
    harness.connector.connected = true;
    harness.connector.supported = false;
    harness.connector.notifyListeners();
    await tester.pump(const Duration(milliseconds: 50));
    expect(harness.connector.radioStatsPollingOwners.value, 0);
    harness.connector.supported = true;
    harness.connector.notifyListeners();
    await tester.pump(const Duration(milliseconds: 50));
    expect(harness.connector.radioStatsPollingOwners.value, 2);
    harness.connector.sending = false;
    harness.connector.notifyListeners();
    expect(harness.connector.radioStatsPollingOwners.value, 1);
    // Освобождение проверено до UI notify; завершаем его таймер перед выходом.
    await tester.pump(Duration(
      milliseconds: harness.settings.settings.powerSaving.effective
          .uiNotificationIntervalMilliseconds,
    ));
    expect(harness.connector.radioStatsPollingOwners.value, 1);
  });

  testWidgets('send-work ownership survives disposal of the last indicator',
      (tester) async {
    final harness = await _open(
      tester,
      home: const Scaffold(),
      powerSaving: const PowerSavingSettings(profile: PowerSavingProfile.maximum),
    );
    await _push(harness, tester,
        const Scaffold(body: RadioStatsIconButton()));
    harness.connector.sending = true;
    harness.connector.notifyListeners();
    // Удержание возникает сразу, до отложенного уведомления интерфейса.
    expect(harness.connector.radioStatsPollingOwners.value, 2);
    harness.navigator.currentState!.pop();
    await _settleRoute(tester);
    expect(harness.connector.radioStatsPollingOwners.value, 1);
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 30));
    expect(harness.connector.polls, 1);
    harness.connector.sending = false;
    harness.connector.notifyListeners();
    expect(harness.connector.radioStatsPollingOwners.value, 0);
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 60));
    expect(harness.connector.polls, 0);
  });

  testWidgets('retry queue acquires without widgets and cancellation releases it',
      (tester) async {
    final harness = await _open(
      tester,
      home: const Scaffold(),
      powerSaving: const PowerSavingSettings(profile: PowerSavingProfile.maximum),
    );
    final retry = MessageRetryService();
    harness.retryServices.add(retry);
    harness.connector.attachRetryServiceForTest(retry);
    // Настоящая очередь повторов, но без записи истории и физической ноды.
    retry.initialize(RetryServiceConfig(
      sendMessage: (_, _, _, _, {required useFlood}) async => DateTime.now(),
      addMessage: (_, _) {},
      updateMessage: (_) {},
      getSelfPublicKey: () => Uint8List(32),
    ));
    retry.setSendingPaused(true);
    await retry.sendMessageWithRetry(
      contact: Contact(
        publicKey: Uint8List.fromList(List<int>.filled(32, 0xAA)),
        name: 'Synthetic peer',
        type: 1,
        pathLength: -1,
        path: Uint8List(0),
        lastSeen: DateTime.now(),
      ),
      text: 'synthetic queued message',
      messageId: 'energy-test',
    );
    expect(retry.pendingMessageCount.value, 1);
    expect(harness.connector.hasPendingRadioStatsWork, isTrue);
    expect(harness.connector.radioStatsPollingOwners.value, 1);
    retry.untrack('energy-test');
    expect(retry.pendingMessageCount.value, 0);
    expect(harness.connector.hasPendingRadioStatsWork, isFalse);
    expect(harness.connector.radioStatsPollingOwners.value, 0);
  });

  testWidgets('visible statistics retain fast polling above an opted-in indicator',
      (tester) async {
    final harness = await _open(
      tester,
      home: const Scaffold(body: RadioStatsIconButton()),
      powerSaving: const PowerSavingSettings(profile: PowerSavingProfile.maximum),
    );
    await _push(harness, tester, const CompanionRadioStatsScreen());
    expect(harness.connector.radioStatsPollingOwners.value, 1);
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 3));
    expect(harness.connector.polls, 3);
    harness.navigator.currentState!.pop();
    await _settleRoute(tester);
    expect(harness.connector.radioStatsPollingOwners.value, 1);
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 30));
    expect(harness.connector.polls, 1);
  });

  testWidgets('native inactivity pauses an indicator while Flutter stays resumed',
      (tester) async {
    final harness = await _open(
      tester,
      home: const Scaffold(body: RadioStatsIconButton()),
      powerSaving: const PowerSavingSettings(profile: PowerSavingProfile.maximum),
    );
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(IosPresentationBridge.platformChannel,
        (call) async => call.method == 'watch' ? {
          'schema': 1, 'enabled': false, 'active': false, 'revision': 0,
        } : null);
    final bridge = IosPresentationBridge(onPresentationChanged: (_) {});
    addTearDown(() async {
      await bridge.dispose();
      messenger.setMockMethodCallHandler(IosPresentationBridge.platformChannel,
          null);
    });
    await bridge.start();
    expect(tester.binding.lifecycleState, AppLifecycleState.resumed);
    expect(harness.connector.radioStatsPollingOwners.value, 0);
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 60));
    expect(harness.connector.polls, 0);
    await bridge.dispose();
    expect(harness.connector.radioStatsPollingOwners.value, 1);
    await tester.pump(const Duration(seconds: 30));
    expect(harness.connector.polls, 1);
  });

  for (final profile in [
    PowerSavingProfile.balanced,
    PowerSavingProfile.economical,
    PowerSavingProfile.maximum,
  ]) {
    testWidgets('${profile.name}: a covered screen uses its selected interval',
        (tester) async {
      final selected = PowerSavingSettings(profile: profile);
      final interval = selected.effective.hiddenRadioStatsIntervalSeconds;
      final harness = await _open(tester,
        home: const CompanionRadioStatsScreen(), powerSaving: selected);
      await _push(harness, tester, const Scaffold(body: Text('cover')));
      harness.connector.sentFrames.clear();
      await tester.pump(Duration(seconds: interval * 2));
      expect(harness.connector.polls, 2);
      await harness.connector.requestRadioStats();
      expect(harness.connector.polls, 3);
      harness.navigator.currentState!.pop();
      await _settleRoute(tester);
      harness.connector.sentFrames.clear();
      await tester.pump(const Duration(seconds: 3));
      expect(harness.connector.polls, 3);
    });
  }

  testWidgets('custom minimum keeps one-second polling while covered and paused',
      (tester) async {
    final harness = await _open(tester,
      home: const CompanionRadioStatsScreen(),
      powerSaving: const PowerSavingSettings(profile: PowerSavingProfile.custom));
    await _push(harness, tester, const Scaffold());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 3));
    expect(harness.connector.polls, 3);
  });

  testWidgets('profile and custom changes apply live while the screen is covered',
      (tester) async {
    final harness = await _open(tester,
      home: const CompanionRadioStatsScreen());
    await _push(harness, tester, const Scaffold());
    await harness.settings.setPowerSavingProfile(PowerSavingProfile.maximum);
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 60));
    expect(harness.connector.polls, 1);
    await harness.settings.setHiddenRadioStatsIntervalSeconds(7);
    await harness.settings.setPowerSavingProfile(PowerSavingProfile.custom);
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 14));
    expect(harness.connector.polls, 2);
    await harness.settings.setPowerSavingProfile(PowerSavingProfile.disabled);
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 3));
    expect(harness.connector.polls, 3);
  });

  testWidgets('inactive cadence respects other polling owners joining and leaving',
      (tester) async {
    final harness = await _open(tester,
      home: const CompanionRadioStatsScreen(),
      powerSaving: const PowerSavingSettings(profile: PowerSavingProfile.maximum));
    harness.connector.acquireRadioStatsPolling();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 60));
    expect(harness.connector.polls, 2);
    harness.connector.releaseRadioStatsPolling();
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 60));
    expect(harness.connector.polls, 1);
    harness.connector.acquireRadioStatsPolling();
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 30));
    expect(harness.connector.polls, 1);
    harness.connector.releaseRadioStatsPolling();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 3));
    expect(harness.connector.polls, 3);
  });

  testWidgets('another visible statistics screen keeps the fast cadence',
      (tester) async {
    final harness = await _open(tester,
      home: const CompanionRadioStatsScreen(),
      powerSaving: const PowerSavingSettings(profile: PowerSavingProfile.maximum));
    await _push(harness, tester, const CompanionRadioStatsScreen());
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 3));
    expect(harness.connector.polls, 3);
    harness.navigator.currentState!.pop();
    await _settleRoute(tester);
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 3));
    expect(harness.connector.polls, 3);
  });

  testWidgets('pending send work keeps fast observations until it finishes',
      (tester) async {
    final harness = await _open(tester,
      home: const CompanionRadioStatsScreen(),
      powerSaving: const PowerSavingSettings(profile: PowerSavingProfile.maximum));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    harness.connector.sending = true;
    harness.connector.notifyListeners();
    await tester.pump(const Duration(milliseconds: 50));
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 3));
    expect(harness.connector.polls, 3);
    harness.connector.sending = false;
    harness.connector.notifyListeners();
    await tester.pump(const Duration(milliseconds: 50));
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 60));
    expect(harness.connector.polls, 1);
  });

  testWidgets('native inactivity slows polling even when Flutter stays resumed',
      (tester) async {
    final harness = await _open(tester,
      home: const CompanionRadioStatsScreen(),
      powerSaving: const PowerSavingSettings(profile: PowerSavingProfile.maximum));
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(IosPresentationBridge.platformChannel,
        (call) async => call.method == 'watch' ? {
          'schema': 1, 'enabled': false, 'active': false, 'revision': 0,
        } : null);
    final bridge = IosPresentationBridge(onPresentationChanged: (_) {});
    addTearDown(() async {
      await bridge.dispose();
      messenger.setMockMethodCallHandler(IosPresentationBridge.platformChannel,
          null);
    });
    await bridge.start();
    expect(tester.binding.lifecycleState, AppLifecycleState.resumed);
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 60));
    expect(harness.connector.polls, 1);
    await bridge.dispose();
    harness.connector.sentFrames.clear();
    await tester.pump(const Duration(seconds: 3));
    expect(harness.connector.polls, 3);
  });
}
