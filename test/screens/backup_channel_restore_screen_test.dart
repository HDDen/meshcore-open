import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/backup_channel_restore.dart';
import 'package:meshcore_open/helpers/backup_channel_settings.dart';
import 'package:meshcore_open/helpers/backup_communities.dart';
import 'package:meshcore_open/helpers/backup_contact_restore.dart';
import 'package:meshcore_open/helpers/backup_contact_settings.dart';
import 'package:meshcore_open/helpers/backup_discovered_contacts.dart';
import 'package:meshcore_open/helpers/backup_message_filter.dart';
import 'package:meshcore_open/helpers/backup_message_history.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/l10n/l10n.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/app_settings_backup.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/community.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/message_filter.dart';
import 'package:meshcore_open/screens/backup_export_screen.dart';
import 'package:meshcore_open/screens/backup_restore_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/backup_file_codec.dart';
import 'package:meshcore_open/services/backup_import_planner.dart';
import 'package:meshcore_open/services/backup_snapshot.dart';
import 'package:meshcore_open/services/message_filter/message_filter_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/utils/backup_json_file.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _key = List.filled(32, 'ab').join();

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('In-memory backup test preferences');
  }
}

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
  int contactWrites = 0;
  int contactSettingsWrites = 0;
  int channelSettingsWrites = 0;
  int historyWrites = 0;
  int discoveryWrites = 0;
  int communityWrites = 0;
  ({bool direct, bool channels})? historyExportSelection;
  BackupChannelRestorePreview? appliedPreview;
  BackupChannelRestoreResult result = (
    confirmed: 2,
    status: BackupChannelRestoreStatus.completed,
  );

  @override
  String get deviceDisplayName => 'Test node';

  @override
  Future<BackupSnapshot?> snapshotNodeBackup({
    required bool includeChannels,
    required bool includeContacts,
    AppSettingsBackup? appSettings,
    bool includeDiscoveredContacts = false,
    bool includeContactGroups = false,
    bool includeCommunities = false,
    bool includeContactSettings = false,
    bool includeChannelSettings = false,
  }) async => ready
      ? BackupSnapshot(
          sourcePublicKey: _key,
          nodeName: deviceDisplayName,
          channels: includeChannels ? current : null,
          contacts: includeContacts
              ? [
                  Contact(
                    publicKey: Uint8List.fromList(List.filled(32, 0x99)),
                    name: 'Saved contact',
                    type: 1,
                    pathLength: -1,
                    path: Uint8List(0),
                    lastSeen: DateTime.utc(2026),
                  ),
                ]
              : null,
          createdAt: DateTime.utc(2026),
          appSettings: appSettings,
        )
      : null;

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
  BackupContactRestorePreview? previewBackupContactRestore({
    required String? sourcePublicKey,
    required Iterable<Contact> contacts,
  }) => ready
      ? BackupContactRestorePreview(
          nodeKey: _key,
          session: this,
          capacity: 2,
          supportsWidePaths: true,
          currentKeys: [List.filled(32, '02').join()],
          sourcePublicKey: sourcePublicKey,
          contacts: contacts,
        )
      : null;

  @override
  Future<BackupContactRestoreResult> restoreBackupContacts(
    BackupContactRestorePreview preview,
  ) async {
    contactWrites++;
    return (confirmed: 1, status: BackupContactRestoreStatus.completed);
  }

  @override
  BackupMessageHistoryPreview? previewBackupMessageHistory(
    BackupMessageHistory source,
  ) => ready && source.nodeKey == _key
      ? source.preview(destination: current, session: this)
      : null;

  @override
  Future<int?> restoreBackupMessageHistory(
    BackupMessageHistoryPreview preview,
  ) async {
    historyWrites++;
    return preview.count;
  }

  @override
  BackupDiscoveredContactsPreview? previewBackupDiscoveredContacts(String json) =>
      ready ? BackupDiscoveredContactsPreview(
        sourceJson: json,
        current: const [],
        knownContactKeys: const {},
        nodeKey: _key,
        capacity: 2,
        session: this,
      ) : null;

  @override
  Future<int?> restoreBackupDiscoveredContacts(
    BackupDiscoveredContactsPreview preview,
  ) async {
    discoveryWrites++;
    return preview.contacts.length;
  }

  @override
  Future<BackupChannelSettingsPreview?> previewBackupChannelSettings(
    BackupChannelSettings source,
  ) async => source.preview(
    session: this,
    bindings: backupChannelBindings(current),
    current: const {},
    canRestoreOrder: true,
    hasCyr2LatProfile: (_) => false,
    hasRegion: (_) => false,
  );

  @override
  Future<({int count, bool completed})?> restoreBackupChannelSettings(
    BackupChannelSettingsPreview preview,
  ) async {
    channelSettingsWrites++;
    return (count: preview.count, completed: true);
  }

  @override
  BackupContactSettingsPreview? previewBackupContactSettings(
    BackupContactSettings source,
  ) => source.preview(
    session: this,
    destinationKeys: source.contacts,
    current: BackupContactSettings({}),
    hasCyr2LatProfile: (_) => false,
  );

  @override
  Future<int?> restoreBackupContactSettings(BackupContactSettingsPreview preview) async {
    contactSettingsWrites++;
    return preview.additions.values.length;
  }

  @override
  Future<BackupCommunitiesPreview?> previewBackupCommunities(
    List<Community> incoming,
  ) async => BackupCommunitiesPreview(
    session: this,
    expectedValue: null,
    current: const [],
    incoming: incoming,
  );

  @override
  Future<int?> restoreBackupCommunities(BackupCommunitiesPreview preview) async {
    communityWrites++;
    return preview.added.length;
  }

  @override
  Future<BackupSnapshot?> snapshotMessageHistoryBackup({
    required bool includeDirect,
    required bool includeChannels,
  }) async {
    historyExportSelection = (direct: includeDirect, channels: includeChannels);
    return null;
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
  bool contactsMode = false,
  bool historyMode = false,
}) async {
  Future<XFile?> pickFile() async => XFile.fromData(
    Uint8List.fromList(utf8.encode(contents)),
    name: 'backup.json',
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<MeshCoreConnector>.value(
      value: node,
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: historyMode
            ? BackupRestoreScreen.messageHistory(pickFile: pickFile)
            : contactsMode
            ? BackupRestoreScreen.contacts(pickFile: pickFile)
            : BackupRestoreScreen.channels(pickFile: pickFile),
      ),
    ),
  );
  return tester.element(find.byType(BackupRestoreScreen)).l10n;
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
  testWidgets('restores filter preferences without a node after confirmation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    addTearDown(PrefsManager.reset);
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferencesDirectory();
    addTearDown(() => PathProviderPlatform.instance = previousPaths);
    await tester.runAsync(PrefsManager.initialize);
    final filter = MessageFilterService()..load();
    addTearDown(filter.dispose);
    const rule = FilterRule(id: 'advert', pattern: 'buy now');
    final contents = await BackupSnapshot(
      messageFilter: BackupMessageFilter.capture(
        const MessageFilterSettings(enabled: true, learning: true, duplicates: true),
        const [rule],
      ),
      createdAt: DateTime.utc(2026),
    ).encode(password: '');

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: BackupRestoreScreen.messageFilter(
        filter,
        pickFile: () async => XFile.fromData(
          Uint8List.fromList(utf8.encode(contents)), name: 'filter.json',
        ),
      ),
    ));
    final l10n = tester.element(find.byType(BackupRestoreScreen)).l10n;
    await _waitAfterTap(
      tester,
      find.text(l10n.backupChannels_choose),
      find.text(l10n.backupMessageFilter_summary(1, 1)),
    );
    expect(filter.rules, isEmpty);
    final restore = find.widgetWithText(FilledButton, l10n.backupChannels_apply);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(find.text(l10n.backupMessageFilter_confirm), findsOneWidget);
    expect(filter.settings.duplicates, isFalse);
    await _waitAfterTap(
      tester,
      find.descendant(of: find.byType(AlertDialog), matching: restore),
      find.text(l10n.backupMessageFilter_applied),
    );
    expect(filter.rules, [rule]);
    expect(filter.settings.duplicates, isTrue);
    expect(filter.settings.enabled, isFalse);
    expect(filter.settings.learning, isFalse);
  });

  testWidgets('channel settings preview includes order and requires confirmation', (tester) async {
    final node = _Node();
    addTearDown(node.dispose);
    final first = node.current[0].storageId!;
    final second = node.current[1].storageId!;
    final contents = await BackupSnapshot(
      sourcePublicKey: _key,
      channelSettings: BackupChannelSettings(
        {(first, BackupChannelOption.urlImages): false}, [second, first],
      ),
      createdAt: DateTime.utc(2026),
    ).encode(password: '');
    await tester.pumpWidget(
      ChangeNotifierProvider<MeshCoreConnector>.value(
        value: node,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BackupRestoreScreen.channelSettings(
            pickFile: () async => XFile.fromData(
              Uint8List.fromList(utf8.encode(contents)),
              name: 'channel-settings.json',
            ),
          ),
        ),
      ),
    );
    final l10n = tester.element(find.byType(BackupRestoreScreen)).l10n;
    await _waitAfterTap(
      tester,
      find.text(l10n.backupChannels_choose),
      find.text(l10n.backupChannelSettings_summary(2, 0)),
    );
    expect(find.text(l10n.backupChannelSettings_includesOrder), findsOneWidget);
    expect(node.channelSettingsWrites, 0);
    final restore = find.widgetWithText(FilledButton, l10n.backupChannels_apply);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(find.text(l10n.backupChannelSettings_confirm('Test node', 2)), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: restore));
    await tester.pumpAndSettle();
    expect(find.text(l10n.backupChannelSettings_applied(2)), findsOneWidget);
    expect(node.channelSettingsWrites, 1);
    expect(node.writes, 0);
  });

  testWidgets('individual contact settings require confirmation', (tester) async {
    final node = _Node();
    addTearDown(node.dispose);
    final contents = await BackupSnapshot(
      sourcePublicKey: _key,
      contactSettings: BackupContactSettings({('cd' * 32, 'url_images_enabled'): '0'}),
      createdAt: DateTime.utc(2026),
    ).encode(password: '');
    await tester.pumpWidget(
      ChangeNotifierProvider<MeshCoreConnector>.value(
        value: node,
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BackupRestoreScreen.contactSettings(
            pickFile: () async => XFile.fromData(
              Uint8List.fromList(utf8.encode(contents)),
              name: 'contact-settings.json',
            ),
          ),
        ),
      ),
    );
    final l10n = tester.element(find.byType(BackupRestoreScreen)).l10n;
    await _waitAfterTap(
      tester,
      find.text(l10n.backupChannels_choose),
      find.text(l10n.backupContactSettings_summary(1, 0)),
    );
    final restore = find.widgetWithText(FilledButton, l10n.backupChannels_apply);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(find.text(l10n.backupContactSettings_confirm('Test node', 1)), findsOneWidget);
    expect(node.contactSettingsWrites, 0);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: restore));
    await tester.pumpAndSettle();
    expect(find.text(l10n.backupContactSettings_applied(1)), findsOneWidget);
    expect(node.contactSettingsWrites, 1);
    expect(node.contactWrites, 0);
  });

  for (final language in ['ru', 'en']) {
    testWidgets('community restore requires confirmation ($language)', (tester) async {
      final node = _Node();
      addTearDown(node.dispose);
      final contents = await BackupSnapshot(
        sourcePublicKey: _key,
        createdAt: DateTime.utc(2026),
        communities: [
          Community(
            id: 'local-id',
            name: 'Neighborhood mesh',
            secret: Uint8List.fromList(List.filled(32, 7)),
            createdAt: DateTime.utc(2026),
          ),
        ],
      ).encode(password: '');
      await tester.pumpWidget(
        ChangeNotifierProvider<MeshCoreConnector>.value(
          value: node,
          child: MaterialApp(
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: BackupRestoreScreen.communities(
              pickFile: () async => XFile.fromData(
                Uint8List.fromList(utf8.encode(contents)),
                name: 'communities.json',
              ),
            ),
          ),
        ),
      );
      final l10n = tester.element(find.byType(BackupRestoreScreen)).l10n;
      await _waitAfterTap(
        tester,
        find.text(l10n.backupChannels_choose),
        find.text(l10n.backupCommunities_summary(1, 0)),
      );
      expect(find.text('Neighborhood mesh'), findsOneWidget);
      expect(node.communityWrites, 0);

      final restore = find.widgetWithText(FilledButton, l10n.backupChannels_apply);
      await tester.ensureVisible(restore);
      await tester.pump();
      await tester.tap(restore);
      await tester.pumpAndSettle();
      expect(find.text(l10n.backupCommunities_confirm('Test node', 1)), findsOneWidget);
      await tester.tap(find.text(l10n.common_cancel));
      await tester.pumpAndSettle();
      expect(node.communityWrites, 0);

      await tester.tap(restore);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: restore));
      await tester.pumpAndSettle();
      expect(find.text(l10n.backupCommunities_applied(1)), findsOneWidget);
      expect(node.communityWrites, 1);
      expect(node.writes, 0);
    });
  }

  testWidgets('discovery backup is applied only after confirmation',
      (tester) async {
    final node = _Node();
    addTearDown(node.dispose);
    final contents = jsonEncode({
      'format': BackupFileCodec.payloadFormat,
      'version': BackupFileCodec.formatVersion,
      'sourcePublicKey': _key,
      'items': ['discoveredContacts'],
      'sections': {
        'discoveredContacts': {
          'preferences': {
            'discovered_contacts${_key.substring(0, 10)}': [
              {
                'publicKey': base64Encode(List.filled(32, 0x21)),
                'type': 2,
                'name': 'Imported discovery',
              },
            ],
          },
        },
      },
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<MeshCoreConnector>.value(
        value: node,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BackupRestoreScreen.discoveredContacts(
            pickFile: () async => XFile.fromData(
              Uint8List.fromList(utf8.encode(contents)),
              name: 'discovery-backup.json',
            ),
          ),
        ),
      ),
    );
    final l10n = tester.element(find.byType(BackupRestoreScreen)).l10n;
    await _waitAfterTap(
      tester,
      find.text(l10n.backupChannels_choose),
      find.text(l10n.backupDiscoveredContacts_summary(1, 0, 0, 0)),
    );
    expect(node.discoveryWrites, 0);
    final apply = find.text(l10n.backupChannels_apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(find.text(l10n.backupDiscoveredContacts_confirm(1)), findsOneWidget);
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: apply,
    ));
    await tester.pumpAndSettle();
    expect(find.text(l10n.discoveredContacts_imported(1)), findsOneWidget);
    expect(node.discoveryWrites, 1);
    expect(node.contactWrites, 0);
  });

  testWidgets('history export sends only its own selections to the connector',
      (tester) async {
    final node = _Node();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<MeshCoreConnector>.value(
        value: node,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const BackupExportScreen.messageHistory(),
        ),
      ),
    );
    final l10n = tester.element(find.byType(BackupExportScreen)).l10n;
    expect(find.text(l10n.backupMessageHistory_exportTitle), findsOneWidget);
    expect(find.text(l10n.settings_appSettings), findsNothing);
    final direct = find.widgetWithText(
      CheckboxListTile,
      l10n.backupMessageHistory_direct,
    );
    final channels = find.widgetWithText(
      CheckboxListTile,
      l10n.backupMessageHistory_channels,
    );
    final create = find.widgetWithText(
      FilledButton,
      l10n.backupChannels_createBackup,
    );
    await tester.tap(channels);
    await tester.pump();
    await tester.tap(direct);
    await tester.pump();
    expect(tester.widget<FilledButton>(create).onPressed, isNull);
    await tester.tap(direct);
    await tester.pump();
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(node.historyExportSelection, (direct: true, channels: false));
    expect(find.text(l10n.backupMessageHistory_exportNotReady), findsOneWidget);
  });

  testWidgets('history import waits for the source node and confirmation',
      (tester) async {
    final node = _Node()..ready = false;
    addTearDown(node.dispose);
    final storageId = node.current[1].storageId;
    final scope = _key.substring(0, 10);
    final contents = jsonEncode({
      'format': BackupFileCodec.payloadFormat,
      'version': BackupFileCodec.formatVersion,
      'sourcePublicKey': _key,
      'items': ['channelHistory'],
      'sections': {
        'channels': {
          'preferences': {
            'channel_messages_${scope}_$storageId': [
              {
                'messageId': 'one',
                'text': 'Saved channel message',
                'senderName': 'Sender',
                'timestamp': 1700000000000,
                'isOutgoing': false,
                'status': 1,
              },
            ],
          },
        },
      },
    });
    final l10n = await _show(tester, node, contents, historyMode: true);
    await _waitAfterTap(
      tester,
      find.text(l10n.backupChannels_choose),
      find.text(l10n.backupMessageHistory_waitForNode),
    );
    final apply = find.text(l10n.backupChannels_apply);
    expect(apply, findsNothing);
    node.ready = true;
    await tester.tap(find.text(l10n.backupChannels_preview));
    await tester.pump();
    expect(find.text(l10n.backupMessageHistory_summary(1, 0)), findsOneWidget);

    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(find.text(l10n.backupMessageHistory_confirm('Test node', 1)), findsOneWidget);
    await tester.tap(find.text(l10n.common_cancel));
    await tester.pumpAndSettle();
    expect(node.historyWrites, 0);

    await tester.tap(apply);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: apply,
    ));
    await tester.pumpAndSettle();
    expect(find.text(l10n.backupMessageHistory_applied(1)), findsOneWidget);
    expect(node.historyWrites, 1);
    expect(node.writes, 0);
    expect(node.contactWrites, 0);
  });

  testWidgets('app settings export and confirmed restore work without a node',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    addTearDown(PrefsManager.reset);
    final service = AppSettingsService();
    addTearDown(service.dispose);
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferencesDirectory();
    addTearDown(() => PathProviderPlatform.instance = previousPaths);
    await tester.runAsync(() async {
      await PrefsManager.initialize();
      await service.updateSettings(
        AppSettings(enableTimeSeconds: true, tcpServerAddress: 'private-address'),
      );
    });
    Future<void> show(Widget screen) => tester.pumpWidget(
      ChangeNotifierProvider<AppSettingsService>.value(
        value: service,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: screen,
        ),
      ),
    );

    String? contents;
    await show(BackupExportScreen.appSettings(
      saveFile: (value, name, {sharePositionOrigin}) async {
        contents = value;
        return BackupJsonSaveResult.saved;
      },
    ));
    final l10n = tester.element(find.byType(BackupExportScreen)).l10n;
    expect(find.text(l10n.channels_title), findsNothing);
    await tester.tap(
      find.widgetWithText(FilledButton, l10n.backupChannels_createBackup),
    );
    // The progress indicator keeps animating while the dialog awaits input.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final passwordDialog = find.byType(AlertDialog);
    expect(passwordDialog, findsOneWidget);
    await _waitAfterTap(
      tester,
      find.descendant(
        of: passwordDialog,
        matching: find.widgetWithText(FilledButton, l10n.common_save),
      ),
      find.text(l10n.backupExport_saved),
    );
    expect(contents, isNot(contains('private-address')));

    await tester.runAsync(
      () => service.updateSettings(
        service.settings.copyWith(enableTimeSeconds: false),
      ),
    );
    await show(BackupRestoreScreen.appSettings(
      pickFile: () async => XFile.fromData(
        Uint8List.fromList(utf8.encode(contents!)),
        name: 'settings.json',
      ),
    ));
    await _waitAfterTap(
      tester,
      find.text(l10n.backupChannels_choose),
      find.text(l10n.appSettings_enableTimeSeconds),
    );
    final restore = find.text(l10n.backupChannels_apply);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(find.text(l10n.backupAppSettings_confirm(1)), findsOneWidget);
    await tester.tap(find.text(l10n.common_cancel));
    await tester.pumpAndSettle();
    expect(service.settings.enableTimeSeconds, isFalse);

    await tester.tap(restore);
    await tester.pumpAndSettle();
    await _waitAfterTap(
      tester,
      find.descendant(of: find.byType(AlertDialog), matching: restore),
      find.text(l10n.backupAppSettings_applied(1)),
    );
    expect(service.settings.enableTimeSeconds, isTrue);
    expect(service.settings.tcpServerAddress, 'private-address');
  });

  testWidgets('contacts mode previews only available additions and confirms',
      (tester) async {
    final node = _Node();
    addTearDown(node.dispose);
    final contents = jsonEncode({
      'public_key': List.filled(32, 'ee').join(),
      'contacts': [
        for (final key in ['02', '03', '04'])
          {
            'public_key': List.filled(32, key).join(),
            'name': 'Contact $key',
            'type': 1,
            'out_path_list': 'ab',
          },
      ],
    });
    final l10n = await _show(tester, node, contents,
        contactsMode: true, language: 'ru');
    await _waitAfterTap(
      tester,
      find.text(l10n.backupChannels_choose),
      find.text(l10n.backupContacts_summary(1, 1, 1)),
    );
    expect(find.text(l10n.backupContacts_floodFallback), findsOneWidget);
    expect(find.text('Contact 03'), findsOneWidget);
    expect(find.text('Contact 02'), findsNothing);
    expect(find.text('Contact 04'), findsNothing);
    expect(node.contactWrites, 0);
    await tester.tap(find.text(l10n.backupChannels_apply));
    await tester.pumpAndSettle();
    expect(find.text(l10n.backupContacts_confirm('Test node', 1)), findsOneWidget);
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(l10n.backupChannels_apply),
    ));
    await tester.pumpAndSettle();
    expect(node.contactWrites, 1);
    expect(node.writes, 0);
    expect(find.text(l10n.backupContacts_applied(1)), findsOneWidget);
  });

  testWidgets('exports both selected lists with a confirmed password',
      (tester) async {
    final node = _Node()..ready = false;
    addTearDown(node.dispose);
    String? contents;
    String? name;
    await tester.pumpWidget(
      ChangeNotifierProvider<MeshCoreConnector>.value(
        value: node,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BackupExportScreen(
            saveFile: (value, fileName, {sharePositionOrigin}) async {
              contents = value;
              name = fileName;
              return BackupJsonSaveResult.saved;
            },
          ),
        ),
      ),
    );
    final l10n = tester.element(find.byType(BackupExportScreen)).l10n;
    final create = find.widgetWithText(
      FilledButton,
      l10n.backupChannels_createBackup,
    );
    await tester.ensureVisible(create);
    await tester.pump();
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(find.text(l10n.backupExport_notReady), findsOneWidget);
    expect(contents, isNull);

    node.ready = true;
    await tester.tap(create);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l10n.backupChannels_target('Test node')), findsOneWidget);
    await tester.tap(find.text(l10n.common_cancel));
    await tester.pumpAndSettle();
    expect(contents, isNull);

    final contacts = find.widgetWithText(CheckboxListTile, l10n.contacts_title);
    await tester.ensureVisible(contacts);
    await tester.pump();
    await tester.tap(contacts);
    await tester.pumpAndSettle();
    await tester.ensureVisible(create);
    await tester.pump();
    await tester.tap(create);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    const password = 'export-password';
    final fields = find.byType(TextField);
    expect(fields, findsOneWidget);
    await tester.enterText(fields.first, password);
    await tester.pump();
    final save = find.ancestor(
      of: find.text(l10n.common_save),
      matching: find.byType(FilledButton),
    );
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(fields.last, password);
    await tester.pump();

    await _waitAfterTap(
      tester,
      find.text(l10n.common_save),
      find.text(l10n.backupExport_saved),
    );
    expect(name, contains('Test node'));
    expect(name, startsWith('meshcore-backup-'));
    expect(contents, isNot(contains('Current name')));
    final decoded = await tester.runAsync(
      () => const BackupImportPlanner().inspect(contents!, password: password),
    );
    expect(decoded!.channels!.map((channel) => channel.index), [0, 2, 3]);
    expect(decoded.contacts!.single.name, 'Saved contact');
  });

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
