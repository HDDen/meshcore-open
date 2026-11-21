import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/message_filter.dart';
import 'package:meshcore_open/screens/message_filter_settings_screen.dart';
import 'package:meshcore_open/services/message_filter/message_filter_service.dart';
import 'package:meshcore_open/storage/message_filter_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Store extends MessageFilterStore {
  @override
  Future<({int spam, int notSpam})> loadTrainingLabelCounts() async => (spam: 0, notSpam: 0);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  for (final locale in ['en', 'ru']) {
    testWidgets('key-bound sender rule is visible and survives switch/edit ($locale)', (tester) async {
      final key = 'ab' * 32;
      final filter = MessageFilterService(store: _Store());
      addTearDown(filter.dispose);
      await filter.updateSettings(const MessageFilterSettings(enabled: true));
      await filter.addRule(FilterRule(id: 'keyed', pattern: 'Alice',
        field: FilterRuleField.sender, match: FilterRuleMatch.exact, senderKeyHex: key));
      await tester.pumpWidget(MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MessageFilterSettingsScreen(service: filter, channels: const []),
      ));
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(tester.element(find.byType(MessageFilterSettingsScreen)));
      await tester.scrollUntilVisible(find.text('Alice'), 250);
      await tester.pumpAndSettle();
      final tile = find.widgetWithText(ListTile, 'Alice');
      expect(find.descendant(of: tile, matching: find.byIcon(Icons.key)), findsOneWidget);
      expect(find.descendant(of: tile, matching: find.textContaining(l10n.messageFilter_senderByKey)),
          findsOneWidget);
      await tester.tap(find.descendant(of: tile, matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      expect(filter.rules.single.enabled, isFalse);
      expect(filter.rules.single.senderKeyHex, key);
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      expect(find.text(key), findsOneWidget);
      expect(find.text(l10n.messageFilter_senderKeyHelp), findsOneWidget);
      expect(find.text(l10n.messageFilter_senderByKey), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Renamed');
      await tester.tap(find.widgetWithText(FilledButton, l10n.common_save));
      await tester.pumpAndSettle();
      expect(filter.rules.single.pattern, 'Renamed');
      expect(filter.rules.single.senderKeyHex, key);
      expect(filter.rules.single.enabled, isFalse);
      final loaded = MessageFilterService(store: _Store())..load();
      addTearDown(loaded.dispose);
      expect(loaded.rules, filter.rules);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
