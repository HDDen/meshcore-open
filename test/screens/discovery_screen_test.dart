import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/screens/discovery_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// What the discovery screen promises about the rows it lists, pinned before
// the list stops being derived anew on every notification of the connector.
// The screen shows the nodes the app has heard that the node does not hold,
// never the node itself, narrowed by the type filter and the search, in the
// order chosen: heard most recently first, or by name. The screen is driven
// through a fake connector whose lists the tests set by hand.

final Uint8List _selfKey = Uint8List.fromList(
  List<int>.generate(32, (i) => 0xF0 + i),
);

Contact _node(
  int seed,
  String name, {
  int type = advTypeChat,
  int heardSecondsAgo = 0,
}) => Contact(
  publicKey: Uint8List.fromList(
    List<int>.generate(32, (i) => i == 0 ? seed : (seed * 7 + i) & 0xFF),
  ),
  name: name,
  type: type,
  pathLength: 0,
  path: Uint8List(0),
  lastSeen: DateTime(2026, 9, 29, 12).subtract(
    Duration(seconds: heardSecondsAgo),
  ),
);

class _FakeConnector extends MeshCoreConnector {
  final List<Contact> discovered = [];
  final Set<String> known = {};

  /// Moves with every change the test makes, as the connector's list
  /// versions do with every change of its lists.
  int revision = 0;

  @override
  bool get hasReadableSession => true;

  @override
  bool get isConnected => true;

  @override
  Uint8List? get selfPublicKey => _selfKey;

  @override
  List<Contact> get discoveredContacts => List.unmodifiable(discovered);

  @override
  Set<String> get knownContactKeys => Set.unmodifiable(known);

  @override
  int get discoveredRevision => revision;

  @override
  int get contactsRevision => revision;

  @override
  Future<void> sendFrame(
    Uint8List frame, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {}

  void notify() {
    revision++;
    notifyListeners();
  }
}

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('en'));

/// Lets the rows finish arriving: each new row starts its entrance on a
/// delay of 24 ms per place in the list, which only the clock advances.
Future<void> _settleRows(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// The names on screen, top to bottom.
List<String> _rowsOf(WidgetTester tester, List<String> names) {
  final shown = <(double, String)>[
    for (final name in names)
      if (find.text(name).evaluate().isNotEmpty)
        (tester.getTopLeft(find.text(name)).dy, name),
  ];
  shown.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final row in shown) row.$2];
}

class _Harness {
  _Harness(this.connector);

  final _FakeConnector connector;

  static Future<_Harness> pump(
    WidgetTester tester, {
    required List<Contact> discovered,
    Set<String> known = const {},
  }) async {
    final connector = _FakeConnector()
      ..discovered.addAll(discovered)
      ..known.addAll(known);
    final settings = AppSettingsService();
    addTearDown(() {
      settings.dispose();
      connector.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MeshCoreConnector>.value(value: connector),
          ChangeNotifierProvider<AppSettingsService>.value(value: settings),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DiscoveryScreen(),
        ),
      ),
    );
    await _settleRows(tester);
    return _Harness(connector);
  }

  static Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  /// Picks [label] from the filter and sort menu, tapping the item it
  /// labels rather than the text, which takes no taps of its own.
  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip(_l10n.listFilter_tooltip));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is PopupMenuEntry),
          )
          .first,
    );
    await _settleRows(tester);
  }

  /// Types [query] into the search field and waits out its debounce.
  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pump(const Duration(milliseconds: 350));
    await _settleRows(tester);
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(PrefsManager.reset);

  testWidgets('a node the node holds is not listed, nor the node itself', (
    tester,
  ) async {
    final alice = _node(2, 'Alice');
    final me = Contact(
      publicKey: _selfKey,
      name: 'Me',
      type: advTypeChat,
      pathLength: 0,
      path: Uint8List(0),
      lastSeen: DateTime(2026, 9, 29, 12),
    );
    try {
      await _Harness.pump(
        tester,
        discovered: [alice, _node(3, 'Bob'), me],
        known: {alice.publicKeyHex},
      );

      expect(_rowsOf(tester, ['Alice', 'Bob', 'Me']), ['Bob']);
    } finally {
      await _Harness.unmount(tester);
    }
  });

  testWidgets('the type filter keeps the chosen type', (tester) async {
    try {
      final harness = await _Harness.pump(
        tester,
        discovered: [
          _node(2, 'Bob'),
          _node(3, 'Relay', type: advTypeRepeater),
          _node(4, 'Lounge', type: advTypeRoom),
        ],
      );
      expect(_rowsOf(tester, ['Bob', 'Relay', 'Lounge']), hasLength(3));

      await harness.choose(tester, _l10n.listFilter_repeaters);
      expect(_rowsOf(tester, ['Bob', 'Relay', 'Lounge']), ['Relay']);

      await harness.choose(tester, _l10n.listFilter_roomServers);
      expect(_rowsOf(tester, ['Bob', 'Relay', 'Lounge']), ['Lounge']);

      await harness.choose(tester, _l10n.listFilter_all);
      expect(_rowsOf(tester, ['Bob', 'Relay', 'Lounge']), hasLength(3));
    } finally {
      await _Harness.unmount(tester);
    }
  });

  testWidgets('the search narrows to a name or a key prefix', (tester) async {
    final relay = _node(3, 'Relay', type: advTypeRepeater);
    try {
      final harness = await _Harness.pump(
        tester,
        discovered: [_node(2, 'Bob'), relay, _node(4, 'Lounge')],
      );

      await harness.search(tester, 'bo');
      expect(_rowsOf(tester, ['Bob', 'Relay', 'Lounge']), ['Bob']);

      await harness.search(tester, relay.publicKeyHex.substring(0, 6));
      expect(_rowsOf(tester, ['Bob', 'Relay', 'Lounge']), ['Relay']);

      await harness.search(tester, 'nobody');
      expect(_rowsOf(tester, ['Bob', 'Relay', 'Lounge']), isEmpty);
      expect(find.text(_l10n.discoveredContacts_noMatching), findsOneWidget);
    } finally {
      await _Harness.unmount(tester);
    }
  });

  testWidgets('the order is most recently heard first, or by name', (
    tester,
  ) async {
    try {
      final harness = await _Harness.pump(
        tester,
        discovered: [
          _node(2, 'Carol', heardSecondsAgo: 300),
          _node(3, 'Alice', heardSecondsAgo: 30),
          _node(4, 'Bob', heardSecondsAgo: 3000),
        ],
      );
      expect(_rowsOf(tester, ['Alice', 'Bob', 'Carol']), [
        'Alice',
        'Carol',
        'Bob',
      ]);

      await harness.choose(tester, _l10n.listFilter_az);
      expect(_rowsOf(tester, ['Alice', 'Bob', 'Carol']), [
        'Alice',
        'Bob',
        'Carol',
      ]);

      await harness.choose(tester, _l10n.listFilter_heardRecently);
      expect(_rowsOf(tester, ['Alice', 'Bob', 'Carol']), [
        'Alice',
        'Carol',
        'Bob',
      ]);
    } finally {
      await _Harness.unmount(tester);
    }
  });

  testWidgets('a node heard while the screen is open joins the list', (
    tester,
  ) async {
    try {
      final harness = await _Harness.pump(tester, discovered: [_node(2, 'Bob')]);

      harness.connector.discovered.add(_node(3, 'Dieter'));
      harness.connector.notify();
      await _settleRows(tester);

      expect(_rowsOf(tester, ['Bob', 'Dieter']), hasLength(2));
    } finally {
      await _Harness.unmount(tester);
    }
  });
}
