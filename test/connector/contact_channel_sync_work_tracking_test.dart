import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
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
// Нода не привязана, слоты пустые: проверяем учёт lifecycle, не БД/миграции.
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

void _expectWork(
  _SyncConnector c, {
  int contacts = 0,
  int channels = 0,
  int writes = 0,
  int requests = 0,
}) {
  final snapshot = c.backgroundWorkSnapshot;
  expect(snapshot.countFor(BackgroundWorkKind.contactSync), contacts);
  expect(snapshot.countFor(BackgroundWorkKind.channelSync), channels);
  expect(snapshot.countFor(BackgroundWorkKind.transportWrite), writes);
  expect(snapshot.countFor(BackgroundWorkKind.queuedMessageRequest), requests);
  expect(snapshot.activeCount, contacts + channels + writes + requests);
  expect(snapshot.isBusy, snapshot.activeCount > 0);
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

  testWidgets('contacts stay held until END and duplicate START adds no lease', (tester) async {
    await _withSync(tester, (c) async {
      await c.getContacts(preserveExisting: true);
      _expectWork(c, contacts: 1);
      final revision = c.backgroundWorkSnapshot.revision;
      await c.getContacts(preserveExisting: true);
      c.handleFrameForTest([respCodeContactsStart, 2, 0, 0, 0]);
      c.handleFrameForTest([respCodeContactsStart, 2, 0, 0, 0]);
      c.handleFrameForTest([respCodeOk]);
      expect(c.backgroundWorkSnapshot.revision, revision);
      _expectWork(c, contacts: 1);
      c.endContacts();
      await tester.pump();
      _expectWork(c);
      expect(c.frames, [[cmdGetContacts]]);
    });
  }, timeout: timeout);

  testWidgets('unsolicited START remains held through the rearmed idle deadline', (tester) async {
    await _withSync(tester, (c) async {
      c.handleFrameForTest([respCodeContactsStart, 2, 0, 0, 0]);
      _expectWork(c, contacts: 1);
      await tester.pump(const Duration(seconds: 9));
      c.handleFrameForTest([respCodeContactsStart, 2, 0, 0, 0]);
      await tester.pump(const Duration(seconds: 9));
      _expectWork(c, contacts: 1);
      await tester.pump(const Duration(seconds: 1));
      _expectWork(c);
      expect(c.isLoadingContacts, isFalse);
      expect(c.frames, isEmpty);
    });
  }, timeout: timeout);

  testWidgets('early END leaves contact preparation and physical write held', (tester) async {
    await _withSync(tester, (c) async {
      final write = c.holdNextWrite();
      final result = _Result(c.getContacts(preserveExisting: true));
      await tester.pump();
      _expectWork(c, contacts: 2, writes: 1);
      c.endContacts();
      await tester.pump();
      _expectWork(c, contacts: 1, writes: 1);
      expect(result.completed, isFalse);
      write.complete();
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('contact write failure propagates and releases both contact holds', (tester) async {
    await _withSync(tester, (c) async {
      final write = c.holdNextWrite();
      final failure = StateError('synthetic contacts write failure');
      final result = _Result(c.getContacts(preserveExisting: true));
      await tester.pump();
      _expectWork(c, contacts: 2, writes: 1);
      write.completeError(failure);
      await tester.pump();
      expect(result.error, same(failure));
      _expectWork(c);
      await tester.pump(const Duration(seconds: 11));
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('contact reset and old write completion preserve a new phase', (tester) async {
    await _withSync(tester, (c) async {
      final write = c.holdNextWrite();
      final old = _Result(c.getContacts(preserveExisting: true));
      await tester.pump();
      c.resetSyncProgressForTest();
      _expectWork(c, contacts: 1, writes: 1);
      await c.getContacts(preserveExisting: true);
      _expectWork(c, contacts: 2, writes: 1);
      write.complete();
      await tester.pump();
      expect(old.completed, isTrue);
      _expectWork(c, contacts: 1);
      c.endContacts();
      await tester.pump();
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('contact write timeout leaves the original physical I/O held', (tester) async {
    await _withSync(tester, (c) async {
      final write = c.holdNextWrite();
      final result = _Result(c.getContacts(preserveExisting: true));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(result.error, isA<TimeoutException>());
      expect(c.isLoadingContacts, isFalse);
      _expectWork(c, writes: 1);
      write.complete();
      await tester.pump();
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('contacts hand off to queued response waiting without an idle callback', (tester) async {
    await _withSync(tester, (c) async {
      await c.getContacts(preserveExisting: true);
      await c.syncQueuedMessages();
      final atWrite = <BackgroundWorkSnapshot>[];
      c.write = () {
        atWrite.add(c.backgroundWorkSnapshot);
        return Future<void>.value();
      };
      c.endContacts();
      await tester.pump();
      _expectWork(c, requests: 1);
      expect(atWrite, hasLength(1));
      expect(atWrite.single.countFor(BackgroundWorkKind.contactSync), 1);
      expect(atWrite.single.countFor(BackgroundWorkKind.queuedMessageRequest), 1);
      c.handleFrameForTest([respCodeNoMoreMessages]);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('contact and channel waits are independent and reset releases both', (tester) async {
    await _withSync(tester, (c) async {
      await c.getContacts(preserveExisting: true);
      await c.getChannels(maxChannels: 2);
      _expectWork(c, contacts: 1, channels: 1);
      c.endContacts();
      await tester.pump();
      _expectWork(c, channels: 1);
      await c.getContacts(preserveExisting: true);
      _expectWork(c, contacts: 1, channels: 1);
      c.resetSyncProgressForTest();
      _expectWork(c);
      await tester.pump(const Duration(seconds: 11));
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('channel retries and the next slot retain the same logical hold', (tester) async {
    await _withSync(tester, (c) async {
      await c.getChannels(maxChannels: 2);
      _expectWork(c, channels: 1);
      for (var retry = 0; retry < 4; retry++) {
        await tester.pump(const Duration(seconds: 2));
        _expectWork(c, channels: 1);
      }
      expect(c.unconfirmedChannelSlots, {0});
      expect(c.frames.last, [cmdGetChannel, 1]);
      c.emptyChannel(1);
      await tester.pump();
      _expectWork(c);
      expect(c.hasLoadedChannels, isTrue);
      final revision = c.backgroundWorkSnapshot.revision;
      await c.getChannels(maxChannels: 2);
      expect(c.backgroundWorkSnapshot.revision, revision);
    });
  }, timeout: timeout);

  testWidgets('ERR_NOT_FOUND completes channels and releases its finalizer', (tester) async {
    await _withSync(tester, (c) async {
      await c.getChannels(maxChannels: 4);
      c.handleFrameForTest([respCodeErr, 2]);
      await tester.pump();
      _expectWork(c);
      await tester.pump(const Duration(seconds: 9));
      _expectWork(c);
      expect(c.frames, [[cmdGetChannel, 0]]);
    });
  }, timeout: timeout);

  testWidgets('forced restart replaces the channel phase without leaking a hold', (tester) async {
    await _withSync(tester, (c) async {
      await c.getChannels(maxChannels: 2);
      await c.getChannels(maxChannels: 1, force: true);
      _expectWork(c, channels: 1);
      c.emptyChannel(0);
      await tester.pump();
      _expectWork(c, channels: 1);
      expect(c.frames, [[cmdGetChannel, 0], [cmdGetChannel, 0]]);
      c.emptyChannel(0);
      await tester.pump();
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('channel write failure is still caught and releases logical work', (tester) async {
    await _withSync(tester, (c) async {
      final write = c.holdNextWrite();
      final result = _Result(c.getChannels(maxChannels: 2));
      await tester.pump();
      _expectWork(c, channels: 1, writes: 1);
      write.completeError(StateError('synthetic channels write failure'));
      await tester.pump();
      _expectWork(c);
      expect(result.completed, isTrue);
      expect(result.error, isNull);
    });
  }, timeout: timeout);

  testWidgets('early channel responses finish sync without finishing the writer', (tester) async {
    await _withSync(tester, (c) async {
      final write = c.holdNextWrite();
      final result = _Result(c.getChannels(maxChannels: 1));
      await tester.pump();
      c.emptyChannel(0);
      await tester.pump();
      _expectWork(c, writes: 1);
      expect(result.completed, isFalse);
      write.complete();
      await tester.pump();
      _expectWork(c);
      expect(result.completed, isTrue);
    });
  }, timeout: timeout);

  testWidgets('channel finalization remains held until queued handoff', (tester) async {
    await _withSync(tester, (c) async {
      final completion = c.hold();
      c.setChannelImageStampForTest((_) => completion.future);
      await c.getChannels(maxChannels: 1);
      await c.syncQueuedMessages();
      c.emptyChannel(0);
      await tester.pump();
      _expectWork(c, channels: 2);
      await tester.pump(const Duration(seconds: 6));
      _expectWork(c, channels: 2);
      final atWrite = <BackgroundWorkSnapshot>[];
      c.write = () {
        atWrite.add(c.backgroundWorkSnapshot);
        return Future<void>.value();
      };
      completion.complete();
      await tester.pump();
      _expectWork(c, requests: 1);
      expect(atWrite, hasLength(1));
      expect(atWrite.single.countFor(BackgroundWorkKind.channelSync), 2);
      expect(atWrite.single.countFor(BackgroundWorkKind.queuedMessageRequest), 1);
      c.handleFrameForTest([respCodeNoMoreMessages]);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('reset does not release the actual channel finalization', (tester) async {
    await _withSync(tester, (c) async {
      final completion = c.hold();
      c.setChannelImageStampForTest((_) => completion.future);
      await c.getChannels(maxChannels: 1);
      c.emptyChannel(0);
      await tester.pump();
      _expectWork(c, channels: 2);
      c.resetSyncProgressForTest();
      _expectWork(c, channels: 1);
      completion.complete();
      await tester.pump();
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('dispose retains finalization and late dispatch preserves its error', (tester) async {
    final c = _SyncConnector();
    final completion = c.hold();
    try {
      c.setChannelImageStampForTest((_) => completion.future);
      await c.getChannels(maxChannels: 1);
      c.emptyChannel(0);
      await tester.pump();
      _expectWork(c, channels: 2);
      c.connected = false;
      c.resetSyncProgressForTest();
      c.dispose();
      expect(c.backgroundWorkSnapshot.isClosed, isTrue);
      _expectWork(c, channels: 1);
      final revision = c.backgroundWorkSnapshot.revision;
      // Прежний dispatch отвергает новый кадр через уже закрытый RX stream.
      // Это не продолжение начатой до dispose асинхронной финализации.
      expect(() => c.emptyChannel(3), throwsStateError);
      await tester.pump();
      expect(c.backgroundWorkSnapshot.revision, revision);
      completion.complete();
      await tester.pump();
      _expectWork(c);
    } finally {
      if (!completion.isCompleted) {
        completion.complete();
      }
      if (!c.backgroundWorkSnapshot.isClosed) {
        c.connected = false;
        c.resetSyncProgressForTest();
        c.dispose();
      }
      await tester.pump(const Duration(seconds: 5));
    }
  }, timeout: timeout);

  testWidgets('dispose leaves the contact wait until its existing idle timeout', (tester) async {
    final c = _SyncConnector();
    try {
      await c.getContacts(preserveExisting: true);
      c.connected = false;
      c.dispose();
      expect(c.backgroundWorkSnapshot.isClosed, isTrue);
      _expectWork(c, contacts: 1);
      await tester.pump(const Duration(seconds: 9));
      _expectWork(c, contacts: 1);
      await tester.pump(const Duration(seconds: 1));
      _expectWork(c);
    } finally {
      c.connected = false;
      c.resetSyncProgressForTest();
      if (!c.backgroundWorkSnapshot.isClosed) {
        c.dispose();
      }
      await tester.pump(const Duration(seconds: 5));
    }
  }, timeout: timeout);

  testWidgets('disconnected calls and unsolicited empty channel leave no pending hold', (tester) async {
    await _withSync(tester, (c) async {
      c.connected = false;
      final revision = c.backgroundWorkSnapshot.revision;
      await c.getContacts(preserveExisting: true);
      await c.getChannels(maxChannels: 2);
      expect(c.backgroundWorkSnapshot.revision, revision);
      c.emptyChannel(0);
      await tester.pump();
      _expectWork(c);
      expect(c.frames, isEmpty);
    });
  }, timeout: timeout);
}

