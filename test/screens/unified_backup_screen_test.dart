import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/portable_app_settings.dart';
import 'package:meshcore_open/helpers/mcoa_theme_options.dart';
import 'package:meshcore_open/theme/mcoa_theme_style.dart';
import 'package:meshcore_open/helpers/backup_node_identity.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/l10n/l10n.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/app_settings_backup.dart';
import 'package:meshcore_open/screens/backup_screen.dart';
import 'package:meshcore_open/services/adaptive_tx_power.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/backup_snapshot.dart';
import 'package:meshcore_open/services/backup_file_codec.dart';
import 'package:meshcore_open/services/message_filter/message_filter_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/utils/backup_json_file.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _OfflineNode extends ChangeNotifier implements MeshCoreConnector {
  @override
  bool get isSessionReady => false;
  @override
  bool get isOfflineMode => true;
  @override
  bool get isReviewMode => false;
  @override
  MessageFilterService? get messageFilterService => null;
  @override
  TxPowerSession? get txPowerSession => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IdentityNode extends _OfflineNode {
  int identityWrites = 0;

  @override
  BackupNodeIdentityPreview? previewBackupNodeIdentity(BackupNodeIdentity source) => (
    session: this, destinationKey: 'ab' * 32, destinationName: 'Test radio', source: source,
  );

  @override
  Future<BackupNodeIdentityResult> restoreBackupNodeIdentity(
    BackupNodeIdentityPreview preview,
  ) async {
    identityWrites++;
    return (written: true, status: BackupNodeIdentityStatus.completed);
  }
}

