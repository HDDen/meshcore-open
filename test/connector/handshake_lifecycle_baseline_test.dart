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

// Настоящие запросы/SELF_INFO dispatch/wait/retry и физический writer seam.
// Открытие транспорта, первый load БД и cold initial sync здесь не запускаются.
class _HandshakeConnector extends MeshCoreConnector {
  bool connected = true;
  final frames = <List<int>>[];
  final gates = <Completer<void>>[];
  Future<void> Function(int command)? beforeWrite;
  final key = Uint8List.fromList(List.generate(32, (i) => i + 1));

  _HandshakeConnector(MeshCoreTransportType transport) {
    setReconnectContextForTest(transport: transport, state: MeshCoreConnectionState.connected);
    setFrameWriterForTest((frame) {
      frames.add(List<int>.of(frame));
      return beforeWrite?.call(frame.first) ?? Future<void>.value();
    });
  }

  @override
  bool get isConnected => connected;

  List<int> get commands => frames.map((f) => f.first).toList();
  int count(int code) => commands.where((c) => c == code).length;

  Completer<void> holdFirstWrite() {
    final gate = Completer<void>();
    gates.add(gate);
    beforeWrite = (_) {
      beforeWrite = null;
      return gate.future;
    };
    return gate;
  }

  void selfInfo() {
    // Cached-path fixture: stores остаются без привязки к ноде.
    setCachedSelfInfoKeyForTest(key);
    final frame = Uint8List(68);
    frame[0] = respCodeSelfInfo;
    frame.setRange(4, 36, key);
    frame.setRange(58, 67, 'synthetic'.codeUnits);
    handleFrameForTest(frame);
  }

  void loseConnection() {
    connected = false;
    notifyListeners();
  }
}

class _Result<T> {
  _Result(Future<T> operation) {
    unawaited(operation.then<void>((result) {
      value = result;
      completed = true;
    }, onError: (Object failure, StackTrace stack) {
      error = failure;
      completed = true;
    }));
  }
  bool completed = false;
  T? value;
  Object? error;
}

Future<void> _withHandshake(WidgetTester tester,
    Future<void> Function(_HandshakeConnector c) check,
    {MeshCoreTransportType transport = MeshCoreTransportType.tcp}) async {
  final c = _HandshakeConnector(transport);
  try {
    await check(c);
  } finally {
    c.loseConnection();
    c.resetConnectionHandshakeForTest();
    for (final gate in c.gates) {
      if (!gate.isCompleted) gate.complete();
    }
    // Notify завершает локальные waiters; dispose не подменяет reset таймера.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 5));
    c.resetConnectionHandshakeForTest();
    c.dispose();
    await tester.pump();
  }
}

