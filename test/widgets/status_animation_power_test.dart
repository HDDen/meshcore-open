import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/ios_presentation_guard.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/utils/app_route_observer.dart';
import 'package:meshcore_open/widgets/mesh_ui.dart';
import 'package:meshcore_open/widgets/message_status_icon.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

const _statusKey = ValueKey('power-message-status');
const _pulseKey = ValueKey('power-pulse');
const _step = Duration(milliseconds: 110);
const _hiddenOnly = PowerSavingOptions(pauseHiddenStatusAnimations: true);
const _staticOnly = PowerSavingOptions(disableContinuousStatusAnimations: true);
const _both = PowerSavingOptions(
  pauseHiddenStatusAnimations: true,
  disableContinuousStatusAnimations: true,
);

Widget _indicators({
  bool pending = true,
  bool pulse = true,
  bool failed = false,
  bool channel = false,
  int repeatCount = 0,
  bool ticker = true,
  Offset offset = Offset.zero,
}) => ClipRect(
  child: SizedBox(
    width: 180,
    height: 90,
    child: Transform.translate(
      offset: offset,
      child: TickerMode(
        enabled: ticker,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MessageStatusIcon(
              key: _statusKey,
              isPending: pending,
              isFailed: failed,
              isAcked: false,
              isChannel: channel,
              repeatCount: repeatCount,
            ),
            const SizedBox(width: 16),
            PulseDot(key: _pulseKey, color: Colors.green, size: 9, animate: pulse),
          ],
        ),
      ),
    ),
  ),
);

Future<void> _flush(WidgetTester tester) async {
  await tester.pump();
  VisibilityDetectorController.instance.notifyNow();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(_step);
}

Future<void> _withIndicators(
  WidgetTester tester,
  PowerSavingOptions options,
  Future<void> Function(ValueNotifier<Widget>, AppSettingsService) body, {
  PowerSavingProfile profile = PowerSavingProfile.custom,
}) async {
  final settings = AppSettingsService();
  final content = ValueNotifier<Widget>(_indicators());
  try {
    await settings.updateSettings(settings.settings.copyWith(
      powerSaving: PowerSavingSettings(profile: profile, custom: options),
    ));
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: settings,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: [appRouteObserver],
        home: Scaffold(body: Center(child: ValueListenableBuilder<Widget>(
          valueListenable: content,
          builder: (context, value, _) => value,
        ))),
      ),
    ));
    await _flush(tester);
    await body(content, settings);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    VisibilityDetectorController.instance.notifyNow();
    await tester.pump();
    content.dispose();
    settings.dispose();
  }
}

List<int> _colors(WidgetTester tester) => tester.widgetList<Container>(
  find.descendant(of: find.byKey(_statusKey), matching: find.byType(Container)),
).map((widget) => (widget.decoration as BoxDecoration).color!.toARGB32()).toList();

double _opacity(WidgetTester tester) => tester.widget<FadeTransition>(
  find.descendant(of: find.byKey(_pulseKey), matching: find.byType(FadeTransition)),
).opacity.value;

String _label(WidgetTester tester) => tester.widget<Tooltip>(
  find.descendant(of: find.byKey(_statusKey), matching: find.byType(Tooltip)),
).message!;

Future<void> _expectMovement(WidgetTester tester) async {
  final colors = _colors(tester);
  final opacity = _opacity(tester);
  expect(colors, hasLength(3));
  expect(tester.hasRunningAnimations, isTrue);
  await tester.pump(_step);
  expect(_colors(tester), isNot(equals(colors)));
  expect(_opacity(tester), isNot(opacity));
}

