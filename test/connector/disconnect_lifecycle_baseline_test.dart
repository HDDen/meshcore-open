import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_connector_tcp.dart';
import 'package:meshcore_open/connector/meshcore_connector_usb.dart';
import 'package:meshcore_open/services/image_codec_service.dart';
import 'package:meshcore_open/services/translation_service.dart';
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
    await s.connector.disconnect(manual: true);
    await tester.pump(const Duration(milliseconds: 60));
    s.connector.dispose();
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

  for (final transport in [
    MeshCoreTransportType.bluetooth,
    MeshCoreTransportType.usb,
    MeshCoreTransportType.tcp,
  ]) {
    testWidgets('baseline: $transport manual disconnect keeps cleanup order', (tester) async {
      await _withSession(tester, (s) async {
        s.connected(transport);
        await s.connector.disconnect(manual: true);
        expect(s.events, ['usb', 'tcp', 'translation', 'image cancel', 'image release']);
        expect(s.connector.state, MeshCoreConnectionState.disconnected);
        expect(s.connector.wasManuallyDisconnected, isTrue);
        expect(s.connector.shouldSuppressAutoconnect(transport), isTrue);
        expect(s.connector.isAutoReconnectScheduled, isFalse);
      });
    }, timeout: timeout);
  }

  testWidgets('baseline: pending USB close has no outer cleanup timeout', (tester) async {
    await _withSession(tester, (s) async {
      final gate = s.gate();
      s.usb.closing = gate.future;
      final close = _Result(s.connector.disconnect());
      await tester.pump(const Duration(seconds: 8));
      expect(close.completed, isFalse);
      expect(s.connector.state, MeshCoreConnectionState.disconnecting);
      expect(s.events, ['usb']);
      gate.complete();
      await tester.pump();
      expect(close.completed, isTrue);
      expect(close.error, isNull);
    });
  }, timeout: timeout);

  testWidgets('baseline: connector waits for the TCP manager Future', (tester) async {
    await _withSession(tester, (s) async {
      final gate = s.gate();
      s.tcp.closing = gate.future;
      final close = _Result(s.connector.disconnect());
      await tester.pump();
      await tester.pump(const Duration(seconds: 8));
      expect(close.completed, isFalse);
      expect(s.events, ['usb', 'tcp']);
      gate.complete();
      await tester.pump();
      expect(close.completed, isTrue);
      expect(close.error, isNull);
    });
  }, timeout: timeout);

  testWidgets('baseline: parallel manual requests join one physical teardown', (tester) async {
    await _withSession(tester, (s) async {
      final gate = s.gate();
      s.usb.closing = gate.future;
      final first = _Result(s.connector.disconnect());
      final second = _Result(s.connector.disconnect());
      final third = _Result(s.connector.disconnect());
      await tester.pump();
      expect(s.usb.closes, 1);
      expect(second.completed, isFalse);
      expect(third.completed, isFalse);
      gate.complete();
      await tester.pump();
      expect([first.completed, second.completed, third.completed], everyElement(isTrue));
      expect(s.tcp.closes, 1);
      expect(s.image.releases, 1);
    });
  }, timeout: timeout);

  testWidgets('baseline: a manual join overrides an automatic disconnect', (tester) async {
    await _withSession(tester, (s) async {
      final gate = s.gate();
      s.usb.closing = gate.future;
      final automatic = _Result(s.connector.disconnect(manual: false));
      await tester.pump();
      final manual = _Result(s.connector.disconnect(manual: true));
      expect(s.connector.wasManuallyDisconnected, isTrue);
      expect(s.connector.shouldSuppressAutoconnect(MeshCoreTransportType.tcp), isTrue);
      gate.complete();
      await tester.pump();
      expect(automatic.completed, isTrue);
      expect(manual.completed, isTrue);
      expect(s.usb.closes, 1);
      expect(s.connector.isAutoReconnectScheduled, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: an automatic join cannot downgrade manual disconnect', (tester) async {
    await _withSession(tester, (s) async {
      final gate = s.gate();
      s.usb.closing = gate.future;
      final manual = _Result(s.connector.disconnect(manual: true));
      final automatic = _Result(s.connector.disconnect(manual: false));
      await tester.pump();
      gate.complete();
      await tester.pump();
      expect(manual.completed, isTrue);
      expect(automatic.completed, isTrue);
      expect(s.connector.wasManuallyDisconnected, isTrue);
      expect(s.connector.isAutoReconnectScheduled, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: eligible automatic TCP disconnect schedules reconnect at the tail', (tester) async {
    await _withSession(tester, (s) async {
      await s.connector.disconnect(manual: false);
      expect(s.connector.state, MeshCoreConnectionState.disconnected);
      expect(s.connector.activeTransport, MeshCoreTransportType.tcp);
      expect(s.connector.wasManuallyDisconnected, isFalse);
      expect(s.connector.isAutoReconnectScheduled, isTrue);
    });
  }, timeout: timeout);

  testWidgets('baseline: automatic USB disconnect does not schedule reconnect', (tester) async {
    await _withSession(tester, (s) async {
      s.connected(MeshCoreTransportType.usb);
      await s.connector.disconnect(manual: false);
      expect(s.connector.state, MeshCoreConnectionState.disconnected);
      expect(s.connector.isAutoReconnectScheduled, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: USB close error propagates and a later call starts a new teardown', (tester) async {
    await _withSession(tester, (s) async {
      final gate = s.gate();
      final error = StateError('synthetic USB close error');
      s.usb.closing = gate.future;
      final close = _Result(s.connector.disconnect());
      await tester.pump();
      gate.completeError(error);
      await tester.pump();
      expect(close.error, same(error));
      expect(s.connector.state, MeshCoreConnectionState.disconnecting);
      expect(s.tcp.closes, 0);
      s.usb.closing = null;
      await s.connector.disconnect();
      expect(s.usb.closes, 2);
      expect(s.connector.state, MeshCoreConnectionState.disconnected);
    });
  }, timeout: timeout);

  testWidgets('baseline: TCP close error propagates before model release', (tester) async {
    await _withSession(tester, (s) async {
      final gate = s.gate();
      final error = StateError('synthetic TCP close error');
      s.tcp.closing = gate.future;
      final close = _Result(s.connector.disconnect());
      await tester.pump();
      gate.completeError(error);
      await tester.pump();
      expect(close.error, same(error));
      expect(s.translation.releases, 0);
      expect(s.connector.state, MeshCoreConnectionState.disconnecting);
      s.tcp.closing = null;
      await s.connector.disconnect();
      expect(s.tcp.closes, 2);
      expect(s.image.releases, 1);
    });
  }, timeout: timeout);

  testWidgets('baseline: all current joiners receive the same close failure', (tester) async {
    await _withSession(tester, (s) async {
      final gate = s.gate();
      final error = StateError('synthetic joined close error');
      s.usb.closing = gate.future;
      final first = _Result(s.connector.disconnect());
      final second = _Result(s.connector.disconnect());
      await tester.pump();
      gate.completeError(error);
      await tester.pump();
      expect(first.error, same(error));
      expect(second.error, same(error));
      expect(s.usb.closes, 1);
    });
  }, timeout: timeout);

  testWidgets('baseline: caller timeout leaves the actual teardown running', (tester) async {
    await _withSession(tester, (s) async {
      final gate = s.gate();
      s.usb.closing = gate.future;
      final caller = _Result(s.connector.disconnect().timeout(const Duration(milliseconds: 1)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(caller.error, isA<TimeoutException>());
      expect(s.connector.state, MeshCoreConnectionState.disconnecting);
      final joined = _Result(s.connector.disconnect());
      gate.complete();
      await tester.pump();
      expect(joined.completed, isTrue);
      expect(joined.error, isNull);
      expect(s.usb.closes, 1);
    });
  }, timeout: timeout);

  testWidgets('baseline: translation release blocks image cleanup until completion', (tester) async {
    await _withSession(tester, (s) async {
      final gate = s.gate();
      s.translation.releasing = gate.future;
      final close = _Result(s.connector.disconnect());
      await tester.pump();
      expect(s.events, ['usb', 'tcp', 'translation']);
      expect(close.completed, isFalse);
      gate.complete();
      await tester.pump();
      expect(close.completed, isTrue);
      expect(s.image.cancellations, 1);
    });
  }, timeout: timeout);

  testWidgets('baseline: translation timeout continues teardown while the old release is pending', (tester) async {
    await _withSession(tester, (s) async {
      final gate = s.gate();
      s.translation.releasing = gate.future;
      final close = _Result(s.connector.disconnect());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2999));
      expect(close.completed, isFalse);
      expect(s.image.releases, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(close.completed, isTrue);
      expect(close.error, isNull);
      expect(gate.isCompleted, isFalse);
      expect(s.image.releases, 1);
    });
  }, timeout: timeout);

  testWidgets('baseline: late old model failure does not resume a newer teardown', (tester) async {
    await _withSession(tester, (s) async {
      final old = s.gate();
      s.translation.releasing = old.future;
      final first = _Result(s.connector.disconnect());
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(first.completed, isTrue);
      s.translation.releasing = null;
      final current = s.gate();
      s.usb.closing = current.future;
      final second = _Result(s.connector.disconnect());
      await tester.pump();
      old.completeError(StateError('synthetic late old release error'));
      await tester.pump();
      expect(second.completed, isFalse);
      expect(s.image.releases, 1);
      current.complete();
      await tester.pump();
      expect(second.completed, isTrue);
      expect(second.error, isNull);
      expect(s.image.releases, 2);
    });
  }, timeout: timeout);

  testWidgets('baseline: image release timeout follows one codec cancellation', (tester) async {
    await _withSession(tester, (s) async {
      final gate = s.gate();
      s.image.releasing = gate.future;
      final close = _Result(s.connector.disconnect());
      await tester.pump();
      expect(s.image.cancellations, 1);
      expect(s.image.releases, 1);
      expect(close.completed, isFalse);
      await tester.pump(const Duration(seconds: 3));
      expect(close.completed, isTrue);
      expect(close.error, isNull);
      expect(gate.isCompleted, isFalse);
      gate.complete();
      await tester.pump();
      expect(s.image.cancellations, 1);
    });
  }, timeout: timeout);

  testWidgets('baseline: model cleanup deadlines apply separately to each step', (tester) async {
    await _withSession(tester, (s) async {
      s.translation.releasing = s.gate().future;
      s.image.releasing = s.gate().future;
      final close = _Result(s.connector.disconnect());
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(close.completed, isFalse);
      expect(s.image.releases, 1);
      await tester.pump(const Duration(seconds: 3));
      expect(close.completed, isTrue);
      expect(close.error, isNull);
      expect(s.connector.state, MeshCoreConnectionState.disconnected);
    });
  }, timeout: timeout);

  testWidgets('baseline: a new call after completion performs another teardown', (tester) async {
    await _withSession(tester, (s) async {
      await s.connector.disconnect();
      await s.connector.disconnect();
      expect(s.usb.closes, 2);
      expect(s.tcp.closes, 2);
      expect(s.translation.releases, 2);
      expect(s.image.releases, 2);
    });
  }, timeout: timeout);
}
