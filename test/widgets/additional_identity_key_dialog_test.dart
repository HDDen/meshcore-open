import 'dart:typed_data';
import 'dart:async';
import 'package:meshcore_open/utils/keys.dart';
import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/meshcore_expanded_identity.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/services/additional_identity_vault.dart';
import 'package:meshcore_open/widgets/additional_identity_key_dialog.dart';

class _PendingSearch extends KeyPairSearcher {
  final results = <Completer<MCKeyPair?>>[];
  Completer<MCKeyPair?> get result => results.first;
  int cancellations = 0;

  @override
  void cancel() {
    cancellations++;
    super.cancel();
  }
  String? prefix;
  @override
  Future<MCKeyPair?> findMatchingKeyPair(String prefixStr, int maxMilliseconds) {
    prefix = prefixStr;
    final pending = Completer<MCKeyPair?>();
    results.add(pending);
    return pending.future;
  }
}

void main() {
  for (final locale in ['ru', 'en']) {
    testWidgets('key dialog derives a read-only public key ($locale)', (tester) async {
      final entry = (await tester.runAsync(() async {
        const seed = '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';
        final bytes = Uint8List.fromList((await Sha512().hash(hex.decode(seed))).bytes);
        bytes[0] &= 248;
        bytes[31] = (bytes[31] & 63) | 64;
        return AdditionalIdentityEntry.parse('Test key', hex.encode(bytes));
      }))!;
      late BuildContext screen;
      await tester.pumpWidget(MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          screen = context;
          return const Scaffold();
        }),
      ));
      void open({AdditionalIdentityEntry? previous, KeyPairSearcher? searcher}) {
        showDialog<AdditionalIdentityEntry>(
          context: screen,
          builder: (_) => AdditionalIdentityKeyDialog(previous: previous, keyPairSearcher: searcher),
        );
      }
      final l10n = AppLocalizations.of(screen);
      Finder field(String label) => find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.labelText == label,
      );
      final name = field(l10n.extraKeys_name);
      final secret = field(l10n.repeater_prvKey);
      final public = field(l10n.repeater_pubKey);
      String preview() => tester.widget<TextField>(public).controller!.text;
      Future<void> settlePreview() async {
        for (var i = 0; i < 30 && preview().isEmpty; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
        }
      }
      open();
      await tester.pumpAndSettle();
      expect(preview(), isEmpty);
      expect(tester.widget<TextField>(public).readOnly, isTrue);
      expect(tester.widget<TextField>(public).minLines, greaterThan(1));
      expect(tester.widget<TextField>(public).maxLines, isNull);
      expect(tester.getTopLeft(secret).dy, greaterThan(tester.getBottomLeft(name).dy));
      expect(tester.getTopLeft(public).dy, greaterThan(tester.getBottomLeft(secret).dy));
      await tester.enterText(secret, entry.identity.privateKeyHex);
      await settlePreview();
      expect(preview(), entry.identity.publicKeyHex);
      await tester.enterText(secret, 'invalid');
      await tester.pump();
      expect(preview(), isEmpty);
      await tester.enterText(secret, entry.identity.privateKeyHex);
      await tester.enterText(secret, '');
      await tester.pumpAndSettle();
      expect(preview(), isEmpty);
      final generateButton = find.byTooltip(l10n.repeater_generatePrvKey);
      await tester.ensureVisible(generateButton);
      final secretController = tester.widget<TextField>(secret).controller!;
      // Generation explicitly yields to event-queue timers. Start and await
      // the real crypto work in runAsync, then render it with fake-clock pumps.
      // Polling only the public preview can finish before a private key exists.
      await tester.runAsync(() async {
        final generated = Completer<void>();
        void keyChanged() {
          if (secretController.text.length == 128 && !generated.isCompleted) {
            generated.complete();
          }
        }
        secretController.addListener(keyChanged);
        try {
          await tester.tap(generateButton);
          await generated.future.timeout(const Duration(seconds: 5));
        } finally {
          secretController.removeListener(keyChanged);
        }
      });
      await tester.pumpAndSettle();
      final generated = secretController.text;
      expect(generated, matches(RegExp(r'^[a-fA-F0-9]{128}$')),
          reason: 'generation must finish before checking the derived public key');
      final derived = (await tester.runAsync(() => MeshCoreExpandedIdentity.fromHex(generated)))!;
      expect(preview(), derived.publicKeyHex);
      await tester.tap(find.text(l10n.common_cancel));
      await tester.pumpAndSettle();
      open(previous: entry);
      await tester.pumpAndSettle();
      expect(preview(), entry.identity.publicKeyHex);
      await tester.tap(find.text(l10n.common_cancel));
      await tester.pumpAndSettle();
      final pending = _PendingSearch();
      open(previous: entry, searcher: pending);
      await tester.pumpAndSettle();
      final prefix = field(l10n.repeater_pubKeyPrefix);
      await tester.ensureVisible(prefix);
      await tester.enterText(prefix, 'ABCDFxyz');
      expect(tester.widget<TextField>(prefix).controller!.text, 'ABCD');
      final generate = find.byTooltip(l10n.repeater_generatePrvKey);
      await tester.ensureVisible(generate);
      await tester.tap(generate);
      await tester.pump(const Duration(milliseconds: 100));
      expect(pending.prefix, 'abcd');
      final stop = find.byTooltip(l10n.repeater_stopGeneratingPrvKey);
      expect(stop, findsOneWidget);
      await tester.tap(stop);
      await tester.pumpAndSettle();
      expect(pending.cancellations, 1);
      expect(find.byTooltip(l10n.repeater_generatePrvKey), findsOneWidget);
      await tester.tap(find.byTooltip(l10n.repeater_generatePrvKey));
      await tester.pump(const Duration(milliseconds: 100));
      expect(pending.results, hasLength(2));
      // A result from the stopped search must not overwrite the key or stop
      // the new search, even if it arrives while that new search is active.
      pending.result.complete(MCKeyPair(Uint8List(32)..[0] = 0x11, Uint8List(64)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byTooltip(l10n.repeater_stopGeneratingPrvKey), findsOneWidget);
      expect(tester.widget<TextField>(secret).controller!.text, entry.identity.privateKeyHex);
      await tester.tap(find.byTooltip(l10n.repeater_stopGeneratingPrvKey));
      await tester.pumpAndSettle();
      expect(pending.cancellations, 2);
      pending.results[1].complete(MCKeyPair(Uint8List(32)..[0] = 0x22, Uint8List(64)));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(secret).controller!.text, entry.identity.privateKeyHex);
      expect(preview(), entry.identity.publicKeyHex);
      await tester.tap(find.text(l10n.common_cancel));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
