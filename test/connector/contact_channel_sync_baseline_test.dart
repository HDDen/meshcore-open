import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('synthetic preferences without a directory');
  }
}

// Настоящие sendFrame/dispatch и sync-таймеры; только физический writer подменён.
// Нода не привязана, слоты пустые: это lifecycle baseline, не проверка БД/миграций.
class _SyncConnector extends MeshCoreConnector {
  bool connected = true;
  final frames = <List<int>>[];
  final held = <Completer<void>>[];
  Future<void> Function()? write;

  _SyncConnector() {
    setFrameWriterForTest((frame) {
      frames.add(List<int>.of(frame));
      return write?.call() ?? Future<void>.value();
    });
  }

  @override
  bool get isConnected => connected;

  Completer<void> hold() {
    final completion = Completer<void>();
    held.add(completion);
    return completion;
  }

  Completer<void> holdNextWrite() {
    final completion = hold();
    write = () {
      write = null;
      return completion.future;
    };
    return completion;
  }

  void endContacts() => handleFrameForTest([respCodeEndOfContacts]);

  void emptyChannel(int index) {
    final frame = Uint8List(50);
    frame[0] = respCodeChannelInfo;
    frame[1] = index;
    handleFrameForTest(frame);
  }
}

class _Result {
  _Result(Future<void> operation) {
    unawaited(operation.then<void>((_) {
      completed = true;
    }, onError: (Object value, StackTrace stack) {
      error = value;
      completed = true;
    }));
  }

  bool completed = false;
  Object? error;
}

