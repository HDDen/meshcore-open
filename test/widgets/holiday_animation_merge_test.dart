import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/holiday_animations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppSettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    settings = AppSettingsService();
    addTearDown(settings.dispose);
  });
  tearDown(PrefsManager.reset);

  HolidayTriggerWatcher watcherFor(WidgetTester tester) {
    final clock = tester.binding.clock;
    final start = clock.now();
    return HolidayTriggerWatcher(elapsed: () => clock.now().difference(start));
  }

  Future<BuildContext> host(
    WidgetTester tester, {
    bool reducedMotion = false,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reducedMotion,
            ),
            child: child!,
          ),
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                key: ValueKey('message'),
                width: 160,
                height: 48,
              ),
            ),
          ),
        ),
      ),
    );
    return tester.element(find.byKey(const ValueKey('message')));
  }

  Future<void> send(
    WidgetTester tester,
    HolidayTriggerWatcher watcher,
    BuildContext context,
    String id, {
    Duration age = Duration.zero,
    bool visible = true,
  }) async {
    watcher.onNewest(
      context,
      id: id,
      text: 'Happy New Year',
      receivedAt: DateTime.now().subtract(age),
      messageContext: (_) => visible ? context : null,
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('U19c: only fresh visible greetings play, and only once', (tester) async {
    final watcher = watcherFor(tester);
    addTearDown(watcher.dispose);
    final context = await host(tester);
    await settings.setHolidayAnimationsEnabled(true);
    await send(tester, watcher, context, 'initial');
    expect(find.byType(HolidayAnimationView), findsNothing);
    await send(tester, watcher, context, 'old', age: const Duration(minutes: 3));
    await send(tester, watcher, context, 'offscreen', visible: false);
    expect(find.byType(HolidayAnimationView), findsNothing);

    await send(tester, watcher, context, 'fresh');
    expect(find.byType(HolidayAnimationView), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(HolidayAnimationView), findsNothing);

    await send(tester, watcher, context, 'later', visible: false);
    await send(tester, watcher, context, 'fresh');
    expect(find.byType(HolidayAnimationView), findsNothing);
  });

  testWidgets('U33 baseline: greetings during a playing effect are not queued',
      (tester) async {
    final watcher = watcherFor(tester);
    addTearDown(watcher.dispose);
    final context = await host(tester);
    await settings.setHolidayAnimationsEnabled(true);
    await send(tester, watcher, context, 'initial');

    await send(tester, watcher, context, 'first');
    expect(find.byType(HolidayAnimationView), findsOneWidget);
    await send(tester, watcher, context, 'while-playing');
    expect(find.byType(HolidayAnimationView), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(HolidayAnimationView), findsNothing);

    await tester.pump(const Duration(seconds: 6));
    expect(find.byType(HolidayAnimationView), findsNothing);
    await send(tester, watcher, context, 'new-greeting');
    expect(find.byType(HolidayAnimationView), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(HolidayAnimationView), findsNothing);
  });

  testWidgets('U33: two chats share the playing gate and five-second pause',
      (tester) async {
    final first = watcherFor(tester);
    final second = watcherFor(tester);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final context = await host(tester);
    await settings.setHolidayAnimationsEnabled(true);
    await send(tester, first, context, 'initial-direct');
    await send(tester, second, context, 'initial-channel');

    await send(tester, first, context, 'playing');
    await send(tester, second, context, 'during-playing');
    expect(find.byType(HolidayAnimationView), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(HolidayAnimationView), findsNothing);

    await tester.pump(const Duration(seconds: 4));
    await send(tester, second, context, 'during-pause');
    expect(find.byType(HolidayAnimationView), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(HolidayAnimationView), findsNothing);
    await send(tester, second, context, 'after-pause');
    expect(find.byType(HolidayAnimationView), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('U19c: settings, reduced motion and power can block an effect', (tester) async {
    final watcher = watcherFor(tester);
    addTearDown(watcher.dispose);
    var context = await host(tester);
    await send(tester, watcher, context, 'initial');
    await send(tester, watcher, context, 'disabled');
    expect(find.byType(HolidayAnimationView), findsNothing);

    await settings.setHolidayAnimationsEnabled(true);
    context = await host(tester, reducedMotion: true);
    await send(tester, watcher, context, 'reduced');
    expect(find.byType(HolidayAnimationView), findsNothing);

    context = await host(tester);
    await settings.setPowerSavingProfile(PowerSavingProfile.maximum);
    await send(tester, watcher, context, 'economical');
    expect(find.byType(HolidayAnimationView), findsNothing);

    await settings.setPowerSavingProfile(PowerSavingProfile.disabled);
    await send(tester, watcher, context, 'restored');
    expect(find.byType(HolidayAnimationView), findsOneWidget);
    await settings.setPowerSavingProfile(PowerSavingProfile.maximum);
    await tester.pump();
    expect(find.byType(HolidayAnimationView), findsNothing);
  });

  testWidgets('U19c: foreground loss or a covering route cancels the overlay', (tester) async {
    final watcher = watcherFor(tester);
    addTearDown(watcher.dispose);
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await settings.setHolidayAnimationsEnabled(true);
    final context = await host(tester);
    await send(tester, watcher, context, 'initial');
    await send(tester, watcher, context, 'fresh');
    expect(find.byType(HolidayAnimationView), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(HolidayAnimationView, skipOffstage: false), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await send(tester, watcher, context, 'next');
    expect(find.byType(HolidayAnimationView), findsOneWidget);
    unawaited(Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('cover'))),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(HolidayAnimationView, skipOffstage: false), findsNothing);
    expect(find.text('cover'), findsOneWidget);
  });
}
