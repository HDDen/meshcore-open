import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/ios_presentation_guard.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/utils/app_route_observer.dart';
import 'package:meshcore_open/widgets/mesh_ui.dart';
import 'package:meshcore_open/widgets/message_status_icon.dart';
import 'package:provider/provider.dart';

const _statusKey = ValueKey('baseline-message-status');
const _pulseKey = ValueKey('baseline-pulse');
const _pulseColor = Color(0xff348359);
const _step = Duration(milliseconds: 110);

// Наблюдаем только публичный UI и запрошенные ticker callbacks.
// Исходный профиль: без загрузки preferences, транспорта, пакетов и ключей.
Widget _indicators({
  bool pending = false,
  bool failed = false,
  bool acked = false,
  bool channel = false,
  int repeatCount = 0,
  ({int resends, int maxResends})? resendProgress,
  ({int hops, int required})? hopShortfall,
  bool pulse = false,
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
              isAcked: acked,
              isChannel: channel,
              repeatCount: repeatCount,
              resendProgress: resendProgress,
              hopShortfall: hopShortfall,
            ),
            const SizedBox(width: 16),
            PulseDot(key: _pulseKey, color: _pulseColor, size: 9, animate: pulse),
          ],
        ),
      ),
    ),
  ),
);

Future<void> _withIndicators(
  WidgetTester tester,
  Future<void> Function(ValueNotifier<Widget>) body,
) async {
  final content = ValueNotifier<Widget>(_indicators());
  try {
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => AppSettingsService(),
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: [appRouteObserver],
        home: Scaffold(
          body: Center(
            child: ValueListenableBuilder<Widget>(
              valueListenable: content,
              builder: (context, value, _) => value,
            ),
          ),
        ),
      ),
    ));
    await tester.pump(_step);
    await body(content);
  } finally {
    // pumpAndSettle здесь неприменим: проверяем бесконечные анимации.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    content.dispose();
  }
}

Future<void> _startTicks(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(_step);
}

List<int> _dotColors(WidgetTester tester) => tester.widgetList<Container>(
  find.descendant(of: find.byKey(_statusKey), matching: find.byType(Container)),
).map((widget) => (widget.decoration as BoxDecoration).color!.toARGB32()).toList();

double _pulseOpacity(WidgetTester tester) => tester.widget<FadeTransition>(
  find.descendant(of: find.byKey(_pulseKey), matching: find.byType(FadeTransition)),
).opacity.value;

String _statusLabel(WidgetTester tester) => tester.widget<Tooltip>(
  find.descendant(of: find.byKey(_statusKey), matching: find.byType(Tooltip)),
).message!;

