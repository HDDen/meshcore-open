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
// more of them than the viewport holds.

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
}
