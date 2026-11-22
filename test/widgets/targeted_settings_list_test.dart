import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/settings_navigation_target.dart';
import 'package:meshcore_open/widgets/targeted_settings_list.dart';

void main() {
  testWidgets('lazy anchors are revealed once and later rebuilds preserve user scrolling', (tester) async {
    final revision = ValueNotifier(0);
    addTearDown(revision.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ValueListenableBuilder<int>(
      valueListenable: revision,
      builder: (context, value, _) => TargetedSettingsList(
        initialTarget: SettingsNavigationTarget.adaptiveTxPower,
        padding: EdgeInsets.zero,
        children: [
          for (var i = 0; i < 75; i++) SizedBox(height: 120, child: Text('row $i')),
          SizedBox(key: SettingsNavigationTarget.adaptiveTxPower.key,
            height: 80, child: Text('target $value')),
          const SizedBox(height: 600),
        ],
      ),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('target 0').hitTestable(), findsOneWidget);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.pixels, greaterThan(5000));
    scrollable.position.jumpTo(0);
    await tester.pump();
    revision.value++;
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('absent anchor stops searching and is safe to dispose', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TargetedSettingsList(
      initialTarget: SettingsNavigationTarget.companionProxy,
      padding: EdgeInsets.zero,
      children: const [SizedBox(height: 1000, child: Text('ordinary settings'))],
    ))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
