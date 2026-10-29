import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/tcp_connection_navigation.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/screens/channels_screen.dart';
import 'package:meshcore_open/screens/tcp_screen.dart';
import 'package:meshcore_open/services/app_debug_log_service.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/ui_view_state_service.dart';
import 'package:meshcore_open/storage/connection_transport_preference_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/utils/app_route_observer.dart';

const _host = 'tailscale://100.64.1.2';
const _port = 5000;

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('synthetic TCP flow preferences');
  }
}

class _Connector extends MeshCoreConnector {
  MeshCoreConnectionState connectionState = MeshCoreConnectionState.disconnected;
  bool handshake = false;
  Object? identity;
  int failuresLeft = 0;
  int attempts = 0;
  int manualDisconnects = 0;

  @override
  MeshCoreConnectionState get state => connectionState;
  @override
  MeshCoreTransportType get activeTransport => MeshCoreTransportType.tcp;
  @override
  bool get isConnected => connectionState == MeshCoreConnectionState.connected;
  @override
  bool get isTcpTransportConnected => isConnected;
  @override
  bool get hasCompletedSelfInfoHandshake => isConnected && handshake;
  @override
  Object? get activeTcpConnectionIdentity => identity;
  @override
  String? get activeTcpEndpoint => isConnected ? '$_host:$_port' : null;
  @override
  List<OfflineHistorySource> get offlineHistorySources => const [];
  @override
  Future<void> getChannels({int? maxChannels, bool force = false}) async {}

  void change(MeshCoreConnectionState next, {bool ready = false}) {
    connectionState = next;
    handshake = ready;
    if (next != MeshCoreConnectionState.connected) {
      identity = null;
    }
    notifyListeners();
  }

  void ready() {
    identity ??= Object();
    change(MeshCoreConnectionState.connected, ready: true);
  }

  @override
  Future<void> connectTcp({required String host, required int port, bool automaticReconnect = false}) async {
    attempts++;
    change(MeshCoreConnectionState.connecting);
    if (failuresLeft > 0) {
      failuresLeft--;
      change(MeshCoreConnectionState.disconnected);
      throw StateError('synthetic overlay dial failed');
    }
    identity = Object();
    change(MeshCoreConnectionState.connected);
  }

  @override
  Future<void> disconnect({bool manual = true, bool skipBleDeviceDisconnect = false}) async {
    if (manual) {
      manualDisconnects++;
    }
    change(MeshCoreConnectionState.disconnected);
  }
}

class _Settings extends AppSettingsService {
  final endpoints = <(String, int)>[];
  Completer<void>? holdSave;

  @override
  Future<void> recordTcpConnection(String host, int port, {String? wifiSsid}) async {
    endpoints.add((host, port));
    final gate = holdSave;
    if (gate != null) {
      await gate.future;
    }
    await super.recordTcpConnection(host, port, wifiSsid: wifiSsid);
  }
}

