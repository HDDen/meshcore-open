import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/ios_presentation_guard.dart';
import 'package:meshcore_open/widgets/snr_indicator.dart';

class _GateBinding extends AutomatedTestWidgetsFlutterBinding
    with IosPresentationFrameGate {}

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
  int builds = 0;
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
  final binding = _GateBinding();
  final messenger = binding.defaultBinaryMessenger;
  const channel = IosPresentationBridge.platformChannel;
  const codec = StandardMethodCodec();
  const shortTimeout = Timeout(Duration(seconds: 10));
  late IosPresentationBridge bridge;
  late List<bool> allowed;

  Map<String, Object> snapshot(int revision, bool active, {bool enabled = true}) => {
    'schema': 1, 'revision': revision, 'active': active, 'enabled': enabled,
  };

  Future<void> emit(Object? data) async {
    await messenger.handlePlatformMessage(channel.name,
        codec.encodeMethodCall(MethodCall('presentation', data)), null);
  }

  setUp(() {
    allowed = <bool>[];
    bridge = IosPresentationBridge(onPresentationChanged: allowed.add);
    messenger.setMockMethodCallHandler(channel, (call) async =>
        call.method == 'watch' ? snapshot(0, true) : null);
  });

  tearDown(() async {
    // These protocol tests use ordinary async, not widget-test fake time.
    await bridge.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('native background event wins over a delayed active watch snapshot', () async {
    final entered = Completer<void>();
    final initial = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'watch') {
        return null;
      }
      entered.complete();
      return initial.future;
    });
    final start = bridge.start();
    try {
      await entered.future;
      await emit(snapshot(2, false));
      initial.complete(snapshot(1, true));
      await start;
      expect(allowed, [false]);
      await emit(snapshot(3, true));
      await emit(snapshot(3, false));
      await emit(snapshot(2, false));
      expect(allowed, [false, true]);
    } finally {
      if (!initial.isCompleted) {
        initial.complete(snapshot(1, true));
      }
      await start;
    }
  }, timeout: shortTimeout);

  test('without an injected tweak native inactivity does not gate frames', () async {
    messenger.setMockMethodCallHandler(channel, (call) async =>
        call.method == 'watch' ? snapshot(0, false, enabled: false) : null);
    await bridge.start();
    expect(allowed, [true]);
    await emit(snapshot(1, false, enabled: false));
    expect(allowed.last, isTrue);
  }, timeout: shortTimeout);

  test('native scene and timing metadata cannot override ordered activity', () async {
    await bridge.start();
    await emit({
      ...snapshot(1, false),
      'source': 'scene.willDeactivate',
      'nativeAtUtcMs': DateTime.now().millisecondsSinceEpoch - 600000,
      'nativeUptimeMs': 1000,
      'applicationActive': true,
      'sceneActive': false,
    });
    expect(allowed, [true, false]);
    // Late delivery and contradictory diagnostic metadata must never reopen
    // the gate; the native aggregate and revision remain authoritative.
    await emit({
      ...snapshot(1, true),
      'source': 'application.didBecomeActive',
      'sceneActive': true,
    });
    expect(allowed, [true, false]);
    await emit({
      ...snapshot(2, true),
      'source': 'scene.didActivate',
      'nativeAtUtcMs': 'bad optional diagnostic field',
    });
    expect(allowed, [true, false, true]);
  }, timeout: shortTimeout);

  test('malformed events cannot reopen presentation after a background event', () async {
    await bridge.start();
    await emit(snapshot(1, false));
    for (final bad in <Object?>[
      null, 'active', <String, Object>{},
      {...snapshot(2, true), 'schema': 2},
      {...snapshot(2, true), 'revision': '2'},
      {...snapshot(2, true), 'active': 1},
      {...snapshot(2, true), 'enabled': 'false'},
      snapshot(-1, true),
    ]) {
      await emit(bad);
    }
    expect(allowed, [true, false]);
    await emit(snapshot(2, true));
    expect(allowed, [true, false, true]);
  }, timeout: shortTimeout);

  test('empty native watch reply preserves ordinary Flutter rendering', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await bridge.start();
    expect(allowed, [true]);
    await emit(snapshot(1, false));
    expect(allowed, [true]);
  }, timeout: shortTimeout);

  test('missing optional native bridge preserves ordinary Flutter rendering', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => throw MissingPluginException());
    await bridge.start();
    expect(allowed, [true]);
    await emit(snapshot(1, false));
    expect(allowed, [true]);
  }, timeout: shortTimeout);

  test('disposing a pending watch fences its late inactive snapshot', () async {
    final entered = Completer<void>();
    final initial = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'watch') {
        return null;
      }
      entered.complete();
      return initial.future;
    });
    final start = bridge.start();
    try {
      await entered.future;
      await bridge.dispose();
      initial.complete(snapshot(0, false));
      await start;
      await emit(snapshot(1, false));
      expect(allowed, [true]);
    } finally {
      if (!initial.isCompleted) {
        initial.complete(snapshot(0, false));
      }
      await start;
    }
  }, timeout: shortTimeout);

  testWidgets('production UI gate defers text painting while background packets and editor state survive', (tester) async {
    await tester.runAsync(bridge.dispose);
    bridge = IosPresentationBridge(
      onPresentationChanged: binding.updateIosPresentation,
    );
    final ticks = ValueNotifier<int>(0);
    final connector = _RepeaterProbe();
    final counts = _PipelineCounts();
    final editor = TextEditingController(text: 'Сохранённый ввод');
    final editorKey = GlobalKey();
    final packets = StreamController<int>(sync: true);
    final received = <int>[];
    final subscription = packets.stream.listen((packet) {
      received.add(packet);
      ticks.value = packet;
      connector.receive(packet);
    });
    var packetCounter = 0;
    final timer = Timer.periodic(const Duration(seconds: 1), (_) {
      packets.add(++packetCounter);
    });
    try {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(bridge.start);
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        appBar: AppBar(
          toolbarHeight: 88,
          title: SNRActivityIndicator(connector: connector),
        ),
        body: ValueListenableBuilder<int>(
          valueListenable: ticks,
          builder: (context, count, child) {
            counts.builds++;
            return _PipelineCounter(
              counts: counts,
              child: Column(children: [
                TextField(key: editorKey, controller: editor),
                Text('Тест связи: $count'),
              ]),
            );
          },
        ),
      )));
      final state = editorKey.currentState;
      expect(state, isNotNull);
      expect(counts.layouts, greaterThan(0));
      expect(counts.paints, greaterThan(0));
      var revision = 0;
      var totalSeconds = 0;
      for (final seconds in [38, 66]) {
        final oldBuilds = counts.builds;
        final oldLayouts = counts.layouts;
        final oldPaints = counts.paints;
        final oldSeconds = totalSeconds;
        await tester.runAsync(() => emit(snapshot(++revision, false)));
        await tester.pump(Duration(seconds: seconds));
        totalSeconds += seconds;

        expect(binding.sendFramesToEngine, isFalse);
        expect(binding.lifecycleState, AppLifecycleState.resumed);
        expect(ticks.value, totalSeconds);
        expect(received, List<int>.generate(totalSeconds, (i) => i + 1));
        expect(connector.activeRepeaters.single.snr, totalSeconds / 4);
        expect(counts.builds, oldBuilds);
        expect(counts.layouts, oldLayouts);
        expect(counts.paints, oldPaints);
        expect(find.text('Тест связи: $oldSeconds'), findsOneWidget);
        expect(editorKey.currentState, same(state));

        // An older or malformed event must not accidentally flush dirty text.
        await tester.runAsync(() => emit(snapshot(revision - 1, true)));
        await tester.runAsync(() => emit({'active': true}));
        await tester.pump();
        expect(counts.builds, oldBuilds);
        expect(counts.layouts, oldLayouts);
        expect(counts.paints, oldPaints);

        await tester.runAsync(() => emit(snapshot(++revision, true)));
        expect(binding.hasScheduledFrame, isTrue);
        await tester.pump();
        expect(binding.sendFramesToEngine, isTrue);
        expect(counts.builds, greaterThan(oldBuilds));
        expect(counts.layouts, greaterThan(oldLayouts));
        expect(counts.paints, greaterThan(oldPaints));
        expect(find.text('Тест связи: $totalSeconds'), findsOneWidget);
        expect(
          find.text('${(totalSeconds / 4).toStringAsFixed(1)} dB'),
          findsOneWidget,
        );
        expect(editorKey.currentState, same(state));
        expect(editor.text, 'Сохранённый ввод');
        expect(tester.takeException(), isNull);
      }
    } finally {
      timer.cancel();
      binding.updateIosPresentation(true);
      try {
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        editor.dispose();
        ticks.dispose();
        connector.dispose();
        await tester.runAsync(() async {
          await subscription.cancel().timeout(const Duration(seconds: 3));
          await packets.close().timeout(const Duration(seconds: 3));
          await bridge.dispose();
        });
      }
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('without the tweak native inactivity keeps ordinary UI updates', (tester) async {
    await tester.runAsync(bridge.dispose);
    bridge = IosPresentationBridge(
      onPresentationChanged: binding.updateIosPresentation,
    );
    messenger.setMockMethodCallHandler(channel, (call) async =>
        call.method == 'watch' ? snapshot(0, false, enabled: false) : null);
    final value = ValueNotifier<int>(0);
    try {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(bridge.start);
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: ValueListenableBuilder<int>(
          valueListenable: value,
          builder: (context, count, child) => Text('Обычный UI: $count'),
        ),
      )));
      await tester.runAsync(() => emit(snapshot(1, false, enabled: false)));
      value.value++;
      await tester.pump();
      expect(binding.sendFramesToEngine, isTrue);
      expect(find.text('Обычный UI: 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      binding.updateIosPresentation(true);
      await tester.pumpWidget(const SizedBox.shrink());
      value.dispose();
      await tester.runAsync(bridge.dispose);
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('native resume respects an outstanding Flutter first-frame deferral', (tester) async {
    binding.resetFirstFrameSent();
    binding.deferFirstFrame();
    try {
      binding.updateIosPresentation(false);
      binding.updateIosPresentation(true);
      expect(binding.sendFramesToEngine, isFalse);
    } finally {
      binding.allowFirstFrame();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
