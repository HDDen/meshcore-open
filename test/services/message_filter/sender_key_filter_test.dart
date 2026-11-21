import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/backup_message_filter.dart';
import 'package:meshcore_open/helpers/mcmp_app_codec.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/models/message_filter.dart';
import 'package:meshcore_open/services/message_filter/message_filter_rules.dart';
import 'package:meshcore_open/services/message_filter/message_filter_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final key = 'ab' * 32;
  final other = 'cd' * 32;
  FilterRule rule({String? boundKey, String id = 'sender'}) => FilterRule(
    id: id, pattern: 'Alice', field: FilterRuleField.sender,
    match: FilterRuleMatch.exact, senderKeyHex: boundKey,
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  test('optional key survives JSON while old rules keep their old shape', () {
    final keyed = rule(boundKey: key);
    expect(FilterRule.fromJson(jsonDecode(jsonEncode(keyed.toJson()))), keyed);
    expect(FilterRule.fromJson({...keyed.toJson(), 'senderKeyHex': key.toUpperCase()}), keyed);
    expect(rule().toJson().containsKey('senderKeyHex'), isFalse);
    expect(FilterRule.fromJson(rule().toJson()), rule());
    expect(() => FilterRule.fromJson({...keyed.toJson(), 'senderKeyHex': 'broken'}),
        throwsFormatException);
  });

  test('verified identity wins; unsigned names and legacy rules remain supported', () {
    final rules = MessageFilterRules([rule(boundKey: key)]);
    bool hidden(String name, String? verified) => rules.match(
      name, 'hello', verifiedSenderKey: verified,
    ) != null;
    expect(hidden('Alice', key), isTrue);
    expect(hidden('Renamed', key.toUpperCase()), isTrue);
    expect(hidden('Alice', other), isFalse);
    expect(hidden('Alice', null), isTrue);
    expect(hidden('Alice', 'not-a-valid-key'), isTrue);
    expect(hidden('Other', null), isFalse);
    expect(MessageFilterRules([rule()]).match('Alice', 'hello', verifiedSenderKey: other),
        isNotNull);
  });

  test('history trusts only valid signatures and preserves explicit restoration', () {
    final rules = MessageFilterRules([rule(boundKey: key)]);
    ChannelMessage post(String name, String claimed, McmpSignatureStatus status) =>
        ChannelMessage(senderName: name, text: 'hello',
          timestamp: DateTime.utc(2026), receivedAt: DateTime.utc(2026),
          isOutgoing: false, mcmpSignatureStatus: status, verifiedSenderKeyHex: claimed);
    expect(rules.project(post('Renamed', key, McmpSignatureStatus.valid)).isFiltered, isTrue);
    expect(rules.project(post('Alice', other, McmpSignatureStatus.valid)).isFiltered, isFalse);
    for (final status in McmpSignatureStatus.values.where((s) => s != McmpSignatureStatus.valid)) {
      expect(rules.project(post('Alice', other, status)).isFiltered, isTrue);
      expect(rules.project(post('Renamed', key, status)).isFiltered, isFalse);
    }
    final restored = post('Alice', key, McmpSignatureStatus.valid).copyWith(filterRestored: true);
    expect(rules.project(restored).isFiltered, isFalse);
    expect(rules.project(post('Alice', key, McmpSignatureStatus.valid)
        .copyWith(isOutgoing: true)).isFiltered, isFalse);
  });

  test('ingest and reload keep the bound sender identity', () async {
    final filter = MessageFilterService();
    addTearDown(filter.dispose);
    await filter.updateSettings(const MessageFilterSettings(enabled: true));
    await filter.addRule(rule(boundKey: key));
    final loaded = MessageFilterService()..load();
    addTearDown(loaded.dispose);
    expect(loaded.rules.single.senderKeyHex, key);
    FilterVerdict? check(String name, String? verified) => loaded.evaluate(
      channelId: 'test', sender: name, text: 'hello', verifiedSenderKey: verified);
    expect(check('Renamed', key)?.reason, FilterReason.senderRule);
    expect(check('Alice', other), isNull);
    expect(check('Alice', null)?.reason, FilterReason.senderRule);
  });

  test('backup preserves keys and does not merge different identities by name', () {
    final first = rule(boundKey: key);
    final second = rule(boundKey: other, id: 'second');
    final backup = BackupMessageFilter.capture(const MessageFilterSettings(), [first, second]);
    final restored = BackupMessageFilter.fromPreferences(backup.toPreferences());
    expect(restored.rules, [first, second]);
    expect(restored.preview(const MessageFilterSettings(), [first]).addedRules, [second]);
    final corrupted = BackupMessageFilter.fromPreferences({
      BackupMessageFilter.rulesKey: [{...first.toJson(), 'senderKeyHex': 'broken'}],
    });
    expect(corrupted.rules, isEmpty);
  });
}
