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