class _NoDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('In-memory backup preferences');
  }
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target, 350, scrollable: find.byType(Scrollable).first, maxScrolls: 80,
  );
  await tester.ensureVisible(target);
  await tester.pump();
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  await tester.runAsync(() async {
    final watch = Stopwatch()..start();
    while (!ready() && watch.elapsed < const Duration(seconds: 12)) {
      await tester.pump(const Duration(milliseconds: 25));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  expect(ready(), isTrue);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  late AppSettingsService service;
  late _OfflineNode node;
  late PathProviderPlatform originalPaths;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoDirectory();
    service = AppSettingsService();
    node = _OfflineNode();
  });
  tearDown(() {
    service.dispose();
    node.dispose();
    PrefsManager.reset();
    PathProviderPlatform.instance = originalPaths;
  });

  Future<AppLocalizations> show(
    WidgetTester tester, BackupScreen screen, {
    String language = 'en',
    double scale = 1,
    Color? warningColor,
  }) async {
    await tester.runAsync(() async {
      await PrefsManager.initialize();
      await service.updateSettings(AppSettings(
        suppressPhantomChannels: false,
        tcpServerAddress: 'keep-local-endpoint',
        uploadIpfsApiKey: 'keep-local-credential',
      ));
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<MeshCoreConnector>.value(value: node),
        ChangeNotifierProvider<AppSettingsService>.value(value: service),
      ],
      child: MaterialApp(
        theme: warningColor == null ? null : ThemeData(extensions: [
          McoaThemeStyle(McoaThemeOptions(colors: {'warning': warningColor})),
        ]),
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: screen,
      ),
    ));
    return tester.element(find.byType(BackupScreen)).l10n;
  }

  testWidgets('official format defaults off and leaves unsupported selection controls unchanged', (tester) async {
    await show(tester, const BackupScreen());
    final toggle = find.byKey(const ValueKey('backup-official-format'));
    await _reveal(tester, toggle);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    final mod = find.byKey(ValueKey('backup-${PortableAppSettings.extension}'));
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await tester.pump();
    await _reveal(tester, mod);
    expect(tester.widget<CheckboxListTile>(mod).onChanged, isNotNull);
    expect(tester.widget<CheckboxListTile>(mod).value, isTrue);
    await _reveal(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await tester.pump();
    await _reveal(tester, mod);
    expect(tester.widget<CheckboxListTile>(mod).value, isTrue);
    expect(tester.widget<CheckboxListTile>(mod).onChanged, isNotNull);
  });

  for (final language in ['en', 'ru']) {
    testWidgets('unified backup exports portable sections offline ($language, scale 2)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? contents;
      final l10n = await show(tester, BackupScreen(
        saveFile: (value, name, {sharePositionOrigin}) async {
          contents = value;
          return BackupJsonSaveResult.saved;
        },
      ), language: language, scale: 2);
      final create = find.widgetWithText(FilledButton, l10n.backupChannels_createBackup);
      await _reveal(tester, create);
      await tester.tap(create);
      await _waitFor(tester, () => contents != null);
      final file = jsonDecode(contents!) as Map<String, dynamic>;
      expect(file['items'], containsAll(['appSettings', PortableAppSettings.extension]));
      expect(file['items'], isNot(contains('contacts')));
      expect(contents, isNot(contains('keep-local-credential')));
      expect(contents, isNot(contains('keep-local-endpoint')));
      expect(find.text(l10n.backupExport_saved), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('display and portable settings in one backup have distinct restore rows', (tester) async {
    final source = AppSettings(clearPathOnMaxRetry: false);
    final contents = await BackupSnapshot(
      createdAt: DateTime.utc(2026, 11, 19),
      appSettings: AppSettingsBackup.capture(source),
      portableSettings: {
        PortableAppSettings.shared: PortableAppSettings.capture(PortableAppSettings.shared, source),
        PortableAppSettings.extension: PortableAppSettings.capture(PortableAppSettings.extension, source),
      },
    ).encode(password: '');
    final l10n = await show(tester, BackupScreen(
      pickFile: () async => XFile.fromData(utf8.encode(contents), name: 'full-settings.json'),
    ));
    await tester.tap(find.widgetWithText(OutlinedButton, l10n.backupRestore_selectImportFile));
    await _waitFor(tester, () => find.text(l10n.backupRestore_sectionHint).evaluate().isNotEmpty);
    expect(tester.takeException(), isNull);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.byKey(const ValueKey('backup-official-format')), findsNothing);
    expect(find.widgetWithText(FilledButton, l10n.backupChannels_createBackup), findsNothing);
    expect(find.text(l10n.backupMessageHistory_exportTitle), findsNothing);
    final shared = find.byKey(const ValueKey('restore-portable-appSettings'));
    await _reveal(tester, shared);
    expect(find.byKey(const ValueKey('restore-appSettings')), findsOneWidget);
    expect(shared, findsOneWidget);
    await tester.tap(shared);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.backupChannels_apply));
    await _waitFor(tester, () => find.text(l10n.backupRestore_localApplied).evaluate().isNotEmpty);
    expect(service.settings.clearPathOnMaxRetry, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single import keeps cancellation and merges fork settings after confirmation', (tester) async {
    final contents = await BackupSnapshot(
      createdAt: DateTime.utc(2026, 11, 19),
      portableSettings: {PortableAppSettings.extension:
        PortableAppSettings.capture(PortableAppSettings.extension, AppSettings()),
      },
    ).encode(password: '');
    var picks = 0;
    final l10n = await show(tester, BackupScreen(
      pickFile: () async {
        picks++;
        return XFile.fromData(utf8.encode(contents), name: 'settings.json');
      },
    ));
    await tester.tap(find.widgetWithText(OutlinedButton, l10n.backupRestore_selectImportFile));
    final restore = find.byKey(const ValueKey('restore-portable-mcoaAppSettings'));
    await _waitFor(tester, () => restore.evaluate().isNotEmpty);
    await _reveal(tester, restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, l10n.common_cancel));
    await tester.pumpAndSettle();
    expect(service.settings.suppressPhantomChannels, isFalse);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.backupChannels_apply));
    await _waitFor(tester, () => find.text(l10n.backupRestore_localApplied).evaluate().isNotEmpty);
    expect(service.settings.suppressPhantomChannels, isTrue);
    expect(service.settings.tcpServerAddress, 'keep-local-endpoint');
    expect(service.settings.uploadIpfsApiKey, 'keep-local-credential');
    expect(jsonDecode(PrefsManager.instance.getString('app_settings')!)['suppress_phantom_channels'], isTrue);
    expect(picks, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('node identity import needs a separate replacement confirmation', (tester) async {
    const key =
        '307c83864f2833cb427a2ef1c00a013cfdff2768d980c0a3a520f006904de94f'
        '9b4f0afe280b746a778684e75442502057b7473a03f08f96f5a38e9287e01f8f';
    final source = await BackupNodeIdentity.read(key, hexadecimal: true, publicKeys: const []);
    final contents = await const BackupFileCodec().encode({
      'format': BackupFileCodec.payloadFormat, 'version': 1,
      'sourcePublicKey': source.publicKey, 'items': ['privateKey'],
      'sections': {'nodeSettings': {
        'privateKey': base64Encode(Uint8List.fromList([
          for (var i = 0; i < key.length; i += 2)
            int.parse(key.substring(i, i + 2), radix: 16),
        ])),
      }},
    }, password: '');
    node.dispose();
    final radio = _IdentityNode();
    node = radio;
    final l10n = await show(tester, BackupScreen(
      pickFile: () async => XFile.fromData(utf8.encode(contents), name: 'identity.json'),
    ), language: 'ru');
    await tester.tap(find.widgetWithText(OutlinedButton, l10n.backupRestore_selectImportFile));
    final restore = find.byKey(const ValueKey('restore-nodeIdentity'));
    await _waitFor(tester, () => restore.evaluate().isNotEmpty);
    await _reveal(tester, restore);
    await tester.tap(restore);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l10n.backupIdentity_confirmTitle), findsOneWidget);
    expect(tester.widgetList<SelectableText>(find.byType(SelectableText))
        .map((widget) => widget.data), containsAll(['ab' * 32, source.publicKey]));
    expect(find.text(key), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, l10n.common_cancel));
    await tester.pumpAndSettle();
    expect(radio.identityWrites, 0);
    await tester.tap(restore);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, l10n.backupChannels_apply));
    await _waitFor(tester, () => find.text(l10n.backupIdentity_completed).evaluate().isNotEmpty);
    expect(radio.identityWrites, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('encrypted import highlights password with theme Warning until decrypted', (tester) async {
    const warning = Color(0xFFAB4312);
    final contents = await tester.runAsync(() => BackupSnapshot(
      createdAt: DateTime.utc(2026, 11, 19),
      portableSettings: {PortableAppSettings.extension:
        PortableAppSettings.capture(PortableAppSettings.extension, AppSettings())},
    ).encode(password: 'unlock'));
    final l10n = await show(tester, BackupScreen(
      pickFile: () async => XFile.fromData(utf8.encode(contents!), name: 'encrypted.json'),
    ), warningColor: warning);
    final password = find.byKey(const ValueKey('backup-password'));
    expect(tester.widget<TextField>(password).decoration!.enabledBorder, isNull);
    await tester.tap(find.widgetWithText(OutlinedButton, l10n.backupRestore_selectImportFile));
    await _waitFor(tester, () => tester.widget<TextField>(password).decoration!.labelText == l10n.backupChannels_password);
    var decoration = tester.widget<TextField>(password).decoration!;
    expect(decoration.enabledBorder!.borderSide.color, warning);
    expect(decoration.focusedBorder!.borderSide.color, warning);
    expect(decoration.labelStyle!.color, warning);
    await tester.enterText(password, 'wrong');
    await tester.tap(find.widgetWithText(TextButton, l10n.backupChannels_preview));
    await _waitFor(tester, () => tester.widget<TextField>(password).decoration!.helperText == l10n.backupChannels_badPassword);
    expect(tester.widget<TextField>(password).decoration!.enabledBorder!.borderSide.color, warning);
    await tester.enterText(password, 'unlock');
    await tester.tap(find.widgetWithText(TextButton, l10n.backupChannels_preview));
    await _waitFor(tester, () => find.byKey(const ValueKey('restore-portable-mcoaAppSettings')).evaluate().isNotEmpty);
    decoration = tester.widget<TextField>(password).decoration!;
    expect(decoration.enabledBorder, isNull);
    expect(decoration.labelText, l10n.backupRestore_password);
    expect(service.settings.tcpServerAddress, 'keep-local-endpoint');
    expect(tester.takeException(), isNull);
  });

  testWidgets('API credentials require an encrypted export', (tester) async {
    const warning = Color(0xFFB56A12);
    var saves = 0;
    final l10n = await show(tester, BackupScreen(
      saveFile: (value, name, {sharePositionOrigin}) async {
        saves++;
        return BackupJsonSaveResult.saved;
      },
    ), warningColor: warning);
    final secret = find.byKey(const ValueKey('backup-ipfsKey'));
    await _reveal(tester, secret);
    await tester.tap(secret);
    final create = find.widgetWithText(FilledButton, l10n.backupChannels_createBackup);
    await _reveal(tester, create);
    await tester.tap(create);
    await tester.pump();
    expect(find.text(l10n.backupRestore_passwordRequired), findsOneWidget);
    expect(saves, 0);
    final snackbar = tester.widget<SnackBar>(find.byType(SnackBar));
    final colors = Theme.of(tester.element(find.byType(BackupScreen))).colorScheme;
    expect(snackbar.backgroundColor, colors.error);
    expect(tester.widget<Text>(find.text(l10n.backupRestore_passwordRequired)).style!.color, colors.onError);
    final password = find.byKey(const ValueKey('backup-password'));
    // The field is above the currently scrolled export controls.
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await tester.pump();
    expect(tester.widget<TextField>(password).decoration!.enabledBorder!.borderSide.color, warning);
    await tester.enterText(password, 'backup password');
    await tester.pump();
    expect(tester.widget<TextField>(password).decoration!.enabledBorder, isNull);
    await tester.pump(const Duration(seconds: 5));

  });
}
