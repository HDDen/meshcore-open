import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/screens/scanner_screen.dart';
import 'package:meshcore_open/screens/tcp_screen.dart';
import 'package:meshcore_open/services/app_debug_log_service.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/connection_transport_preference_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';

class _FakeMeshCoreConnector extends MeshCoreConnector {
  _FakeMeshCoreConnector();

  MeshCoreConnectionState initialState = MeshCoreConnectionState.disconnected;
  MeshCoreTransportType initialTransport = MeshCoreTransportType.bluetooth;
  String? initialEndpoint;
  int connectTcpCalls = 0;
  int stopScanCalls = 0;
  Completer<void>? pendingScanStop;
  Completer<void>? pendingScanStart;
  String? lastHost;
  int? lastPort;

  @override
  MeshCoreConnectionState get state => initialState;

  @override
  MeshCoreTransportType get activeTransport => initialTransport;

  @override
  bool get isTcpTransportConnected =>
      initialState == MeshCoreConnectionState.connected &&
      initialTransport == MeshCoreTransportType.tcp;

  @override
  String? get activeTcpEndpoint => initialEndpoint;

  // The offline-history button lists the node scopes of the message
  // history, a storage no screen test opens.
  @override
  List<OfflineHistorySource> get offlineHistorySources => const [];

  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    initialState = MeshCoreConnectionState.scanning;
    notifyListeners();
    await pendingScanStart?.future;
  }

  @override
  Future<void> stopScan() async {
    stopScanCalls += 1;
    await pendingScanStop?.future;
    if (initialState == MeshCoreConnectionState.scanning) {
      initialState = MeshCoreConnectionState.disconnected;
      notifyListeners();
    }
  }

  @override
  Future<void> connectTcp({
    required String host,
    required int port,
    bool automaticReconnect = false,
  }) async {
    connectTcpCalls += 1;
    lastHost = host;
    lastPort = port;
  }
}

