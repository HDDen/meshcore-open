import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/translated_message_content.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A contact link in a message, among other words, is a link of its own. A
// tap asks whether to add the contact, showing its name, type and key. The
// MeshCore app's link is written as a shared contact card writes one; an
// advert packet goes to the node, which verifies and keeps it. Our own key,
// a lost link and the offline history get a message instead of the
// question, and a key the node holds already adds a line to it.

const _addKey =
    '0946621c621e4410ee1f43cec55d463b1e8b7006ca8014057306383a95b8b725';
const _add =
    'meshcore://contact/add?name=%F0%9F%A4%94&public_key=$_addKey&type=1';
const _advertHex =
    '1100afdad95d3a1e3ee4c5152e45dbfd89b3ef584d542c958e90c4b90feb6a1bc023'
    '6139c96ac2b0a6fea46b4a4b4e93aa0e40074ee0a4b25f9f2caa1b1ceed6900fa548'
    'b759d3a8cb5d968fc118012b50c4e7a2ef4ae68b40587935b71f282e6ef48286530'
    'c8151524c';
const _advert = 'meshcore://$_advertHex';

/// The connector as the import sees it: the contacts the node holds, the
/// state of the link, and what reached the node.
class _Node extends MeshCoreConnector {
  final held = <String, Contact>{};
  final added = <String>[];
  final written = <Uint8List>[];
  bool connected = true;
  bool offline = false;
  String self = 'ab' * 32;

  @override
  bool get isConnected => connected;

  @override
  bool get isOfflineMode => offline;

  @override
  String get selfPublicKeyHex => self;

  @override
  Contact? getContactByPubKeyHex(String contactPubKeyHex) =>
      held[contactPubKeyHex];

  @override
  Future<void> addOrUpdateSharedContact({
    required Uint8List publicKey,
    required int type,
    required String name,
  }) async {
    added.add('$name $type ${pubKeyToHex(publicKey)}');
  }

  @override
  Future<void> sendFrame(
    Uint8List frame, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {
    written.add(frame);
  }
}

Widget _app(_Node node, String text) =>
    ChangeNotifierProvider<MeshCoreConnector>.value(
      value: node,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: TranslatedMessageContent(
            displayText: text,
            style: const TextStyle(),
          ),
        ),
      ),
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

/// Lets the snackbar on screen run out: the messenger shows the next one
/// only after it, and a message of a later step would otherwise wait in
/// its queue.
Future<void> _letSnackBarGo(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Contact _contact(String keyHex, String name) => Contact(
  publicKey: hex2Uint8List(keyHex),
  name: name,
  type: advTypeChat,
  pathLength: 0,
  path: Uint8List(0),
  lastSeen: DateTime(2026, 10, 9),
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  testWidgets("a tap on the app's link asks to add the contact and writes "
      'it as a shared contact card does', (tester) async {
    final node = _Node();
    await tester.pumpWidget(_app(node, 'всем привет, $_add пишите мне'));

    _tapSpan(tester, _add);
    await tester.pumpAndSettle();

    expect(find.text('Add contact'), findsOneWidget);
    expect(find.text('\u{1F914}'), findsOneWidget);
    expect(find.text('Contact type: Node'), findsOneWidget);
    expect(find.text('Open Link?'), findsNothing);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(node.added, isEmpty);

    _tapSpan(tester, _add);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(node.added, ['\u{1F914} 1 $_addKey']);
    expect(node.written, isEmpty);
    expect(find.text('Contact has been imported.'), findsOneWidget);
  });

  testWidgets('a tap on an advert link hands the packet to the node', (
    tester,
  ) async {
    final node = _Node();
    await tester.pumpWidget(_app(node, 'my node: $_advert.'));

    _tapSpan(tester, _advert);
    await tester.pumpAndSettle();
    expect(find.text('QRL'), findsOneWidget);
    expect(find.text('Contact type: Node'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(node.added, isEmpty);
    expect(node.written, hasLength(1));
    expect(node.written.single[0], cmdImportContact);
    expect(node.written.single.sublist(1), hex2Uint8List(_advertHex));
    expect(find.text('Contact has been imported.'), findsOneWidget);
  });

  testWidgets('our own key, a key the node holds, the offline history and a '
      'lost link', (tester) async {
    final node = _Node()..self = _addKey;
    await tester.pumpWidget(_app(node, _add));
    _tapSpan(tester, _add);
    await tester.pumpAndSettle();
    expect(find.text('It is you'), findsOneWidget);
    expect(find.text('Add contact'), findsNothing);
    await _letSnackBarGo(tester);

    node
      ..self = 'ab' * 32
      ..held[_addKey] = _contact(_addKey, 'Old name');
    _tapSpan(tester, _add);
    await tester.pumpAndSettle();
    expect(find.text('Add contact'), findsOneWidget);
    expect(find.text('Contact is already exists, replace it?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    node.offline = true;
    _tapSpan(tester, _add);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'You cannot send messages or perform other actions while offline',
      ),
      findsOneWidget,
    );
    await _letSnackBarGo(tester);

    node
      ..offline = false
      ..connected = false;
    _tapSpan(tester, _add);
    await tester.pumpAndSettle();
    expect(find.text('Not connected'), findsOneWidget);
    expect(node.added, isEmpty);
  });
}
