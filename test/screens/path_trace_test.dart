import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/path_history.dart';
import 'package:meshcore_open/screens/manual_path_trace_screen.dart';
import 'package:meshcore_open/screens/path_trace_map.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/map_tile_cache_service.dart';
import 'package:meshcore_open/services/path_history_service.dart';
import 'package:meshcore_open/services/storage_service.dart';
import 'package:meshcore_open/services/ui_view_state_service.dart';
import 'package:meshcore_open/services/wardrive_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';

class _FakeMeshCoreConnector extends MeshCoreConnector {
  _FakeMeshCoreConnector({this.firmwareVerCode});

  @override
  final int? firmwareVerCode;

  bool connected = false;
  String radioKey = '01' * 32;

  @override
  bool get isConnected => connected;

  @override
  String get selfPublicKeyHex => radioKey;

  final StreamController<Uint8List> _receivedFramesController =
      StreamController<Uint8List>.broadcast();

  @override
  Stream<Uint8List> get receivedFrames => _receivedFramesController.stream;

  @override
  Uint8List? get selfPublicKey =>
      Uint8List.fromList(List.generate(32, (i) => i));

  @override
  double? get selfLatitude => 48.8566;

  @override
  double? get selfLongitude => 2.3522;

  @override
  List<Contact> get allContactsUnfiltered => [];

  @override
  List<Contact> get contacts => [];

  void emitFrame(Uint8List frame) {
    _receivedFramesController.add(frame);
  }

  final List<Uint8List> sentFrames = [];

  @override
  Future<void> sendFrame(
    Uint8List frame, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {
    sentFrames.add(frame);
  }
}

class _FakePathStorageService extends StorageService {
  final Map<String, ContactPathHistory> _pathHistory =
      <String, ContactPathHistory>{};

  @override
  Future<void> savePathHistory(
    String contactPubKeyHex,
    ContactPathHistory history,
  ) async {
    _pathHistory[contactPubKeyHex] = history;
  }

  @override
  Future<ContactPathHistory?> loadPathHistory(String contactPubKeyHex) async {
    return _pathHistory[contactPubKeyHex];
  }

