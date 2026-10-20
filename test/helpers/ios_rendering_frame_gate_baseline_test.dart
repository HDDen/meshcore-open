import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Probe the framework seam before wiring any native lifecycle workaround.
// This does not reproduce Metal corruption or prove that a device is fixed.
class _PresentationProbeBinding extends AutomatedTestWidgetsFlutterBinding {
  bool presentationAllowed = true;

  @override
  bool get sendFramesToEngine =>
      presentationAllowed && super.sendFramesToEngine;
}

void main() {
  final binding = _PresentationProbeBinding();

  testWidgets(
    'presentation gate preserves Dart work and widget state while lifecycle stays resumed',
    (tester) async {
      final packets = StreamController<String>(sync: true);
      final ticks = ValueNotifier<int>(0);
      final input = TextEditingController(text: 'Сохранённый ввод');
      final editorKey = GlobalKey();
      final received = <String>[];
      final subscription = packets.stream.listen(received.add);
      final timer = Timer.periodic(const Duration(seconds: 1), (_) {
        ticks.value++;
      });
      try {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: Column(children: [
            TextField(key: editorKey, controller: input),
            ValueListenableBuilder<int>(
              valueListenable: ticks,
              builder: (context, count, child) =>
                  Text('Тест связи · 2 hops · 0123456789 · C2L: $count'),
            ),
          ])),
        ));
        final editor = editorKey.currentState;
        expect(editor, isNotNull);
        expect(binding.sendFramesToEngine, isTrue);

        // A tweaked app may still report resumed after physical backgrounding.
        binding.presentationAllowed = false;
        packets.add('background packet');
        await tester.pump(const Duration(seconds: 3));
        expect(binding.sendFramesToEngine, isFalse);
        expect(binding.lifecycleState, AppLifecycleState.resumed);
        expect(ticks.value, 3);
        expect(received, ['background packet']);
        expect(find.text('Тест связи · 2 hops · 0123456789 · C2L: 3'),
            findsOneWidget);
        expect(editorKey.currentState, same(editor));
        expect(input.text, 'Сохранённый ввод');

        binding.presentationAllowed = true;
        binding.scheduleForcedFrame();
        packets.add('foreground packet');
        await tester.pump(const Duration(seconds: 1));
        expect(binding.sendFramesToEngine, isTrue);
        expect(binding.lifecycleState, AppLifecycleState.resumed);
        expect(ticks.value, 4);
        expect(received, ['background packet', 'foreground packet']);
        expect(editorKey.currentState, same(editor));
        expect(input.text, 'Сохранённый ввод');
      } finally {
        timer.cancel();
        // Restore presentation before any awaited cleanup, also after a failed
        // assertion. The framework must be able to paint its teardown frame.
        binding.presentationAllowed = true;
        try {
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          input.dispose();
          ticks.dispose();
          // Stream completion may cross the fake-clock/root-zone boundary.
          // runAsync lets the harness drive both zones instead of awaiting a
          // completion outside pump with no further fake-clock advancement.
          await tester.runAsync(() async {
            await subscription.cancel().timeout(const Duration(seconds: 3));
            await packets.close().timeout(const Duration(seconds: 3));
          });
        }
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
