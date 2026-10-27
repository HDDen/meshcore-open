import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mco_service/mco_service.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/south_frame_fragment_reassembler.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('Synthetic preferences without a directory');
  }
}

// Только контракт переключателя FR01; коммерческие службы не создаются.
class _Features extends Fake implements SettingsSectionsService {
  _Features(this.enabled);
  final bool enabled;

  @override
  bool get southFrameFragmentsEnabled => enabled;
  @override
  void mcoX2(Uint8List frame) {}
  @override
  Future<void> mcoX1(Uint8List frame, Future<void> Function() direct) => direct();
  @override
  void setDeviceRawVars(Map<String, String>? vars, {String? raw}) {}
}

class _Connector extends MeshCoreConnector {
  _Connector({required bool fragments}) {
    setFrameInterceptorForTest(_Features(fragments));
    setFrameWriterForTest((frame) async {
      sent.add(List<int>.of(frame));
      if (frame.first == cmdAppStart && failNextAppStart) {
        failNextAppStart = false;
        throw StateError('Synthetic APP_START writer failure');
      }
    });
  }

  bool connected = true;
  bool failNextAppStart = false;
  final sent = <List<int>>[];
  @override
  bool get isConnected => connected;

  int count(int code) => sent.where((frame) => frame.first == code).length;
  List<List<int>> get syncFrames =>
      sent.where((frame) => frame.first == cmdSyncNextMessage).toList();

  void gps(bool enabled) => handleFrameForTest([
    respCodeCustomVars,
    ...utf8.encode('gps:${enabled ? 1 : 0}'),
    0,
  ]);

  void finishQueue() => handleFrameForTest([respCodeNoMoreMessages]);
}

// Не меняет wire codec: синтетические FR01 байты по существующему контракту.
Uint8List _fragment(
  Uint8List original, {
  int id = 0x1234,
  required int index,
  bool queued = false,
}) {
  final offset = index * SouthFrameFragmentReassembler.chunkLength;
  final end = (offset + SouthFrameFragmentReassembler.chunkLength)
      .clamp(0, original.length)
      .toInt();
  final count = (original.length + SouthFrameFragmentReassembler.chunkLength - 1) ~/
      SouthFrameFragmentReassembler.chunkLength;
  return Uint8List.fromList([
    0xED, 0x46, 0x52, 0x30, 0x31,
    queued ? 1 : 0,
    id & 0xFF, (id >> 8) & 0xFF,
    index, count,
    original.first,
    original.length & 0xFF, (original.length >> 8) & 0xFF,
    offset & 0xFF, (offset >> 8) & 0xFF,
    ...original.sublist(offset, end),
  ]);
}

Uint8List _live({int seed = 0}) => Uint8List.fromList([
  pushCodeControlData,
  ...List.generate(258, (i) => (i + seed) & 0xFF),
]);

// Валидный длинный GRP_DATA неизвестного namespace: проходит реальную queued
// обработку, не запускает MCOimg/MCMP декодирование и запись сообщений в БД.
Uint8List _queuedData() => Uint8List.fromList([
  respCodeChannelDataRecv, 0, 0, 0, 0, 0xFF, 0x77, 0x77, 168,
  ...List.generate(168, (i) => i),
]);

