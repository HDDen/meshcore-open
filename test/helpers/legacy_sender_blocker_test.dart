import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mco_service/mco_service.dart';
import 'package:meshcore_open/helpers/blocked_senders.dart';
import 'package:meshcore_open/helpers/legacy_sender_blocker.dart';
import 'package:meshcore_open/helpers/legacy_sender_blocker_binding.dart';
import 'package:meshcore_open/helpers/mcmp_app_codec.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/models/message_filter.dart';
import 'package:meshcore_open/services/message_filter/message_filter_rules.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Sections extends ChangeNotifier implements SettingsSectionsService {
  bool unlocked = false;
  @override
  bool get legacySenderBlockerEnabled => unlocked;
  void grant(bool value) { unlocked = value; notifyListeners(); }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final policy = LegacySenderBlocker.instance;
  final blocked = BlockedSenders.instance;
  Future<void> clear() async {
    for (final name in blocked.rules.keys.toList()) {
      await blocked.unblock(name);
    }
  }
  setUp(() async {
    policy.setEnabled(false);
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    await clear();
  });
  tearDown(() async {
    policy.setEnabled(false);
    await clear();
    PrefsManager.reset();
  });

  ChannelMessage post({bool stamped = false}) => ChannelMessage(
    senderName: 'Alice', text: 'hello', isOutgoing: false,
    timestamp: DateTime.now(), receivedAt: DateTime.now().add(const Duration(seconds: 1)),
    wasBlocked: stamped,
  );

  test('default-off ignores old rules and stamps without erasing them', () async {
    await blocked.blockName('Alice');
    final message = post(stamped: true);
    final saved = Map.of(blocked.rules);
    expect(policy.enabled, isFalse);
    expect(message.wasBlocked, isTrue);
    expect(message.copyWith(repeatCount: 1).wasBlocked, isTrue);
    expect(message.isLegacyBlocked, isFalse);
    expect(blocked.isSenderBlocked(message, 'Public'), isFalse);
    expect(blocked.hidesStoredMessage(message, 'Public'), isFalse);
    expect(blocked.hidesQuotedMessage(quoted: null, senderName: 'Alice',
        channelName: 'Public', isOwnQuote: false), isFalse);
    policy.setEnabled(true);
    expect(message.isLegacyBlocked, isTrue);
    expect(blocked.isSenderBlocked(message, 'Public'), isTrue);
    policy.setEnabled(false);
    expect(message.isLegacyBlocked, isFalse);
    expect(blocked.rules, saved);
  });

  test('room stamps also become dormant and survive copyWith', () async {
    final room = Message(senderKey: Uint8List(32), text: 'room',
      timestamp: DateTime.now(), isOutgoing: false, wasBlocked: true,
      fourByteRoomContactKey: Uint8List.fromList([1, 2, 3, 4]));
    await blocked.blockRoomAuthor(room);
    expect(blocked.isRoomAuthorBlocked(room), isFalse);
    expect(room.isLegacyBlocked, isFalse);
    expect(room.copyWith(text: 'changed').wasBlocked, isTrue);
    policy.setEnabled(true);
    expect(room.isLegacyBlocked, isTrue);
    expect(blocked.isRoomAuthorBlocked(room), isTrue);
  });

  test('new filter reprojects old stamps when legacy activation changes', () {
    final rules = MessageFilterRules(const [FilterRule(id: 'new', pattern: 'Alice',
      field: FilterRuleField.sender, match: FilterRuleMatch.exact)]);
    final message = post(stamped: true);
    policy.setEnabled(true);
    expect(rules.project(message).isFiltered, isFalse);
    policy.setEnabled(false);
    expect(rules.project(message).isFiltered, isTrue);
    final signed = message.copyWith(mcmpSignatureStatus: McmpSignatureStatus.valid,
      verifiedSenderKeyHex: 'ab' * 32);
    expect(BlockedSenders.verifiedKeyOf(signed), 'ab' * 32);
  });

  test('private grant/revoke updates live state; binding disposal detaches', () {
    final sections = _Sections();
    final binding = LegacySenderBlockerBinding(sections);
    var changes = 0;
    void changed() { changes++; }
    blocked.addListener(changed);
    final revision = blocked.revision;
    sections.grant(true);
    expect(policy.enabled, isTrue);
    expect(blocked.revision, greaterThan(revision));
    sections.grant(false);
    expect(policy.enabled, isFalse);
    expect(changes, 2);
    binding.dispose();
    sections.grant(true);
    expect(policy.enabled, isFalse);
    blocked.removeListener(changed);
    sections.dispose();
  });
}
