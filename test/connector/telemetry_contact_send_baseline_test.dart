import 'dart:async';
import 'dart:typed_data' show Endian;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/connector/pending_command_replies.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/storage/contact_region_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Baseline before the map gains one-shot telemetry. Real command locking,
// sendFrame and ACK dispatch; only the physical writer and region lookup are
// scripted. No SQLite, map tiles, BLE plugin or real preferences directory.
class _NoDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async =>
      throw MissingPluginException('Synthetic contact telemetry baseline');
}

class _Radio extends MeshCoreConnector {
  bool connected = true;
  final writes = <List<int>>[];
  final regions = <String, String>{};

  _Radio() {
    setFrameWriterForTest((frame) async {
      writes.add(List<int>.of(frame));
    });
  }

  @override
  bool get isConnected => connected;

  @override
  String getContactRegion(String contactKeyHex) => regions[contactKeyHex] ?? '';

  void sent(int tag) {
    final bytes = ByteData(10)
      ..setUint8(0, respCodeSent)
      ..setUint32(2, tag, Endian.little)
      ..setUint32(6, 5000, Endian.little);
    handleFrameForTest(bytes.buffer.asUint8List());
  }
}

class _Outcome {
  _Outcome(Future<void> operation) {
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

Contact _contact(int seed, int type) => Contact(
  publicKey: Uint8List.fromList(List<int>.generate(32, (i) => seed + i)),
  name: 'Synthetic contact $seed',
  type: type,
  pathLength: -1,
  path: Uint8List(0),
  lastSeen: DateTime.utc(2026, 1, 1),
);

Future<void> _withRadio(
  WidgetTester tester,
  Future<void> Function(_Radio radio) check,
) async {
  final radio = _Radio();
  try {
    await check(radio);
  } finally {
    // Release an outstanding scope wait even if an assertion failed. The
    // Outcome observers already own failures, so teardown cannot mask them.
    radio.connected = false;
    if (radio.pendingCommandReplyCountForTest > 0) {
      radio.handleFrameForTest([respCodeErr, errCodeUnsupportedCmd]);
    }
    await tester.pump();
    radio.dispose();
    await tester.pump(const Duration(seconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PathProviderPlatform originalPaths;
  final chat = _contact(0x20, advTypeChat);
  final sensor = _contact(0x60, advTypeSensor);

  setUpAll(() {
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoDirectory();
  });
  tearDownAll(() {
    PathProviderPlatform.instance = originalPaths;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  for (final target in [chat, sensor]) {
    final frame = target.type == advTypeChat
        ? buildSendTelemetryReq(target.publicKey)
        : buildSendBinaryReq(target.publicKey, payload: buildTelemetryBinaryPayload());
    testWidgets('U11a2 baseline: default-scope telemetry preserves frame type=${target.type}', (tester) async {
      await _withRadio(tester, (radio) async {
        final result = _Outcome(radio.sendContactFrame(target, frame, useFlood: true));
        await tester.pump();
        expect(radio.writes, [frame]);
        radio.sent(1);
        await tester.pump();
        expect(result.completed, isTrue);
        expect(result.error, isNull);
      });
    });
  }

  testWidgets('U11a2 baseline: scope OK precedes telemetry and SENT precedes scope reset', (tester) async {
    await _withRadio(tester, (radio) async {
      radio.regions[chat.publicKeyHex] = 'test-region';
      final frame = buildSendTelemetryReq(chat.publicKey);
      final result = _Outcome(radio.sendContactFrame(chat, frame, useFlood: true));
      await tester.pump();
      expect(radio.writes, [buildSetFloodScopeFrame('test-region')]);
      expect(result.completed, isFalse);
      radio.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(radio.writes, [buildSetFloodScopeFrame('test-region'), frame]);
      expect(result.completed, isFalse);
      radio.sent(2);
      await tester.pump();
      expect(radio.writes, [
        buildSetFloodScopeFrame('test-region'), frame, buildSetFloodScopeFrame(''),
      ]);
      expect(result.completed, isFalse);
      radio.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
    });
  });

  testWidgets('U11a2 baseline: direct telemetry does not open a flood region', (tester) async {
    await _withRadio(tester, (radio) async {
      radio.regions[chat.publicKeyHex] = 'test-region';
      final frame = buildSendTelemetryReq(chat.publicKey);
      final result = _Outcome(radio.sendContactFrame(chat, frame, useFlood: false));
      await tester.pump();
      radio.sent(3);
      await tester.pump();
      expect(radio.writes, [frame]);
      expect(result.completed, isTrue);
      expect(result.error, isNull);
    });
  });

  testWidgets('U11a2 baseline: unsupported unscoped mode retains the existing fallback', (tester) async {
    await _withRadio(tester, (radio) async {
      radio.regions[chat.publicKeyHex] = ContactRegionStore.unscoped;
      final frame = buildSendTelemetryReq(chat.publicKey);
      final first = _Outcome(radio.sendContactFrame(chat, frame, useFlood: true));
      await tester.pump();
      expect(radio.writes, [buildSetFloodUnscopedFrame()]);
      // Older firmware may refuse the flag; the fork then sends under the
      // default scope and remembers the limitation for this connection.
      radio.handleFrameForTest([respCodeErr, errCodeUnsupportedCmd]);
      await tester.pump();
      expect(radio.writes.last, frame);
      radio.sent(7);
      await tester.pump();
      expect(radio.writes.last, buildSetFloodScopeFrame(''));
      radio.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(first.completed, isTrue);
      expect(first.error, isNull);
      radio.writes.clear();

      final second = _Outcome(radio.sendContactFrame(chat, frame, useFlood: true));
      await tester.pump();
      expect(radio.writes, [frame]);
      radio.sent(8);
      await tester.pump();
      radio.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(second.completed, isTrue);
      expect(second.error, isNull);
      expect(radio.writes, [frame, buildSetFloodScopeFrame('')]);
    });
  });

  testWidgets('U11a2 baseline: refused scope sends no telemetry and releases the lock', (tester) async {
    await _withRadio(tester, (radio) async {
      radio.regions[chat.publicKeyHex] = 'test-region';
      final frame = buildSendTelemetryReq(chat.publicKey);
      final result = _Outcome(radio.sendContactFrame(chat, frame, useFlood: true));
      await tester.pump();
      radio.handleFrameForTest([respCodeErr, errCodeUnsupportedCmd]);
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isA<CommandFailedException>());
      expect(radio.writes, [buildSetFloodScopeFrame('test-region')]);
      final next = _Outcome(radio.sendContactFrame(chat, frame, useFlood: false));
      await tester.pump();
      radio.sent(4);
      await tester.pump();
      expect(next.completed, isTrue);
      expect(next.error, isNull);
      expect(radio.writes, [buildSetFloodScopeFrame('test-region'), frame]);
    });
  });

  testWidgets('U11a2: send hook runs after region setup and before the payload writer', (tester) async {
    await _withRadio(tester, (radio) async {
      radio.regions[chat.publicKeyHex] = 'test-region';
      final frame = buildSendTelemetryReq(chat.publicKey);
      var armed = 0;
      List<List<int>>? writesWhenArmed;
      final result = _Outcome(radio.sendContactFrame(chat, frame,
        useFlood: true,
        onSending: () {
          // A Flutter expect here runs inside tester.pump's async guard.
          // Capture evidence; assert it after the guarded pump has returned.
          writesWhenArmed = [for (final bytes in radio.writes) List<int>.of(bytes)];
          armed++;
        },
      ));
      await tester.pump();
      expect(armed, 0);
      radio.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(result.error, isNull);
      expect(armed, 1);
      expect(writesWhenArmed, [buildSetFloodScopeFrame('test-region')]);
      radio.sent(9);
      await tester.pump();
      radio.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(armed, 1);
    });
  });

  testWidgets('U11a2: cancellation during region setup skips payload and still resets scope', (tester) async {
    await _withRadio(tester, (radio) async {
      radio.regions[chat.publicKeyHex] = 'test-region';
      var current = true;
      var armed = false;
      final result = _Outcome(radio.sendContactFrame(chat, buildSendTelemetryReq(chat.publicKey),
        useFlood: true, canSend: () => current, onSending: () => armed = true,
      ));
      await tester.pump();
      current = false;
      radio.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(radio.writes, [
        buildSetFloodScopeFrame('test-region'), buildSetFloodScopeFrame(''),
      ]);
      expect(armed, isFalse);
      radio.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
    });
  });

  testWidgets('U11a2: cancelled queued request never opens its region', (tester) async {
    await _withRadio(tester, (radio) async {
      radio.regions[chat.publicKeyHex] = 'first-region';
      radio.regions[sensor.publicKeyHex] = 'second-region';
      var current = true;
      var armed = false;
      final frame = buildSendTelemetryReq(chat.publicKey);
      final first = _Outcome(radio.sendContactFrame(chat, frame, useFlood: true));
      final second = _Outcome(radio.sendContactFrame(sensor,
        buildSendBinaryReq(sensor.publicKey, payload: buildTelemetryBinaryPayload()),
        useFlood: true, canSend: () => current, onSending: () => armed = true,
      ));
      await tester.pump();
      current = false;
      radio.handleFrameForTest([respCodeOk]);
      await tester.pump();
      radio.sent(10);
      await tester.pump();
      radio.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(first.completed, isTrue);
      expect(first.error, isNull);
      expect(second.completed, isTrue);
      expect(second.error, isNull);
      expect(armed, isFalse);
      expect(radio.writes, [
        buildSetFloodScopeFrame('first-region'), frame, buildSetFloodScopeFrame(''),
      ]);
    });
  });

  testWidgets('U11a2 baseline: a second request waits until the first region is reset', (tester) async {
    await _withRadio(tester, (radio) async {
      radio.regions[chat.publicKeyHex] = 'first-region';
      radio.regions[sensor.publicKeyHex] = 'second-region';
      final chatFrame = buildSendTelemetryReq(chat.publicKey);
      final sensorFrame = buildSendBinaryReq(sensor.publicKey, payload: buildTelemetryBinaryPayload());
      final first = _Outcome(radio.sendContactFrame(chat, chatFrame, useFlood: true));
      final second = _Outcome(radio.sendContactFrame(sensor, sensorFrame, useFlood: true));
      await tester.pump();
      expect(radio.writes, [buildSetFloodScopeFrame('first-region')]);
      radio.handleFrameForTest([respCodeOk]);
      await tester.pump();
      radio.sent(5);
      await tester.pump();
      expect(radio.writes, [
        buildSetFloodScopeFrame('first-region'), chatFrame, buildSetFloodScopeFrame(''),
      ]);
      expect(second.completed, isFalse);
      radio.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(first.completed, isTrue);
      expect(first.error, isNull);
      expect(radio.writes.last, buildSetFloodScopeFrame('second-region'));
      radio.handleFrameForTest([respCodeOk]);
      await tester.pump();
      radio.sent(6);
      await tester.pump();
      radio.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(second.completed, isTrue);
      expect(second.error, isNull);
      expect(radio.writes, [
        buildSetFloodScopeFrame('first-region'), chatFrame, buildSetFloodScopeFrame(''),
        buildSetFloodScopeFrame('second-region'), sensorFrame, buildSetFloodScopeFrame(''),
      ]);
    });
  });
}
