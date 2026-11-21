import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/widgets/edge_swipe_pop.dart';

void main() {
  for (final block in [false, true]) {
    testWidgets('edge swipe respects a protected panel ($block)', (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      var open = true;
      var enteredText = '';
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        builder: (_, child) => EdgeSwipePop(
          navigatorKey: navigator,
          child: child!,
        ),
        home: const Scaffold(body: Text('root route')),
      ));
      navigator.currentState!.push<void>(MaterialPageRoute(
        builder: (_) => StatefulBuilder(builder: (context, setState) {
          void close() => setState(() { open = false; });
          final panel = Container(
            color: Colors.blue,
            child: Column(children: [
              const SizedBox(height: 40, child: Text('trace panel')),
              TextField(onChanged: (value) { enteredText = value; }),
              TextButton(onPressed: close, child: const Text('Close')),
            ]),
          );
          return PopScope(
            canPop: !open,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && open) { close(); }
            },
            child: Scaffold(body: Stack(children: [
              const Positioned.fill(child: ColoredBox(color: Colors.white)),
              if (open) Positioned(
                left: 16, right: 16, top: 80, height: 240,
                child: block ? EdgeSwipePopBlocker(child: panel) : panel,
              ),
            ])),
          );
        }),
      ));
      await tester.pumpAndSettle();
      expect(navigator.currentState!.canPop(), isTrue);
      await tester.enterText(find.byType(TextField), 'AAAA,BBBB');
      expect(enteredText, 'AAAA,BBBB');
      // This starts over the panel, within the app's 36px edge-back zone.
      await tester.dragFrom(const Offset(20, 100), const Offset(150, 0));
      await tester.pumpAndSettle();
      expect(find.text('trace panel'), block ? findsOneWidget : findsNothing);
      expect(open, block);
      if (block) {
        // Neither the metadata nor the edge listener consumes normal taps.
        expect(find.text('AAAA,BBBB'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(open, isFalse);
      }
      // The exclusion is local: an ordinary edge swipe outside it still pops.
      await tester.dragFrom(const Offset(20, 400), const Offset(150, 0));
      await tester.pumpAndSettle();
      expect(find.text('root route'), findsOneWidget);
      expect(navigator.currentState!.canPop(), isFalse);
    });
  }
}
