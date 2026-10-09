import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/l10n/l10n.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/models/direct_echo_observation.dart';
import 'package:meshcore_open/screens/channel_message_path_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/mesh_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The delivery-route section of the path screen, shown for an outgoing
// direct message or room post between the message details and the repeater
// hops: the hops of the route the delivery was confirmed along, with the map
// button in the header live; a line for a delivery without repeaters, the
// button off; the placeholder while no acknowledgement named a route. The
// message's own path stays in the repeater-hops section. A channel message
// and an incoming direct message get no section. The incomplete-paths
// section, when a message has them, explains under its header why they are
// incomplete.

class _Connector extends MeshCoreConnector {
  @override
  Future<void> sendFrame(
    Uint8List frame, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {}
}

/// An outgoing message whose latest attempt went by the hop 20.
ChannelMessage _message({bool isOutgoing = true}) => ChannelMessage(
  senderName: 'Me',
  text: 'hi',
  timestamp: DateTime(2026, 10, 9, 12),
  receivedAt: DateTime(2026, 10, 9, 12),
  isOutgoing: isOutgoing,
  status: ChannelMessageStatus.sent,
  pathLength: 1,
  pathBytes: Uint8List.fromList([0x20]),
);

Future<void> _pump(
  WidgetTester tester, {
  bool showDeliveryPath = true,
  Uint8List? route,
  int? width,
  bool channelMessage = false,
  bool isOutgoing = true,
  List<DirectEchoObservation> incompletePaths = const [],
}) async {
  final connector = _Connector();
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
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChannelMessagePathScreen(
          message: _message(isOutgoing: isOutgoing),
          channelMessage: channelMessage,
          showDeliveryPath: showDeliveryPath,
          deliveryPathBytes: route,
          deliveryPathHashWidth: width,
          incompletePaths: incompletePaths,
        ),
      ),
    ),
  );
  // The hop rows animate in.
  await tester.pump(const Duration(seconds: 1));
}

AppLocalizations _l10n(WidgetTester tester) =>
    tester.element(find.byType(ChannelMessagePathScreen)).l10n;

Finder _header(WidgetTester tester) => find.text(
  _l10n(tester).channelPath_deliveryConfirmedPath.toUpperCase(),
);

/// The map button in the section's header.
IconButton _mapButton(WidgetTester tester) => tester.widget<IconButton>(
  find.descendant(
    of: find.byWidgetPredicate(
      (widget) =>
          widget is SectionHeader &&
          widget.label == _l10n(tester).channelPath_deliveryConfirmedPath,
    ),
    matching: find.byType(IconButton),
  ),
);

void main() {
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('mco_path_screen_');
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

  testWidgets('a confirmed route is listed hop by hop after the details, '
      'with the map button live', (tester) async {
    await _pump(tester, route: Uint8List.fromList([0x12, 0x34]), width: 1);
    final l10n = _l10n(tester);

    expect(_header(tester), findsOneWidget);
    expect(find.textContaining('(12)'), findsOneWidget);
    expect(find.textContaining('(34)'), findsOneWidget);
    // The message's own path, the latest attempt's, stays in its section.
    expect(find.textContaining('(20)'), findsOneWidget);
    expect(_mapButton(tester).onPressed, isNotNull);

    final details = tester.getTopLeft(
      find.text(l10n.channelPath_messageDetails.toUpperCase()),
    );
    final delivery = tester.getTopLeft(_header(tester));
    final hops = tester.getTopLeft(
      find.text(l10n.channelPath_repeaterHops.toUpperCase()),
    );
    expect(delivery.dy, greaterThan(details.dy));
    expect(delivery.dy, lessThan(hops.dy));
  });

  testWidgets('a delivery without repeaters says so, the map button '
      'off', (tester) async {
    await _pump(tester, route: Uint8List(0), width: 1);

    expect(_header(tester), findsOneWidget);
    expect(
      find.text(_l10n(tester).channelPath_deliveredDirectly),
      findsOneWidget,
    );
    expect(_mapButton(tester).onPressed, isNull);
  });

  testWidgets('a message with no confirmed route shows the placeholder, the '
      'map button off', (tester) async {
    await _pump(tester, route: null);

    expect(_header(tester), findsOneWidget);
    expect(
      find.text(_l10n(tester).channelPath_deliveryPathUnknown),
      findsOneWidget,
    );
    expect(_mapButton(tester).onPressed, isNull);
  });

  testWidgets('a channel message has no delivery section', (tester) async {
    await _pump(tester, showDeliveryPath: false, channelMessage: true);

    expect(_header(tester), findsNothing);
  });

  testWidgets('an incoming direct message has no delivery section', (
    tester,
  ) async {
    await _pump(tester, showDeliveryPath: false, isOutgoing: false);

    expect(_header(tester), findsNothing);
  });

  testWidgets('the incomplete paths come with the note on why they are '
      'incomplete', (tester) async {
    await _pump(
      tester,
      showDeliveryPath: false,
      isOutgoing: false,
      incompletePaths: [
        DirectEchoObservation(
          remainingPath: Uint8List.fromList([0x12, 0x34]),
          pathHashWidth: 1,
        ),
      ],
    );
    final l10n = _l10n(tester);

    final header = tester.getTopLeft(
      find.text(l10n.channelPath_incompletePaths.toUpperCase()),
    );
    final note = find.text(l10n.channelPath_incompletePathsNote);
    expect(note, findsOneWidget);
    expect(tester.getTopLeft(note).dy, greaterThan(header.dy));
  });

  testWidgets('a message without incomplete paths shows no note', (
    tester,
  ) async {
    await _pump(tester, showDeliveryPath: false, isOutgoing: false);

    expect(
      find.text(_l10n(tester).channelPath_incompletePathsNote),
      findsNothing,
    );
  });
}
