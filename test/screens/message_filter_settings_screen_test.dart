import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/message_filter.dart';
import 'package:meshcore_open/screens/message_filter_settings_screen.dart';
import 'package:meshcore_open/services/message_filter/message_filter_service.dart';
import 'package:meshcore_open/storage/message_filter_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/channel_filter_rule_dialog.dart';
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
    final repeatSends = find.byKey(const ValueKey('messageFilter_repeatSends'));
    expect(repeatSends, findsNothing);
    await tester.tap(duplicates);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(repeatSends, 100);
    expect(tester.widget<DropdownButton<int>>(repeatSends).value, 2);
    await tester.tap(repeatSends);
    await tester.pumpAndSettle();
    await tester.tap(find.text('4').last);
    await tester.pumpAndSettle();
    expect(service.settings.repeatSends, 4);

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
    expect(reloaded.settings.repeatSends, 4);
    expect(reloaded.appliesTo(channel.storageId), isFalse);

    final savedRule = find.widgetWithText(ListTile, 'bonus');
    await tester.scrollUntilVisible(savedRule, -120);
    await tester.ensureVisible(savedRule);
    await tester.tap(savedRule);
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    await tester.tap(find.descendant(of: dialog, matching: find.text('Delete')));
    await tester.pumpAndSettle();
    expect(service.rules, isEmpty);
    final afterDelete = MessageFilterService(store: store)..load();
    addTearDown(afterDelete.dispose);
    expect(afterDelete.rules, isEmpty);
  });

  for (final locale in ['ru', 'en']) {
    testWidgets('U29 baseline: rule editing preserves match and scope ($locale)',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 760);
      addTearDown(tester.view.reset);

      const original = FilterRule(
        id: 'synthetic',
        pattern: 'Alice',
        field: FilterRuleField.sender,
        match: FilterRuleMatch.exact,
        enabled: false,
      );
      FilterRule? saved;
      await tester.pumpWidget(MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await showChannelFilterRuleDialog(
                  context, rule: original,
                );
                saved = result?.rule;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ));
      final l10n = AppLocalizations.of(tester.element(find.text('Open')));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final input = find.byType(TextField);
      expect(tester.widget<TextField>(input).controller!.text, 'Alice');
      await tester.tap(input);
      await tester.enterText(input, 'Bob');
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(find.byType(EditableText))
          .focusNode.hasFocus, isTrue);
      final label = find.text(l10n.messageFilter_rulePattern);
      final viewport = find.byType(SingleChildScrollView);
      expect(label, findsOneWidget);
      expect(viewport, findsOneWidget);
      final labelRect = tester.getRect(label);
      final viewportRect = tester.getRect(viewport);
      expect(labelRect.top, greaterThanOrEqualTo(viewportRect.top));
      expect(labelRect.bottom, lessThanOrEqualTo(viewportRect.bottom));
      expect(tester.widget<TextField>(input).scrollPadding.top,
          greaterThanOrEqualTo(labelRect.height + 8));

      final save = find.widgetWithText(FilledButton, l10n.common_save);
      await tester.ensureVisible(save);
      expect(save.hitTestable(), findsOneWidget);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saved?.id, original.id);
      expect(saved?.pattern, 'Bob');
      expect(saved?.field, original.field);
      expect(saved?.match, original.match);
      expect(saved?.enabled, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
