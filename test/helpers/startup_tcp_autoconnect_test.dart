import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/startup_tcp_autoconnect.dart';
import 'package:meshcore_open/storage/connection_transport_preference_store.dart';
import 'package:meshcore_open/storage/last_radio_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import '../support/history_test_environment.dart';

class _Connector extends MeshCoreConnector {
  final targets = <({String host, int port})>[];
  MeshCoreConnectionState connectionState =
      MeshCoreConnectionState.disconnected;
  bool manual = false;
  bool legacyOffline = false;
  bool review = false;
  bool reconnectScheduled = false;
  bool fail = false;

  @override
  MeshCoreConnectionState get state => connectionState;
  @override
  bool get isConnected => connectionState == MeshCoreConnectionState.connected;
  @override
  bool get wasManuallyDisconnected => manual;
  @override
  bool get isLegacyOfflineSession => legacyOffline;
  @override
  bool get isReviewMode => review;
  @override
  bool get isAutoReconnectScheduled => reconnectScheduled;
  @override
  bool shouldSuppressAutoconnect(MeshCoreTransportType transport) => manual;
  @override
  Future<void> connectTcp({
    required String host,
    required int port,
    bool automaticReconnect = false,
  }) async {
    targets.add((host: host, port: port));
    if (fail) throw StateError('Synthetic connection failure');
    connectionState = MeshCoreConnectionState.connected;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final history = HistoryTestEnvironment();
  late _Connector connector;
  final preferences = ConnectionTransportPreferenceStore();

  Future<void> remember({
    String transport = LastRadio.transportTcp,
    String host = 'last.radio.test',
    int port = 5000,
  }) async {
    await LastRadioStore().save(
      LastRadio(
        publicKeyHex: 'ab' * 32,
        name: 'Saved node',
        transport: transport,
        tcpHost: host,
        tcpPort: port,
        savedAt: DateTime.utc(2026, 11, 23),
      ),
    );
    await connector.restoreLastRadio();
  }

  setUp(() async {
    await history.setUp();
    ConnectionTransportPreferenceStore.resetCache();
    await preferences.setAutoconnectEnabled(
      ConnectionTransportPreferenceStore.tcp,
      true,
    );
    connector = _Connector();
  });
  tearDown(() async {
    connector.dispose();
    ConnectionTransportPreferenceStore.resetCache();
    await history.tearDown();
  });

  test(
    'saved-radio offline startup reconnects to the last successful TCP endpoint',
    () async {
      await remember();
      await PrefsManager.instance.setString(
        'app_settings',
        jsonEncode({
          'tcp_server_address': 'edited-but-never-connected.test',
          'tcp_server_port': 9999,
        }),
      );
      expect(connector.hasRadioData, isTrue);
      expect(connector.isOfflineMode, isTrue);
      expect(await autoconnectSavedTcpRadio(connector), isTrue);
      expect(connector.targets, [(host: 'last.radio.test', port: 5000)]);
      expect(await autoconnectSavedTcpRadio(connector), isFalse);
      expect(connector.targets, hasLength(1));
    },
  );

  test('TCP autoconnect off leaves offline data untouched', () async {
    await remember();
    await preferences.setAutoconnectEnabled(
      ConnectionTransportPreferenceStore.tcp,
      false,
    );
    expect(await autoconnectSavedTcpRadio(connector), isFalse);
    expect(connector.targets, isEmpty);
    expect(connector.hasRadioData, isTrue);
  });

  for (final transport in [LastRadio.transportBle, LastRadio.transportUsb]) {
    test('the last $transport session does not start TCP', () async {
      await remember(transport: transport);
      expect(await autoconnectSavedTcpRadio(connector), isFalse);
      expect(connector.targets, isEmpty);
    });
  }

  for (final block in [
    'manual',
    'legacy',
    'review',
    'scheduled',
    'connecting',
    'web',
  ]) {
    test('startup respects $block suppression', () async {
      await remember();
      connector.manual = block == 'manual';
      connector.legacyOffline = block == 'legacy';
      connector.review = block == 'review';
      connector.reconnectScheduled = block == 'scheduled';
      if (block == 'connecting') {
        connector.connectionState = MeshCoreConnectionState.connecting;
      }
      expect(
        await autoconnectSavedTcpRadio(connector, isWeb: block == 'web'),
        isFalse,
      );
      expect(connector.targets, isEmpty);
    });
  }

  test(
    'no saved radio leaves first-run scanner autoconnect in control',
    () async {
      expect(await autoconnectSavedTcpRadio(connector), isFalse);
      expect(connector.targets, isEmpty);
    },
  );

  for (final port in [0, 65536]) {
    test('invalid saved port $port is not dialed', () async {
      await remember(port: port);
      expect(await autoconnectSavedTcpRadio(connector), isFalse);
      expect(connector.targets, isEmpty);
    });
  }

  test('a failed connection retains saved offline data', () async {
    await remember();
    connector.fail = true;
    expect(await autoconnectSavedTcpRadio(connector), isFalse);
    expect(connector.targets, hasLength(1));
    expect(connector.hasRadioData, isTrue);
    expect(connector.isOfflineMode, isTrue);
    expect(connector.lastRadio!.tcpHost, 'last.radio.test');
  });
}
