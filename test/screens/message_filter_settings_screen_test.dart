import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/screens/message_filter_settings_screen.dart';
import 'package:meshcore_open/services/message_filter/message_filter_service.dart';
import 'package:meshcore_open/storage/message_filter_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SettingsStore extends MessageFilterStore {
  @override
  Future<({int spam, int notSpam})> loadTrainingLabelCounts() async =>
      (spam: 0, notSpam: 0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  testWidgets('U27b: manual rules and per-channel opt-out persist', (tester) async {
    final store = _SettingsStore();
    final service = MessageFilterService(store: store)..load();
    addTearDown(service.dispose);
    final channel = Channel.fromHex(0, 'Synthetic', Channel.publicChannelPsk);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MessageFilterSettingsScreen(
          service: service,
          channels: [channel],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final master = find.widgetWithText(SwitchListTile, 'Filter messages');
    expect(tester.widget<SwitchListTile>(master).value, isFalse);
    await tester.tap(master);
    await tester.pumpAndSettle();
    expect(service.settings.enabled, isTrue);

    final duplicates = find.widgetWithText(
      SwitchListTile,
      'Repeated publications',
    );
    final characters = find.widgetWithText(SwitchListTile, 'Repeated characters');
    await tester.scrollUntilVisible(duplicates, 100);
    expect(tester.widget<SwitchListTile>(duplicates).value, isFalse);
    await tester.tap(duplicates);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(characters, 100);
    expect(tester.widget<SwitchListTile>(characters).value, isFalse);
    expect(service.settings.duplicates, isTrue);
    expect(service.settings.repeatedCharacters, isFalse);

    final learning = find.widgetWithText(
      SwitchListTile,
      'Learn from spam feedback',
    );
    await tester.scrollUntilVisible(learning, 100);
    expect(tester.widget<SwitchListTile>(learning).value, isFalse);
    await tester.tap(learning);
    await tester.pumpAndSettle();
    expect(service.learningEnabled, isTrue);

    await tester.scrollUntilVisible(find.text('Add rule'), 100);
    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bonus');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(service.rules.single.pattern, 'bonus');

    final exclusion = find.widgetWithText(CheckboxListTile, 'Synthetic');
    await tester.scrollUntilVisible(exclusion, 180);
    await tester.tap(exclusion);
    await tester.pumpAndSettle();
    final reloaded = MessageFilterService(store: store)..load();
    addTearDown(reloaded.dispose);
    expect(reloaded.rules.single.pattern, 'bonus');
    expect(reloaded.settings.enabled, isTrue);
    expect(reloaded.settings.learning, isTrue);
    expect(reloaded.appliesTo(channel.storageId), isFalse);
  });
}