Future<void> _withConnector(
  WidgetTester tester,
  Future<void> Function(_Connector c, List<Uint8List> received) check, {
  bool fragments = true,
}) async {
  // Connector/Futures созданы внутри FakeAsync, а не во внешнем setUp.
  final c = _Connector(fragments: fragments);
  final received = <Uint8List>[];
  final subscription = c.receivedFrames.listen(received.add);
  try {
    await check(c, received);
  } finally {
    c.connected = false;
    c.resetSyncProgressForTest();
    await tester.pump();
    // cancel() broadcast-подписки возвращает общий Future из root zone.
    // FakeAsync не прокачивает его microtasks; ждём только отмену в real zone.
    await tester.runAsync(() async {
      await subscription.cancel();
    });
    c.setFrameInterceptorForTest(null);
    c.dispose();
    await tester.pump(const Duration(seconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const timeout = Timeout(Duration(seconds: 30));
  late PathProviderPlatform previousPaths;
  setUpAll(() {
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferencesDirectory();
  });
  tearDownAll(() => PathProviderPlatform.instance = previousPaths);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  for (final fragments in [false, true]) {
    testWidgets('baseline: idle GPS polling preserves cadence and FR01 capability=$fragments',
        (tester) async {
      await _withConnector(tester, (c, received) async {
        c.gps(true);
        await tester.pump(const Duration(seconds: 59));
        expect(c.count(cmdAppStart), 0);
        await tester.pump(const Duration(seconds: 1));
        final first = c.sent.single;
        expect(
          first,
          orderedEquals(buildAppStartFrame(
            appName: buildMeshCoreOpenAppName(
              enableSouthFrameFragments: fragments,
            ),
          )),
        );
        expect(c.awaitingSelfInfoForTest, isFalse);
        expect(c.isSyncingQueuedMessages, isFalse);
        await tester.pump(const Duration(seconds: 60));
        expect(c.count(cmdAppStart), 2);
      }, fragments: fragments);
    }, timeout: timeout);
  }

  testWidgets('baseline: a failed GPS write does not stop the next poll', (tester) async {
    await _withConnector(tester, (c, received) async {
      c.failNextAppStart = true;
      c.gps(true);
      await tester.pump(const Duration(seconds: 60));
      expect(c.count(cmdAppStart), 1);
      await tester.pump(const Duration(seconds: 60));
      expect(c.count(cmdAppStart), 2);
      c.gps(false);
      await tester.pump(const Duration(seconds: 120));
      expect(c.count(cmdAppStart), 2);
    });
  }, timeout: timeout);

  testWidgets('baseline: live FR01 dispatches only the complete original frame', (tester) async {
    await _withConnector(tester, (c, received) async {
      final original = _live();
      c.handleFrameForTest(_fragment(original, index: 0));
      await tester.pump();
      expect(received, isEmpty);
      expect(c.syncFrames, isEmpty);
      c.handleFrameForTest(_fragment(original, index: 1));
      await tester.pump();
      expect(received.single, orderedEquals(original));
      expect(c.syncFrames, isEmpty);
    });
  }, timeout: timeout);

  testWidgets('baseline: queued FR01 carries each ACK until NO_MORE clears it', (tester) async {
    await _withConnector(tester, (c, received) async {
      final original = _queuedData();
      await c.syncQueuedMessages();
      expect(c.syncFrames, [[cmdSyncNextMessage]]);
      c.handleFrameForTest(_fragment(original, index: 0, queued: true));
      await tester.pump();
      expect(c.syncFrames.last, [cmdSyncNextMessage, 1, 0x34, 0x12, 0]);
      expect(received, isEmpty);
      c.handleFrameForTest(_fragment(original, index: 1, queued: true));
      await tester.pump();
      expect(received.single, orderedEquals(original));
      expect(c.syncFrames, [
        [cmdSyncNextMessage],
        [cmdSyncNextMessage, 1, 0x34, 0x12, 0],
        [cmdSyncNextMessage, 1, 0x34, 0x12, 1],
      ]);
      c.finishQueue();
      await tester.pump();
      expect(c.isSyncingQueuedMessages, isFalse);
      await c.syncQueuedMessages();
      expect(c.syncFrames.last, [cmdSyncNextMessage]);
      c.finishQueue();
    });
  }, timeout: timeout);

  testWidgets('baseline: live FR01 does not consume the outstanding queued response',
      (tester) async {
    await _withConnector(tester, (c, received) async {
      await c.syncQueuedMessages();
      final live = _live();
      c.handleFrameForTest(_fragment(live, id: 9, index: 0));
      c.handleFrameForTest(_fragment(live, id: 9, index: 1));
      await tester.pump();
      expect(c.syncFrames, [[cmdSyncNextMessage]]);
      expect(received.single, orderedEquals(live));
      final queued = _queuedData();
      c.handleFrameForTest(_fragment(queued, index: 0, queued: true));
      await tester.pump();
      expect(c.syncFrames.last, [cmdSyncNextMessage, 1, 0x34, 0x12, 0]);
      c.handleFrameForTest(_fragment(queued, index: 1, queued: true));
      await tester.pump();
      expect(received.last, orderedEquals(queued));
      expect(c.syncFrames.last, [cmdSyncNextMessage, 1, 0x34, 0x12, 1]);
      c.finishQueue();
    });
  }, timeout: timeout);

  testWidgets('baseline: contact sync GPS skip preserves an in-progress FR01 frame',
      (tester) async {
    await _withConnector(tester, (c, received) async {
      c.gps(true);
      await tester.pump(const Duration(seconds: 59));
      c.setContactSyncInProgressForTest(true);
      final original = _live();
      c.handleFrameForTest(_fragment(original, index: 0));
      await tester.pump(const Duration(seconds: 1));
      expect(c.count(cmdAppStart), 0);
      c.handleFrameForTest(_fragment(original, index: 1));
      await tester.pump();
      expect(received.where((f) => f.first == pushCodeControlData).single,
        orderedEquals(original));
      c.setContactSyncInProgressForTest(false);
      await tester.pump(const Duration(seconds: 60));
      expect(c.count(cmdAppStart), 1);
    });
  }, timeout: timeout);

  testWidgets('baseline: a new connection session discards fragments from the old one',
      (tester) async {
    await _withConnector(tester, (c, received) async {
      c.handleFrameForTest(_fragment(_live(seed: 1), index: 0));
      c.resetConnectionHandshakeForTest();
      final current = _live(seed: 2);
      c.handleFrameForTest(_fragment(current, index: 1));
      await tester.pump();
      expect(received, isEmpty);
      c.handleFrameForTest(_fragment(current, index: 0));
      await tester.pump();
      expect(received.single, orderedEquals(current));
    });
  }, timeout: timeout);

  testWidgets('regression: a GPS tick preserves an incomplete live FR01 frame',
      (tester) async {
    await _withConnector(tester, (c, received) async {
      c.gps(true);
      await tester.pump(const Duration(seconds: 59));
      final original = _live();
      c.handleFrameForTest(_fragment(original, index: 0));
      await tester.pump(const Duration(seconds: 1));
      expect(c.count(cmdAppStart), 0);
      c.handleFrameForTest(_fragment(original, index: 1));
      await tester.pump();
      expect(received.where((f) => f.first == pushCodeControlData).single,
          orderedEquals(original));
      await tester.pump(const Duration(seconds: 60));
      expect(c.count(cmdAppStart), 1);
    });
  }, timeout: timeout);

  testWidgets('regression: GPS does not erase queued FR01 or its next ACK',
      (tester) async {
    await _withConnector(tester, (c, received) async {
      c.gps(true);
      await tester.pump(const Duration(seconds: 59));
      await c.syncQueuedMessages();
      final original = _queuedData();
      c.handleFrameForTest(_fragment(original, index: 0, queued: true));
      await tester.pump();
      expect(c.syncFrames.last, [cmdSyncNextMessage, 1, 0x34, 0x12, 0]);
      await tester.pump(const Duration(seconds: 1));
      expect(c.count(cmdAppStart), 0);
      c.handleFrameForTest(_fragment(original, index: 1, queued: true));
      await tester.pump();
      expect(received.where((f) => f.first == respCodeChannelDataRecv).single,
          orderedEquals(original));
      expect(c.syncFrames, [
        [cmdSyncNextMessage],
        [cmdSyncNextMessage, 1, 0x34, 0x12, 0],
        [cmdSyncNextMessage, 1, 0x34, 0x12, 1],
      ]);
      c.finishQueue();
      await tester.pump();
      await tester.pump(const Duration(seconds: 60));
      expect(c.count(cmdAppStart), 1);
    });
  }, timeout: timeout);

  testWidgets('regression: final fragment ACK is protected until queue timeout',
      (tester) async {
    await _withConnector(tester, (c, received) async {
      c.gps(true);
      await tester.pump(const Duration(seconds: 58));
      await c.syncQueuedMessages();
      final original = _queuedData();
      c.handleFrameForTest(_fragment(original, index: 0, queued: true));
      await tester.pump();
      c.handleFrameForTest(_fragment(original, index: 1, queued: true));
      await tester.pump();
      expect(c.syncFrames.last, [cmdSyncNextMessage, 1, 0x34, 0x12, 1]);
      await tester.pump(const Duration(seconds: 2));
      expect(c.count(cmdAppStart), 0);
      await tester.pump(const Duration(seconds: 3));
      expect(c.isSyncingQueuedMessages, isFalse);
      // После прежнего timeout GPS возобновляется на плановом тике,
      // без нового разрушительного чтения очереди и без добавленного retry.
      await tester.pump(const Duration(seconds: 57));
      expect(c.count(cmdAppStart), 1);
      expect(c.syncFrames.length, 3);
    });
  }, timeout: timeout);

  for (final fragments in [false, true]) {
    testWidgets('regression: GPS waits for an ordinary queue response, FR01=$fragments',
        (tester) async {
      await _withConnector(tester, (c, received) async {
        c.gps(true);
        await tester.pump(const Duration(seconds: 59));
        await c.syncQueuedMessages();
        await tester.pump(const Duration(seconds: 1));
        expect(c.count(cmdAppStart), 0);
        c.finishQueue();
        await tester.pump();
        await tester.pump(const Duration(seconds: 60));
        expect(c.count(cmdAppStart), 1);
        expect(c.syncFrames, [[cmdSyncNextMessage]]);
      }, fragments: fragments);
    }, timeout: timeout);
  }
}
