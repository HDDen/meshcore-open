import 'dart:async';
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
// order chosen: heard most recently first, or by name. A discovery request
// sent from the screen lists the nodes that answer it above a rule and
// leaves the list as it was below: a node listed before that answers stands
// in both, a contact the node holds and a node first heard through its
// answer above alone. The screen is driven through a fake connector whose
// lists the tests set by hand and whose frames the tests write.

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
  final frames = StreamController<Uint8List>.broadcast();
  final written = <Uint8List>[];

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
  Stream<Uint8List> get receivedFrames => frames.stream;

  @override
  Future<void> sendFrame(
    Uint8List frame, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {
    written.add(frame);
  }

  /// What the connector does with a discovery answer: a node not yet in the
  /// discovered list joins it, nameless until it advertises.
  @override
  void recordZeroHopDiscoveredContact({
    required Uint8List publicKey,
    required int type,
    String? name,
  }) {
    final keyHex = pubKeyToHex(publicKey);
    if (!discovered.any((c) => c.publicKeyHex == keyHex)) {
      discovered.add(
        Contact(
          publicKey: publicKey,
          name: name ?? '',
          type: type,
          pathLength: 0,
          path: Uint8List(0),
          lastSeen: DateTime(2026, 9, 29, 12),
        ),
      );
    }
    notify();
  }

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

/// Lets the rows arrive and finish their entrance without waiting for the
/// tree to settle, which a running discovery request's spinner never does.
Future<void> _pumpRows(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 1));
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
      unawaited(connector.frames.close());
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

  /// Sends a discovery request from the menu and hands back its tag, read
  /// from the frame the screen wrote. The request keeps the app bar's
  /// spinner going, so from here on the tests pump by the clock.
  Future<int> discover(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.discoveredContacts_discoverDevices));
    await _pumpRows(tester);
    final request = connector.written.singleWhere(
      (frame) => frame.isNotEmpty && frame[0] == cmdSendControlData,
    );
    return readUint32LE(request, 3);
  }

  /// [node] answers the request [tag]: the frame the companion pushes for
  /// a discovery response, as the screen's listener reads it, with the
  /// reading our radio made of it and the SNR the node heard the request
  /// with.
  Future<void> answer(
    WidgetTester tester,
    Contact node, {
    required int tag,
    double snr = 0,
    int rssi = 0,
    double requestSnr = 0,
  }) async {
    connector.frames.add(
      Uint8List.fromList([
        pushCodeControlData,
        (snr * 4).round() & 0xFF,
        rssi & 0xFF,
        0, // path length
        (controlSubtypeDiscoverResp << 4) | node.type,
        (requestSnr * 4).round() & 0xFF,
        tag & 0xFF,
        (tag >> 8) & 0xFF,
        (tag >> 16) & 0xFF,
        (tag >> 24) & 0xFF,
        ...node.publicKey,
      ]),
    );
    await _pumpRows(tester);
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

  testWidgets('a discovery request lists the nodes that answer it above a '
      'rule and leaves the earlier list below as it was', (tester) async {
    final alice = _node(2, 'Alice');
    final bob = _node(3, 'Bob');
    final rule = find.text(_l10n.discoveredContacts_previouslyHeard);
    double top(Finder finder) => tester.getTopLeft(finder).dy;
    // Three answered cards with their readings, the rule and the earlier
    // list outgrow the default test window, and a row below the window is
    // never built: the window is made tall enough for all of them.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      final harness = await _Harness.pump(
        tester,
        discovered: [alice, bob, _node(4, 'Carol')],
        known: {alice.publicKeyHex},
      );
      expect(rule, findsNothing);
      expect(find.text('Alice'), findsNothing);

      final tag = await harness.discover(tester);
      expect(rule, findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(top(rule), lessThan(top(find.text('Bob'))));

      // Listed before and answering again: above as an answer, below as it
      // was. The readings go under the key of the answered card alone: how
      // Bob heard the request behind the up arrow, how we heard the answer
      // behind the down one.
      await harness.answer(
        tester,
        bob,
        tag: tag,
        snr: 7.5,
        rssi: -92,
        requestSnr: 4,
      );
      expect(find.text('Bob'), findsNWidgets(2));
      expect(top(find.text('Bob').first), lessThan(top(rule)));
      expect(top(find.text('Bob').last), greaterThan(top(rule)));
      final reading = find.textContaining('\u21914.0dB');
      expect(reading, findsOneWidget);
      expect(top(reading), lessThan(top(rule)));
      expect(find.textContaining('\u21937.5dB'), findsOneWidget);
      expect(find.textContaining('-92dBm'), findsOneWidget);

      // A contact the node holds: among the answers, dimmed, and nowhere
      // else.
      await harness.answer(tester, alice, tag: tag);
      expect(find.text('Alice'), findsOneWidget);
      expect(top(find.text('Alice')), lessThan(top(rule)));
      expect(find.text(_l10n.discoveredContacts_alreadyAdded), findsOneWidget);

      // Heard for the first time through its answer: among the answers
      // alone, nameless until it advertises.
      await harness.answer(tester, _node(9, 'Zed'), tag: tag);
      final unnamed = find.text(_l10n.common_unknownDevice);
      expect(unnamed, findsOneWidget);
      expect(top(unnamed), lessThan(top(rule)));
      expect(find.text('Carol'), findsOneWidget);
      expect(top(find.text('Carol')), greaterThan(top(rule)));
    } finally {
      await _Harness.unmount(tester);
    }
  });
}
