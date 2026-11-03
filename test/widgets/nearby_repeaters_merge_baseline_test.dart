import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/widgets/node_info_sheet.dart';
import 'package:meshcore_open/widgets/repeater_login_dialog.dart';
import 'package:meshcore_open/widgets/room_login_dialog.dart';
import 'package:meshcore_open/widgets/snr_indicator.dart';
import 'package:provider/provider.dart';

// U06a3 baseline: the fork's two indicators share a scrollable list and
// contact resolution, but opening it must not perform radio operations.
// The fixture supplies snapshots directly: no BLE, database, GPS or plugins.
class _NearbyConnector extends MeshCoreConnector {
  final nodes = <Contact>[];
  final direct = <DirectRepeater>[];
  final active = <DirectRepeater>[];
  final sent = <Uint8List>[];
  double? latitude;
  double? longitude;
  bool offline = false;
  int hashWidth = 1;
  int imports = 0;

  @override
  bool get isConnected => !offline;

  @override
  bool get isOfflineMode => offline;

  @override
  int get pathHashByteWidth => hashWidth;

  @override
  Contact? getContactByPubKeyHex(String contactPubKeyHex) {
    for (final contact in nodes) {
      if (contact.isActive && contact.publicKeyHex == contactPubKeyHex) {
        return contact;
      }
    }
    return null;
  }

  @override
  Future<bool> importDiscoveredContact(Contact contact) async {
    imports++;
    return false;
  }

  @override
  List<Contact> get allContacts => List.unmodifiable(nodes);

  @override
  List<DirectRepeater> get directRepeaters => direct;

  @override
  List<DirectRepeater> get activeRepeaters => active;

  @override
  double? get selfLatitude => latitude;

  @override
  double? get selfLongitude => longitude;

  @override
  int? get currentSf => 7;

  @override
  Future<void> sendFrame(
    Uint8List frame, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {
    sent.add(Uint8List.fromList(frame));
  }
}

Contact _contact(
  List<int> prefix,
  String name, {
  int tail = 1,
  int type = advTypeRepeater,
  bool favorite = false,
  double? latitude,
  double? longitude,
  DateTime? lastSeen,
}) {
  final key = Uint8List(32)..setRange(0, prefix.length, prefix);
  key[31] = tail;
  return Contact(
    publicKey: key,
    name: name,
    type: type,
    flags: favorite ? contactFlagFavorite : 0,
    pathLength: -1,
    path: Uint8List(0),
    latitude: latitude,
    longitude: longitude,
    lastSeen: lastSeen ?? DateTime.now(),
  );
}

DirectRepeater _heard(
  List<int> prefix, {
  double snr = 8,
  DateTime? lastUpdated,
  String? contactKeyHex,
}) => DirectRepeater(
  pubkeyPrefix: prefix,
  pathHashWidth: prefix.length,
  snr: snr,
  lastUpdated: lastUpdated,
  contactKeyHex: contactKeyHex,
);

Future<void> _withIndicators(
  WidgetTester tester,
  Future<void> Function(_NearbyConnector connector, ValueNotifier<int> builds) check, {
  double scale = 1,
}) async {
  final connector = _NearbyConnector();
  final builds = ValueNotifier<int>(0);
  try {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => ChangeNotifierProvider<MeshCoreConnector>.value(
          value: connector,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) {
                builds.value++;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SNRIndicator(connector: connector),
                    SNRActivityIndicator(connector: connector),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await check(connector, builds);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    connector.dispose();
    builds.dispose();
    await tester.pump();
  }
}

Finder _dialogText(String text) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.text(text),
);

Future<void> _open(WidgetTester tester, {required bool activity}) async {
  await tester.tap(find.byType(activity ? SNRActivityIndicator : SNRIndicator));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(_dialogText('Close'));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsNothing);
}

