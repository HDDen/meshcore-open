import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/companion_radio_stats.dart';
import 'package:meshcore_open/screens/line_of_sight_map_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/map_tile_cache_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// What the line-of-sight map's banner promises, pinned before the screen
// stops rebuilding on every notification of the connector: it shows the
// node's battery and the last SNR the radio reported, dashes while either is
// unknown, and follows them when they change. The screen is opened with no
// endpoints, so it runs no analysis and asks nothing of the network.

CompanionRadioStats _stats(double snr) => CompanionRadioStats(
  noiseFloorDbm: -110,
  lastRssiDbm: -80,
  lastSnrDb: snr,
  txAirSecs: 10,
  rxAirSecs: 20,
  receivedAt: DateTime(2026, 9, 29, 12),
);

class _FakeConnector extends MeshCoreConnector {
  int? battery;
  CompanionRadioStats? stats;

  @override
  bool get hasReadableSession => true;

  @override
  bool get isConnected => true;

  @override
  int? get batteryPercent => battery;

  @override
  CompanionRadioStats? get latestRadioStats => stats;

  @override
  int getTotalChannelsUnreadCount() => 0;

  @override
  Future<void> sendFrame(
    Uint8List frame, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {}

  void notify() => notifyListeners();
}

/// Lets the screen's first run and the tile layers settle.
Future<void> _pumpFrames(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Harness {
  _Harness(this.connector);

  final _FakeConnector connector;

  static Future<_Harness> pump(
    WidgetTester tester, {
    int? battery,
    CompanionRadioStats? stats,
  }) async {
    final connector = _FakeConnector()
      ..battery = battery
      ..stats = stats;
    final settings = AppSettingsService();
    addTearDown(() {
      settings.dispose();
      connector.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MeshCoreConnector>.value(value: connector),
          ChangeNotifierProvider<AppSettingsService>.value(value: settings),
          ChangeNotifierProvider<MapTileCacheService>(
            create: (_) => MapTileCacheService(appSettingsService: settings),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LineOfSightMapScreen(title: 'LOS', candidates: []),
        ),
      ),
    );
    await _pumpFrames(tester);
    return _Harness(connector);
  }

  static Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }
}

void main() {
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('mco_los_banner_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => tempDir.path);
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(() {
    PrefsManager.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    tempDir.deleteSync(recursive: true);
  });

  testWidgets('the banner shows the battery and the SNR the connector '
      'reports', (tester) async {
    try {
      await _Harness.pump(tester, battery: 83, stats: _stats(7.5));

      expect(find.text('83%'), findsOneWidget);
      expect(find.text('7.5 dB'), findsOneWidget);
    } finally {
      await _Harness.unmount(tester);
    }
  });

  testWidgets('unknown readings show as dashes', (tester) async {
    try {
      await _Harness.pump(tester);

      expect(find.text('--'), findsAtLeastNWidgets(2));
    } finally {
      await _Harness.unmount(tester);
    }
  });

  testWidgets('the banner follows the readings when they change', (
    tester,
  ) async {
    try {
      final harness = await _Harness.pump(
        tester,
        battery: 83,
        stats: _stats(7.5),
      );

      harness.connector
        ..battery = 60
        ..stats = _stats(-2.5)
        ..notify();
      await _pumpFrames(tester, frames: 2);

      expect(find.text('60%'), findsOneWidget);
      expect(find.text('83%'), findsNothing);
      expect(find.text('-2.5 dB'), findsOneWidget);
    } finally {
      await _Harness.unmount(tester);
    }
  });
}
