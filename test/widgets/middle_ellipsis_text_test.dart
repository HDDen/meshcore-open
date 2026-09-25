import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/widgets/middle_ellipsis_text.dart';

/// What the widget shows for a ten-digit text in [width] logical pixels. The
/// test font draws every character one em wide, so at font size 10 a cell is
/// ten pixels times the text scale.
Future<String> _shown(
  WidgetTester tester, {
  required double width,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: const MiddleEllipsisText(
              text: '0123456789',
              style: TextStyle(fontSize: 10),
            ),
          ),
        ),
      ),
    ),
  );
  return tester.widget<Text>(find.byType(Text)).data!;
}

void main() {
  testWidgets('shows the whole text when it fits, exactly or with room', (
    tester,
  ) async {
    expect(await _shown(tester, width: 100), '0123456789');
    expect(await _shown(tester, width: 140), '0123456789');
  });

  testWidgets('cuts the middle, the head taking the odd character', (
    tester,
  ) async {
    expect(await _shown(tester, width: 95), '0123…6789');
    expect(await _shown(tester, width: 65), '012…89');
  });

  testWidgets('falls back to the ellipsis alone when nothing else fits', (
    tester,
  ) async {
    expect(await _shown(tester, width: 5), '…');
  });

  testWidgets('follows the text scale, which is where the DPI setting lands', (
    tester,
  ) async {
    const doubled = TextScaler.linear(2);
    expect(await _shown(tester, width: 95, textScaler: doubled), '01…9');
    expect(await _shown(tester, width: 200, textScaler: doubled), '0123456789');
  });
}
