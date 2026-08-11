import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/widgets/chat_additional_actions_menu.dart';

void main() {
  testWidgets('long press opens the secondary action without sending', (
    tester,
  ) async {
    var sendCount = 0;
    var longPressCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposerSendButton(
            tooltip: 'Send',
            onPressed: () => sendCount++,
            onLongPress: () => longPressCount++,
          ),
        ),
      ),
    );

    await tester.longPress(find.byType(ChatComposerSendButton));
    await tester.pumpAndSettle();

    expect(longPressCount, 1);
    expect(sendCount, 0);
  });

  testWidgets('tap keeps the normal send action', (tester) async {
    var sendCount = 0;
    var longPressCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposerSendButton(
            tooltip: 'Send',
            onPressed: () => sendCount++,
            onLongPress: () => longPressCount++,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(ChatComposerSendButton));
    await tester.pumpAndSettle();

    expect(sendCount, 1);
    expect(longPressCount, 0);
  });
}
