import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_connector_tcp.dart';
import 'package:meshcore_open/connector/meshcore_connector_usb.dart';
import 'package:meshcore_open/services/image_codec_service.dart';
import 'package:meshcore_open/services/translation_service.dart';
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

// Только границы close/release: нет UsbSerialService/flserial, сокетов,
// физических BLE-устройств или настоящих моделей.
class _Usb extends Fake implements MeshCoreUsbManager {
  _Usb(this.events);
  final List<String> events;
  Future<void>? closing;
  int closes = 0;

  @override
  Future<void> disconnect() async {
    closes++;
    events.add('usb');
    await closing;
  }

  @override
  void dispose() {}
}

class _Tcp extends Fake implements MeshCoreTcpConnector {
  _Tcp(this.events);
  final List<String> events;
  Future<void>? closing;
  int closes = 0;

  @override
  Future<void> disconnect() async {
    closes++;
    events.add('tcp');
    await closing;
  }

  @override
  void dispose() {}
}

class _Translation extends Fake implements TranslationService {
  _Translation(this.events);
  final List<String> events;
  Future<void>? releasing;
  int releases = 0;

  @override
  Future<void> releaseModel() async {
    releases++;
    events.add('translation');
    await releasing;
  }
}

class _Image extends Fake implements ImageCodecService {
  _Image(this.events);
  final List<String> events;
  Future<void>? releasing;
  int cancellations = 0;
  int releases = 0;

  @override
  void cancelCodecJob() {
    cancellations++;
    events.add('image cancel');
  }

  @override
  Future<void> releaseModel() async {
    releases++;
    events.add('image release');
    await releasing;
  }
}

class _Session {
  _Session() {
    usb = _Usb(events);
    tcp = _Tcp(events);
    translation = _Translation(events);
    image = _Image(events);
    connector = MeshCoreConnector(usbManager: usb, tcpConnector: tcp);
    connector.attachDisconnectServicesForTest(
      translationService: translation,
      imageCodecService: image,
    );
    connected();
  }

  final events = <String>[];
  final gates = <Completer<void>>[];
  late final _Usb usb;
  late final _Tcp tcp;
  late final _Translation translation;
  late final _Image image;
  late final MeshCoreConnector connector;

  void connected([MeshCoreTransportType transport = MeshCoreTransportType.tcp]) {
    connector.setReconnectContextForTest(
      transport: transport,
      tcpHost: 'synthetic.invalid',
      tcpPort: 5000,
      state: MeshCoreConnectionState.connected,
    );
  }

  Completer<void> gate() {
    final result = Completer<void>();
    gates.add(result);
    return result;
  }
}

class _Result<T> {
  _Result(Future<T> operation) {
    unawaited(operation.then<void>((value) {
      completed = true;
    }, onError: (Object failure, StackTrace stack) {
      error = failure;
      completed = true;
    }));
  }
  bool completed = false;
  Object? error;
}

Future<void> _withSession(
  WidgetTester tester,
  Future<void> Function(_Session) check,
) async {
  final s = _Session();
  try {
    await check(s);
  } finally {
    s.usb.closing = null;
    s.tcp.closing = null;
    s.translation.releasing = null;
    s.image.releasing = null;
    for (final gate in s.gates) {
      if (!gate.isCompleted) gate.complete();
    }
    await tester.pump();
    if (!s.connector.backgroundWorkSnapshot.isClosed) await s.connector.disconnect(manual: true);
    await tester.pump(const Duration(milliseconds: 60));
    if (!s.connector.backgroundWorkSnapshot.isClosed) s.connector.dispose();
    await tester.pump();
  }
}

