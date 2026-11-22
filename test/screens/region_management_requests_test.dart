import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/screens/region_management_screen.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Radio extends ChangeNotifier implements MeshCoreConnector {
  _Radio(this.version);

  final int version;
  final incoming = StreamController<Uint8List>.broadcast();
  final writes = <Uint8List>[];
  final paths = <({Uint8List bytes, int hops, int? width, bool acknowledged})>[];
  final peers = <Contact>[];
  bool acceptImport = true;
  int imports = 0;
  bool rejectDiscovery = false;
  Timer? discoveryReplyTimer;
  final discoveryAckWaits = <bool>[];
  Contact? restored;

  final target = Contact(
    publicKey: Uint8List.fromList(List.filled(32, 0x42)),
    name: 'Neighbour', type: advTypeRepeater,
    pathLength: 2, path: Uint8List.fromList([0x70, 0x71]),
    lastSeen: DateTime(2026),
  );

  @override
  bool get isConnected => true;
  @override
  String get storageKeyHex => 'aa' * 32;
  @override
  String get selfPublicKeyHex => storageKeyHex;
  @override
  Uint8List get selfPublicKey => Uint8List.fromList(List.filled(32, 0xaa));
  @override
  int get pathHashByteWidth => 1;
  @override
  int get firmwareVerCode => version;
  @override
  List<Contact> get contacts => peers;
  @override
  Stream<Uint8List> get receivedFrames => incoming.stream;
  @override
  bool get isLoadingContacts => false;
  @override
  bool get isLoadingChannels => false;
  @override
  bool get isSyncingChannels => false;
  @override
  bool get isSyncingQueuedMessages => false;
  @override
  Future<String?> getDefaultRegionScope() async => null;
  @override
  Contact? getContactByPubKeyHex(String key) =>
      peers.where((peer) => peer.publicKeyHex == key).firstOrNull;

  @override
  Future<bool> importDiscoveredContact(Contact contact) async {
    imports++;
    if (!acceptImport) return false;
    peers.add(contact);
    return true;
  }

  @override
  Future<void> setContactPath(Contact contact, Uint8List path, int hops,
      {int? pathHashWidth, bool waitForAck = false}) async {
    if (getContactByPubKeyHex(contact.publicKeyHex) == null) {
      throw StateError('Route installation requires a stored node contact');
    }
    paths.add((bytes: Uint8List.fromList(path), hops: hops,
      width: pathHashWidth, acknowledged: waitForAck));
    if (!waitForAck) restored = contact;
  }

  @override
  Future<void> sendFrame(Uint8List data, {String? channelSendQueueId,
      bool expectsGenericAck = false, bool waitForGenericAck = false}) async {
    writes.add(Uint8List.fromList(data));
    if (data.first == cmdSendControlData) {
      // Firmware discovery response: control header, type/SNR, echoed tag, key.
      discoveryAckWaits.add(waitForGenericAck);
      if (rejectDiscovery) throw StateError('Discovery command rejected');
      final tag = data.sublist(3, 7);
      // Ignore unrelated tags and non-repeater nodes even with mask 0xFF.
      incoming.add(Uint8List.fromList([
        pushCodeControlData, 20, 160, 0,
        (controlSubtypeDiscoverResp << 4) | advTypeRepeater, 20,
        for (final byte in tag) byte ^ 0xff,
        ...List.filled(32, 0x43),
      ]));
      incoming.add(Uint8List.fromList([
        pushCodeControlData, 20, 160, 0,
        (controlSubtypeDiscoverResp << 4) | advTypeChat, 20,
        ...tag, ...List.filled(32, 0x44),
      ]));
      // Repeater firmware randomises this delay; it can exceed 15 seconds.
      discoveryReplyTimer = Timer(const Duration(seconds: 20), () {
        incoming.add(Uint8List.fromList([
          pushCodeControlData, 20, 160, 0,
          (controlSubtypeDiscoverResp << 4) | advTypeRepeater, 20,
          ...tag, ...target.publicKey,
        ]));
      });
    } else if (data.first == cmdSendAnonReq) {
      // Firmware SENT, then BINARY_RESPONSE: reserved, tag, clock, CSV names.
      incoming.add(Uint8List.fromList([
        respCodeSent, 0, 1, 2, 3, 4, 100, 0, 0, 0,
      ]));
      incoming.add(Uint8List.fromList([
        pushCodeBinaryResponse, 0, 1, 2, 3, 4, 5, 6, 7, 8,
        ...utf8.encode('test-region'),
      ]));
    } else {
      throw StateError('Unexpected command ${data.first}');
    }
  }

  Future<void> close() async {
    discoveryReplyTimer?.cancel();
    await incoming.close();
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<AppLocalizations> _open(WidgetTester tester, _Radio radio,
    {bool routed = false, int width = 1}) async {
  await tester.pumpWidget(ChangeNotifierProvider<MeshCoreConnector>.value(
    value: radio,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RegionManagementScreen(
        initialFetchRepeater: routed ? radio.target : null,
        initialFetchPath: routed
            ? Uint8List.fromList(List.generate(width * 2, (index) => index + 1))
            : null,
        initialFetchHopCount: routed ? 2 : null,
        initialFetchPathHashByteWidth: routed ? width : null,
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return AppLocalizations.of(tester.element(find.byType(RegionManagementScreen)));
}

// Stream delivery, subscription cancellation and dialog presentation finish in
// separate asynchronous turns. Wait for the result itself, with a fixed bound;
// an indeterminate fetching spinner makes pumpAndSettle unsuitable here.
Future<void> _waitForResult(
  WidgetTester tester,
  _Radio radio,
  String text,
) async {
  final result = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.text(text),
  );
  for (var attempt = 0; attempt < 40; attempt++) {
    // Broadcast subscription cancellation can return Future._nullFuture from
    // the SDK's root zone. FakeAsync pumps do not drain that zone; let its
    // continuations finish before pumping the resulting Flutter frame.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final exception = tester.takeException();
    expect(exception, isNull);
    if (result.evaluate().length == 1) return;
  }
  fail('Region result did not appear: "$text"; '
      'commands=${radio.writes.map((frame) => frame.first).toList()}, '
      'paths=${radio.paths.length}, imports=${radio.imports}, '
      'dialogs=${find.byType(AlertDialog).evaluate().length}');
}

Future<void> _close(WidgetTester tester, _Radio radio) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await radio.close();
  radio.dispose();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  for (final version in [12, 13]) {
    testWidgets('automatic discovery without saved repeaters: firmware $version', (tester) async {
      final radio = _Radio(version);
      try {
        final l10n = await _open(tester, radio);
        await tester.tap(find.byTooltip(l10n.settings_regionFetchRegions));
        await tester.pump();
        if (version < 13) {
          expect(find.text(l10n.settings_regionFetchNoRepeaters), findsOneWidget);
          expect(radio.writes, isEmpty);
        } else {
          expect(radio.writes.single.first, cmdSendControlData);
          expect(radio.writes.single.sublist(1, 3), [0x80, 0xFF]);
          expect(radio.discoveryAckWaits, [true]);
          await tester.pump(const Duration(seconds: 16));
          expect(radio.writes.where((data) => data.first == cmdSendAnonReq), isEmpty);
          expect(find.text(l10n.settings_regionFetchRegionsFail), findsNothing);
          await tester.pump(const Duration(seconds: 45));
          await _waitForResult(tester, radio, 'test-region');
          final request = radio.writes.singleWhere((data) => data.first == cmdSendAnonReq);
          expect(request.sublist(1, 33), radio.target.publicKey);
          expect(request.sublist(33), [anonReqTypeRegions, 0]);
          expect(radio.imports, 0);
          expect(radio.paths, isEmpty);
          expect(radio.peers, isEmpty);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, radio);
      }
    });
  }

  testWidgets('rejected discovery stops before region queries', (tester) async {
    final radio = _Radio(13)..rejectDiscovery = true;
    try {
      final l10n = await _open(tester, radio);
      await tester.tap(find.byTooltip(l10n.settings_regionFetchRegions));
      await _waitForResult(tester, radio, l10n.settings_regionFetchRegionsFail);
      expect(radio.discoveryAckWaits, [true]);
      expect(radio.writes, hasLength(1));
      expect(find.text(l10n.settings_regionFetchRegionsFail), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await _close(tester, radio);
    }
  });

  for (final outcome in ['cancel', 'reject', 'approve']) {
    testWidgets('routed request to an unstored repeater: $outcome', (tester) async {
      final radio = _Radio(13)..acceptImport = outcome != 'reject';
      try {
        final l10n = await _open(tester, radio, routed: true, width: 2);
        expect(find.text(l10n.contacts_addToNodeTitle), findsOneWidget);
        expect(radio.writes, isEmpty);
        await tester.tap(find.text(outcome == 'cancel' ? l10n.common_cancel : l10n.common_add));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        if (outcome == 'approve') {
          await _waitForResult(tester, radio, 'test-region');
          expect(radio.imports, 1);
          final applied = radio.paths.first;
          expect(applied.bytes, [1, 2, 3, 4]);
          expect(applied.hops, 2);
          expect(applied.width, 2); // Explicit map width wins over radio mode 1.
          expect(applied.acknowledged, isTrue);
          final request = radio.writes.singleWhere((data) => data.first == cmdSendAnonReq);
          expect(request.sublist(33), [anonReqTypeRegions, 0x42, 3, 4, 1, 2]);
          expect(radio.paths.last.bytes, [0x70, 0x71]);
          expect(radio.paths.last.width, 1);
          expect(radio.restored, same(radio.target));
        } else {
          expect(radio.imports, outcome == 'cancel' ? 0 : 1);
          expect(radio.writes, isEmpty);
          expect(radio.paths, isEmpty);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, radio);
      }
    });
  }
}
