import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/message_filter.dart';
import 'package:meshcore_open/services/message_filter/message_filter_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _bonus = FilterRule(
  id: 'bonus',
  pattern: 'bonus',
  field: FilterRuleField.both,
  match: FilterRuleMatch.wholeWord,
);
const _sender = FilterRule(
  id: 'sender',
  pattern: 'Alice',
  field: FilterRuleField.sender,
  match: FilterRuleMatch.exact,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  test('rules require opt-in and channel exclusions survive reload', () async {
    final filter = MessageFilterService()..load();
    await filter.replaceRules(const [_bonus]);
    expect(filter.settings.enabled, isFalse);
    expect(
      filter.evaluate(channelId: 'test', sender: 'Bob', text: 'A bonus!'),
      isNull,
    );

    await filter.updateSettings(
      const MessageFilterSettings(
        enabled: true,
        excludedChannelIds: {'excluded'},
      ),
    );
    final reloaded = MessageFilterService()..load();
    expect(reloaded.rules, [_bonus]);
    expect(reloaded.settings.enabled, isTrue);
    expect(reloaded.settings.excludedChannelIds, {'excluded'});
    expect(
      reloaded.evaluate(channelId: 'excluded', sender: 'Bob', text: 'A bonus!'),
      isNull,
    );
    expect(
      reloaded.evaluate(channelId: 'test', sender: 'Bob', text: 'A bonus!'),
      const FilterVerdict(reason: FilterReason.textRule, detail: 'bonus'),
    );

    await reloaded.updateSettings(reloaded.settings.copyWith(enabled: false));
    expect((MessageFilterService()..load()).settings.enabled, isFalse);
  });

  test('sender rules take precedence and text rules respect word bounds', () async {
    final filter = MessageFilterService();
    await filter.updateSettings(const MessageFilterSettings(enabled: true));
    await filter.replaceRules(const [
      _bonus,
      _sender,
      FilterRule(id: 'disabled', pattern: 'hello', enabled: false),
    ]);

    expect(
      filter.evaluate(channelId: 'test', sender: 'ÁLICE', text: 'A bonus!'),
      const FilterVerdict(reason: FilterReason.senderRule, detail: 'Alice'),
    );
    expect(
      filter.evaluate(
        channelId: 'test',
        sender: 'Alice Jr',
        text: 'A ＢＯ\u200bＮＵＳ!',
      ),
      const FilterVerdict(reason: FilterReason.textRule, detail: 'bonus'),
    );
    for (final text in ['bonus123', 'prebonus', 'hello']) {
      expect(
        filter.evaluate(channelId: 'test', sender: 'Alice Jr', text: text),
        isNull,
        reason: text,
      );
    }
  });

  test('automatic checks are independent and opt in', () async {
    final filter = MessageFilterService();
    addTearDown(filter.dispose);
    await filter.updateSettings(const MessageFilterSettings(enabled: true));
    const text = 'join the local mesh channel today';
    final run = 'аＡ' * 10;

    FilterReason? check(String text, {String? key, String sender = 'Bob'}) =>
        filter.evaluate(
          channelId: 'test',
          sender: sender,
          text: text,
          verifiedSenderKey: key,
        )?.reason;

    expect(check(text), isNull);
    expect(check(text), isNull);
    expect(check(run), isNull);

    await filter.updateSettings(
      filter.settings.copyWith(repeatedCharacters: true),
    );
    expect(check('a' * 19), isNull);
    expect(check('١' * 20), isNull);
    expect(check('g:$run'), isNull);
    expect(check(run), FilterReason.repeatedCharacters);
    expect(check(text), isNull);
    expect(check(text), isNull);

    await filter.updateSettings(
      filter.settings.copyWith(duplicates: true, repeatedCharacters: false),
    );
    expect(check(run), isNull);
    expect(check(text, key: 'key-one'), isNull);
    expect(check(text, key: 'key-two'), isNull);
    expect(
      check(text, key: 'key-one', sender: 'Changed name'),
      FilterReason.duplicate,
    );
    expect(check(text, key: 'key-three'), FilterReason.crossSenderDuplicate);

    filter.allowRestoredText('test', text);
    expect(check(text, key: 'key-one'), isNull);
    await filter.updateSettings(filter.settings.copyWith(duplicates: false));
    await filter.updateSettings(filter.settings.copyWith(duplicates: true));
    expect(check(text, key: 'key-one'), isNull);
    expect(check(text, key: 'key-one'), FilterReason.duplicate);

    final reloaded = MessageFilterService()..load();
    addTearDown(reloaded.dispose);
    expect(reloaded.settings.duplicates, isTrue);
    expect(reloaded.settings.repeatedCharacters, isFalse);
  });

  test('structured messages bypass even a matching sender rule', () async {
    final filter = MessageFilterService();
    await filter.updateSettings(const MessageFilterSettings(enabled: true));
    await filter.replaceRules(const [_sender, _bonus]);

    for (final text in [
      '  ',
      'g:bonus',
      'V1|bonus',
      'm:bonus',
      'del:m:bonus',
      'im:bonus',
      'im3:bonus',
      'im4:bonus',
      'mcoimg-unsupported:bonus',
      'mcoapp-unknown:bonus',
    ]) {
      expect(
        filter.evaluate(channelId: 'test', sender: 'Alice', text: text),
        isNull,
        reason: text,
      );
    }
  });
}