void _expectWork(_Session s, int count) {
  final snapshot = s.connector.backgroundWorkSnapshot;
  expect(snapshot.countFor(BackgroundWorkKind.transportTeardown), count);
  expect(snapshot.activeCount, count);
  expect(snapshot.isBusy, count > 0);
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

  for (final boundary in ['usb', 'tcp']) {
    testWidgets('$boundary close holds the original teardown without an outer deadline', (tester) async {
      await _withSession(tester, (s) async {
        final gate = s.gate();
        if (boundary == 'usb') {
          s.usb.closing = gate.future;
        } else {
          s.tcp.closing = gate.future;
        }
        final close = _Result(s.connector.disconnect());
        await tester.pump();
        await tester.pump(const Duration(seconds: 8));
        expect(close.completed, isFalse);
        _expectWork(s, 1);
        gate.complete();
        await tester.pump();
        expect(close.completed, isTrue);
        expect(close.error, isNull);
        _expectWork(s, 0);
      });
    }, timeout: timeout);
  }

  testWidgets('parallel callers and a manual join keep one teardown lease', (tester) async {
    await _withSession(tester, (s) async {
      final gate = s.gate();
      s.usb.closing = gate.future;
      final automatic = _Result(s.connector.disconnect(manual: false));
      final manual = _Result(s.connector.disconnect(manual: true));
      final third = _Result(s.connector.disconnect());
      await tester.pump();
      _expectWork(s, 1);
      expect(s.usb.closes, 1);
      gate.complete();
      await tester.pump();
      expect([automatic.completed, manual.completed, third.completed], everyElement(isTrue));
      expect(s.connector.wasManuallyDisconnected, isTrue);
      expect(s.connector.isAutoReconnectScheduled, isFalse);
      _expectWork(s, 0);
    });
  }, timeout: timeout);

  testWidgets('automatic join preserves the manual teardown and its one lease', (tester) async {
    await _withSession(tester, (s) async {
      final gate = s.gate();
      s.tcp.closing = gate.future;
      final manual = _Result(s.connector.disconnect());
      final automatic = _Result(s.connector.disconnect(manual: false));
      await tester.pump();
      _expectWork(s, 1);
      gate.complete();
      await tester.pump();
      expect(manual.completed, isTrue);
      expect(automatic.completed, isTrue);
      expect(s.connector.wasManuallyDisconnected, isTrue);
      _expectWork(s, 0);
    });
  }, timeout: timeout);

  testWidgets('caller timeout does not release the actual teardown', (tester) async {
    await _withSession(tester, (s) async {
      final gate = s.gate();
      s.usb.closing = gate.future;
      final caller = _Result(s.connector.disconnect().timeout(const Duration(milliseconds: 1)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(caller.error, isA<TimeoutException>());
      _expectWork(s, 1);
      final joined = _Result(s.connector.disconnect());
      gate.complete();
      await tester.pump();
      expect(joined.completed, isTrue);
      _expectWork(s, 0);
    });
  }, timeout: timeout);

  for (final boundary in ['usb', 'tcp']) {
    testWidgets('$boundary close error releases only when the original Future fails', (tester) async {
      await _withSession(tester, (s) async {
        final gate = s.gate();
        final error = StateError('synthetic close failure');
        if (boundary == 'usb') {
          s.usb.closing = gate.future;
        } else {
          s.tcp.closing = gate.future;
        }
        final first = _Result(s.connector.disconnect());
        final joined = _Result(s.connector.disconnect());
        await tester.pump();
        _expectWork(s, 1);
        gate.completeError(error);
        await tester.pump();
        expect(first.error, same(error));
        expect(joined.error, same(error));
        expect(s.connector.state, MeshCoreConnectionState.disconnecting);
        _expectWork(s, 0);
        s.usb.closing = null;
        s.tcp.closing = null;
        await s.connector.disconnect();
        _expectWork(s, 0);
      });
    }, timeout: timeout);
  }

  for (final model in ['translation', 'image']) {
    testWidgets('$model release has a lease independent of outer teardown', (tester) async {
      await _withSession(tester, (s) async {
        final gate = s.gate();
        if (model == 'translation') {
          s.translation.releasing = gate.future;
        } else {
          s.image.releasing = gate.future;
        }
        final close = _Result(s.connector.disconnect());
        await tester.pump();
        expect(close.completed, isFalse);
        _expectWork(s, 2);
        gate.complete();
        await tester.pump();
        expect(close.completed, isTrue);
        expect(close.error, isNull);
        _expectWork(s, 0);
      });
    }, timeout: timeout);
  }

  for (final model in ['translation', 'image']) {
    testWidgets('$model timeout leaves actual cleanup counted until late completion', (tester) async {
      await _withSession(tester, (s) async {
        final gate = s.gate();
        if (model == 'translation') {
          s.translation.releasing = gate.future;
        } else {
          s.image.releasing = gate.future;
        }
        final close = _Result(s.connector.disconnect());
        await tester.pump();
        _expectWork(s, 2);
        await tester.pump(const Duration(seconds: 3));
        expect(close.completed, isTrue);
        expect(close.error, isNull);
        expect(s.connector.state, MeshCoreConnectionState.disconnected);
        _expectWork(s, 1);
        gate.complete();
        await tester.pump();
        _expectWork(s, 0);
      });
    }, timeout: timeout);
  }

  testWidgets('two independent timeout operations survive the completed teardown', (tester) async {
    await _withSession(tester, (s) async {
      final translation = s.gate();
      final image = s.gate();
      s.translation.releasing = translation.future;
      s.image.releasing = image.future;
      final close = _Result(s.connector.disconnect());
      await tester.pump();
      _expectWork(s, 2);
      await tester.pump(const Duration(seconds: 3));
      _expectWork(s, 3);
      await tester.pump(const Duration(seconds: 3));
      expect(close.completed, isTrue);
      _expectWork(s, 2);
      translation.complete();
      await tester.pump();
      _expectWork(s, 1);
      image.complete();
      await tester.pump();
      _expectWork(s, 0);
    });
  }, timeout: timeout);

  testWidgets('late old release error drains its lease without ending the new teardown', (tester) async {
    await _withSession(tester, (s) async {
      final old = s.gate();
      s.translation.releasing = old.future;
      final first = _Result(s.connector.disconnect());
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(first.completed, isTrue);
      _expectWork(s, 1);
      s.translation.releasing = null;
      final current = s.gate();
      s.usb.closing = current.future;
      final second = _Result(s.connector.disconnect());
      await tester.pump();
      _expectWork(s, 2);
      old.completeError(StateError('synthetic old release failure'));
      await tester.pump();
      expect(second.completed, isFalse);
      expect(s.image.releases, 1);
      _expectWork(s, 1);
      current.complete();
      await tester.pump();
      expect(second.completed, isTrue);
      expect(second.error, isNull);
      _expectWork(s, 0);
    });
  }, timeout: timeout);

  testWidgets('dispose retains an old timed out cleanup until its actual end', (tester) async {
    await _withSession(tester, (s) async {
      final old = s.gate();
      s.image.releasing = old.future;
      final close = _Result(s.connector.disconnect());
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(close.completed, isTrue);
      s.connector.dispose();
      expect(s.connector.backgroundWorkSnapshot.isClosed, isTrue);
      _expectWork(s, 1);
      old.complete();
      await tester.pump();
      _expectWork(s, 0);
    });
  }, timeout: timeout);

  testWidgets('native iOS reply timeout leaves its actual operation counted', (tester) async {
    const channel = MethodChannel('mco_service/ios_ble_central');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    try {
      await _withSession(tester, (s) async {
        final reply = s.gate();
        var calls = 0;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls++;
          await reply.future;
          return null;
        });
        s.connector.attachDisconnectServicesForTest(
          translationService: s.translation,
          imageCodecService: s.image,
          iosNativeBleCentral: true,
        );
        final close = _Result(s.connector.disconnect());
        await tester.pump();
        expect(calls, 1);
        _expectWork(s, 2);
        await tester.pump(const Duration(seconds: 3));
        expect(close.completed, isTrue);
        _expectWork(s, 1);
        reply.complete();
        await tester.pump();
        expect(calls, 1);
        _expectWork(s, 0);
      });
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
    }
  }, timeout: timeout);

  testWidgets('successful automatic teardown drains while reconnect wait stays passive', (tester) async {
    await _withSession(tester, (s) async {
      await s.connector.disconnect(manual: false);
      expect(s.connector.isAutoReconnectScheduled, isTrue);
      _expectWork(s, 0);
    });
  }, timeout: timeout);
}
