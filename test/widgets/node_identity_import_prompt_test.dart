import 'dart:async';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/services/adaptive_tx_power.dart';
import 'package:meshcore_open/services/additional_identity_inbox.dart';
import 'package:meshcore_open/services/additional_identity_vault.dart';
import 'package:meshcore_open/utils/keys.dart';
import 'package:meshcore_open/widgets/node_identity_import_prompt.dart';

import '../support/history_test_environment.dart';

class _Node extends MeshCoreConnector {
  _Node(this.entry) : super(additionalIdentityInbox: AdditionalIdentityInbox());

  final AdditionalIdentityEntry entry;
  int revision = 1;
  int exports = 0;

  @override
  bool get isConnected => true;

  @override
  bool get isSessionReady => true;

  @override
  bool get hasCompletedSelfInfoHandshake => true;

  @override
  String get selfName => entry.name;

  @override
  TxPowerSession get txPowerSession => (
    nodeKey: entry.identity.publicKeyHex,
    revision: revision,
  );

  @override
  Future<AdditionalIdentityEntry?> exportNodeIdentity(
    TxPowerSession session, {
    required String name,
  }) async {
    exports++;
    expect(session, txPowerSession);
    expect(name, entry.name);
    return entry;
  }
}

class _ExportNode extends MeshCoreConnector {
  @override
  bool get isConnected => true;

  @override
  bool get isSessionReady => true;
}

void main() {
  final history = HistoryTestEnvironment();
  late _Node node;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await history.setUp();
    MCKeyPair pair;
    do {
      pair = await generateKeyPair();
    } while (pair.public.first == 0 || pair.public.first == 0xff);
    final entry = await AdditionalIdentityEntry.parse(
      'Test radio',
      hex.encode(pair.private),
    );
    node = _Node(entry);
  });

  tearDown(() async {
    node.dispose();
    await history.tearDown();
  });

  Future<BuildContext> pumpScreen(WidgetTester tester) async {
    late BuildContext screen;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            screen = context;
            return const Scaffold();
          },
        ),
      ),
    );
    return screen;
  }

  Future<AppLocalizations> showPrompt(WidgetTester tester) async {
    final screen = await pumpScreen(tester);
    final l10n = AppLocalizations.of(screen);
    unawaited(NodeIdentityImportPrompt.show(screen, node, node.txPowerSession));
    await tester.pumpAndSettle();
    expect(find.text(l10n.extraKeys_importNodePrompt), findsOneWidget);
    expect(node.exports, 0);
    return l10n;
  }

  testWidgets('an identity already saved in a locked vault skips the prompt', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final vault = await AdditionalIdentityVault.open(
        password: 'test vault password',
        saved: null,
      );
      await vault.save(node.entry);
    });
    final screen = await pumpScreen(tester);
    expect(node.additionalIdentityInbox!.isUnlocked, isFalse);
    var checked = false;
    unawaited(NodeIdentityImportPrompt.show(screen, node, node.txPowerSession)
        .then((_) => checked = true));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(checked, isTrue);
    expect(node.exports, 0);
  });

  testWidgets('declining remembers the node across reconnects without export', (
    tester,
  ) async {
    final l10n = await showPrompt(tester);
    await tester.tap(find.text(l10n.common_cancel));
    await tester.pumpAndSettle();

    node.revision++;
    expect(NodeIdentityImportPrompt.shouldOffer(node, node.txPowerSession), isFalse);
    expect(node.exports, 0);
  });

  testWidgets('cancelling vault creation after consent skips export', (
    tester,
  ) async {
    final l10n = await showPrompt(tester);
    await tester.tap(find.text(l10n.common_ok));
    await tester.pumpAndSettle();

    expect(find.text(l10n.extraKeys_setPassword), findsOneWidget);
    expect(node.exports, 0);
    await tester.tap(find.text(l10n.common_cancel));
    await tester.pumpAndSettle();
    expect(NodeIdentityImportPrompt.shouldOffer(node, node.txPowerSession), isTrue);
    expect(node.exports, 0);
  });

  test('the connector validates the exported identity and handles refusal', () async {
    final radio = _ExportNode();
    addTearDown(radio.dispose);
    final identity = node.entry.identity;
    final key = identity.publicKey;
    final info = Uint8List(64)
      ..[0] = respCodeSelfInfo
      ..[1] = advTypeChat
      ..[2] = 11
      ..[3] = 22
      ..setRange(4, 36, key)
      ..setRange(58, 62, 'Node'.codeUnits);
    radio.setCachedSelfInfoKeyForTest(key);
    var exports = 0;
    var reply = <int>[respCodePrivateKey, ...hex.decode(identity.privateKeyHex)];
    radio.setFrameWriterForTest((frame) async {
      if (frame.first == cmdAppStart) {
        radio.handleFrameForTest(info);
      } else if (frame.first == cmdExportPrivateKey) {
        exports++;
        radio.handleFrameForTest(reply);
      }
    });
    await radio.refreshDeviceInfo();
    final session = radio.txPowerSession!;
    expect(radio.hasCompletedSelfInfoHandshake, isTrue);
    expect(exports, 0);

    final entry = await radio.exportNodeIdentity(session, name: 'Node');
    expect(entry?.name, 'Node');
    expect(entry?.identity.publicKeyHex, identity.publicKeyHex);
    expect(exports, 1);

    reply = [respCodeDisabled];
    expect(await radio.exportNodeIdentity(session, name: 'Node'), isNull);

    radio.resetConnectionHandshakeForTest();
    await expectLater(
      radio.exportNodeIdentity(session, name: 'Node'),
      throwsStateError,
    );
    expect(exports, 2);
  });

  testWidgets('consent after the radio changed does not export any key', (
    tester,
  ) async {
    final l10n = await showPrompt(tester);
    node.revision++;
    await tester.tap(find.text(l10n.common_ok));
    await tester.pumpAndSettle();

    expect(NodeIdentityImportPrompt.shouldOffer(node, node.txPowerSession), isTrue);
    expect(node.exports, 0);
  });
}
