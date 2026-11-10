import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/backup_channel_restore.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/l10n/l10n.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/screens/backup_channel_restore_screen.dart';
import 'package:meshcore_open/services/backup_file_codec.dart';
import 'package:provider/provider.dart';

final _key = List.filled(32, 'ab').join();

Channel _channel(int slot, String name, int key) =>
    Channel(index: slot, name: name, psk: Uint8List.fromList(List.filled(16, key)));

class _Node extends ChangeNotifier implements MeshCoreConnector {
  final current = [
    _channel(0, 'Other', 1),
    _channel(2, 'Current name', 2),
    _channel(3, 'Conflict', 4),
  ];
  bool ready = true;
  int writes = 0;
  BackupChannelRestorePreview? appliedPreview;
  BackupChannelRestoreResult result = (
    confirmed: 2,
    status: BackupChannelRestoreStatus.completed,
  );

  @override
  String get deviceDisplayName => 'Test node';

  @override
  BackupChannelRestorePreview? previewBackupChannelRestore(
    Iterable<Channel> source,
  ) => ready
      ? BackupChannelRestorePreview(
          nodeKey: _key,
          session: this,
          capacity: 4,
          current: current,
          source: source,
        )
      : null;

  @override
  Future<BackupChannelRestoreResult> restoreBackupChannels(
    BackupChannelRestorePreview preview,
  ) async {
    writes++;
    appliedPreview = preview;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _officialBackup() => jsonEncode({
  'public_key': _key,
  'channels': [
    {'name': 'From backup', 'secret': List.filled(16, '02').join()},
    {'name': 'New channel', 'secret': List.filled(16, '03').join()},
    {'name': 'Conflict', 'secret': List.filled(16, '05').join()},
    {'name': 'No room', 'secret': List.filled(16, '06').join()},
  ],
});

Future<AppLocalizations> _show(
  WidgetTester tester,
  _Node node,
  String contents, {
  String language = 'en',
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<MeshCoreConnector>.value(
      value: node,
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BackupChannelRestoreScreen(
          pickFile: () async => XFile.fromData(
            Uint8List.fromList(utf8.encode(contents)),
            name: 'backup.json',
          ),
        ),
      ),
    ),
  );
  return tester.element(find.byType(BackupChannelRestoreScreen)).l10n;
}

Future<void> _waitAfterTap(
  WidgetTester tester,
  Finder button,
  Finder expected,
) async {
  // File reading and compute run in real async time.
  await tester.runAsync(() async {
    await tester.tap(button);
    final clock = Stopwatch()..start();
    while (clock.elapsed < const Duration(seconds: 12)) {
      await tester.pump(const Duration(milliseconds: 25));
      if (expected.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  expect(expected, findsOneWidget);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _openConfirm(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  final restore = find.text(l10n.backupChannels_apply);
  await tester.ensureVisible(restore);
  await tester.pump();
  await tester.tap(restore.hitTestable());
  await tester.pumpAndSettle();
  expect(
    find.text(l10n.backupChannels_confirm('Test node', 2)),
    findsOneWidget,
  );
}

void main() {
  for (final language in ['ru', 'en']) {
    testWidgets('shows planned changes and writes only after confirmation ($language)',
        (tester) async {
      final node = _Node();
      addTearDown(node.dispose);
      final l10n = await _show(tester, node, _officialBackup(), language: language);
      await _waitAfterTap(
        tester,
        find.text(l10n.backupChannels_choose),
        find.text(l10n.backupChannels_rename('Current name', 2)),
      );
      expect(find.text(l10n.backupChannels_add(1)), findsOneWidget);
      expect(find.text(l10n.backupChannels_nameConflict), findsOneWidget);
      expect(find.text(l10n.channels_noFreeSlots), findsOneWidget);
      expect(node.writes, 0);

      await _openConfirm(tester, l10n);
      await tester.tap(find.text(l10n.common_cancel));
      await tester.pumpAndSettle();
      expect(node.writes, 0);

      await _openConfirm(tester, l10n);
      final dialog = find.byType(AlertDialog);
      await tester.tap(find.descendant(
        of: dialog,
        matching: find.text(l10n.backupChannels_apply),
      ));
      await tester.pumpAndSettle();
      expect(node.writes, 1);
      expect(node.appliedPreview!.decisions.first.destination!.index, 2);
      expect(find.text(l10n.backupChannels_applied(2)), findsOneWidget);
    });
  }

  testWidgets('a stale preview requires another refresh and confirmation',
      (tester) async {
    final node = _Node()..ready = false;
    addTearDown(node.dispose);
    final l10n = await _show(tester, node, _officialBackup());
    await _waitAfterTap(
      tester,
      find.text(l10n.backupChannels_choose),
      find.text(l10n.backupChannels_waitForNode),
    );
    expect(find.text(l10n.backupChannels_apply), findsNothing);
    node.ready = true;
    await tester.tap(find.text(l10n.backupChannels_preview));
    await tester.pumpAndSettle();
    await _openConfirm(tester, l10n);

    node.result = (
      confirmed: 0,
      status: BackupChannelRestoreStatus.destinationChanged,
    );
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(l10n.backupChannels_apply),
    ));
    await tester.pumpAndSettle();
    expect(find.text(l10n.backupChannels_changed(0)), findsOneWidget);
    expect(find.text(l10n.backupChannels_apply), findsNothing);
    expect(node.writes, 1);
  });

  testWidgets('an encrypted backup can be retried after a wrong password',
      (tester) async {
    const password = 'test-password';
    final encrypted = (await tester.runAsync(
      () => const BackupFileCodec().encode({
        'format': 'meshcore-open-backup',
        'version': 1,
        'sourcePublicKey': _key,
        'items': ['channels'],
        'sections': {
          'channels': {
            'preferences': {
              'channelsababababab': [
                {'index': 1, 'name': 'Private', 'psk': base64Encode(List.filled(16, 3))},
              ],
            },
          },
        },
      }, password: password),
    ))!;
    final node = _Node();
    addTearDown(node.dispose);
    final l10n = await _show(tester, node, encrypted);
    final field = find.byType(TextField);
    await _waitAfterTap(tester, find.text(l10n.backupChannels_choose), field);
    expect(tester.widget<TextField>(field).obscureText, isTrue);
    await tester.enterText(field, 'wrong-password');
    await tester.pump();
    await _waitAfterTap(
      tester,
      find.text(l10n.common_ok),
      find.text(l10n.backupChannels_badPassword),
    );
    await tester.enterText(field, password);
    await tester.pump();
    await _waitAfterTap(
      tester,
      find.text(l10n.common_ok),
      find.text(l10n.backupChannels_add(1)),
    );
    expect(find.text(password), findsNothing);
    expect(node.writes, 0);
  });
}