Widget _buildTestApp({
  required MeshCoreConnector connector,
  required Widget child,
  Locale? locale,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<MeshCoreConnector>.value(value: connector),
      ChangeNotifierProvider<AppSettingsService>(
        create: (_) => AppSettingsService(),
      ),
      ChangeNotifierProvider<AppDebugLogService>(
        create: (_) => AppDebugLogService(),
      ),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  setUp(() async {
    PrefsManager.reset();
    ConnectionTransportPreferenceStore.resetCache();
    SharedPreferences.setMockInitialValues({});
    await PrefsManager.initialize();
  });

  testWidgets('TcpScreen uses localized TCP copy', (tester) async {
    final connector = _FakeMeshCoreConnector();

    await tester.pumpWidget(
      _buildTestApp(
        connector: connector,
        child: const TcpScreen(),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(TcpScreen));
    final l10n = AppLocalizations.of(context);

    expect(find.text(l10n.tcpScreenTitle), findsOneWidget);
    expect(find.text(l10n.tcpHostLabel), findsOneWidget);
    expect(find.text(l10n.tcpPortLabel), findsOneWidget);
    expect(find.text(l10n.tcpStatus_notConnected), findsOneWidget);
  });

  testWidgets('TcpScreen validation errors are localized', (tester) async {
    final connector = _FakeMeshCoreConnector();

    await tester.pumpWidget(
      _buildTestApp(
        connector: connector,
        child: const TcpScreen(),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(TcpScreen));
    final l10n = AppLocalizations.of(context);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.tap(find.byKey(const Key('tcp_connect_button')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.tcpErrorHostRequired), findsOneWidget);
    expect(connector.connectTcpCalls, 0);

    await tester.enterText(find.byType(TextField).first, '192.168.1.50');
    await tester.enterText(find.byType(TextField).at(1), '99999');
    await tester.tap(find.byKey(const Key('tcp_connect_button')));
    await tester.pumpAndSettle();

    expect(connector.connectTcpCalls, 0);
  });

  testWidgets('TCP Bluetooth action returns to existing scanner route', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector();

    await tester.pumpWidget(
      _buildTestApp(connector: connector, child: const ScannerScreen()),
    );
    await tester.pumpAndSettle();

    final scannerContext = tester.element(find.byType(ScannerScreen));
    final scannerL10n = AppLocalizations.of(scannerContext);
    await tester.tap(find.byTooltip(scannerL10n.connectionChoiceTcpLabel));
    await tester.pumpAndSettle();
    expect(find.byType(TcpScreen), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Bluetooth'));
    await tester.pumpAndSettle();

    expect(find.byType(TcpScreen), findsNothing);
    expect(find.byType(ScannerScreen), findsOneWidget);
    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigatorState.canPop(), isFalse);

    // ScannerScreen.dispose() schedules disconnect work that debounces notify.
    // Drain that debounce timer before test teardown.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 60));
  });

  for (final preferred in [false, true]) {
    testWidgets('Scanner waits for BLE stop before TCP: preferred=$preferred', (
      tester,
    ) async {
      final connector = _FakeMeshCoreConnector();
      if (preferred) {
        await ConnectionTransportPreferenceStore().save(
          ConnectionTransportPreferenceStore.tcp,
        );
        connector.initialState = MeshCoreConnectionState.scanning;
        connector.pendingScanStop = Completer<void>();
      }
      await tester.pumpWidget(
        _buildTestApp(connector: connector, child: const ScannerScreen()),
      );
      if (!preferred) {
        await tester.pumpAndSettle();
        connector.initialState = MeshCoreConnectionState.scanning;
        connector.pendingScanStop = Completer<void>();
        connector.notifyListeners();
        await tester.pump(const Duration(milliseconds: 60));
        final l10n = AppLocalizations.of(
          tester.element(find.byType(ScannerScreen)),
        );
        // Repeated taps must still produce just one TCP route.
        await tester.tap(find.byTooltip(l10n.connectionChoiceTcpLabel));
        await tester.tap(find.byTooltip(l10n.connectionChoiceTcpLabel));
      }
      await tester.pump(const Duration(milliseconds: 60));
      expect(connector.stopScanCalls, greaterThan(0));
      expect(find.byType(TcpScreen), findsNothing);
      expect(connector.initialState, MeshCoreConnectionState.scanning);

      connector.pendingScanStop!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(TcpScreen), findsOneWidget);
      expect(
        tester.widget<ButtonStyleButton>(
          find.byKey(const Key('tcp_connect_button')),
        ).onPressed,
        isNotNull,
      );
      expect(connector.connectTcpCalls, 0);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Bluetooth'));
      await tester.pumpAndSettle();
      expect(find.byType(ScannerScreen), findsOneWidget);
      expect(find.byType(TcpScreen), findsNothing);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 60));
    });
  }

  testWidgets('TCP transition stops a scan that is still starting', (tester) async {
    final connector = _FakeMeshCoreConnector();
    await tester.pumpWidget(
      _buildTestApp(connector: connector, child: const ScannerScreen()),
    );
    await tester.pumpAndSettle();
    connector.pendingScanStart = Completer<void>();
    connector.pendingScanStop = Completer<void>();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(milliseconds: 60));
    final stopCalls = connector.stopScanCalls;
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ScannerScreen)),
    );
    await tester.tap(find.byTooltip(l10n.connectionChoiceTcpLabel));
    await tester.pump();
    expect(connector.stopScanCalls, stopCalls);
    expect(find.byType(TcpScreen), findsNothing);

    connector.pendingScanStart!.complete();
    await tester.pump();
    expect(connector.stopScanCalls, stopCalls + 1);
    expect(find.byType(TcpScreen), findsNothing);
    connector.pendingScanStop!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(TcpScreen), findsOneWidget);
    expect(connector.initialState, MeshCoreConnectionState.disconnected);
    expect(connector.connectTcpCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 60));
  });

  testWidgets('late BLE stop cannot navigate from a removed scanner', (tester) async {
    final connector = _FakeMeshCoreConnector();
    await tester.pumpWidget(
      _buildTestApp(connector: connector, child: const ScannerScreen()),
    );
    await tester.pumpAndSettle();
    connector.initialState = MeshCoreConnectionState.scanning;
    connector.pendingScanStop = Completer<void>();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ScannerScreen)),
    );
    await tester.tap(find.byTooltip(l10n.connectionChoiceTcpLabel));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    connector.pendingScanStop!.complete();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(TcpScreen), findsNothing);
    expect(connector.connectTcpCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TCP scan baseline unlocks connect only after scan completion', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector()
      ..initialState = MeshCoreConnectionState.scanning;

    await tester.pumpWidget(
      _buildTestApp(
        connector: connector,
        child: const TcpScreen(),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('tcp_connect_button')),
    );
    expect(button.onPressed, isNull);
    expect(connector.connectTcpCalls, 0);

    // Completing a scan must unlock TCP without starting a connection itself.
    connector.initialState = MeshCoreConnectionState.disconnected;
    connector.notifyListeners();
    await tester.pump(const Duration(milliseconds: 60));
    final readyButton = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('tcp_connect_button')),
    );
    expect(readyButton.onPressed, isNotNull);
    expect(connector.connectTcpCalls, 0);
    expect(find.byType(TcpScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 60));
  });

  testWidgets('TCP connect baseline preserves LAN availability and connector guards', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector();
    await tester.pumpWidget(
      _buildTestApp(
        connector: connector,
        child: const TcpScreen(),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    ButtonStyleButton connectButton() => tester.widget<ButtonStyleButton>(
      find.byKey(const Key('tcp_connect_button')),
    );

    // Adding an optional transport prerequisite must leave ordinary TCP usable.
    for (final host in ['192.168.1.50', 'desktop.local']) {
      await tester.enterText(find.byType(TextField).first, host);
      await tester.pump();
      expect(connectButton().onPressed, isNotNull, reason: host);
    }

    // A transport becoming ready must not bypass any existing connector guard.
    for (final state in [
      MeshCoreConnectionState.scanning,
      MeshCoreConnectionState.connecting,
      MeshCoreConnectionState.connected,
      MeshCoreConnectionState.disconnecting,
    ]) {
      connector.initialState = state;
      connector.notifyListeners();
      await tester.pump(const Duration(milliseconds: 60));
      expect(connectButton().onPressed, isNull, reason: state.name);
    }
    connector.initialState = MeshCoreConnectionState.disconnected;
    connector.notifyListeners();
    await tester.pumpAndSettle();
    expect(connectButton().onPressed, isNotNull);
    expect(connector.connectTcpCalls, 0);

    // Unmount first so the connector's debounced callbacks can drain.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 60));
  });

  testWidgets('TcpScreen narrow width long status text does not overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final connector = _FakeMeshCoreConnector()
      ..initialState = MeshCoreConnectionState.connected
      ..initialTransport = MeshCoreTransportType.tcp
      ..initialEndpoint = 'meshcore-room-server-very-long-hostname.local:5000';

    await tester.pumpWidget(
      _buildTestApp(
        connector: connector,
        child: const TcpScreen(),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final context = tester.element(find.byType(TcpScreen));
    final l10n = AppLocalizations.of(context);
    expect(
      find.text(l10n.scanner_connectedTo(connector.initialEndpoint!)),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 60));
  });
}
