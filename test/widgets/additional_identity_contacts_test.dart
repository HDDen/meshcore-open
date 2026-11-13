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

Future<AdditionalIdentityEntry> _testEntry() async {
  final seed = hex.decode(
    '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
  );
  final expanded = Uint8List.fromList((await Sha512().hash(seed)).bytes);
  expanded[0] &= 248;
  expanded[31] = (expanded[31] & 63) | 64;
  return AdditionalIdentityEntry.parse('Extra key', hex.encode(expanded));
}

void main() {
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
