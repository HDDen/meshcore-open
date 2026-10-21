import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/widgets/snr_indicator.dart';

// Probe the earlier frame boundary before changing the production guard.
// This deliberately leaves Dart's lifecycle resumed, as Immortalizer can.
// UIKit, Metal and the injected dylib are not exercised by this test.
class _PipelineProbeBinding extends AutomatedTestWidgetsFlutterBinding {
  bool _deferred = false;

  @override
  bool get sendFramesToEngine => !_deferred && super.sendFramesToEngine;

  @override
  void drawFrame() {
    if (!_deferred) {
      super.drawFrame();
    }
  }

  void deferPipeline(bool deferred) {
    if (_deferred == deferred) {
      return;
    }
    _deferred = deferred;
    if (!deferred) {
      scheduleFrame();
    }
  }
}

// Only the real SNR widget's read-only model/notifier contract is needed.
// Avoid constructing a transport or starting the application's services.
class _RepeaterProbe extends ChangeNotifier implements MeshCoreConnector {
  @override
  final ValueNotifier<int> repeaterActivity = ValueNotifier<int>(0);

  @override
  final List<DirectRepeater> activeRepeaters = [
    DirectRepeater(pubkeyPrefix: const [0x22], pathHashWidth: 1, snr: 0),
  ];

  @override
  int? get currentSf => 7;

  void receive(int packet) {
    activeRepeaters.single.update(packet / 4);
    repeaterActivity.value++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  void dispose() {
    repeaterActivity.dispose();
    super.dispose();
  }
}

class _PipelineCounts {
  int layouts = 0;
  int paints = 0;
}

class _PipelineCounter extends SingleChildRenderObjectWidget {
  const _PipelineCounter({required this.counts, required super.child});

  final _PipelineCounts counts;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PipelineCounterBox(counts);

  @override
  void updateRenderObject(BuildContext context, _PipelineCounterBox renderObject) {
    // Each rebuilt sample needs layout/paint, so their absence while deferred
    // cannot be mistaken for an otherwise clean rendering pipeline.
    renderObject.markNeedsLayout();
    renderObject.markNeedsPaint();
  }
}

class _PipelineCounterBox extends RenderProxyBox {
  _PipelineCounterBox(this.counts);

  final _PipelineCounts counts;

  @override
  void performLayout() {
    counts.layouts++;
    super.performLayout();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    counts.paints++;
    super.paint(context, offset);
  }
}

void main() {
  final binding = _PipelineProbeBinding();

  testWidgets(
    'deferring the UI pipeline preserves background packets and SNR state across resume',
    (tester) async {
      final connector = _RepeaterProbe();
      final counts = _PipelineCounts();
      final ticks = ValueNotifier<int>(0);
      final editor = TextEditingController(text: 'Сохранённый ввод');
      final editorKey = GlobalKey();
      final packets = StreamController<int>(sync: true);
      final received = <int>[];
      final subscription = packets.stream.listen((packet) {
        received.add(packet);
        connector.receive(packet);
      });
      final timer = Timer.periodic(const Duration(seconds: 1), (_) {
        ticks.value++;
        packets.add(ticks.value);
      });

      try {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              toolbarHeight: 88,
              title: SNRActivityIndicator(connector: connector),
            ),
            body: ValueListenableBuilder<int>(
              valueListenable: ticks,
              builder: (context, count, child) => _PipelineCounter(
                counts: counts,
                child: Column(children: [
                  TextField(key: editorKey, controller: editor),
                  Text('Принято: $count'),
                ]),
              ),
            ),
          ),
        ));
        final editorState = editorKey.currentState;
        expect(editorState, isNotNull);
        expect(counts.layouts, greaterThan(0));
        expect(counts.paints, greaterThan(0));
        expect(find.text('0.0 dB'), findsOneWidget);

        var totalSeconds = 0;
        for (final seconds in [38, 66]) {
          final oldLayouts = counts.layouts;
          final oldPaints = counts.paints;
          binding.deferPipeline(true);
          await tester.pump(Duration(seconds: seconds));
          totalSeconds += seconds;

          expect(binding.lifecycleState, AppLifecycleState.resumed);
          expect(binding.sendFramesToEngine, isFalse);
          expect(ticks.value, totalSeconds);
          expect(received, List<int>.generate(totalSeconds, (i) => i + 1));
          expect(connector.activeRepeaters.single.snr, totalSeconds / 4);
          expect(counts.layouts, oldLayouts);
          expect(counts.paints, oldPaints);
          expect(editor.text, 'Сохранённый ввод');

          binding.deferPipeline(false);
          await tester.pump();
          expect(binding.sendFramesToEngine, isTrue);
          expect(counts.layouts, greaterThan(oldLayouts));
          expect(counts.paints, greaterThan(oldPaints));
          expect(find.text('Принято: $totalSeconds'), findsOneWidget);
          expect(
            find.text('${(totalSeconds / 4).toStringAsFixed(1)} dB'),
            findsOneWidget,
          );
          expect(editorKey.currentState, same(editorState));
          expect(editor.text, 'Сохранённый ввод');
          expect(tester.takeException(), isNull);
        }
      } finally {
        timer.cancel();
        binding.deferPipeline(false);
        try {
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          editor.dispose();
          ticks.dispose();
          connector.dispose();
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
