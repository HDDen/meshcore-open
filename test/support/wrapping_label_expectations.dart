import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds a dropdown option even when tall earlier items keep it unbuilt.
Future<Finder> revealDropdownOption(WidgetTester tester, String label) async {
  // Flutter's dropdown popup uses its own primary, shrink-wrapped ListView;
  // the editor underneath uses a separately controlled list. Do not scroll
  // that editor or call .last on an option which may not exist yet.
  final menu = find.byWidgetPredicate(
    (widget) => widget is ListView && widget.primary == true && widget.shrinkWrap,
    description: 'dropdown popup list',
  );
  expect(menu, findsOneWidget, reason: 'The dropdown must open before selecting an option');
  final scrollable = find.descendant(of: menu, matching: find.byType(Scrollable));
  expect(scrollable, findsOneWidget);
  final option = find.descendant(of: menu, matching: find.text(label));
  await tester.scrollUntilVisible(option, 120,
      scrollable: scrollable, maxScrolls: 40);
  await tester.pumpAndSettle();
  expect(option.hitTestable(), findsOneWidget);
  return option;
}

/// Checks the rendered label, not just the source string retained by Text.
void expectCompleteWrappingLabel(
  WidgetTester tester,
  Finder finder, {
  required bool wraps,
}) {
  expect(finder, findsOneWidget);
  final text = tester.widget<Text>(finder).data!;
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  expect(paragraph.didExceedMaxLines, isFalse,
      reason: 'The complete label must remain readable: $text');
  final boxes = paragraph.getBoxesForSelection(TextSelection(
    baseOffset: 0,
    extentOffset: text.length,
  ));
  expect(boxes, isNotEmpty);
  // A fixed-height paragraph could clip lower lines even without maxLines.
  for (final box in boxes) {
    expect(box.top, greaterThanOrEqualTo(-0.01));
    expect(box.bottom, lessThanOrEqualTo(paragraph.size.height + 0.01));
  }
  if (wraps) {
    // Several boxes can share one line; require a later vertical position.
    expect(boxes.any((box) => box.top > boxes.first.top + 1), isTrue,
        reason: 'The long label must wrap onto more than one line');
  }
}
