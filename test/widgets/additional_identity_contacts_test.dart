import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/additional_identity_message.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/services/additional_identity_inbox.dart';
import 'package:meshcore_open/services/additional_identity_vault.dart';
import 'package:meshcore_open/widgets/additional_identity_contacts.dart';
import 'package:meshcore_open/widgets/unread_badge.dart';

class _Connector implements MeshCoreConnector {
  @override
  String selfPublicKeyHex = '';

  @override
  int get pathHashByteWidth => 1;

  @override
  Contact? getContactByPubKeyHex(String publicKeyHex) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _Inbox extends AdditionalIdentityInbox {
  List<AdditionalIdentityThread> _threads = const [];

  @override
  Future<List<AdditionalIdentityThread>> threads(String recipientKey) async =>
      _threads;

  void updateThreads(List<AdditionalIdentityThread> threads) {
    _threads = threads;
    notifyListeners();
  }
}

Future<AdditionalIdentityEntry> _testEntry({
  String seedHex = '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
}) async {
  final seed = hex.decode(seedHex);
  final expanded = Uint8List.fromList((await Sha512().hash(seed)).bytes);
  expanded[0] &= 248;
  expanded[31] = (expanded[31] & 63) | 64;
  return AdditionalIdentityEntry.parse('Extra key', hex.encode(expanded));
}

void main() {
  testWidgets('the primary node key has no duplicate group and reappears after a node switch', (tester) async {
    final primary = await _testEntry();
    final other = await _testEntry(
      seedHex: '4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb',
    );
    final inbox = _Inbox()..unlock([primary, other]);
    addTearDown(inbox.dispose);
    final connector = _Connector()..selfPublicKeyHex = primary.identity.publicKeyHex;
    Future<void> show() async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AdditionalIdentityContacts(
          inbox: inbox, connector: connector,
        )),
      ));
      await tester.pumpAndSettle();
    }
    Finder card(AdditionalIdentityEntry entry) => find.byKey(
      ValueKey('additional-identity:${entry.identity.publicKeyHex}'),
    );

    await show();
    expect(card(primary), findsNothing);
    expect(card(other), findsOneWidget);
    connector.selfPublicKeyHex = other.identity.publicKeyHex;
    await show();
    expect(card(primary), findsOneWidget);
    expect(card(other), findsNothing);
    connector.selfPublicKeyHex = '';
    await show();
    expect(card(primary), findsOneWidget);
    expect(card(other), findsOneWidget);
    expect(inbox.entries, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('history updates refresh an expanded additional key group', (
    tester,
  ) async {
    final entry = await _testEntry();
    final inbox = _Inbox()..unlock([entry]);
    addTearDown(inbox.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AdditionalIdentityContacts(
            inbox: inbox,
            connector: _Connector(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(entry.name));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.remove), findsOneWidget);
    expect(find.text('Peer'), findsNothing);

    final thread = (
      senderKey: 'ab' * 32,
      senderName: 'Peer',
      peerType: advTypeChat,
      unread: 0,
    );
    inbox.updateThreads([thread]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.remove), findsOneWidget);
    expect(find.text('Peer'), findsOneWidget);
    expect(find.byType(UnreadBadge), findsNothing);

    inbox.updateThreads([
      (
        senderKey: thread.senderKey,
        senderName: thread.senderName,
        peerType: thread.peerType,
        unread: 1,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(UnreadBadge), findsNWidgets(2));
    final tile = find.widgetWithText(ListTile, 'Peer');
    final badge = find.descendant(of: tile, matching: find.byType(UnreadBadge));
    expect(
      tester.getRect(badge).left,
      greaterThan(tester.getRect(find.text('Peer')).right),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
