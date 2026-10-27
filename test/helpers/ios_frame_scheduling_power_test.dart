import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/ios_presentation_guard.dart';

class _PowerBinding extends AutomatedTestWidgetsFlutterBinding
    with IosPresentationFrameGate {}

void main() {
  final binding = _PowerBinding();

  Future<void> restore(WidgetTester tester) async {
    binding.updateIosPresentation(true);
    binding.updateIosFrameSchedulingPause(false);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('opted-in scheduling drains one pending frame and resumes the same ticker', (tester) async {
    var ticks = 0;
    final ticker = Ticker((_) { ticks++; });
    try {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
      ticker.start();
      await tester.pump();
      binding.updateIosFrameSchedulingPause(true);
      expect(binding.framesEnabled, isTrue); // Visible screen is unaffected.
      binding.updateIosPresentation(false);
      expect(binding.framesEnabled, isFalse);
      await tester.pump(const Duration(milliseconds: 16)); // Already requested Vsync.
      final drainedTicks = ticks;
      expect(binding.hasScheduledFrame, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(ticks, drainedTicks);
      expect(ticker.isActive, isTrue);
      expect(binding.lifecycleState, AppLifecycleState.resumed);

      binding.updateIosPresentation(true);
      expect(binding.hasScheduledFrame, isTrue);
      await tester.pump(const Duration(milliseconds: 16));
      expect(ticks, drainedTicks + 1);
      expect(binding.sendFramesToEngine, isTrue);
    } finally {
      ticker.dispose();
      await restore(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('UI pause preserves timers packet callbacks and retained editor; Off restores scheduling', (tester) async {
    var received = 0;
    var microtasks = 0;
    final value = ValueNotifier<int>(0);
    final packets = StreamController<int>(sync: true);
    final subscription = packets.stream.listen((packet) {
      received += packet;
      scheduleMicrotask(() { microtasks++; });
    });
    final editor = TextEditingController(text: 'Сохранённый ввод');
    final editorKey = GlobalKey();
    Timer? timer;
    try {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [
        TextField(key: editorKey, controller: editor),
        ValueListenableBuilder<int>(valueListenable: value,
          builder: (context, value, child) => Text('RX: $value')),
      ]))));
      final editorState = editorKey.currentState;
      binding.updateIosFrameSchedulingPause(true);
      binding.updateIosPresentation(false);
      await tester.pump();
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        value.value++;
        packets.add(1);
      });
      await tester.pump(const Duration(seconds: 3));
      expect([value.value, received, microtasks], [3, 3, 3]);
      expect(binding.hasScheduledFrame, isFalse);
      expect(binding.lifecycleState, AppLifecycleState.resumed);
      expect(find.text('RX: 0'), findsOneWidget);
      expect(editorKey.currentState, same(editorState));

      binding.updateIosFrameSchedulingPause(false);
      expect(binding.framesEnabled, isTrue);
      expect(binding.hasScheduledFrame, isTrue);
      await tester.pump();
      expect(binding.sendFramesToEngine, isFalse); // GPU/pipeline guard still closed.
      expect(find.text('RX: 0'), findsOneWidget);
      binding.updateIosPresentation(true);
      await tester.pump();
      expect(find.text('RX: 3'), findsOneWidget);
      expect(editorKey.currentState, same(editorState));
      expect(editor.text, 'Сохранённый ввод');
      expect(tester.takeException(), isNull);
    } finally {
      timer?.cancel();
      await restore(tester);
      editor.dispose();
      value.dispose();
      await tester.runAsync(() async {
        await subscription.cancel().timeout(const Duration(seconds: 3));
        await packets.close().timeout(const Duration(seconds: 3));
      });
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('forced frames retain the pipeline guard and opting out never overrides OS paused', (tester) async {
    try {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const Text('Visible', textDirection: TextDirection.ltr));
      binding.updateIosFrameSchedulingPause(true);
      binding.updateIosPresentation(false);
      await tester.pump();
      final before = binding.iosFrameDiagnostics.snapshot['gatedSuppressedDraws'] as int;
      binding.scheduleForcedFrame();
      await tester.pump();
      expect(binding.iosFrameDiagnostics.snapshot['gatedSuppressedDraws'], before + 1);
      expect(binding.sendFramesToEngine, isFalse);
      expect(binding.framesEnabled, isFalse);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      binding.updateIosFrameSchedulingPause(false);
      binding.updateIosPresentation(true);
      expect(binding.framesEnabled, isFalse);
      expect(binding.lifecycleState, AppLifecycleState.paused);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(binding.framesEnabled, isTrue);
    } finally {
      await restore(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