Future<void> _withSync(
  WidgetTester tester,
  Future<void> Function(_SyncConnector c) check,
) async {
  final c = _SyncConnector();
  try {
    await check(c);
  } finally {
    c.connected = false;
    for (final completion in c.held) {
      if (!completion.isCompleted) {
        completion.complete();
      }
    }
    await tester.pump();
    c.resetSyncProgressForTest();
    c.dispose();
    await tester.pump(const Duration(seconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const timeout = Timeout(Duration(seconds: 30));
  late PathProviderPlatform savedPaths;

  setUpAll(() {
    // PrefsManager на desktop не должен читать/исправлять реальные файлы тестера.
    savedPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferencesDirectory();
  });

  tearDownAll(() {
    PathProviderPlatform.instance = savedPaths;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(() {
    PrefsManager.reset();
  });

  testWidgets('baseline: contact write completes before END and duplicates are ignored', (tester) async {
    await _withSync(tester, (c) async {
      await c.getContacts(preserveExisting: true);
      expect(c.frames, [[cmdGetContacts]]);
      expect(c.isLoadingContacts, isTrue);
      expect(c.hasLoadedContacts, isFalse);
      await c.getContacts(preserveExisting: true);
      expect(c.frames, [[cmdGetContacts]]);
      c.handleFrameForTest([respCodeContactsStart, 2, 0, 0, 0]);
      expect(c.contactSyncProgress, 0.0);
      c.handleFrameForTest([respCodeOk]);
      expect(c.isLoadingContacts, isTrue);
      c.endContacts();
      await tester.pump();
      expect(c.isLoadingContacts, isFalse);
      expect(c.hasLoadedContacts, isTrue);
      expect(c.contactSyncProgress, isNull);
      await tester.pump(const Duration(seconds: 11));
      expect(c.frames, [[cmdGetContacts]]);
    });
  }, timeout: timeout);

  testWidgets('baseline: contact START restarts the ten-second idle timeout', (tester) async {
    await _withSync(tester, (c) async {
      await c.getContacts(preserveExisting: true);
      await tester.pump(const Duration(seconds: 9));
      expect(c.isLoadingContacts, isTrue);
      c.handleFrameForTest([respCodeContactsStart, 2, 0, 0, 0]);
      await tester.pump(const Duration(seconds: 9));
      expect(c.isLoadingContacts, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(c.isLoadingContacts, isFalse);
      expect(c.hasLoadedContacts, isTrue);
      expect(c.frames, [[cmdGetContacts]]);
    });
  }, timeout: timeout);

  testWidgets('baseline: unsolicited contact START and END update loading without sending', (tester) async {
    await _withSync(tester, (c) async {
      c.handleFrameForTest([respCodeContactsStart, 2, 0, 0, 0]);
      expect(c.isLoadingContacts, isTrue);
      expect(c.contactSyncProgress, 0.0);
      expect(c.frames, isEmpty);
      c.endContacts();
      await tester.pump();
      expect(c.isLoadingContacts, isFalse);
      expect(c.hasLoadedContacts, isTrue);
      expect(c.frames, isEmpty);
    });
  }, timeout: timeout);

  testWidgets('baseline: contact write failure propagates and ends loading without retry', (tester) async {
    await _withSync(tester, (c) async {
      final write = c.holdNextWrite();
      final failure = StateError('synthetic contacts write failure');
      final result = _Result(c.getContacts(preserveExisting: true));
      await tester.pump();
      expect(c.isLoadingContacts, isTrue);
      write.completeError(failure);
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, same(failure));
      expect(c.isLoadingContacts, isFalse);
      expect(c.hasLoadedContacts, isFalse);
      await tester.pump(const Duration(seconds: 11));
      expect(c.frames, [[cmdGetContacts]]);
    });
  }, timeout: timeout);

  testWidgets('baseline: contact END may arrive before its physical write completes', (tester) async {
    await _withSync(tester, (c) async {
      final write = c.holdNextWrite();
      final result = _Result(c.getContacts(preserveExisting: true));
      await tester.pump();
      c.endContacts();
      await tester.pump();
      expect(result.completed, isFalse);
      expect(c.isLoadingContacts, isFalse);
      expect(c.hasLoadedContacts, isTrue);
      write.complete();
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(c.isLoadingContacts, isFalse);
      expect(c.frames, [[cmdGetContacts]]);
    });
  }, timeout: timeout);

  testWidgets('baseline: incremental contacts retain the filter bytes and unknown total', (tester) async {
    await _withSync(tester, (c) async {
      await c.getContacts(since: 0x01020304, preserveExisting: true);
      expect(c.frames, [[cmdGetContacts, 4, 3, 2, 1]]);
      c.handleFrameForTest([respCodeContactsStart, 2, 0, 0, 0]);
      expect(c.isLoadingContacts, isTrue);
      expect(c.contactSyncProgress, isNull);
      c.endContacts();
      await tester.pump();
      expect(c.isLoadingContacts, isFalse);
      expect(c.hasLoadedContacts, isTrue);
    });
  }, timeout: timeout);

  testWidgets('baseline: queued messages wait for contact sync to finish', (tester) async {
    await _withSync(tester, (c) async {
      await c.getContacts(preserveExisting: true);
      await c.syncQueuedMessages();
      expect(c.frames, [[cmdGetContacts]]);
      expect(c.isSyncingQueuedMessages, isFalse);
      c.endContacts();
      await tester.pump();
      expect(c.frames, [[cmdGetContacts], [cmdSyncNextMessage]]);
      expect(c.isLoadingContacts, isFalse);
      expect(c.isSyncingQueuedMessages, isTrue);
      c.handleFrameForTest([respCodeNoMoreMessages]);
    });
  }, timeout: timeout);

  testWidgets('baseline: empty channel slots advance before the original write completes', (tester) async {
    await _withSync(tester, (c) async {
      final write = c.holdNextWrite();
      final result = _Result(c.getChannels(maxChannels: 2));
      await tester.pump();
      expect(c.frames, [[cmdGetChannel, 0]]);
      c.emptyChannel(0);
      await tester.pump();
      expect(c.frames, [[cmdGetChannel, 0], [cmdGetChannel, 1]]);
      expect(c.isSyncingChannels, isTrue);
      expect(result.completed, isFalse);
      c.emptyChannel(1);
      await tester.pump();
      expect(c.isSyncingChannels, isFalse);
      expect(c.hasLoadedChannels, isTrue);
      expect(c.channels, isEmpty);
      write.complete();
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      await c.getChannels(maxChannels: 2);
      expect(c.frames, [[cmdGetChannel, 0], [cmdGetChannel, 1]]);
    });
  }, timeout: timeout);

  testWidgets('baseline: channel retries three times then keeps the unknown slot and advances', (tester) async {
    await _withSync(tester, (c) async {
      await c.getChannels(maxChannels: 2);
      for (var retry = 1; retry <= 3; retry++) {
        await tester.pump(const Duration(seconds: 2));
        expect(c.frames, List.generate(retry + 1, (_) => [cmdGetChannel, 0]));
        expect(c.isSyncingChannels, isTrue);
      }
      await tester.pump(const Duration(seconds: 2));
      expect(c.frames, [
        [cmdGetChannel, 0], [cmdGetChannel, 0],
        [cmdGetChannel, 0], [cmdGetChannel, 0],
        [cmdGetChannel, 1],
      ]);
      expect(c.unconfirmedChannelSlots, {0});
      c.emptyChannel(1);
      await tester.pump();
      expect(c.isSyncingChannels, isFalse);
      expect(c.hasLoadedChannels, isTrue);
      expect(c.unconfirmedChannelSlots, {0});
    });
  }, timeout: timeout);

  testWidgets('baseline: channel ERR_NOT_FOUND ends sync without querying later indexes', (tester) async {
    await _withSync(tester, (c) async {
      await c.getChannels(maxChannels: 4);
      c.handleFrameForTest([respCodeErr, 2]); // Existing ERR_NOT_FOUND.
      await tester.pump();
      expect(c.isSyncingChannels, isFalse);
      expect(c.hasLoadedChannels, isTrue);
      await tester.pump(const Duration(seconds: 9));
      expect(c.frames, [[cmdGetChannel, 0]]);
    });
  }, timeout: timeout);

  testWidgets('baseline: forced channel restart waits for the current response', (tester) async {
    await _withSync(tester, (c) async {
      await c.getChannels(maxChannels: 2);
      await c.getChannels(maxChannels: 1, force: true);
      expect(c.frames, [[cmdGetChannel, 0]]);
      c.emptyChannel(0);
      await tester.pump();
      expect(c.frames, [[cmdGetChannel, 0], [cmdGetChannel, 0]]);
      expect(c.isSyncingChannels, isTrue);
      c.emptyChannel(0);
      await tester.pump();
      expect(c.hasLoadedChannels, isTrue);
      expect(c.isSyncingChannels, isFalse);
      expect(c.frames, [[cmdGetChannel, 0], [cmdGetChannel, 0]]);
    });
  }, timeout: timeout);

  testWidgets('baseline: channel write failure stops sync and is caught by the queue', (tester) async {
    await _withSync(tester, (c) async {
      final write = c.holdNextWrite();
      final result = _Result(c.getChannels(maxChannels: 2));
      await tester.pump();
      write.completeError(StateError('synthetic channels write failure'));
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(c.isSyncingChannels, isFalse);
      expect(c.hasLoadedChannels, isFalse);
      await tester.pump(const Duration(seconds: 9));
      expect(c.frames, [[cmdGetChannel, 0]]);
    });
  }, timeout: timeout);

  testWidgets('baseline: finalization stays active without retries and delays queued messages', (tester) async {
    await _withSync(tester, (c) async {
      final finalization = c.hold();
      Map<int, String>? stampedSlots;
      c.setChannelImageStampForTest((slots) {
        stampedSlots = Map<int, String>.of(slots);
        return finalization.future;
      });
      await c.getChannels(maxChannels: 1);
      await c.syncQueuedMessages();
      c.emptyChannel(0);
      await tester.pump();
      expect(stampedSlots, isNotNull);
      expect(stampedSlots, isEmpty);
      expect(c.isSyncingChannels, isTrue);
      expect(c.hasLoadedChannels, isFalse);
      await tester.pump(const Duration(seconds: 6));
      expect(c.isSyncingChannels, isTrue);
      expect(c.frames, [[cmdGetChannel, 0]]);
      finalization.complete();
      await tester.pump();
      expect(c.isSyncingChannels, isFalse);
      expect(c.hasLoadedChannels, isTrue);
      expect(c.isSyncingQueuedMessages, isTrue);
      expect(c.frames, [[cmdGetChannel, 0], [cmdSyncNextMessage]]);
      c.handleFrameForTest([respCodeNoMoreMessages]);
    });
  }, timeout: timeout);

  testWidgets('baseline: sync reset cancels both contact and channel waits', (tester) async {
    await _withSync(tester, (c) async {
      await c.getContacts(preserveExisting: true);
      await c.getChannels(maxChannels: 2);
      expect(c.isLoadingContacts, isTrue);
      expect(c.isSyncingChannels, isTrue);
      c.resetSyncProgressForTest();
      await tester.pump(const Duration(seconds: 11));
      expect(c.isLoadingContacts, isFalse);
      expect(c.isSyncingChannels, isFalse);
      expect(c.frames, [[cmdGetContacts], [cmdGetChannel, 0]]);
    });
  }, timeout: timeout);

  testWidgets('baseline: disconnected contact and channel requests send nothing', (tester) async {
    await _withSync(tester, (c) async {
      c.connected = false;
      await c.getContacts(preserveExisting: true);
      await c.getChannels(maxChannels: 2);
      expect(c.frames, isEmpty);
      expect(c.isLoadingContacts, isFalse);
      expect(c.isSyncingChannels, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: unsolicited empty channel does not start a sync', (tester) async {
    await _withSync(tester, (c) async {
      c.emptyChannel(0);
      await tester.pump();
      expect(c.isSyncingChannels, isFalse);
      expect(c.hasLoadedChannels, isFalse);
      expect(c.channels, isEmpty);
      expect(c.frames, isEmpty);
    });
  }, timeout: timeout);
}
