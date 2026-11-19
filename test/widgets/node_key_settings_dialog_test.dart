import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/backup_node_identity.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/services/adaptive_tx_power.dart';
import 'package:meshcore_open/services/additional_identity_vault.dart';
import 'package:meshcore_open/widgets/node_key_settings_dialog.dart';

class _Node extends MeshCoreConnector {
  _Node(this.entry);
  final AdditionalIdentityEntry entry;
  int revision = 1;
  int exports = 0;
  bool refused = false;
  final written = <BackupNodeIdentityPreview>[];
  @override
  bool get isSessionReady => true;
  @override
  String get deviceDisplayName => entry.name;
  @override
  TxPowerSession get txPowerSession => (nodeKey: entry.identity.publicKeyHex, revision: revision);
  @override
  Future<AdditionalIdentityEntry?> exportNodeIdentity(TxPowerSession session, {required String name}) async {
    exports++;
    return refused ? null : entry;
  }
  @override
  BackupNodeIdentityPreview? previewBackupNodeIdentity(BackupNodeIdentity source) => (
    session: revision, destinationKey: entry.identity.publicKeyHex,
    destinationName: entry.name, source: source,
  );
  @override
  Future<BackupNodeIdentityResult> restoreBackupNodeIdentity(BackupNodeIdentityPreview preview) async {
    written.add(preview);
    return (written: true, status: BackupNodeIdentityStatus.completed);
  }
}

void main() {
  Future<AdditionalIdentityEntry> identity(String seed) async {
    final bytes = Uint8List.fromList((await Sha512().hash(hex.decode(seed))).bytes);
    bytes[0] &= 248;
    bytes[31] = (bytes[31] & 63) | 64;
    return AdditionalIdentityEntry.parse('Radio', hex.encode(bytes));
  }
  for (final locale in ['ru', 'en']) {
    for (final action in ['close', 'unchanged', 'save', 'changed-session', 'refused']) {
      testWidgets('node key editor $action ($locale)', (tester) async {
        final original = (await tester.runAsync(() => identity(
          '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
        )))!;
        final replacement = (await tester.runAsync(() => identity(
          '4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb',
        )))!;
        final node = _Node(original)..refused = action == 'refused';
        addTearDown(node.dispose);
        late BuildContext screen;
        await tester.pumpWidget(MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(builder: (context) {
            screen = context;
            return Scaffold(body: TextButton(
              child: const Text('Open'),
              onPressed: () => showDialog<void>(
                context: context, builder: (_) => NodeKeySettingsDialog(connector: node),
              ),
            ));
          }),
        ));
        final l10n = AppLocalizations.of(screen);
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(node.exports, 1);
        if (action == 'refused') {
          expect(find.text(l10n.extraKeys_nodeExportUnavailable), findsOneWidget);
          expect(find.text(l10n.common_save), findsNothing);
        } else {
          expect(find.text(l10n.extraKeys_name), findsNothing);
          expect(find.text(l10n.extraKeys_encrypted), findsNothing);
          Finder field(String label) => find.byWidgetPredicate(
            (widget) => widget is TextField && widget.decoration?.labelText == label,
          );
          final secret = field(l10n.repeater_prvKey);
          final public = field(l10n.repeater_pubKey);
          expect(tester.widget<TextField>(secret).controller!.text, original.identity.privateKeyHex);
          expect(tester.widget<TextField>(public).controller!.text, original.identity.publicKeyHex);
          expect(tester.widget<TextField>(public).readOnly, isTrue);
          if (action == 'save' || action == 'changed-session') {
            await tester.enterText(secret, replacement.identity.privateKeyHex);
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
            await tester.pump();
          }
          if (action == 'changed-session') node.revision++;
          if (action != 'close') {
            await tester.tap(find.text(l10n.common_save));
            // Key validation is asynchronous; allow it to finish outside fake time.
            for (var i = 0; i < 20; i++) {
              await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
              await tester.pump(const Duration(milliseconds: 50));
            }
            if (action == 'save') {
              expect(node.written.single.source.publicKey, replacement.identity.publicKeyHex);
              expect(find.text(l10n.backupIdentity_completed), findsOneWidget);
            } else if (action == 'changed-session') {
              expect(find.text(l10n.backupIdentity_notReady), findsOneWidget);
            } else {
              expect(find.byType(NodeKeySettingsDialog), findsNothing);
            }
          }
        }
        if (action != 'save') expect(node.written, isEmpty);
        if (find.text(l10n.common_close).evaluate().isNotEmpty) {
          await tester.tap(find.text(l10n.common_close));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