void main() {
  for (final activity in [false, true]) {
    for (final width in [1, 2, 3]) {
      testWidgets('U06a3: known repeater details are read-only, activity=$activity width=$width', (tester) async {
        await _withIndicators(tester, (connector, builds) async {
          final prefix = [0xA1, 0xB2, 0xC3].take(width).toList();
          final contact = _contact(prefix, 'Known repeater', latitude: 55.75, longitude: 37.62)
              .copyWith(pathLength: 1, path: Uint8List.fromList(prefix), pathHashWidth: width);
          connector.hashWidth = width;
          connector.nodes.add(contact);
          connector.direct.add(_heard(prefix));
          connector.active.add(_heard(prefix));
          connector.repeaterActivity.value++;
          await tester.pump();
          await _open(tester, activity: activity);
          await tester.tap(_dialogText(contact.name));
          await tester.pumpAndSettle();
          expect(find.byType(NodeInfoSheet), findsOneWidget);
          final sheet = tester.widget<NodeInfoSheet>(find.byType(NodeInfoSheet));
          expect(sheet.contact, same(contact));
          expect(sheet.pathHashByteWidth, width);
          expect(find.byWidgetPredicate((w) => w is SelectableText && w.data == contact.publicKeyHex), findsOneWidget);
          expect(find.byWidgetPredicate((w) => w is SelectableText && w.data == '55.750000, 37.620000'), findsOneWidget);
          expect(find.byType(RepeaterLoginDialog), findsNothing);
          expect(find.byType(RoomLoginDialog), findsNothing);
          expect(connector.nodes, [contact]);
          expect(connector.imports, 0);
          expect(connector.sent, isEmpty);
          Navigator.of(tester.element(find.byType(NodeInfoSheet))).pop();
          await tester.pumpAndSettle();
          await _close(tester);
        });
      });
    }

    testWidgets('U06a3: unknown prefix exposes signal without contact actions, activity=$activity', (tester) async {
      await _withIndicators(tester, (connector, builds) async {
        final heard = _heard([0xAB, 0xCD, 0xEF], snr: -3.5);
        connector.direct.add(heard);
        connector.active.add(heard);
        connector.repeaterActivity.value++;
        await tester.pump();
        await _open(tester, activity: activity);
        await tester.tap(_dialogText('ABCDEF').first);
        await tester.pumpAndSettle();
        final sheet = find.byKey(const ValueKey('heard-repeater-info'));
        expect(sheet, findsOneWidget);
        expect(find.descendant(of: sheet, matching: find.text('Unknown repeater')), findsOneWidget);
        expect(find.descendant(of: sheet, matching: find.byType(FilledButton)), findsNothing);
        expect(find.byWidgetPredicate((w) => w is SelectableText && w.data == '-3.5 dB'), findsOneWidget);
        expect(find.byWidgetPredicate((w) => w is SelectableText && w.data == 'ABCDEF'), findsOneWidget);
        expect(connector.imports, 0);
        expect(connector.sent, isEmpty);
      });
    });

    for (final hasFullKey in [false, true]) {
      testWidgets('U06a3: collision needs a full key for actions, activity=$activity key=$hasFullKey', (tester) async {
        await _withIndicators(tester, (connector, builds) async {
          final preferred = _contact([0x77], 'Preferred', favorite: true);
          final exact = _contact([0x77], 'Exact', tail: 2);
          connector.nodes.addAll([preferred, exact]);
          final heard = _heard([0x77], contactKeyHex: hasFullKey ? exact.publicKeyHex : null);
          connector.direct.add(heard);
          connector.active.add(heard);
          connector.repeaterActivity.value++;
          await tester.pump();
          await _open(tester, activity: activity);
          await tester.tap(_dialogText(hasFullKey ? '(?) Exact' : '(?) Preferred'));
          await tester.pumpAndSettle();
          if (hasFullKey) {
            expect(tester.widget<NodeInfoSheet>(find.byType(NodeInfoSheet)).contact, same(exact));
          } else {
            final sheet = find.byKey(const ValueKey('heard-repeater-info'));
            expect(sheet, findsOneWidget);
            expect(find.byType(NodeInfoSheet), findsNothing);
            expect(find.descendant(of: sheet, matching: find.byType(FilledButton)), findsNothing);
            expect(find.byWidgetPredicate((w) => w is SelectableText && w.data == preferred.publicKeyHex), findsNothing);
          }
          expect(connector.imports, 0);
          expect(connector.sent, isEmpty);
        });
      });
    }
  }

  testWidgets('U06a3: managing a discovered contact asks before import and supports cancel', (tester) async {
    await _withIndicators(tester, (connector, builds) async {
      final contact = _contact([0x51], 'Discovered').copyWith(isActive: false);
      connector.nodes.add(contact);
      connector.active.add(_heard([0x51]));
      connector.repeaterActivity.value++;
      await tester.pump();
      await _open(tester, activity: true);
      await tester.tap(_dialogText(contact.name));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(NodeInfoSheet), matching: find.text('Manage Repeater')));
      await tester.pumpAndSettle();
      expect(find.text('Add to node memory?'), findsOneWidget);
      expect(connector.imports, 0);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(RepeaterLoginDialog), findsNothing);
      expect(connector.imports, 0);
      expect(connector.sent, isEmpty);
    });
  });

  testWidgets('U06a3: room details offer explicit join and management without login', (tester) async {
    await _withIndicators(tester, (connector, builds) async {
      final contact = _contact([0x53], 'Known room', type: advTypeRoom);
      connector.nodes.add(contact);
      connector.active.add(_heard([0x53]));
      connector.repeaterActivity.value++;
      await tester.pump();
      await _open(tester, activity: true);
      await tester.tap(_dialogText(contact.name));
      await tester.pumpAndSettle();
      final sheet = find.byType(NodeInfoSheet);
      expect(sheet, findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Join Room')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Manage Server')), findsOneWidget);
      expect(find.byType(RoomLoginDialog), findsNothing);
      expect(connector.imports, 0);
      expect(connector.sent, isEmpty);
    });
  });

  testWidgets('U06a3: offline details stay readable but cannot start node actions', (tester) async {
    await _withIndicators(tester, (connector, builds) async {
      final contact = _contact([0x52], 'Offline repeater');
      connector.offline = true;
      connector.nodes.add(contact);
      connector.active.add(_heard([0x52]));
      connector.repeaterActivity.value++;
      await tester.pump();
      await _open(tester, activity: true);
      await tester.tap(_dialogText(contact.name));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(NodeInfoSheet), matching: find.text('Manage Repeater')));
      await tester.pump();
      expect(find.byType(NodeInfoSheet), findsOneWidget);
      expect(find.byType(RepeaterLoginDialog), findsNothing);
      expect(connector.imports, 0);
      expect(connector.sent, isEmpty);
    });
  });

  testWidgets('U06a3 baseline: empty indicators do not open a list', (tester) async {
    await _withIndicators(tester, (connector, builds) async {
      for (final type in [SNRIndicator, SNRActivityIndicator]) {
        final ink = find.descendant(of: find.byType(type), matching: find.byType(InkWell));
        expect(tester.widget<InkWell>(ink).onTap, isNull);
      }
      expect(find.byType(AlertDialog), findsNothing);
      expect(connector.sent, isEmpty);
    });
  });

  testWidgets('U06a3 baseline: direct ranking and activity recency remain separate', (tester) async {
    await _withIndicators(tester, (connector, builds) async {
      final now = DateTime.now();
      connector.nodes.addAll([
        _contact([0x11], 'Stronger'),
        _contact([0x22], 'Weaker'),
      ]);
      connector.direct.addAll([
        _heard([0x22], snr: -4, lastUpdated: now),
        _heard([0x11], snr: 8, lastUpdated: now),
      ]);
      connector.active.addAll([
        _heard([0x11], snr: 8, lastUpdated: now.subtract(const Duration(minutes: 2))),
        _heard([0x22], snr: -4, lastUpdated: now),
      ]);
      connector.repeaterActivity.value++;
      await tester.pump();
      await _open(tester, activity: false);
      expect(_dialogText('Nearby Repeaters'), findsOneWidget);
      expect(tester.getTopLeft(_dialogText('Stronger')).dy,
          lessThan(tester.getTopLeft(_dialogText('Weaker')).dy));
      await _close(tester);
      await _open(tester, activity: true);
      expect(_dialogText("Repeater's activity"), findsOneWidget);
      expect(tester.getTopLeft(_dialogText('Weaker')).dy,
          lessThan(tester.getTopLeft(_dialogText('Stronger')).dy));
      expect(connector.sent, isEmpty);
    });
  });

  for (final activity in [false, true]) {
    for (final choice in ['favorite', 'nearest', 'full key']) {
      testWidgets('U06a3 baseline: $choice resolves a collision, activity=$activity', (tester) async {
        await _withIndicators(tester, (connector, builds) async {
          final now = DateTime.now();
          final favorite = _contact([0xA1], 'Favorite', favorite: true,
              latitude: 60, longitude: 40, lastSeen: now.subtract(const Duration(days: 1)));
          final nearest = _contact([0xA1], 'Nearest', tail: 2,
              latitude: 55.75, longitude: 37.62, lastSeen: now);
          connector.nodes.addAll([favorite, nearest]);
          if (choice == 'nearest') {
            connector.latitude = 55.751;
            connector.longitude = 37.621;
          }
          final heard = _heard([0xA1],
              contactKeyHex: choice == 'full key' ? nearest.publicKeyHex : null);
          connector.direct.add(heard);
          connector.active.add(heard);
          connector.repeaterActivity.value++;
          await tester.pump();
          await _open(tester, activity: activity);
          final selected = choice == 'favorite' ? 'Favorite' : 'Nearest';
          expect(_dialogText('(?) $selected'), findsOneWidget);
          expect(_dialogText('(?) ${selected == 'Favorite' ? 'Nearest' : 'Favorite'}'), findsNothing);
          expect(connector.sent, isEmpty);
        });
      });
    }
  }

  testWidgets('U06a3 baseline: prefixes keep all bytes and only resolve repeater or room contacts', (tester) async {
    await _withIndicators(tester, (connector, builds) async {
      connector.nodes.addAll([
        _contact([0x10, 0x20], 'Two-byte repeater'),
        _contact([0x10, 0x21], 'Different second byte'),
        _contact([0x30, 0x40, 0x50], 'Three-byte room', type: advTypeRoom),
        _contact([0xAB, 0xCD, 0xEF], 'Chat is not a repeater', type: advTypeChat),
      ]);
      connector.active.addAll([
        _heard([0x10, 0x20]),
        _heard([0x30, 0x40, 0x50]),
        _heard([0xAB, 0xCD, 0xEF]),
      ]);
      connector.repeaterActivity.value++;
      await tester.pump();
      await _open(tester, activity: true);
      expect(_dialogText('Two-byte repeater'), findsOneWidget);
      expect(_dialogText('Three-byte room'), findsOneWidget);
      expect(_dialogText('Chat is not a repeater'), findsNothing);
      expect(_dialogText('Different second byte'), findsNothing);
      expect(_dialogText('1020'), findsOneWidget);
      expect(_dialogText('304050'), findsOneWidget);
      expect(_dialogText('ABCDEF'), findsWidgets);
      expect(connector.sent, isEmpty);
    });
  });

  for (final scale in [1.0, 1.5]) {
    testWidgets('U06a3 baseline: list owns its scrollbar and survives reopen (scale=$scale)', (tester) async {
      await _withIndicators(tester, (connector, builds) async {
        final now = DateTime.now();
        for (var i = 0; i < 12; i++) {
          final prefix = [0x80 + i];
          connector.nodes.add(_contact(prefix, 'Repeater $i'));
          connector.active.add(
            _heard(prefix, lastUpdated: now.subtract(Duration(seconds: i))),
          );
        }
        connector.repeaterActivity.value++;
        await tester.pump();
        await _open(tester, activity: true);
        final listFinder = find.descendant(of: find.byType(AlertDialog), matching: find.byType(ListView));
        final barFinder = find.descendant(of: find.byType(AlertDialog), matching: find.byType(Scrollbar));
        final controller = tester.widget<ListView>(listFinder).controller;
        expect(controller, isNotNull);
        expect(tester.widget<Scrollbar>(barFinder).controller, same(controller));
        expect(controller!.hasClients, isTrue);
        expect(controller.position.maxScrollExtent, greaterThan(0));
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(_dialogText('Repeater 11').hitTestable(), findsOneWidget);
        await _close(tester);
        await _open(tester, activity: true);
        final reopened = tester.widget<ListView>(listFinder).controller;
        expect(reopened, isNot(same(controller)));
        expect(reopened!.offset, 0);
        expect(tester.takeException(), isNull);
        expect(connector.sent, isEmpty);
      }, scale: scale);
    });
  }

  testWidgets('U06a3 baseline: activity updates indicators without rebuilding their parent', (tester) async {
    await _withIndicators(tester, (connector, builds) async {
      final parentBuilds = builds.value;
      var broadNotifications = 0;
      connector.addListener(() => broadNotifications++);
      connector.direct.add(_heard([0x12], snr: 9));
      connector.active.add(_heard([0x34], snr: 7));
      connector.repeaterActivity.value++;
      await tester.pump();
      expect(find.text('9.0 dB'), findsOneWidget);
      expect(find.text('7.0 dB'), findsOneWidget);
      expect(builds.value, parentBuilds);
      expect(broadNotifications, 0);
      expect(connector.sent, isEmpty);
    });
  });
}