Future<void> _expectMovement(WidgetTester tester) async {
  final dots = _dotColors(tester);
  final opacity = _pulseOpacity(tester);
  expect(dots, hasLength(3));
  expect(tester.hasRunningAnimations, isTrue);
  await tester.pump(_step);
  expect(_dotColors(tester), isNot(equals(dots)));
  expect(_pulseOpacity(tester), isNot(opacity));
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('baseline: pending dots animate and stop when the message is sent',
      (tester) async {
    await _withIndicators(tester, (content) async {
      content.value = _indicators(pending: true);
      await _startTicks(tester);
      final dots = _dotColors(tester);
      expect(dots, hasLength(3));
      expect(_statusLabel(tester), 'Sending');
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(_step);
      expect(_dotColors(tester), isNot(equals(dots)));
      content.value = _indicators();
      await _startTicks(tester);
      expect(find.byIcon(Icons.done), findsOneWidget);
      expect(_statusLabel(tester), 'Sent. Waiting for the contact to confirm.');
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  testWidgets('baseline: pulse is opt-in and returns to a static full-opacity dot',
      (tester) async {
    await _withIndicators(tester, (content) async {
      expect(_pulseOpacity(tester), 1);
      expect(tester.hasRunningAnimations, isFalse);
      content.value = _indicators(pulse: true);
      await _startTicks(tester);
      final opacity = _pulseOpacity(tester);
      await tester.pump(_step);
      expect(_pulseOpacity(tester), isNot(opacity));
      content.value = _indicators();
      await _startTicks(tester);
      expect(_pulseOpacity(tester), 1);
      final dot = tester.widget<PulseDot>(find.byKey(_pulseKey));
      expect(dot.color, _pulseColor);
      expect(dot.size, 9);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  testWidgets('baseline: static delivery and channel states keep labels and counts',
      (tester) async {
    await _withIndicators(tester, (content) async {
      content.value = _indicators(acked: true);
      await _startTicks(tester);
      expect(_statusLabel(tester), 'Delivered. The contact confirmed they got it.');
      expect(tester.hasRunningAnimations, isFalse);
      content.value = _indicators(channel: true, repeatCount: 3);
      await _startTicks(tester);
      expect(find.byIcon(Icons.repeat), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(_statusLabel(tester),
          'Heard repeated 3 times. Nearby repeaters passed it on.');
      content.value = _indicators(
        channel: true, repeatCount: 3,
        resendProgress: (resends: 2, maxResends: 5),
      );
      await _startTicks(tester);
      expect(find.byIcon(Icons.autorenew), findsOneWidget);
      expect(find.text('2/5'), findsOneWidget);
      content.value = _indicators(
        channel: true, resendProgress: (resends: 2, maxResends: 5),
        hopShortfall: (hops: 3, required: 5),
      );
      await _startTicks(tester);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(_statusLabel(tester),
          'Sent, but only heard back through 3 of 5 repeaters. '
          'It may still have gone further than your radio can hear.');
      content.value = _indicators(failed: true, channel: true);
      await _startTicks(tester);
      expect(find.byIcon(Icons.cancel), findsOneWidget);
      expect(_statusLabel(tester), "Your radio couldn't send this message.");
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  testWidgets('baseline: failed status hides pending dots but keeps the legacy ticker',
      (tester) async {
    await _withIndicators(tester, (content) async {
      content.value = _indicators(pending: true, failed: true);
      await _startTicks(tester);
      expect(find.byIcon(Icons.cancel), findsOneWidget);
      expect(_statusLabel(tester), 'Failed to send');
      expect(_dotColors(tester), isEmpty);
      expect(tester.hasRunningAnimations, isTrue);
      content.value = _indicators(failed: true);
      await _startTicks(tester);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  testWidgets('baseline: TickerMode mutes and resumes both mounted indicators',
      (tester) async {
    await _withIndicators(tester, (content) async {
      content.value = _indicators(pending: true, pulse: true);
      await _startTicks(tester);
      await _expectMovement(tester);
      content.value = _indicators(pending: true, pulse: true, ticker: false);
      await tester.pump();
      final dots = _dotColors(tester);
      final opacity = _pulseOpacity(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_dotColors(tester), dots);
      expect(_pulseOpacity(tester), opacity);
      expect(tester.hasRunningAnimations, isFalse);
      content.value = _indicators(pending: true, pulse: true);
      await _startTicks(tester);
      await _expectMovement(tester);
    });
  });

  testWidgets('baseline: clipping offscreen indicators does not stop their tickers',
      (tester) async {
    await _withIndicators(tester, (content) async {
      content.value = _indicators(
        pending: true, pulse: true, offset: const Offset(0, 1200),
      );
      await _startTicks(tester);
      expect(tester.getRect(find.byKey(_pulseKey)).top, greaterThan(1000));
      await _expectMovement(tester);
    });
  });

  testWidgets('baseline: an opaque route mutes and restores the existing indicators',
      (tester) async {
    await _withIndicators(tester, (content) async {
      content.value = _indicators(pending: true, pulse: true);
      await _startTicks(tester);
      final statusState = tester.state(find.byKey(_statusKey));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(navigator.push<void>(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('covered')),
      )));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(tester.state(find.byKey(_statusKey, skipOffstage: false)),
          same(statusState));
      expect(tester.hasRunningAnimations, isFalse);
      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await _startTicks(tester);
      expect(tester.state(find.byKey(_statusKey)), same(statusState));
      await _expectMovement(tester);
    });
  });

  testWidgets('baseline: Flutter inactive alone does not pause the status tickers',
      (tester) async {
    final previous = binding.lifecycleState ?? AppLifecycleState.resumed;
    try {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _withIndicators(tester, (content) async {
        content.value = _indicators(pending: true, pulse: true);
        await _startTicks(tester);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await _expectMovement(tester);
      });
    } finally {
      binding.handleAppLifecycleStateChanged(previous);
      await tester.pump();
    }
  });

  testWidgets('baseline: native inactivity alone does not pause the status tickers',
      (tester) async {
    final previous = binding.lifecycleState ?? AppLifecycleState.resumed;
    final messenger = binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(IosPresentationBridge.platformChannel,
        (call) async => call.method == 'watch' ? {
          'schema': 1, 'enabled': false, 'active': false, 'revision': 0,
        } : null);
    // Обычный test binding: gate drawFrame сюда не подмешивается.
    final bridge = IosPresentationBridge(onPresentationChanged: (_) {});
    try {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _withIndicators(tester, (content) async {
        content.value = _indicators(pending: true, pulse: true);
        await _startTicks(tester);
        await bridge.start();
        expect(iosAppPresentationActive.value, isFalse);
        expect(binding.lifecycleState, AppLifecycleState.resumed);
        await _expectMovement(tester);
      });
    } finally {
      await bridge.dispose();
      messenger.setMockMethodCallHandler(IosPresentationBridge.platformChannel, null);
      binding.handleAppLifecycleStateChanged(previous);
      await tester.pump();
    }
  });
}
