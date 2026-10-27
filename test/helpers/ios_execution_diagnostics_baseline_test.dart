import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/ios_presentation_guard.dart';

// Count delivered test frames around the real production gate. Explicit pumps
// do not measure native Vsync delivery, audio hardware, or device energy.
class _DiagnosticBaselineBinding extends AutomatedTestWidgetsFlutterBinding
    with IosPresentationFrameGate {
  int beginCallbacks = 0;
  int drawCallbacks = 0;

  @override
  void handleBeginFrame(Duration? rawTimeStamp) {
    beginCallbacks++;
    super.handleBeginFrame(rawTimeStamp);
  }

  @override
  void drawFrame() {
    drawCallbacks++;
    super.drawFrame();
  }
}

void main() {
  final binding = _DiagnosticBaselineBinding();

  testWidgets(
    'baseline: a deferred pipeline still permits resumed frame scheduling and ticker callbacks',
    (tester) async {
      var ticks = 0;
      final ticker = Ticker((_) {
        ticks++;
      });
      try {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        binding.updateIosPresentation(true);
        await tester.pumpWidget(const SizedBox.shrink());
        ticker.start();
        await tester.pump();

        binding.updateIosPresentation(false);
        final oldTicks = ticks;
        final oldBegins = binding.beginCallbacks;
        final oldDraws = binding.drawCallbacks;
        expect(binding.framesEnabled, isTrue);
        expect(binding.sendFramesToEngine, isFalse);

        for (var frame = 0; frame < 3; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(binding.beginCallbacks - oldBegins, 3);
        expect(binding.drawCallbacks - oldDraws, 3);
        expect(ticks - oldTicks, 3);
        expect(ticker.isActive, isTrue);
        expect(binding.hasScheduledFrame, isTrue);
        expect(binding.lifecycleState, AppLifecycleState.resumed);

        binding.updateIosPresentation(true);
        await tester.pump(const Duration(milliseconds: 16));
        expect(binding.sendFramesToEngine, isTrue);
        expect(ticks - oldTicks, 4);
      } finally {
        ticker.dispose();
        binding.updateIosPresentation(true);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'baseline: deferred presentation preserves timers microtasks packets and editor state',
    (tester) async {
      final packets = StreamController<int>(sync: true);
      final received = <int>[];
      var microtasks = 0;
      final subscription = packets.stream.listen((packet) {
        received.add(packet);
        scheduleMicrotask(() {
          microtasks++;
        });
      });
      final ticks = ValueNotifier<int>(0);
      final editor = TextEditingController(text: 'Сохранённый ввод');
      final editorKey = GlobalKey();
      Timer? timer;
      try {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        binding.updateIosPresentation(true);
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: Column(children: [
            TextField(key: editorKey, controller: editor),
            ValueListenableBuilder<int>(
              valueListenable: ticks,
              builder: (context, value, child) => Text('Тики: $value'),
            ),
          ])),
        ));
        final editorState = editorKey.currentState;
        expect(editorState, isNotNull);
        timer = Timer.periodic(const Duration(seconds: 1), (_) {
          ticks.value++;
          packets.add(ticks.value);
        });

        binding.updateIosPresentation(false);
        await tester.pump(const Duration(seconds: 3));
        expect(binding.lifecycleState, AppLifecycleState.resumed);
        expect(binding.sendFramesToEngine, isFalse);
        expect(ticks.value, 3);
        expect(received, [1, 2, 3]);
        expect(microtasks, 3);
        expect(find.text('Тики: 0'), findsOneWidget);
        expect(editorKey.currentState, same(editorState));
        expect(editor.text, 'Сохранённый ввод');

        binding.updateIosPresentation(true);
        await tester.pump();
        expect(find.text('Тики: 3'), findsOneWidget);
        expect(editorKey.currentState, same(editorState));
        expect(editor.text, 'Сохранённый ввод');
        expect(tester.takeException(), isNull);
      } finally {
        timer?.cancel();
        binding.updateIosPresentation(true);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpWidget(const SizedBox.shrink());
        editor.dispose();
        ticks.dispose();
        await tester.runAsync(() async {
          await subscription.cancel().timeout(const Duration(seconds: 3));
          await packets.close().timeout(const Duration(seconds: 3));
        });
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'baseline: allowing presentation does not override framework paused scheduling',
    (tester) async {
      try {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        binding.updateIosPresentation(true);
        await tester.pumpWidget(const SizedBox.shrink());
        binding.updateIosPresentation(false);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        expect(binding.framesEnabled, isFalse);
        final alreadyScheduled = binding.hasScheduledFrame;

        binding.updateIosPresentation(true);
        expect(binding.lifecycleState, AppLifecycleState.paused);
        expect(binding.framesEnabled, isFalse);
        expect(binding.hasScheduledFrame, alreadyScheduled);

        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        expect(binding.framesEnabled, isTrue);
        expect(binding.sendFramesToEngine, isTrue);
      } finally {
        binding.updateIosPresentation(true);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets('diagnostics count delivered gated frames without disabling the ticker', (tester) async {
    var ticks = 0;
    final ticker = Ticker((_) {
      ticks++;
    });
    try {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      binding.updateIosPresentation(true);
      await tester.pumpWidget(const SizedBox.shrink());
      ticker.start();
      await tester.pump();
      final oldTicks = ticks;
      binding.updateIosPresentation(false);
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final snapshot = binding.iosFrameDiagnostics.snapshot;
      expect(snapshot['gatedBeginCallbacks'], 3);
      expect(snapshot['gatedDrawCallbacks'], 3);
      expect(snapshot['gatedSuppressedDraws'], 3);
      expect(snapshot['gatedWarmUpCallbacks'], 0);
      expect(ticks - oldTicks, 3);
      expect(binding.framesEnabled, isTrue);
      binding.updateIosPresentation(true);
      expect(binding.iosFrameDiagnostics.snapshot['gatedBeginCallbacks'], 3);
      await tester.pump(const Duration(milliseconds: 16));
      expect(ticks - oldTicks, 4);
    } finally {
      ticker.dispose();
      binding.updateIosPresentation(true);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
