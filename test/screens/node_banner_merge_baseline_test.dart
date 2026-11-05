import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/screens/scanner_screen.dart';
import 'package:meshcore_open/storage/connection_transport_preference_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/get_node_banner.dart';
import 'package:meshcore_open/widgets/offline_history_button.dart';

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('synthetic node banner baseline');
  }
}

// Count even a failed attempt: an invisible banner must not create an HTTP
// client, regardless of whether the eventual DNS lookup would succeed.
class _NoNetwork extends HttpOverrides {
  int clientCreations = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clientCreations++;
    throw const SocketException('Network is forbidden in this baseline');
  }
}

class _ScannerConnector extends MeshCoreConnector {
  @override
  List<OfflineHistorySource> get offlineHistorySources => const [];

  // The screen owns scan teardown. Keep this UI test away from real radios
  // and persistence; the normal connector notification batcher is retained.
  @override
  Future<void> stopScan() async {}

  @override
  Future<void> disconnect({
    bool manual = true,
    bool skipBleDeviceDisconnect = false,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PathProviderPlatform previousPaths;
  late HttpOverrides? previousNetwork;
  late _NoNetwork network;

  setUp(() async {
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferencesDirectory();
    previousNetwork = HttpOverrides.current;
    network = _NoNetwork();
    HttpOverrides.global = network;
    PrefsManager.reset();
    ConnectionTransportPreferenceStore.resetCache();
    SharedPreferences.setMockInitialValues({
      'last_connection_transport': 'bluetooth',
      // A remote/cache value must never override the fork's availability gate.
      'node_banner_txt': 'v=1;on=1;url=https://example.com/node',
      'node_banner_expires_ms': DateTime.utc(2100).millisecondsSinceEpoch,
    });
    await PrefsManager.initialize();
  });

  tearDown(() {
    HttpOverrides.global = previousNetwork;
    PathProviderPlatform.instance = previousPaths;
    ConnectionTransportPreferenceStore.resetCache();
    PrefsManager.reset();
  });

  for (final language in ['en', 'ru']) {
    testWidgets(
      'U07 baseline: scanner keeps banner and network off across rebuilds ($language)',
      (tester) async {
        final connector = _ScannerConnector();
        addTearDown(connector.dispose);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        Widget app(ThemeData theme) {
          return ChangeNotifierProvider<MeshCoreConnector>.value(
            value: connector,
            child: MaterialApp(
              theme: theme,
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const ScannerScreen(),
            ),
          );
        }

        void expectScanner() {
          expect(getNodeBannerAvailable, isFalse);
          expect(find.byType(GetNodeBanner), findsNothing);
          final context = tester.element(find.byType(ScannerScreen));
          final l10n = AppLocalizations.of(context);
          expect(find.byType(OfflineHistoryButton), findsOneWidget);
          expect(find.text(l10n.app_offline), findsOneWidget);
          expect(find.text(l10n.scanner_scan), findsOneWidget);
          expect(network.clientCreations, 0);
          expect(tester.takeException(), isNull);
        }

        await tester.pumpWidget(app(ThemeData.light()));
        await tester.pumpAndSettle();
        expectScanner();

        connector.notifyListeners();
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pumpWidget(app(ThemeData.dark()));
        await tester.pumpAndSettle();
        expectScanner();

        // Dispose and drain the screen's post-frame disconnect before reopening.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pumpWidget(app(ThemeData.light()));
        await tester.pumpAndSettle();
        expectScanner();

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(network.clientCreations, 0);
      },
    );
  }
}
