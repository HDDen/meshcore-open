import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/chat_scroll_controller.dart';

// What the chats' scroll controller promises, pinned before the snap to the
// bottom learns to leave the reader alone. Both chats show their messages in
// a reversed list, so pixel 0 is the newest message: the jump button shows
// once the reader is further than 100 px from it, a rebuild pulls the list to
// the bottom only while the reader is within those 100 px, the jump button
// brings the reader back from anywhere, and the pagination hook fires near
// the top. The list here is the chats' shape: reversed, rows of one height,
// more of them than the viewport holds. The second half is the change: a
// snap never ends the reader's drag or fling, and the screens follow the
// newest message rather than every rebuild.

const double _rowHeight = 40;
const double _viewport = 400;

/// A chat-shaped list of [rows] rows of 40 px in a 400 px viewport: fifty
/// rows leave 1600 px to scroll.
Widget _chat(ChatScrollController controller, {int rows = 50}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      height: _viewport,
      child: ListView.builder(
        controller: controller,
        reverse: true,
        itemExtent: _rowHeight,
        itemCount: rows,
        itemBuilder: (_, index) => Text('row $index'),
      ),
    ),
  ),
);

Future<ChatScrollController> _pumpChat(
  WidgetTester tester, {
  int rows = 50,
}) async {
  final controller = ChatScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(_chat(controller, rows: rows));
  return controller;
}

void main() {
  testWidgets('the jump button shows past 100 px from the bottom and hides '
      'within', (tester) async {
    final controller = await _pumpChat(tester);
    expect(controller.showJumpToBottom.value, isFalse);

    controller.jumpTo(150);
    await tester.pump();
    expect(controller.showJumpToBottom.value, isTrue);

    controller.jumpTo(80);
    await tester.pump();
    expect(controller.showJumpToBottom.value, isFalse);
  });

  testWidgets('a rebuild pulls the list down while the reader is within '
      '100 px of the bottom', (tester) async {
    final controller = await _pumpChat(tester);
    controller.jumpTo(60);
    await tester.pump();

    controller.scrollToBottomIfAtBottom();
    await tester.pumpAndSettle();

    expect(controller.position.pixels, 0);
  });

  testWidgets('and leaves a reader who scrolled further alone', (
    tester,
  ) async {
    final controller = await _pumpChat(tester);
    controller.jumpTo(300);
    await tester.pump();

    controller.scrollToBottomIfAtBottom();
    await tester.pumpAndSettle();

    expect(controller.position.pixels, 300);
    expect(controller.showJumpToBottom.value, isTrue);
  });

  testWidgets('a list that does not scroll is left alone', (tester) async {
    final controller = await _pumpChat(tester, rows: 5);
    expect(controller.position.maxScrollExtent, 0);

    controller.scrollToBottomIfAtBottom();
    await tester.pumpAndSettle();

    expect(controller.position.pixels, 0);
    expect(controller.showJumpToBottom.value, isFalse);
  });

  testWidgets('the jump button brings the reader back from anywhere and '
      'hides', (tester) async {
    final controller = await _pumpChat(tester);
    controller.jumpTo(1000);
    await tester.pump();
    expect(controller.showJumpToBottom.value, isTrue);

    controller.jumpToBottom();
    await tester.pumpAndSettle();

    expect(controller.position.pixels, 0);
    expect(controller.showJumpToBottom.value, isFalse);
  });

  testWidgets('the pagination hook fires near the top and nowhere else', (
    tester,
  ) async {
    final controller = await _pumpChat(tester);
    var calls = 0;
    controller.onScrollNearTop = () => calls++;

    controller.jumpTo(800);
    await tester.pump();
    expect(calls, 0);

    controller.jumpTo(controller.position.maxScrollExtent - 20);
    await tester.pump();
    expect(calls, greaterThanOrEqualTo(1));
  });

  group('the reader\'s scrolling', () {
    /// A finger on the list, dragged [dy] px down, which in a reversed list
    /// scrolls towards older rows; the drag is still in progress.
    Future<TestGesture> drag(WidgetTester tester, double dy) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ListView)),
      );
      await gesture.moveBy(Offset(0, dy));
      await tester.pump();
      return gesture;
    }

    testWidgets('a snap during a drag leaves the finger in charge', (
      tester,
    ) async {
      final controller = await _pumpChat(tester);
      final gesture = await drag(tester, 60);
      final dragged = controller.position.pixels;
      expect(dragged, greaterThan(0));
      expect(dragged, lessThan(100));

      controller.scrollToBottomIfAtBottom();
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.position.pixels, dragged);

      await gesture.moveBy(const Offset(0, 100));
      await tester.pump();
      expect(controller.position.pixels, greaterThan(dragged + 50));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a snap during a fling leaves it running', (tester) async {
      final controller = await _pumpChat(tester);
      await tester.fling(find.byType(ListView), const Offset(0, 50), 800);
      await tester.pump();
      final flung = controller.position.pixels;
      expect(flung, greaterThan(0));
      expect(flung, lessThan(100));

      controller.scrollToBottomIfAtBottom();
      await tester.pump(const Duration(milliseconds: 100));

      expect(controller.position.pixels, greaterThan(flung));
      await tester.pumpAndSettle();
    });

    testWidgets('a new message that comes during a drag is not followed '
        'once the drag ends', (tester) async {
      final controller = await _pumpChat(tester);
      final gesture = await drag(tester, 60);
      final dragged = controller.position.pixels;

      controller.followNewMessage('m1');
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.position.pixels, dragged);
      await gesture.up();
      await tester.pumpAndSettle();
      final rested = controller.position.pixels;
      expect(rested, greaterThan(0));

      // The rebuild after the drag shows the same newest message.
      controller.followNewMessage('m1');
      await tester.pumpAndSettle();
      expect(controller.position.pixels, rested);
    });
  });

  group('following the newest message', () {
    testWidgets('a new message pulls the list down once, a rebuild with the '
        'same one not at all', (tester) async {
      final controller = await _pumpChat(tester);
      controller.jumpTo(60);
      await tester.pump();

      controller.followNewMessage('m1');
      await tester.pumpAndSettle();
      expect(controller.position.pixels, 0);

      controller.jumpTo(60);
      await tester.pump();
      controller.followNewMessage('m1');
      await tester.pumpAndSettle();
      expect(controller.position.pixels, 60, reason: 'a relay, a reading');

      controller.followNewMessage('m2');
      await tester.pumpAndSettle();
      expect(controller.position.pixels, 0);
    });

    testWidgets('a new message that came while the reader was away is not '
        'followed when they come back', (tester) async {
      final controller = await _pumpChat(tester);
      controller.jumpTo(300);
      await tester.pump();

      controller.followNewMessage('m1');
      await tester.pumpAndSettle();
      expect(controller.position.pixels, 300);

      controller.jumpTo(60);
      await tester.pump();
      controller.followNewMessage('m1');
      await tester.pumpAndSettle();
      expect(controller.position.pixels, 60);
    });

    testWidgets('its own animation does not block the next message', (
      tester,
    ) async {
      final controller = await _pumpChat(tester);
      controller.jumpTo(90);
      await tester.pump();

      controller.followNewMessage('m1');
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.position.isScrollingNotifier.value, isTrue);
      expect(controller.position.pixels, greaterThan(0));
      controller.followNewMessage('m2');
      await tester.pumpAndSettle();

      expect(controller.position.pixels, 0);
    });
  });
}
