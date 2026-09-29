import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/storage/region_store.dart';
import 'package:meshcore_open/widgets/formatted_message_text.dart';
import 'package:meshcore_open/widgets/translated_message_content.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A channel link (meshcore://channel/add?...) in a message is a link of its
// own. A tap asks whether to add the channel, showing its name and region,
// and adds it to the node's first free slot with its region. A channel the
// node holds already, a node with no free slot, a lost link and the offline
// history get a message instead of the question.

const _secret = 'cbf8c4bc9379ab17b216721171f3ba89';
const _link =
    'meshcore://channel/add?name=%23public_mco&secret=$_secret&region_scope=ru-kda';

/// The connector as the import sees it: the node's channels and regions, the
/// state of the link, and what reached the node, in order.
class _Node extends MeshCoreConnector {
  _Node({List<Channel> channels = const []}) : _held = [...channels];

  final List<Channel> _held;
  final regions = <int, String>{};
  final written = <String>[];
  bool connected = true;
  bool offline = false;
  int slots = 8;

  @override
  bool get isConnected => connected;

  @override
  bool get isOfflineMode => offline;

  @override
  List<Channel> get channels => List.unmodifiable(_held);

  @override
  int get maxChannels => slots;

  @override
  String get selfPublicKeyHex => 'ab' * 32;

  @override
  String getChannelRegion(int channelIndex) => regions[channelIndex] ?? '';

  @override
  Future<void> setChannel(int index, String name, Uint8List psk) async {
    final secret = Channel.formatPskHex(psk).toLowerCase();
    written.add('channel $index $name $secret');
  }

  @override
  Future<void> setChannelRegion(int channelIndex, String region) async {
    written.add('region $channelIndex $region');
  }
}

Channel _channel(int index, String name, String secret) =>
    Channel(index: index, name: name, psk: Channel.parsePskHex(secret));

Widget _app(_Node node, Widget body) =>
    ChangeNotifierProvider<MeshCoreConnector>.value(
      value: node,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: body),
      ),
    );

Widget _plainMessage() => const TranslatedMessageContent(
  displayText: 'join $_link please',
  style: TextStyle(),
);

/// Taps the span showing [text], whatever the body was built with: a
/// RichText, or the SelectableText linkify gives a desktop.
void _tapSpan(WidgetTester tester, String text) {
  final roots = <InlineSpan>[
    for (final rich in tester.widgetList<RichText>(find.byType(RichText)))
      rich.text,
    for (final selectable in tester.widgetList<SelectableText>(
      find.byType(SelectableText),
    ))
      if (selectable.textSpan != null) selectable.textSpan!,
  ];
  for (final root in roots) {
    TapGestureRecognizer? tap;
    root.visitChildren((span) {
      if (span is TextSpan &&
          span.text == text &&
          span.recognizer is TapGestureRecognizer) {
        tap = span.recognizer! as TapGestureRecognizer;
        return false;
      }
      return true;
    });
    if (tap != null) {
      tap!.onTap!();
      return;
    }
  }
  fail('No tappable span shows "$text"');
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  testWidgets('a tap asks to add the channel, with its name and region', (
    tester,
  ) async {
    final node = _Node();
    await tester.pumpWidget(_app(node, _plainMessage()));

    _tapSpan(tester, _link);
    await tester.pumpAndSettle();

    expect(find.text('Add Channel'), findsOneWidget);
    expect(find.text('#public_mco'), findsOneWidget);
    expect(find.text('Region: ru-kda'), findsOneWidget);
    expect(find.text('Open Link?'), findsNothing);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(node.written, isEmpty);
  });

  testWidgets('adding puts the channel into the first free slot with its '
      'region', (tester) async {
    final node = _Node(
      channels: [
        _channel(0, 'Public', '8b3387e9c5cdea6ac9e5edbaa115cd72'),
        _channel(1, '#other', '00112233445566778899aabbccddeeff'),
      ],
    );
    await tester.pumpWidget(_app(node, _plainMessage()));

    _tapSpan(tester, _link);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(node.written, [
      'channel 2 #public_mco $_secret',
      'region 2 ru-kda',
    ]);
    expect(RegionStore().loadRegions(), contains('ru-kda'));
    expect(find.text('Channel "#public_mco" added'), findsOneWidget);
  });

  testWidgets('a link among formatted runs asks the same', (tester) async {
    final node = _Node();
    await tester.pumpWidget(
      _app(
        node,
        const FormattedMessageText(
          text: '**new** $_link',
          style: TextStyle(),
          textScale: 1,
          simplified: false,
        ),
      ),
    );

    _tapSpan(tester, _link);
    await tester.pumpAndSettle();

    expect(find.text('Add Channel'), findsOneWidget);
  });

  testWidgets('a channel the node holds already is not added twice', (
    tester,
  ) async {
    final node = _Node(channels: [_channel(3, '#public_mco', _secret)])
      ..regions[3] = 'ru-kda';
    await tester.pumpWidget(_app(node, _plainMessage()));

    _tapSpan(tester, _link);
    await tester.pumpAndSettle();

    expect(find.text('Add Channel'), findsNothing);
    expect(find.text('Channel "#public_mco" is already added'), findsOneWidget);
    expect(node.written, isEmpty);
  });

  testWidgets('a node with no free slot says so', (tester) async {
    final node = _Node(
      channels: [
        _channel(0, 'Public', '8b3387e9c5cdea6ac9e5edbaa115cd72'),
        _channel(1, '#other', '00112233445566778899aabbccddeeff'),
      ],
    )..slots = 2;
    await tester.pumpWidget(_app(node, _plainMessage()));

    _tapSpan(tester, _link);
    await tester.pumpAndSettle();

    expect(find.text('Add Channel'), findsNothing);
    expect(find.text('All channel slots are in use'), findsOneWidget);
    expect(node.written, isEmpty);
  });

  testWidgets('without a link to the node nothing is asked', (tester) async {
    final node = _Node()..connected = false;
    await tester.pumpWidget(_app(node, _plainMessage()));

    _tapSpan(tester, _link);
    await tester.pumpAndSettle();

    expect(find.text('Add Channel'), findsNothing);
    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets('the offline history cannot add a channel', (tester) async {
    final node = _Node()..offline = true;
    await tester.pumpWidget(_app(node, _plainMessage()));

    _tapSpan(tester, _link);
    await tester.pumpAndSettle();

    expect(find.text('Add Channel'), findsNothing);
    expect(
      find.text(
        'You cannot send messages or perform other actions while offline',
      ),
      findsOneWidget,
    );
  });
}