Future<void> _expectStill(WidgetTester tester) async {
  final colors = _colors(tester);
  final opacity = _opacity(tester);
  expect(tester.hasRunningAnimations, isFalse);
  await tester.pump(const Duration(milliseconds: 300));
  expect(_colors(tester), colors);
  expect(_opacity(tester), opacity);
  expect(tester.hasRunningAnimations, isFalse);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Duration previousVisibilityInterval;
  setUp(() async {
    // Подготовка prefs выполняется вне FakeAsync widget-теста.
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    previousVisibilityInterval = VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });
  tearDown(() {
    PrefsManager.reset();
    VisibilityDetectorController.instance.updateInterval = previousVisibilityInterval;
  });

  testWidgets('Off ignores saved animation flags and adds no viewport observers',
      (tester) async {
    await _withIndicators(tester, _both, (content, settings) async {
      expect(settings.settings.powerSaving.custom.pauseHiddenStatusAnimations, isTrue);
      expect(find.byType(VisibilityDetector), findsNothing);
      await _expectMovement(tester);
    }, profile: PowerSavingProfile.disabled);
  });

  testWidgets('hidden pause preserves visible animation and stops clipped tickers',
      (tester) async {
    await _withIndicators(tester, _hiddenOnly, (content, settings) async {
      final state = tester.state(find.byKey(_statusKey));
      await _expectMovement(tester);
      content.value = _indicators(offset: const Offset(0, 1200));
      await _flush(tester);
      expect(tester.getRect(find.byKey(_pulseKey)).top, greaterThan(1000));
      await _expectStill(tester);
      content.value = _indicators();
      await _flush(tester);
      expect(tester.state(find.byKey(_statusKey)), same(state));
      await _expectMovement(tester);
    });
  });

  testWidgets('static mode preserves sending status without tickers or observers',
      (tester) async {
    await _withIndicators(tester, _staticOnly, (content, settings) async {
      expect(_label(tester), 'Sending');
      expect(_colors(tester), hasLength(3));
      expect(_colors(tester).toSet(), hasLength(1));
      expect(_opacity(tester), 1);
      expect(tester.widget<PulseDot>(find.byKey(_pulseKey)).color, Colors.green);
      expect(find.byType(VisibilityDetector), findsNothing);
      await _expectStill(tester);
      await settings.setPauseHiddenStatusAnimations(true);
      await _flush(tester);
      expect(find.byType(VisibilityDetector), findsNothing);
      await settings.setDisableContinuousStatusAnimations(false);
      await _flush(tester);
      expect(settings.settings.powerSaving.custom.pauseHiddenStatusAnimations, isTrue);
      expect(find.byType(VisibilityDetector), findsNWidgets(2));
      await _expectMovement(tester);
      await settings.setDisableContinuousStatusAnimations(true);
      await _flush(tester);
      expect(find.byType(VisibilityDetector), findsNothing);
      await _expectStill(tester);
    });
  });

  testWidgets('turning hidden pause off restores legacy offscreen animation live',
      (tester) async {
    await _withIndicators(tester, _hiddenOnly, (content, settings) async {
      content.value = _indicators(offset: const Offset(0, 1200));
      await _flush(tester);
      await _expectStill(tester);
      await settings.setPauseHiddenStatusAnimations(false);
      await _flush(tester);
      expect(find.byType(VisibilityDetector), findsNothing);
      await _expectMovement(tester);
    });
  });

  testWidgets('live flag changes keep ancestor TickerMode authoritative',
      (tester) async {
    await _withIndicators(tester, _hiddenOnly, (content, settings) async {
      content.value = _indicators(ticker: false);
      await _flush(tester);
      await _expectStill(tester);
      await settings.setPauseHiddenStatusAnimations(false);
      await settings.setDisableContinuousStatusAnimations(true);
      await _flush(tester);
      await settings.setDisableContinuousStatusAnimations(false);
      await _flush(tester);
      await _expectStill(tester);
      content.value = _indicators();
      await _flush(tester);
      await _expectMovement(tester);
    });
  });

  testWidgets('covered indicators resume their existing states after route return',
      (tester) async {
    await _withIndicators(tester, _hiddenOnly, (content, settings) async {
      final state = tester.state(find.byKey(_statusKey));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(navigator.push<void>(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('covered')),
      )));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.state(find.byKey(_statusKey, skipOffstage: false)), same(state));
      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await _flush(tester);
      expect(tester.state(find.byKey(_statusKey)), same(state));
      await _expectMovement(tester);
    });
  });

  testWidgets('inactive and paused stop status tickers and resume restores them',
      (tester) async {
    final previous = binding.lifecycleState ?? AppLifecycleState.resumed;
    try {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _withIndicators(tester, _hiddenOnly, (content, settings) async {
        await _expectMovement(tester);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await _flush(tester);
        await _expectStill(tester);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        expect(tester.hasRunningAnimations, isFalse);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await _flush(tester);
        await _expectMovement(tester);
      });
    } finally {
      binding.handleAppLifecycleStateChanged(previous);
      await tester.pump();
    }
  });

  testWidgets('native inactivity stops tickers while Flutter remains resumed',
      (tester) async {
    final previous = binding.lifecycleState ?? AppLifecycleState.resumed;
    final messenger = binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(IosPresentationBridge.platformChannel,
        (call) async => call.method == 'watch' ? {
          'schema': 1, 'enabled': false, 'active': false, 'revision': 0,
        } : null);
    final bridge = IosPresentationBridge(onPresentationChanged: (_) {});
    try {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _withIndicators(tester, _hiddenOnly, (content, settings) async {
        await _expectMovement(tester);
        await bridge.start();
        await _flush(tester);
        expect(iosAppPresentationActive.value, isFalse);
        expect(binding.lifecycleState, AppLifecycleState.resumed);
        await _expectStill(tester);
        await bridge.dispose();
        await _flush(tester);
        await _expectMovement(tester);
      });
      // Поздний native callback после unmount не обращается к контроллерам.
      await bridge.start();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.hasRunningAnimations, isFalse);
    } finally {
      await bridge.dispose();
      messenger.setMockMethodCallHandler(IosPresentationBridge.platformChannel, null);
      binding.handleAppLifecycleStateChanged(previous);
      await tester.pump();
    }
  });

  testWidgets('failed pending state stops its hidden animation with the pause flag',
      (tester) async {
    await _withIndicators(tester, _hiddenOnly, (content, settings) async {
      content.value = _indicators(failed: true, pulse: false);
      await _flush(tester);
      expect(find.byIcon(Icons.cancel), findsOneWidget);
      expect(_label(tester), 'Failed to send');
      expect(_colors(tester), isEmpty);
      expect(find.byType(VisibilityDetector), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
      content.value = _indicators(pulse: false);
      await _flush(tester);
      final colors = _colors(tester);
      expect(_label(tester), 'Sending');
      await tester.pump(_step);
      expect(_colors(tester), isNot(equals(colors)));
    });
  });

  testWidgets('static mode still updates completed status and repeat counts',
      (tester) async {
    await _withIndicators(tester, _both, (content, settings) async {
      content.value = _indicators(pending: false, channel: true, repeatCount: 3);
      await _flush(tester);
      expect(find.byIcon(Icons.repeat), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      content.value = _indicators(pending: false, channel: true, repeatCount: 4);
      await _flush(tester);
      expect(find.text('4'), findsOneWidget);
      expect(_label(tester), 'Heard repeated 4 times. Nearby repeaters passed it on.');
      expect(_opacity(tester), 1);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