void main() {
  const timeout = Timeout(Duration(seconds: 30));
  late PathProviderPlatform savedPaths;
  setUpAll(() {
    savedPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferencesDirectory();
  });
  tearDownAll(() => PathProviderPlatform.instance = savedPaths);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  testWidgets('baseline: request returns after writes while SELF_INFO remains pending', (tester) async {
    await _withHandshake(tester, (c) async {
      final request = _Result(c.requestDeviceInfoForTest());
      await tester.pump();
      expect(request.completed, isTrue);
      expect(request.error, isNull);
      expect(c.commands, [cmdDeviceQuery, cmdAppStart, buildGetCustomVarsFrame().first, cmdGetBattAndStorage]);
      expect(c.awaitingSelfInfoForTest, isTrue);
      expect(c.selfInfoRetryActiveForTest, isTrue);
      expect(c.hasCompletedSelfInfoHandshake, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: duplicate request returns without joining the held writer', (tester) async {
    await _withHandshake(tester, (c) async {
      final gate = c.holdFirstWrite();
      final first = _Result(c.requestDeviceInfoForTest());
      await tester.pump();
      final duplicate = _Result(c.requestDeviceInfoForTest());
      await tester.pump();
      expect(first.completed, isFalse);
      expect(duplicate.completed, isTrue);
      expect(c.commands, [cmdDeviceQuery]);
      gate.complete();
      await tester.pump();
      expect(first.completed, isTrue);
      expect(first.error, isNull);
      expect(c.count(cmdAppStart), 1);
    });
  }, timeout: timeout);

  testWidgets('baseline: explicit refresh forces battery and uses its existing command order', (tester) async {
    await _withHandshake(tester, (c) async {
      await c.requestBatteryStatus();
      c.frames.clear();
      await c.refreshDeviceInfo();
      expect(c.commands, [cmdDeviceQuery, cmdAppStart, cmdGetBattAndStorage, buildGetCustomVarsFrame().first]);
      expect(c.awaitingSelfInfoForTest, isTrue);
    });
  }, timeout: timeout);

  testWidgets('baseline: initial request reuses the already requested battery', (tester) async {
    await _withHandshake(tester, (c) async {
      await c.requestBatteryStatus();
      c.frames.clear();
      await c.requestDeviceInfoForTest();
      expect(c.commands, [cmdDeviceQuery, cmdAppStart, buildGetCustomVarsFrame().first]);
    });
  }, timeout: timeout);

  for (final transport in [MeshCoreTransportType.tcp, MeshCoreTransportType.bluetooth, MeshCoreTransportType.usb]) {
    testWidgets('baseline: $transport common retry sends APP_START every 3500 ms', (tester) async {
      await _withHandshake(tester, (c) async {
        await c.requestDeviceInfoForTest();
        c.frames.clear();
        await tester.pump(const Duration(milliseconds: 3499));
        expect(c.commands, isEmpty);
        await tester.pump(const Duration(milliseconds: 1));
        expect(c.commands, [cmdAppStart]);
        await tester.pump(const Duration(milliseconds: 3500));
        expect(c.commands, [cmdAppStart, cmdAppStart]);
      }, transport: transport);
    }, timeout: timeout);
  }

  testWidgets('baseline: valid cached SELF_INFO completes flags and cancels retries', (tester) async {
    await _withHandshake(tester, (c) async {
      await c.requestDeviceInfoForTest();
      c.selfInfo();
      expect(c.awaitingSelfInfoForTest, isFalse);
      expect(c.selfInfoRetryActiveForTest, isFalse);
      expect(c.hasCompletedSelfInfoHandshake, isTrue);
      expect(c.isSessionReady, isFalse);
      final sent = c.frames.length;
      await tester.pump(const Duration(seconds: 7));
      expect(c.frames, hasLength(sent));
    });
  }, timeout: timeout);

  testWidgets('baseline: loss stops the retry at its next tick', (tester) async {
    await _withHandshake(tester, (c) async {
      await c.requestDeviceInfoForTest();
      c.frames.clear();
      c.loseConnection();
      await tester.pump(const Duration(milliseconds: 3500));
      expect(c.commands, isEmpty);
      expect(c.selfInfoRetryActiveForTest, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: handshake reset clears flags and allows the next request', (tester) async {
    await _withHandshake(tester, (c) async {
      await c.requestDeviceInfoForTest();
      c.resetConnectionHandshakeForTest();
      expect(c.awaitingSelfInfoForTest, isFalse);
      expect(c.selfInfoRetryActiveForTest, isFalse);
      await c.requestDeviceInfoForTest();
      expect(c.count(cmdAppStart), 2);
      expect(c.awaitingSelfInfoForTest, isTrue);
    });
  }, timeout: timeout);

  testWidgets('baseline: writer failure preserves the pending guard until reset', (tester) async {
    await _withHandshake(tester, (c) async {
      final error = StateError('synthetic handshake writer failure');
      c.beforeWrite = (_) async => throw error;
      final failed = _Result(c.requestDeviceInfoForTest());
      await tester.pump();
      expect(failed.error, same(error));
      expect(c.awaitingSelfInfoForTest, isTrue);
      expect(c.selfInfoRetryActiveForTest, isFalse);
      c.beforeWrite = null;
      await c.requestDeviceInfoForTest();
      expect(c.commands, [cmdDeviceQuery]);
      c.resetConnectionHandshakeForTest();
      await c.requestDeviceInfoForTest();
      expect(c.count(cmdDeviceQuery), 2);
    });
  }, timeout: timeout);

  testWidgets('baseline: early SELF_INFO does not abort remaining writes and late retry cancels without TX', (tester) async {
    await _withHandshake(tester, (c) async {
      final gate = c.holdFirstWrite();
      final request = _Result(c.requestDeviceInfoForTest());
      await tester.pump();
      c.selfInfo();
      expect(c.awaitingSelfInfoForTest, isFalse);
      gate.complete();
      await tester.pump();
      expect(request.completed, isTrue);
      expect(request.error, isNull);
      expect(c.commands, [cmdDeviceQuery, cmdAppStart, buildGetCustomVarsFrame().first, cmdGetBattAndStorage]);
      expect(c.selfInfoRetryActiveForTest, isTrue);
      await tester.pump(const Duration(milliseconds: 3500));
      expect(c.selfInfoRetryActiveForTest, isFalse);
      expect(c.count(cmdAppStart), 1);
    });
  }, timeout: timeout);

  testWidgets('baseline: missing SELF_INFO times out without resetting the pending handshake', (tester) async {
    await _withHandshake(tester, (c) async {
      await c.requestDeviceInfoForTest();
      final wait = _Result(c.waitForSelfInfoForTest(const Duration(seconds: 3)));
      await tester.pump(const Duration(milliseconds: 2999));
      expect(wait.completed, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      expect(wait.completed, isTrue);
      expect(wait.value, isFalse);
      expect(wait.error, isNull);
      expect(c.awaitingSelfInfoForTest, isTrue);
      expect(c.selfInfoRetryActiveForTest, isTrue);
    });
  }, timeout: timeout);

  testWidgets('baseline: SELF_INFO wait returns immediately if disconnected', (tester) async {
    await _withHandshake(tester, (c) async {
      c.connected = false;
      expect(await c.waitForSelfInfoForTest(const Duration(seconds: 3)), isFalse);
      expect(c.commands, isEmpty);
    });
  }, timeout: timeout);

  testWidgets('baseline: SELF_INFO wait accepts an already known key without another frame', (tester) async {
    await _withHandshake(tester, (c) async {
      c.selfInfo();
      expect(await c.waitForSelfInfoForTest(const Duration(seconds: 3)), isTrue);
      expect(c.commands, isEmpty);
    });
  }, timeout: timeout);

  testWidgets('baseline: pending SELF_INFO wait completes through existing UI notification', (tester) async {
    await _withHandshake(tester, (c) async {
      await c.requestDeviceInfoForTest();
      final wait = _Result(c.waitForSelfInfoForTest(const Duration(seconds: 3)));
      c.selfInfo();
      await tester.pump(const Duration(milliseconds: 50));
      expect(wait.completed, isTrue);
      expect(wait.value, isTrue);
      expect(wait.error, isNull);
    });
  }, timeout: timeout);

  testWidgets('baseline: loss completes the pending SELF_INFO listener with false', (tester) async {
    await _withHandshake(tester, (c) async {
      final wait = _Result(c.waitForSelfInfoForTest(const Duration(seconds: 3)));
      c.loseConnection();
      await tester.pump(const Duration(milliseconds: 50));
      expect(wait.completed, isTrue);
      expect(wait.value, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: location refresh times out and removes its waiter without failing', (tester) async {
    await _withHandshake(tester, (c) async {
      final refresh = _Result(c.refreshSelfLocation());
      await tester.pump();
      expect(c.commands, [cmdAppStart]);
      expect(c.selfLocationWaiterCountForTest, 1);
      await tester.pump(const Duration(seconds: 3));
      expect(refresh.completed, isTrue);
      expect(refresh.value, isNull);
      expect(refresh.error, isNull);
      expect(c.selfLocationWaiterCountForTest, 0);
    });
  }, timeout: timeout);

  testWidgets('baseline: malformed SELF_INFO still releases an existing location waiter', (tester) async {
    await _withHandshake(tester, (c) async {
      final refresh = _Result(c.refreshSelfLocation());
      await tester.pump();
      c.handleFrameForTest([respCodeSelfInfo]);
      await tester.pump();
      expect(refresh.completed, isTrue);
      expect(refresh.error, isNull);
      expect(refresh.value, isNull);
      expect(c.selfLocationWaiterCountForTest, 0);
    });
  }, timeout: timeout);

  testWidgets('baseline: location refresh catches writer failure and removes its waiter', (tester) async {
    await _withHandshake(tester, (c) async {
      c.beforeWrite = (_) async => throw StateError('synthetic location writer failure');
      final refresh = _Result(c.refreshSelfLocation());
      await tester.pump();
      expect(refresh.completed, isTrue);
      expect(refresh.error, isNull);
      expect(c.selfLocationWaiterCountForTest, 0);
    });
  }, timeout: timeout);

  testWidgets('baseline: contact sync defers APP_START until END while other query writes continue', (tester) async {
    await _withHandshake(tester, (c) async {
      await c.getContacts();
      await c.requestDeviceInfoForTest();
      expect(c.count(cmdAppStart), 0);
      expect(c.count(cmdDeviceQuery), 1);
      expect(c.count(cmdGetBattAndStorage), 1);
      c.handleFrameForTest([respCodeEndOfContacts]);
      await tester.pump();
      expect(c.count(cmdAppStart), 1);
      expect(c.awaitingSelfInfoForTest, isTrue);
    });
  }, timeout: timeout);

  testWidgets('baseline: reset and transport loss do not finish an already running writer', (tester) async {
    await _withHandshake(tester, (c) async {
      final gate = c.holdFirstWrite();
      final request = _Result(c.requestDeviceInfoForTest());
      await tester.pump();
      c.resetConnectionHandshakeForTest();
      c.loseConnection();
      await tester.pump();
      expect(request.completed, isFalse);
      expect(c.awaitingSelfInfoForTest, isFalse);
      gate.complete();
      await tester.pump();
      expect(request.completed, isTrue);
      expect(request.error, isNotNull);
      expect(c.commands, [cmdDeviceQuery]);
      expect(c.selfInfoRetryActiveForTest, isFalse);
    });
  }, timeout: timeout);
}
