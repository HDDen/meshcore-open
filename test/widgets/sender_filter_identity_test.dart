import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/message_filter.dart';
import 'package:meshcore_open/screens/message_filter_settings_screen.dart';
import 'package:meshcore_open/services/message_filter/message_filter_service.dart';
import 'package:meshcore_open/storage/message_filter_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meshcore_open/widgets/channel_filter_rule_dialog.dart';

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

  testWidgets('adding MCMP rule locks exact matching and validates the key', (tester) async {
    FilterRule? saved;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () async {
          saved = (await showChannelFilterRuleDialog(context))?.rule;
        },
        child: const Text('Open'),
      ))),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(AlertDialog)));
    await tester.tap(find.byType(DropdownButtonFormField<FilterRuleField>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.messageFilter_ruleFieldMcmpKey).last);
    await tester.pumpAndSettle();
    final match = tester.widget<DropdownButtonFormField<FilterRuleMatch>>(
      find.byType(DropdownButtonFormField<FilterRuleMatch>),
    );
    expect(match.onChanged, isNull);
    expect(find.text(l10n.messageFilter_ruleMatchExact), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'bad');
    await tester.pump();
    final save = find.widgetWithText(FilledButton, l10n.common_save);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'AB' * 32);
    await tester.pump();
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved?.field, FilterRuleField.mcmpKey);
    expect(saved?.match, FilterRuleMatch.exact);
    expect(saved?.senderKeyHex, 'ab' * 32);
    expect(saved?.pattern, 'ab' * 32);
  });

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
      final match = tester.widget<DropdownButtonFormField<FilterRuleMatch>>(
        find.byType(DropdownButtonFormField<FilterRuleMatch>),
      );
      expect(match.onChanged, isNull);
      await tester.enterText(find.byType(TextField), 'not a key');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, l10n.common_save)).onPressed, isNull);
      await tester.enterText(find.byType(TextField), key.toUpperCase());
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, l10n.common_save));
      await tester.pumpAndSettle();
      expect(filter.rules.single.pattern, key);
      expect(filter.rules.single.field, FilterRuleField.mcmpKey);
      expect(filter.rules.single.senderKeyHex, key);
      expect(filter.rules.single.enabled, isFalse);
      final loaded = MessageFilterService(store: _Store())..load();
      addTearDown(loaded.dispose);
      expect(loaded.rules, filter.rules);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
