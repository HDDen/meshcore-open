import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/screens/telemetry_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TelemetryConnector extends MeshCoreConnector {
  final frames = StreamController<Uint8List>.broadcast();

  @override
  Stream<Uint8List> get receivedFrames => frames.stream;

  @override
  Future<void> sendFrame(
    Uint8List frame, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {}
}

final _key = Uint8List.fromList(List.filled(32, 0x11));

Future<_TelemetryConnector> _openTelemetry(
  WidgetTester tester,
  String locale,
) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final connector = _TelemetryConnector();
  final settings = AppSettingsService();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await connector.frames.close();
    connector.dispose();
    settings.dispose();
  });
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<MeshCoreConnector>.value(value: connector),
        ChangeNotifierProvider<AppSettingsService>.value(value: settings),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TelemetryScreen(
          isSelf: true,
          contact: Contact(
            publicKey: _key,
            name: 'Synthetic telemetry node',
            type: advTypeChat,
            pathLength: 0,
            path: Uint8List(0),
            lastSeen: DateTime(2026, 10, 21),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return connector;
}

Future<void> _respond(
  WidgetTester tester,
  _TelemetryConnector connector,
  List<int> payload,
) async {
  connector.frames.add(Uint8List.fromList([
    pushCodeTelemetryResponse, 0, ..._key.take(6), ...payload,
  ]));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  for (final locale in ['ru', 'en']) {
    testWidgets('shows reported and calculated power alongside pressure ($locale)', (
      tester,
    ) async {
      final connector = await _openTelemetry(tester, locale);
      await _respond(tester, connector, [
        2, 103, 0x01, 0x1C,
        2, 104, 0x5F,
        3, 115, 0x27, 0xFE,
        4, 116, 0x01, 0x80,
        4, 117, 0xFF, 0xF5,
        4, 128, 0x00, 0x00,
      ]);
      final unit = locale == 'ru' ? 'Вт' : 'W';
      final label = locale == 'ru'
          ? 'Расчётная мощность (U × I)'
          : 'Calculated power (V × I)';
      expect(find.text(label), findsOneWidget);
      expect(find.text('0.000 $unit'), findsOneWidget);
      expect(find.text('-0.042 $unit'), findsOneWidget);
      expect(
        find.text(locale == 'ru' ? '1023.80 гПа' : '1023.80 hPa'),
        findsOneWidget,
      );
      expect(find.text('47.50%'), findsOneWidget);

      await _respond(tester, connector, [
        4, 116, 0x01, 0x80,
        4, 117, 0x01, 0xF4,
        4, 128, 0x00, 0x0D,
      ]);
      expect(find.text('13.000 $unit'), findsOneWidget);
      expect(find.text('1.920 $unit'), findsOneWidget);
      expect(find.text('-0.042 $unit'), findsNothing);
    });
  }

  testWidgets('never combines different channels or reuses the previous current', (
    tester,
  ) async {
    final connector = await _openTelemetry(tester, 'en');
    await _respond(tester, connector, [
      4, 116, 0x01, 0x80,
      4, 117, 0x01, 0xF4,
    ]);
    expect(find.text('Calculated power (V × I)'), findsOneWidget);
    expect(find.text('1.920 W'), findsOneWidget);
    expect(find.text('Power'), findsNothing);

    await _respond(tester, connector, [
      4, 116, 0x01, 0x80,
      5, 117, 0x01, 0xF4,
    ]);
    expect(find.text('Calculated power (V × I)'), findsNothing);
    expect(find.text('1.920 W'), findsNothing);
  });
}
