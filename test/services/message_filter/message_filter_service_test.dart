import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/backup_message_filter.dart';
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

  test('U27g: concurrent appends keep both rules in storage', () async {
    final filter = MessageFilterService();
    addTearDown(filter.dispose);
    await Future.wait([filter.addRule(_bonus), filter.addRule(_sender)]);
    expect(filter.rules, [_bonus, _sender]);

    final reloaded = MessageFilterService()..load();
    addTearDown(reloaded.dispose);
    expect(reloaded.rules, [_bonus, _sender]);
  });

  test('backup merges rules after queued writes and preserves opt-in and exclusions', () async {
    final filter = MessageFilterService()..load();
    addTearDown(filter.dispose);
    const manual = FilterRule(id: 'existing', pattern: 'local rule');
    final localChannel = 'ab' * 8;
    final incomingChannel = 'cd' * 8;
    await filter.addRule(_bonus);
    final backup = BackupMessageFilter.capture(
      MessageFilterSettings(
        enabled: true, learning: true, duplicates: true,
        excludedChannelIds: {incomingChannel},
      ),
      const [
        FilterRule(id: 'same-text', pattern: ' BONUS ',
          field: FilterRuleField.both, match: FilterRuleMatch.wholeWord),
        _sender,
      ],
    );
    final stale = backup.preview(filter.settings, filter.rules);
    final edit = filter.addRule(manual);
    expect(await filter.restoreBackup(stale), isFalse);
    await edit;
    await filter.setChannelExcluded(localChannel, excluded: true);
    final preview = backup.preview(filter.settings, filter.rules);
    expect(preview.addedRules, [_sender]);
    expect(await filter.restoreBackup(preview), isTrue);
    expect(filter.rules, [_bonus, manual, _sender]);
    expect(filter.settings.enabled, isFalse);
    expect(filter.settings.learning, isFalse);
    expect(filter.settings.duplicates, isTrue);
    expect(filter.settings.excludedChannelIds, {localChannel, incomingChannel});

    final reloaded = MessageFilterService()..load();
    addTearDown(reloaded.dispose);
    expect(reloaded.rules, filter.rules);
    expect(reloaded.settings.toJson(), filter.settings.toJson());
  });

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

  test('U33 baseline: manual rules outrank repeat verdicts', () async {
    final filter = MessageFilterService();
    addTearDown(filter.dispose);
    await filter.updateSettings(
      const MessageFilterSettings(enabled: true, duplicates: true),
    );
    await filter.replaceRules(const [_bonus]);

    final start = DateTime.utc(2026, 1, 1);
    const text = 'claim a bonus from the local mesh';
    FilterReason? check(int minutes) {
      final time = start.add(Duration(minutes: minutes));
      return filter.evaluate(
        channelId: 'test',
        sender: 'Alice',
        text: text,
        sentAt: time,
        receivedAt: time,
      )?.reason;
    }

    expect(check(0), FilterReason.textRule);
    expect(check(1), FilterReason.textRule);
    await filter.replaceRules(const []);
    expect(check(2), FilterReason.duplicate);

    filter.allowRestoredText('test', text);
    expect(check(3), isNull);
    await filter.replaceRules(const [_bonus]);
    expect(check(4), FilterReason.textRule);
  });

  test('U33 baseline: verified keys distinguish senders with the same name',
      () async {
    final filter = MessageFilterService();
    addTearDown(filter.dispose);
    await filter.updateSettings(
      const MessageFilterSettings(enabled: true, duplicates: true),
    );

    final start = DateTime.utc(2026, 1, 1);
    FilterReason? check(String key, String name, int minutes) {
      final time = start.add(Duration(minutes: minutes));
      return filter.evaluate(
        channelId: 'test',
        sender: name,
        text: 'claim a bonus from the local mesh',
        verifiedSenderKey: key,
        sentAt: time,
        receivedAt: time,
      )?.reason;
    }

    expect(check('one', 'Alice', 0), isNull);
    expect(check('two', 'Alice', 1), isNull);
    expect(check('three', 'Alice', 2), FilterReason.crossSenderDuplicate);
    expect(check('one', 'Renamed', 3), FilterReason.duplicate);
  });

  test('U33: an exact replay stays out of the same-sender threshold', () async {
    final filter = MessageFilterService();
    addTearDown(filter.dispose);
    await filter.updateSettings(
      const MessageFilterSettings(enabled: true, duplicates: true, repeatSends: 3),
    );
    final time = DateTime.utc(2026, 1, 1);
    FilterReason? check(String text, {String? binaryKey}) => filter.evaluate(
      channelId: binaryKey == null ? 'text' : 'binary',
      sender: 'Alice',
      text: text,
      sentAt: time,
      receivedAt: time,
      binaryPublicationKey: binaryKey,
    )?.reason;

    const text = 'join the local mesh channel today';
    expect(check(text), isNull);
    expect(check(text), isNull);
    expect(check('$text!'), isNull);
    expect(check('$text.'), FilterReason.duplicate);

    expect(check(text, binaryKey: 'packet-one'), isNull);
    expect(check(text, binaryKey: 'packet-one'), isNull);
    expect(check(text, binaryKey: 'packet-two'), isNull);
    expect(check(text, binaryKey: 'packet-three'), FilterReason.duplicate);
  });

  test('U33: addressed posts bypass only the repeat check', () async {
    final filter = MessageFilterService();
    addTearDown(filter.dispose);
    await filter.updateSettings(
      const MessageFilterSettings(
        enabled: true,
        duplicates: true,
        repeatedCharacters: true,
      ),
    );
    await filter.replaceRules(const [_bonus]);

    const text = 'join the local mesh channel today';
    final start = DateTime.utc(2026, 1, 1);
    FilterReason? check(String body, int seconds, {bool isAddressed = false}) =>
        filter.evaluate(
          channelId: 'test',
          sender: 'Alice',
          text: body,
          sentAt: start.add(Duration(seconds: seconds)),
          receivedAt: start.add(Duration(seconds: seconds)),
          isAddressed: isAddressed,
        )?.reason;

    expect(check('@[Bob] $text', 0), isNull);
    expect(check('$text @[Eve]', 1), isNull);
    expect(check(text, 2, isAddressed: true), isNull);
    expect(check(text, 3), isNull);
    expect(check(text, 4), FilterReason.duplicate);
    expect(check('claim a bonus @[Bob]', 5), FilterReason.textRule);
    expect(check('а' * 20, 6, isAddressed: true), FilterReason.repeatedCharacters);
  });

  test('U33: legacy and invalid threshold settings fall back safely', () {
    expect(MessageFilterSettings.fromJson({}).repeatSends, 2);
    expect(MessageFilterSettings.fromJson({'repeatSends': '4'}).repeatSends, 2);
    expect(MessageFilterSettings.fromJson({'repeatSends': 1}).repeatSends, 2);
    expect(MessageFilterSettings.fromJson({'repeatSends': 9}).repeatSends, 5);
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
