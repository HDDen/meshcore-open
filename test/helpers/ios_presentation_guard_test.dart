import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/ios_presentation_guard.dart';

class _GateBinding extends AutomatedTestWidgetsFlutterBinding
    with IosPresentationFrameGate {}

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

  testWidgets('production frame gate keeps the editor and Dart callbacks alive', (tester) async {
    await tester.runAsync(bridge.dispose);
    bridge = IosPresentationBridge(
      onPresentationChanged: binding.updateIosPresentation,
    );
    final ticks = ValueNotifier<int>(0);
    final editor = TextEditingController(text: 'Сохранённый ввод');
    final editorKey = GlobalKey();
    final timer = Timer.periodic(const Duration(seconds: 1), (_) => ticks.value++);
    try {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(bridge.start);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [
        TextField(key: editorKey, controller: editor),
        ValueListenableBuilder<int>(
          valueListenable: ticks,
          builder: (context, count, child) => Text('Тест связи: $count'),
        ),
      ]))));
      final state = editorKey.currentState;
      expect(state, isNotNull);
      await tester.runAsync(() => emit(snapshot(1, false)));
      await tester.pump(const Duration(seconds: 3));
      expect(binding.sendFramesToEngine, isFalse);
      expect(binding.lifecycleState, AppLifecycleState.resumed);
      expect(ticks.value, 3);
      expect(find.text('Тест связи: 3'), findsOneWidget);
      expect(editorKey.currentState, same(state));
      await tester.runAsync(() => emit(snapshot(2, true)));
      await tester.pump();
      expect(binding.sendFramesToEngine, isTrue);
      expect(editorKey.currentState, same(state));
      expect(editor.text, 'Сохранённый ввод');
    } finally {
      timer.cancel();
      binding.updateIosPresentation(true);
      await tester.pumpWidget(const SizedBox.shrink());
      editor.dispose();
      ticks.dispose();
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
