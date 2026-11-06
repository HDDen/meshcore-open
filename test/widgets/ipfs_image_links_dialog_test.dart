import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/widgets/ipfs_image_links_dialog.dart';

const _secret = 'synthetic-test-key-123456789';

class _Settings extends AppSettingsService {
  AppSettings value = AppSettings(
    publicIpfsGateway: 'https://chosen.example/ipfs/',
    uploadIpfsEndpoint: 'https://kubo.example/api/v0/add',
    uploadIpfsApiKey: _secret,
  );
  int saves = 0;
  @override
  AppSettings get settings => value;
  @override
  Future<void> setIpfsImageSettings({
    required String publicGateway,
    required String uploadGateway,
    required String uploadEndpoint,
    required String uploadApiKey,
  }) async {
    saves++;
    value = value.copyWith(
      publicIpfsGateway: publicGateway,
      uploadIpfsGateway: uploadGateway,
      uploadIpfsEndpoint: uploadEndpoint,
      uploadIpfsApiKey: uploadApiKey,
    );
  }
}

void main() {
  Future<void> open(WidgetTester tester, _Settings settings, String language) async {
    await tester.pumpWidget(MaterialApp(
      locale: Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => IpfsImageLinksDialog(settingsService: settings),
        ),
        child: const Text('Open IPFS'),
      ))),
    ));
    await tester.tap(find.text('Open IPFS'));
    await tester.pumpAndSettle();
  }

  for (final language in ['en', 'ru']) {
    testWidgets('focus alone cannot replace the API key ($language)', (tester) async {
      final settings = _Settings();
      addTearDown(settings.dispose);
      await open(tester, settings, language);
      final keyField = find.byKey(const ValueKey('ipfs-upload-key'));
      expect(tester.widget<TextField>(keyField).obscureText, isTrue);
      expect(tester.widget<TextField>(keyField).controller!.text, isNot(_secret));
      await tester.ensureVisible(keyField);
      await tester.pumpAndSettle();
      await tester.tap(keyField);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(keyField).controller!.text, isEmpty);
      final l10n = AppLocalizations.of(tester.element(find.byType(IpfsImageLinksDialog)));
      await tester.tap(find.text(l10n.common_save));
      await tester.pumpAndSettle();
      expect(settings.saves, 1);
      expect(settings.value.uploadIpfsApiKey, _secret);
      expect(settings.value.publicIpfsGateway, 'https://chosen.example/ipfs/');
      expect(find.byType(IpfsImageLinksDialog), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final language in ['en', 'ru']) {
    testWidgets('U17: fresh settings select Filebase without saving ($language)', (
      tester,
    ) async {
      final settings = _Settings();
      settings.value = AppSettings.fromJson({});
      addTearDown(settings.dispose);
      await open(tester, settings, language);
      final selector = find.byType(DropdownButtonFormField<String>).first;
      expect(
        tester.widget<DropdownButtonFormField<String>>(selector).initialValue,
        'filebase',
      );
      final field = find.byKey(const ValueKey('ipfs-public-gateway'));
      expect(
        tester.widget<TextField>(field).controller!.text,
        'https://ipfs.filebase.io/ipfs/',
      );
      expect(settings.saves, 0);
      expect(settings.value.loadLinkImages, isFalse);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(IpfsImageLinksDialog)),
      );
      await tester.tap(find.text(l10n.common_cancel));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('U17 baseline: presets keep their own gateway URLs ($language)', (
      tester,
    ) async {
      final settings = _Settings();
      addTearDown(settings.dispose);
      await open(tester, settings, language);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(IpfsImageLinksDialog)),
      );
      final presets = [
        (l10n.appSettings_ipfsGatewayDeactivated, ''),
        (l10n.appSettings_ipfsGatewayIpfsIo, 'https://ipfs.io/ipfs/'),
        (l10n.appSettings_ipfsGatewayPinata, 'https://gateway.pinata.cloud/ipfs/'),
        (l10n.appSettings_ipfsGatewayFilebase, 'https://ipfs.filebase.io/ipfs/'),
        (l10n.appSettings_ipfsGatewayCustom, 'http://127.0.0.1:8080/ipfs/'),
      ];
      final gateway = find.byKey(const ValueKey('ipfs-public-gateway'));
      final selector = find.byType(DropdownButtonFormField<String>).first;
      for (final preset in presets) {
        await tester.ensureVisible(selector);
        await tester.pumpAndSettle();
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.text(preset.$1).hitTestable().last);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(gateway).controller!.text,
          preset.$2,
          reason: preset.$1,
        );
        expect(settings.saves, 0);
      }
      await tester.tap(find.text(l10n.common_cancel));
      await tester.pumpAndSettle();
      expect(settings.value.publicIpfsGateway, 'https://chosen.example/ipfs/');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final saved in [
      '',
      'https://ipfs.io/ipfs/',
      'https://ipfs.filebase.io/ipfs/',
      'https://gateway.pinata.cloud/ipfs/',
      'https://chosen.example/ipfs/',
    ]) {
      testWidgets('U17 baseline: saved gateway survives open/save ($language, $saved)', (
        tester,
      ) async {
        final settings = _Settings();
        settings.value = settings.value.copyWith(publicIpfsGateway: saved);
        addTearDown(settings.dispose);
        await open(tester, settings, language);
        final field = find.byKey(const ValueKey('ipfs-public-gateway'));
        expect(tester.widget<TextField>(field).controller!.text, saved);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(IpfsImageLinksDialog)),
        );
        await tester.tap(find.text(l10n.common_save));
        await tester.pumpAndSettle();
        expect(settings.saves, 1);
        expect(settings.value.publicIpfsGateway, saved);
        expect(settings.value.uploadIpfsApiKey, _secret);
        expect(settings.value.uploadIpfsEndpoint, 'https://kubo.example/api/v0/add');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('edited key is saved; cancellation does not apply edits', (tester) async {
    final settings = _Settings();
    addTearDown(settings.dispose);
    await open(tester, settings, 'en');
    final field = find.byKey(const ValueKey('ipfs-upload-key'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'replacement-test-key');
    final l10n = AppLocalizations.of(tester.element(find.byType(IpfsImageLinksDialog)));
    await tester.tap(find.text(l10n.common_cancel));
    await tester.pumpAndSettle();
    expect(settings.saves, 0);
    expect(settings.value.uploadIpfsApiKey, _secret);
    await tester.tap(find.text('Open IPFS'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'replacement-test-key');
    await tester.tap(find.text(l10n.common_save));
    await tester.pumpAndSettle();
    expect(settings.value.uploadIpfsApiKey, 'replacement-test-key');
    expect(settings.saves, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
