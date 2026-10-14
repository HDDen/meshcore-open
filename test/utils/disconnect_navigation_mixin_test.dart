import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/utils/disconnect_navigation_mixin.dart';

// What the disconnect navigation of the screens that need a radio promises:
// a link that is gone for good sends the screen back to the first route, a
// link the connector brings back on its own keeps it, as a recovering drop
// and as a transport restart (the companion proxy's session restart, a
// manual disconnect in the connector's terms), and a restart that ended with
// the link down sends it back at the next notification. The restart case is
// the change: the mixin used to pop on it whatever the app shell did, which
// left the app on the scanner with the radio connected.

class _FakeConnector extends MeshCoreConnector {
  bool readable = true;
  bool recovering = false;
  bool restarting = false;

  @override
  bool get hasReadableSession => readable;

  @override
  bool get isRecoveringConnection => recovering;

  @override
  bool get isRestartingTransport => restarting;

  void notify() => notifyListeners();
}

class _Screen extends StatefulWidget {
  const _Screen(this.connector);

  final _FakeConnector connector;

  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen>
    with DisconnectNavigationMixin<_Screen> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.connector,
      builder: (context, _) {
        if (!checkConnectionAndNavigate(widget.connector)) {
          return const SizedBox.shrink();
        }
        return const Text('screen');
      },
    );
  }
}

Future<_FakeConnector> _pumpScreen(WidgetTester tester) async {
  final connector = _FakeConnector();
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: Text('home'))),
  );
  tester
      .state<NavigatorState>(find.byType(Navigator))
      .push(MaterialPageRoute<void>(builder: (_) => _Screen(connector)));
  await tester.pumpAndSettle();
  expect(find.text('screen'), findsOneWidget);
  return connector;
}

void main() {
  testWidgets('a link gone for good sends the screen back to the first route',
      (tester) async {
    final connector = await _pumpScreen(tester);

    connector.readable = false;
    connector.notify();
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(find.byType(_Screen), findsNothing);
  });

  testWidgets('a recovering link keeps the screen', (tester) async {
    final connector = await _pumpScreen(tester);

    connector
      ..readable = false
      ..recovering = true
      ..notify();
    await tester.pumpAndSettle();

    expect(find.byType(_Screen), findsOneWidget);
    expect(find.text('home'), findsNothing);
  });

  testWidgets('a transport restart keeps the screen until the link is back',
      (tester) async {
    final connector = await _pumpScreen(tester);

    connector
      ..readable = false
      ..restarting = true
      ..notify();
    await tester.pumpAndSettle();
    expect(find.byType(_Screen), findsOneWidget);

    connector
      ..readable = true
      ..restarting = false
      ..notify();
    await tester.pumpAndSettle();

    expect(find.text('screen'), findsOneWidget);
    expect(find.text('home'), findsNothing);
  });

  testWidgets('a restart that ended with the link down sends the screen back '
      'at the next notification', (tester) async {
    final connector = await _pumpScreen(tester);

    connector
      ..readable = false
      ..restarting = true
      ..notify();
    await tester.pumpAndSettle();
    expect(find.byType(_Screen), findsOneWidget);

    connector
      ..restarting = false
      ..notify();
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(find.byType(_Screen), findsNothing);
  });
}
