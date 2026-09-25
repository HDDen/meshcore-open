import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/widgets/chat_bubble_box.dart';

void main() {
  testWidgets('a new width limit applies at once, with no animation', (
    tester,
  ) async {
    Widget bubble(double maxWidth) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: ChatBubbleBox(
          duration: const Duration(seconds: 1),
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: const SizedBox(width: 500, height: 20),
        ),
      ),
    );

    await tester.pumpWidget(bubble(200));
    expect(tester.getSize(find.byType(ChatBubbleBox)).width, 200);

    await tester.pumpWidget(bubble(120));
    expect(tester.getSize(find.byType(ChatBubbleBox)).width, 120);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('the decoration still fades', (tester) async {
    Widget bubble(Color color) => Directionality(
      textDirection: TextDirection.ltr,
      child: ChatBubbleBox(
        duration: const Duration(seconds: 1),
        decoration: BoxDecoration(color: color),
        child: const SizedBox(width: 50, height: 20),
      ),
    );

    await tester.pumpWidget(bubble(const Color(0xFF000000)));
    await tester.pumpWidget(bubble(const Color(0xFFFFFFFF)));
    // The first frame starts the animation, the second lands halfway.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final decorated = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(ChatBubbleBox),
        matching: find.byType(DecoratedBox),
      ),
    );
    final color = (decorated.decoration as BoxDecoration).color;
    expect(color, isNot(const Color(0xFF000000)));
    expect(color, isNot(const Color(0xFFFFFFFF)));
    await tester.pumpAndSettle();
  });

  testWidgets('keeps the padding inside the decoration, as before', (
    tester,
  ) async {
    const childKey = Key('child');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: ChatBubbleBox(
            duration: const Duration(seconds: 1),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(maxWidth: 100),
            decoration: BoxDecoration(border: Border.all(width: 1)),
            child: const SizedBox(key: childKey, width: 500, height: 10),
          ),
        ),
      ),
    );

    // The limit covers border and padding; the child gets what they leave.
    expect(tester.getSize(find.byType(ChatBubbleBox)), const Size(100, 28));
    expect(tester.getSize(find.byKey(childKey)), const Size(82, 10));
  });
}