  @override
  Future<void> clearPathHistory(String contactPubKeyHex) async {
    _pathHistory.remove(contactPubKeyHex);
  }
}

Future<Widget> _buildTestApp({
  required MeshCoreConnector connector,
  required Widget child,
  bool includeMapServices = true,
}) async {
  final appSettingsService = AppSettingsService();
  // With the option on, the screen asks the wardrive service for the phone's
  // position from initState, and the service notifies from inside that
  // first build, which the test framework reports as an error.
  await appSettingsService.updateSettings(
    appSettingsService.settings.copyWith(alwaysRequestMapLocation: false),
  );

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<MeshCoreConnector>.value(value: connector),
      ChangeNotifierProvider<AppSettingsService>.value(
        value: appSettingsService,
      ),
      ChangeNotifierProvider<UiViewStateService>(
        create: (_) => UiViewStateService(),
      ),
      if (includeMapServices)
        ChangeNotifierProvider<MapTileCacheService>(
          create: (_) =>
              MapTileCacheService(appSettingsService: appSettingsService),
        ),
      ChangeNotifierProvider<PathHistoryService>(
        create: (_) => PathHistoryService(_FakePathStorageService()),
      ),
      // The screen asks it for the phone's position while the map location
      // option is on; the service reads its settings at construction.
      if (includeMapServices)
        ChangeNotifierProvider<WardriveService>(
          create: (_) => WardriveService(connector),
        ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

List<Contact> _relays(int count) => [
  for (var i = 0; i < count; i++)
    Contact(
      publicKey: Uint8List.fromList([
        i + 1, 0xA2, 0xB3, 0xC4, ...List<int>.filled(28, 0),
      ]),
      name: 'Relay ${i + 1}',
      type: advTypeRepeater,
      pathLength: -1,
      path: Uint8List(0),
      lastSeen: DateTime.utc(2026),
    ),
];

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(PrefsManager.reset);

  for (final sample in [
    (width: 1, hops: 64, roundTrip: false, flags: 0, frameBytes: 74),
    (width: 2, hops: 32, roundTrip: true, flags: 1, frameBytes: 136),
    (width: 3, hops: 21, roundTrip: true, flags: 2, frameBytes: 174),
  ]) {
    testWidgets(
      'U32 baseline: trace encodes ${sample.hops} hops of width ${sample.width} '
      'without coordinates (roundTrip=${sample.roundTrip})',
      (tester) async {
        final connector = _FakeMeshCoreConnector(firmwareVerCode: 13);
        addTearDown(connector.dispose);
        final contacts = _relays(sample.hops);
        final keys = contacts.map((contact) => contact.publicKey).toList();
        final path = Uint8List.fromList([
          for (final key in keys) ...key.take(sample.width),
        ]);
        final wireWidth = sample.width == 3 ? 4 : sample.width;
        final wireKeys = [
          ...keys,
          if (sample.roundTrip) ...keys.take(keys.length - 1).toList().reversed,
        ];
        final screen = PathTraceMapScreen(
          title: 'Trace fixture',
          path: path,
          pathHashByteWidth: sample.width,
          pathContacts: contacts,
          flipPathAround: sample.roundTrip,
          revealMapManually: true,
        );

        await tester.pumpWidget(
          await _buildTestApp(connector: connector, child: screen),
        );
        await tester.pump();

        final frame = connector.sentFrames.single;
        expect(frame.length, sample.frameBytes);
        expect(frame.first, cmdSendTracePath);
        // The tag varies per run. Authentication, flags and hop bytes are fixed.
        expect(frame.sublist(5), [
          0, 0, 0, 0, sample.flags,
          for (final key in wireKeys) ...key.take(wireWidth),
        ]);
        expect(find.byType(FlutterMap), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final sample in [
    (width: 1, hops: 33, code: 13),
    (width: 3, hops: 21, code: 12),
    (width: 3, hops: 22, code: 13),
  ]) {
    testWidgets('U32: oversized expanded trace never sends ($sample)', (tester) async {
      final connector = _FakeMeshCoreConnector(firmwareVerCode: sample.code);
      addTearDown(connector.dispose);
      final contacts = _relays(sample.hops);
      final screen = PathTraceMapScreen(
        title: 'Trace fixture',
        path: Uint8List.fromList([
          for (final contact in contacts) ...contact.publicKey.take(sample.width),
        ]),
        pathHashByteWidth: sample.width,
        flipPathAround: true,
        pathContacts: contacts,
      );
      await tester.pumpWidget(
        await _buildTestApp(connector: connector, child: screen),
      );
      await tester.pump();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(PathTraceMapScreen)),
      );
      expect(find.text(l10n.manualTrace_requestTooLong), findsOneWidget);
      await tester.pump(const Duration(seconds: 16));
      expect(connector.sentFrames, isEmpty);
      expect(connector._receivedFramesController.hasListener, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('U32: manual trace reports SNR without GPS or map services',
      (tester) async {
    final connector = _FakeMeshCoreConnector(firmwareVerCode: 13)
      ..connected = true;
    addTearDown(connector.dispose);
    await tester.pumpWidget(await _buildTestApp(
      connector: connector,
      child: const ManualPathTraceScreen(),
      includeMapServices: false,
    ));
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ManualPathTraceScreen)),
    );
    final field = find.byType(TextField);
    final run = find.ancestor(
      of: find.text(l10n.map_runTrace),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    await tester.enterText(field, 'A1, zz');
    await tester.pump();
    expect(find.text(l10n.manualTrace_invalidHashes), findsOneWidget);
    expect(tester.widget<FilledButton>(run).onPressed, isNull);

    await tester.enterText(field, List.filled(33, 'A1').join(','));
    await tester.pump();
    expect(find.text(l10n.manualTrace_requestTooLong), findsOneWidget);
    expect(tester.widget<FilledButton>(run).onPressed, isNull);

    await tester.enterText(field, 'A1B2C3, D4E5F6');
    await tester.pump();
    await tester.tap(run);
    await tester.pump();
    expect(find.text(l10n.manualTrace_unresolvedHop), findsOneWidget);
    expect(connector.sentFrames, isEmpty);

    await tester.enterText(field, 'A1, B2');
    await tester.pump();
    await tester.tap(find.text(l10n.map_pathTraceModeAsEntered));
    await tester.pump();
    final radioKey = connector.radioKey;
    connector.radioKey = '02' * 32;
    connector.notifyListeners();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<FilledButton>(run).onPressed, isNull);
    expect(connector.sentFrames, isEmpty);
    connector.radioKey = radioKey;
    connector.notifyListeners();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(run);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final sent = connector.sentFrames.single;
    expect(sent.sublist(9), [0, 0xA1, 0xB2]);
    connector.emitFrame(Uint8List.fromList([
      pushCodeTraceData, 0, 2, 0, ...sent.sublist(1, 5),
      0, 0, 0, 0, 0xA1, 0xB2, 12, 16, 20,
    ]));
    await tester.pumpAndSettle();
    expect(find.textContaining('A1'), findsWidgets);
    expect(find.textContaining('B2'), findsWidgets);
    expect(find.byType(FlutterMap), findsNothing);
    expect(connector.sentFrames, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('U32: four-byte trace replies keep their complete hop prefixes',
      (tester) async {
    final connector = _FakeMeshCoreConnector(firmwareVerCode: 13);
    addTearDown(connector.dispose);
    final contacts = _relays(2);
    await tester.pumpWidget(await _buildTestApp(
      connector: connector,
      child: PathTraceMapScreen(
        title: 'Four-byte trace',
        path: Uint8List.fromList([
          for (final contact in contacts) ...contact.publicKey.take(3),
        ]),
        pathHashByteWidth: 3,
        pathContacts: contacts,
        revealMapManually: true,
        deferLocationUntilMapShown: true,
      ),
      includeMapServices: false,
    ));
    await tester.pump();
    final sent = connector.sentFrames.single;
    final payload = sent.sublist(10);
    connector.emitFrame(Uint8List.fromList([
      pushCodeTraceData, 0, payload.length, 2, ...sent.sublist(1, 5),
      0, 0, 0, 0, ...payload, 12, 16, 20,
    ]));
    await tester.pumpAndSettle();
    expect(find.textContaining('Relay 1'), findsWidgets);
    expect(find.textContaining('Relay 2'), findsWidgets);
    expect(find.byType(ListTile), findsNWidgets(3));
    expect(find.byType(FlutterMap), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('PathTraceMapScreen parses response frames correctly', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector();

    final screen = PathTraceMapScreen(
      title: 'Test Trace',
      path: Uint8List.fromList([0x12, 0x34]),
      pathHashByteWidth: 1,
    );

    await tester.pumpWidget(
      await _buildTestApp(connector: connector, child: screen),
    );
    await tester.pump();

    // Verify a send request was made
    expect(connector.sentFrames.length, 1);
    final sentFrame = connector.sentFrames.first;
    expect(sentFrame[0], cmdSendTracePath);

    // Extract the tag sent in the request (bytes 1-4; byte 0 is the command)
    final tag = sentFrame.sublist(1, 5);

    // Emit respCodeSent (6)
    final respCodeSentFrame = Uint8List(10);
    respCodeSentFrame[0] = respCodeSent;
    respCodeSentFrame[1] = 0; // reserved / is_flood
    respCodeSentFrame.setRange(2, 6, tag);
    // timeout milliseconds = 5000 (0x1388)
    respCodeSentFrame[6] = 0x88;
    respCodeSentFrame[7] = 0x13;
    respCodeSentFrame[8] = 0x00;
    respCodeSentFrame[9] = 0x00;

    connector.emitFrame(respCodeSentFrame);
    await tester.pump();

    // Now emit PUSH_CODE_TRACE_DATA (0x89)
    // Structure:
    // Offset 0: pushCodeTraceData (0x89)
    // Offset 1: reserved (0)
    // Offset 2: pathLength (2)
    // Offset 3: flag (0)
    // Offset 4..7: tag
    // Offset 8..11: auth (0)
    // Offset 12..13: pathBytes [0x12, 0x34]
    // Offset 14..16: SNR bytes [12, 16, 20] -> signed 8 bit Snr/4.
    // Firmware emits one SNR per hop plus one final SNR to this node.
    final pushTraceFrame = Uint8List(17);
    pushTraceFrame[0] = pushCodeTraceData;
    pushTraceFrame[1] = 0; // reserved
    pushTraceFrame[2] = 2; // pathLength
    pushTraceFrame[3] = 0; // flag
    pushTraceFrame.setRange(4, 8, tag);
    // auth bytes (8..11) = 0
    pushTraceFrame.setRange(12, 14, [0x12, 0x34]); // pathBytes
    pushTraceFrame.setRange(14, 17, [12, 16, 20]); // SNR bytes

    connector.emitFrame(pushTraceFrame);
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Verify it doesn't show "Path trace not available" or similar
    expect(find.text('Path trace not available.'), findsNothing);
    expect(find.byType(FlutterMap), findsOneWidget);
  });

  testWidgets(
    'PathTraceMapScreen parses multi-byte encoded path trace response correctly',
    (tester) async {
      final connector = _FakeMeshCoreConnector();

      final screen = PathTraceMapScreen(
        title: 'Test Trace Multi-byte',
        path: Uint8List.fromList([0x12, 0x34]),
        pathHashByteWidth: 2,
      );

      await tester.pumpWidget(
        await _buildTestApp(connector: connector, child: screen),
      );
      await tester.pump();

      // Verify a send request was made
      expect(connector.sentFrames.length, 1);
      final sentFrame = connector.sentFrames.first;
      expect(sentFrame[0], cmdSendTracePath);

      // Extract the tag sent in the request (bytes 1-4; byte 0 is the command)
      final tag = sentFrame.sublist(1, 5);

      // Emit respCodeSent (6)
      final respCodeSentFrame = Uint8List(10);
      respCodeSentFrame[0] = respCodeSent;
      respCodeSentFrame[1] = 0;
      respCodeSentFrame.setRange(2, 6, tag);
      respCodeSentFrame[6] = 0x88;
      respCodeSentFrame[7] = 0x13;
      respCodeSentFrame[8] = 0x00;
      respCodeSentFrame[9] = 0x00;

      connector.emitFrame(respCodeSentFrame);
      await tester.pump();

      // Now emit PUSH_CODE_TRACE_DATA (0x89)
      // Structure:
      // Offset 0: pushCodeTraceData (0x89)
      // Offset 1: reserved (0)
      // Offset 2: pathLength (65) -> mode 1 (width 2), 1 hop
      // Offset 3: flag (0)
      // Offset 4..7: tag
      // Offset 8..11: auth (0)
      // Offset 12..13: pathBytes [0x12, 0x34]
      // Offset 14..15: SNR bytes [12, 16]
      final pushTraceFrame = Uint8List(16);
      pushTraceFrame[0] = pushCodeTraceData;
      pushTraceFrame[1] = 0; // reserved
      pushTraceFrame[2] = 65; // pathLength encoded (mode 1, 1 hop -> 2 bytes)
      pushTraceFrame[3] = 0; // flag
      pushTraceFrame.setRange(4, 8, tag);
      pushTraceFrame.setRange(12, 14, [0x12, 0x34]); // pathBytes
      pushTraceFrame.setRange(14, 16, [12, 16]); // SNR bytes

      connector.emitFrame(pushTraceFrame);
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Verify it parsed correctly (should not show the unavailable message)
      expect(find.text('Path trace not available.'), findsNothing);
      expect(find.byType(FlutterMap), findsOneWidget);
    },
  );

  testWidgets('PathTraceMapScreen buildPath: Direct repeater ping (0-hop)', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector();
    final target = Contact(
      publicKey: Uint8List.fromList([0xAA, 0xBB, 0xCC]),
      name: 'Repeater Node',
      type: advTypeRepeater,
      path: Uint8List(0),
      pathLength: 0,
      lastSeen: DateTime.now(),
    );

    final screen = PathTraceMapScreen(
      title: 'Direct Repeater Ping',
      path: Uint8List.fromList([0xAA]),
      targetContact: target,
      flipPathAround: true,
      pathHashByteWidth: 1,
    );

    await tester.pumpWidget(
      await _buildTestApp(connector: connector, child: screen),
    );
    await tester.pump();

    expect(connector.sentFrames.length, 1);
    final sentFrame = connector.sentFrames.first;
    expect(sentFrame[0], cmdSendTracePath);
    final payload = sentFrame.sublist(10);
    expect(payload, Uint8List.fromList([0xAA]));
  });

  testWidgets('PathTraceMapScreen buildPath: 1-hop chat contact trace', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector();
    final target = Contact(
      publicKey: Uint8List.fromList([0xCC, 0xDD, 0xEE]),
      name: 'Chat User',
      type: advTypeChat,
      path: Uint8List.fromList([0xBB]),
      pathLength: 1,
      lastSeen: DateTime.now(),
    );

    final screen = PathTraceMapScreen(
      title: '1-Hop Chat Trace',
      path: Uint8List.fromList([0xBB]),
      targetContact: target,
      flipPathAround: true,
      pathHashByteWidth: 1,
    );

    await tester.pumpWidget(
      await _buildTestApp(connector: connector, child: screen),
    );
    await tester.pump();

    expect(connector.sentFrames.length, 1);
    final sentFrame = connector.sentFrames.first;
    expect(sentFrame[0], cmdSendTracePath);
    final payload = sentFrame.sublist(10);
    // A chat contact does not forward trace packets, so the endpoint is not
    // appended as a hop (_forwardsTracePackets: repeaters and sensors only)
    // and the trace covers the route alone.
    expect(payload, Uint8List.fromList([0xBB]));
  });

  testWidgets('PathTraceMapScreen buildPath: Multi-hop chat contact trace', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector();
    final target = Contact(
      publicKey: Uint8List.fromList([0x33, 0x44, 0x55]),
      name: 'Chat User Multi-hop',
      type: advTypeChat,
      path: Uint8List.fromList([0x11, 0x22]),
      pathLength: 2,
      lastSeen: DateTime.now(),
    );

    final screen = PathTraceMapScreen(
      title: 'Multi-Hop Chat Trace',
      path: Uint8List.fromList([0x11, 0x22]),
      targetContact: target,
      flipPathAround: true,
      pathHashByteWidth: 1,
    );

    await tester.pumpWidget(
      await _buildTestApp(connector: connector, child: screen),
    );
    await tester.pump();

    expect(connector.sentFrames.length, 1);
    final sentFrame = connector.sentFrames.first;
    expect(sentFrame[0], cmdSendTracePath);
    final payload = sentFrame.sublist(10);
    // The chat endpoint is left out, as in the 1-hop case.
    expect(payload, Uint8List.fromList([0x11, 0x22, 0x11]));
  });

  testWidgets(
    'PathTraceMapScreen buildPath: Map trace with null target contact',
    (tester) async {
      final connector = _FakeMeshCoreConnector();

      final screen = PathTraceMapScreen(
        title: 'Map Trace No Target',
        path: Uint8List.fromList([0x11, 0x22]),
        targetContact: null,
        flipPathAround: true,
        pathHashByteWidth: 1,
      );

      await tester.pumpWidget(
        await _buildTestApp(connector: connector, child: screen),
      );
      await tester.pump();

      expect(connector.sentFrames.length, 1);
      final sentFrame = connector.sentFrames.first;
      expect(sentFrame[0], cmdSendTracePath);
      final payload = sentFrame.sublist(10);
      expect(payload, Uint8List.fromList([0x11, 0x22, 0x11]));
    },
  );

  testWidgets('PathTraceMapScreen parses raw byte length fallback correctly', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector();

    final screen = PathTraceMapScreen(
      title: 'Test Raw Fallback',
      path: Uint8List.fromList([0x12, 0x34]),
      pathHashByteWidth: 2,
    );

    await tester.pumpWidget(
      await _buildTestApp(connector: connector, child: screen),
    );
    await tester.pump();

    expect(connector.sentFrames.length, 1);
    final sentFrame = connector.sentFrames.first;
    // Extract the tag sent in the request (bytes 1-4; byte 0 is the command)
    final tag = sentFrame.sublist(1, 5);

    // Emit respCodeSent (6)
    final respCodeSentFrame = Uint8List(10);
    respCodeSentFrame[0] = respCodeSent;
    respCodeSentFrame[1] = 0;
    respCodeSentFrame.setRange(2, 6, tag);
    respCodeSentFrame[6] = 0x88;
    respCodeSentFrame[7] = 0x13;
    respCodeSentFrame[8] = 0x00;
    respCodeSentFrame[9] = 0x00;

    connector.emitFrame(respCodeSentFrame);
    await tester.pump();

    // Now emit PUSH_CODE_TRACE_DATA (0x89)
    // Structure:
    // Offset 2: pathLength (2) -> raw byte length count, mode is 0!
    // Offset 12..13: pathBytes [0x12, 0x34]
    final pushTraceFrame = Uint8List(17);
    pushTraceFrame[0] = pushCodeTraceData;
    pushTraceFrame[1] = 0; // reserved
    pushTraceFrame[2] = 2; // pathLength as raw byte length (2 bytes)
    pushTraceFrame[3] = 0; // flag
    pushTraceFrame.setRange(4, 8, tag);
    pushTraceFrame.setRange(12, 14, [0x12, 0x34]); // pathBytes
    pushTraceFrame.setRange(14, 17, [12, 16, 20]); // SNR bytes

    connector.emitFrame(pushTraceFrame);
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Verify it parsed correctly (should not show the unavailable message)
    expect(find.text('Path trace not available.'), findsNothing);
    expect(find.byType(FlutterMap), findsOneWidget);
  });
}