class _Navigation extends NavigatorObserver {
  int replacements = 0;
  PageRoute<dynamic>? replacement;

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    replacements++;
    if (newRoute is PageRoute<dynamic>) {
      replacement = newRoute;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PathProviderPlatform savedPaths;
  setUp(() async {
    savedPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferencesDirectory();
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    ConnectionTransportPreferenceStore.resetCache();
    await PrefsManager.initialize();
  });
  tearDown(() {
    PrefsManager.reset();
    PathProviderPlatform.instance = savedPaths;
  });

  Future<void> show(WidgetTester tester, _Connector connector, _Settings settings, _Navigation observer) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<MeshCoreConnector>.value(value: connector),
        ChangeNotifierProvider<AppSettingsService>.value(value: settings),
        ChangeNotifierProvider(create: (_) => AppDebugLogService()),
        ChangeNotifierProvider(create: (_) => UiViewStateService()),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: [appRouteObserver, observer],
        home: const TcpScreen(),
      ),
    ));
    await tester.pump();
  }

  // Channels can legitimately show their initial loading spinner. Advance only
  // bounded frames; pumpAndSettle would wait forever for that unrelated spinner.
  Future<void> advance(WidgetTester tester) async {
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  // A replacement keeps the old route alive until the incoming animation
  // completes. The preparation above takes part of advance()'s frame budget;
  // Flutter's current Material transition alone can take 450 ms. Start a frame,
  // then advance the actual route duration and flush Navigator's disposal.
  Future<void> finishReplacement(WidgetTester tester, _Navigation observer) async {
    expect(observer.replacement, isNotNull, reason: 'TCP must request a route replacement');
    final route = observer.replacement!;
    await tester.pump();
    await tester.pump(route.transitionDuration + const Duration(milliseconds: 1));
    await tester.pump();
    expect(route.animation?.status, AnimationStatus.completed);
    expect(route.isCurrent, isTrue);
    expect(find.byType(TcpScreen), findsNothing);
  }

  Future<void> close(WidgetTester tester, _Connector c, _Settings settings) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 80));
    c.dispose();
    settings.dispose();
  }

  testWidgets('fifth Tailscale TCP attempt opens channels after SELF_INFO although first connect failed', (tester) async {
    final c = _Connector()..failuresLeft = 4;
    final settings = _Settings();
    final observer = _Navigation();
    await show(tester, c, settings, observer);
    await tester.enterText(find.byType(TextField).at(0), _host);
    await tester.enterText(find.byType(TextField).at(1), '$_port');
    await tester.tap(find.byKey(const Key('tcp_connect_button')));
    await advance(tester);
    expect(c.attempts, 1);
    for (var attempt = 0; attempt < 3; attempt++) {
      await expectLater(c.connectTcp(host: _host, port: _port, automaticReconnect: true), throwsStateError);
      await advance(tester);
    }
    await c.connectTcp(host: _host, port: _port, automaticReconnect: true);
    await advance(tester);
    expect(c.attempts, 5);
    expect(find.byType(TcpScreen), findsOneWidget);
    expect(settings.endpoints, isEmpty); // A socket alone is not a handshake.
    c.ready();
    await advance(tester);
    await finishReplacement(tester, observer);
    expect(find.byType(ChannelsScreen), findsOneWidget);
    expect(find.byType(TcpScreen), findsNothing);
    expect(settings.endpoints, [(_host, _port)]);
    expect(observer.replacements, 1);
    expect(c.manualDisconnects, 0);
    await close(tester, c, settings);
  });

  testWidgets('repeated ready notifications share one pending save and one route replacement', (tester) async {
    final c = _Connector();
    final gate = Completer<void>();
    final settings = _Settings()..holdSave = gate;
    final observer = _Navigation();
    await show(tester, c, settings, observer);
    c.ready();
    await advance(tester);
    for (var event = 0; event < 5; event++) {
      c.notifyListeners();
      await advance(tester);
    }
    expect(settings.endpoints.length, 1);
    expect(find.byType(TcpScreen), findsOneWidget);
    gate.complete();
    await advance(tester);
    await finishReplacement(tester, observer);
    expect(find.byType(ChannelsScreen), findsOneWidget);
    expect(observer.replacements, 1);
    expect(c.manualDisconnects, 0);
    await close(tester, c, settings);
  });

  testWidgets('covered TCP route waits and opens channels when it becomes current again', (tester) async {
    final c = _Connector();
    final settings = _Settings();
    final observer = _Navigation();
    await show(tester, c, settings, observer);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator.push<void>(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('cover')))));
    await advance(tester);
    c.ready();
    await advance(tester);
    expect(find.text('cover'), findsOneWidget);
    expect(settings.endpoints, isEmpty);
    expect(observer.replacements, 0);
    navigator.pop();
    await advance(tester);
    await finishReplacement(tester, observer);
    expect(find.byType(ChannelsScreen), findsOneWidget);
    expect(observer.replacements, 1);
    expect(c.manualDisconnects, 0);
    await close(tester, c, settings);
  });

  testWidgets('late preparation from a previous socket cannot navigate twice after reconnect', (tester) async {
    final c = _Connector();
    final oldSave = Completer<void>();
    final settings = _Settings()..holdSave = oldSave;
    final observer = _Navigation();
    await show(tester, c, settings, observer);
    c.ready();
    final firstIdentity = c.identity;
    await advance(tester);
    c.change(MeshCoreConnectionState.disconnected);
    await advance(tester);
    settings.holdSave = null;
    c.ready();
    expect(identical(firstIdentity, c.identity), isFalse);
    await advance(tester);
    expect(settings.endpoints.length, 2);
    await finishReplacement(tester, observer);
    expect(find.byType(ChannelsScreen), findsOneWidget);
    expect(observer.replacements, 1);
    oldSave.complete();
    await advance(tester);
    expect(observer.replacements, 1);
    expect(c.manualDisconnects, 0);
    expect(tester.takeException(), isNull);
    await close(tester, c, settings);
  });

  test('endpoint parsing preserves LAN, IPv6 and the Tailscale scheme', () {
    expect(connectedTcpEndpoint('192.168.1.4:5000'), (host: '192.168.1.4', port: 5000));
    expect(connectedTcpEndpoint('fd00::1234:5000'), (host: 'fd00::1234', port: 5000));
    expect(connectedTcpEndpoint('$_host:$_port'), (host: _host, port: _port));
    expect(connectedTcpEndpoint(null), isNull);
    expect(connectedTcpEndpoint('host:0'), isNull);
  });
}
