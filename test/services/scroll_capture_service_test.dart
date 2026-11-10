import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/chat_scroll_controller.dart';
import 'package:meshcore_open/services/scroll_capture_service.dart';

Future<void> _pumpList(
  WidgetTester tester,
  ScrollController controller, {
  bool reverse = false,
  GlobalKey<NavigatorState>? navigator,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.viewPadding = const FakeViewPadding(top: 48);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewPadding);
  await tester.pumpWidget(MaterialApp(
    navigatorKey: navigator,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 240,
          height: 300,
          child: ListView.builder(
            controller: controller,
            reverse: reverse,
            padding: EdgeInsets.zero,
            itemExtent: 40,
            itemCount: 50,
            itemBuilder: (_, index) => Text('Row $index'),
          ),
        ),
      ),
    ),
  ));
}

Future<Object?> _call(
  ScrollCaptureService service,
  String method,
  int id, {
  int? top,
  int? bottom,
}) => service.handle(MethodCall(method, {
  'id': id,
  if (top != null) 'top': top,
  if (bottom != null) 'bottom': bottom,
}));

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  for (final reverse in [false, true]) {
    testWidgets('returns physical bounds and restores the list (reverse=$reverse)', (
      tester,
    ) async {
      final controller = ScrollController(initialScrollOffset: 300);
      addTearDown(controller.dispose);
      await _pumpList(tester, controller, reverse: reverse);
      final service = ScrollCaptureService();

      expect(await _call(service, 'search', 1), {
        'left': 160, 'top': 48, 'right': 640, 'bottom': 600,
      });
      expect(await _call(service, 'start', 1), isTrue);
      final strip = reverse
          ? _call(service, 'scroll', 1, top: -300, bottom: -100)
          : _call(service, 'scroll', 1, top: 650, bottom: 752);
      await _frames(tester);
      expect(await strip, reverse ? -300 : 200);
      expect(controller.offset, reverse ? 450 : 400);

      final ended = _call(service, 'end', 1);
      await _frames(tester);
      await ended;
      expect(controller.offset, 300);
    });
  }

  testWidgets('cancelling a chat strip restores its position without loading history', (
    tester,
  ) async {
    final controller = ChatScrollController();
    addTearDown(controller.dispose);
    await _pumpList(tester, controller, reverse: true);
    controller.jumpTo(50);
    await tester.pump();
    var olderLoads = 0;
    controller.onScrollNearTop = () => olderLoads++;
    final service = ScrollCaptureService();

    expect(await _call(service, 'search', 1), isNotNull);
    expect(await _call(service, 'start', 1), isTrue);
    final strip = _call(service, 'scroll', 1, top: -4000, bottom: -3700);
    await tester.pump();
    expect(controller.offset, controller.position.maxScrollExtent);
    expect(controller.showJumpToBottom.value, isFalse);
    expect(olderLoads, 0);
    controller.followNewMessage('received during capture');
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.offset, controller.position.maxScrollExtent);
    await _frames(tester);
    expect(await strip, isA<int>());

    final pending = _call(service, 'scroll', 1, top: 400, bottom: 700);
    final ended = _call(service, 'end', 1);
    await _frames(tester);
    await ended;
    expect(await pending, isNull);
    expect(controller.offset, 50);
    expect(await _call(service, 'scroll', 1, top: 1000, bottom: 1200), isNull);
    expect(olderLoads, 0);
    expect(controller.showJumpToBottom.value, isFalse);

    controller.jumpTo(controller.position.maxScrollExtent);
    expect(olderLoads, greaterThan(0));
    expect(controller.showJumpToBottom.value, isTrue);
  });

  testWidgets('a covering page ends the capture and excludes the old list', (tester) async {
    final controller = ScrollController(initialScrollOffset: 100);
    final navigator = GlobalKey<NavigatorState>();
    addTearDown(controller.dispose);
    await _pumpList(tester, controller, navigator: navigator);
    final service = ScrollCaptureService();

    expect(await _call(service, 'search', 1), isNotNull);
    expect(await _call(service, 'start', 1), isTrue);
    final strip = _call(service, 'scroll', 1, top: 700, bottom: 800);
    await _frames(tester);
    expect(await strip, 248);
    expect(controller.offset, 224);

    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Center(child: Text('Covering page'))),
    ));
    await tester.pumpAndSettle();
    expect(await _call(service, 'scroll', 1, top: 850, bottom: 950), isNull);
    expect(controller.offset, 100);
    expect(await _call(service, 'search', 2), isNull);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(controller.offset, 100);
  });

  testWidgets('a missed native end restores the list after the idle limit', (tester) async {
    final controller = ScrollController(initialScrollOffset: 100);
    addTearDown(controller.dispose);
    await _pumpList(tester, controller);
    final service = ScrollCaptureService();
    expect(await _call(service, 'search', 1), isNotNull);
    expect(await _call(service, 'start', 1), isTrue);
    final strip = _call(service, 'scroll', 1, top: 700, bottom: 800);
    await _frames(tester);
    expect(await strip, 248);
    await tester.pump(const Duration(seconds: 5));
    expect(controller.offset, 100);
    expect(await _call(service, 'scroll', 1, top: 700, bottom: 800), isNull);
  });
}
