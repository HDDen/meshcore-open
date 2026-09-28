import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/blocked_senders.dart';
import 'package:meshcore_open/helpers/mcmp_app_codec.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Invariants of the rule that hides a muted sender's words inside somebody
// else's quote. The channel screen looks the quoted original up for exactly
// this question, and these tests pin what the lookup must keep answering
// whichever list it reads the original from.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // On Windows PrefsManager.initialize() looks for a corrupt preferences file
  // through path_provider, which has no implementation in a unit test: answer
  // it with an empty temporary directory.
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final tempDir = Directory.systemTemp.createTempSync('mco_blocked_quote_');

  final blocked = BlockedSenders.instance;
  const channel = 'Public';
  // Dates in the past: a block made from a message is clamped to now, so a
  // fixture dated later than the test run would move the boundary.
  final noon = DateTime(2026, 9, 20, 12);

  Future<void> clearRules() async {
    for (final name in blocked.rules.keys.toList()) {
      await blocked.unblock(name);
    }
  }

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => tempDir.path);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    await clearRules();
  });

  tearDown(() async {
    await clearRules();
    PrefsManager.reset();
  });

  ChannelMessage incoming(
    String sender, {
    DateTime? receivedAt,
    bool wasBlocked = false,
    String? verifiedKeyHex,
  }) {
    final at = receivedAt ?? noon;
    return ChannelMessage(
      senderName: sender,
      text: 'hello from $sender',
      timestamp: at,
      receivedAt: at,
      isOutgoing: false,
      channelIndex: 0,
      wasBlocked: wasBlocked,
      verifiedSenderKeyHex: verifiedKeyHex,
      mcmpSignatureStatus: verifiedKeyHex == null
          ? McmpSignatureStatus.none
          : McmpSignatureStatus.valid,
    );
  }

  bool hidden({
    ChannelMessage? quoted,
    String? senderName,
    bool isOwnQuote = false,
  }) {
    return blocked.hidesQuotedMessage(
      quoted: quoted,
      senderName: senderName,
      channelName: channel,
      isOwnQuote: isOwnQuote,
    );
  }

  test('a quote of our own message is never hidden', () async {
    await blocked.blockName('Me');
    expect(hidden(senderName: 'Me', isOwnQuote: true), isFalse);
    expect(
      hidden(
        quoted: incoming('Me', wasBlocked: true),
        senderName: 'Me',
        isOwnQuote: true,
      ),
      isFalse,
    );
  });

  test('an original flagged at receipt stays hidden after the block is lifted',
      () {
    expect(blocked.rules, isEmpty);
    final original = incoming('Eve', wasBlocked: true);
    expect(hidden(quoted: original, senderName: 'Eve'), isTrue);
  });

  test('a found original decides by the moment of the block', () async {
    final anchor = incoming('Eve', receivedAt: noon);
    await blocked.block(anchor);

    expect(hidden(quoted: anchor, senderName: 'Eve'), isTrue);
    expect(
      hidden(
        quoted: incoming('Eve', receivedAt: noon.add(const Duration(minutes: 1))),
        senderName: 'Eve',
      ),
      isTrue,
    );
    expect(
      hidden(
        quoted: incoming(
          'Eve',
          receivedAt: noon.subtract(const Duration(minutes: 1)),
        ),
        senderName: 'Eve',
      ),
      isFalse,
    );
  });

  test('with the original out of memory the name alone decides', () async {
    expect(hidden(senderName: 'Eve'), isFalse);
    await blocked.blockName('Eve');
    expect(hidden(senderName: 'Eve'), isTrue);
    expect(hidden(senderName: ' Eve '), isTrue);
    expect(hidden(senderName: 'Bob'), isFalse);
    expect(hidden(senderName: null), isFalse);
    expect(hidden(senderName: ''), isFalse);
  });

  test('a verified key exempts a namesake, an unsigned original does not',
      () async {
    final keyOne = 'a1' * 32;
    final keyTwo = 'b2' * 32;
    await blocked.block(incoming('Eve', verifiedKeyHex: keyOne));
    final later = noon.add(const Duration(minutes: 5));

    expect(
      hidden(
        quoted: incoming('Eve', receivedAt: later, verifiedKeyHex: keyTwo),
        senderName: 'Eve',
      ),
      isFalse,
    );
    expect(
      hidden(
        quoted: incoming('Eve', receivedAt: later, verifiedKeyHex: keyOne),
        senderName: 'Eve',
      ),
      isTrue,
    );
    expect(
      hidden(quoted: incoming('Eve', receivedAt: later), senderName: 'Eve'),
      isTrue,
    );
    // Out of memory the name is all there is, whatever key the rule carries.
    expect(hidden(senderName: 'Eve'), isTrue);
  });

  test('an outgoing original is never covered by a rule', () async {
    await blocked.blockName('Me');
    final ours = ChannelMessage(
      senderName: 'Me',
      text: 'ours',
      timestamp: noon,
      receivedAt: noon,
      isOutgoing: true,
      channelIndex: 0,
    );
    expect(hidden(quoted: ours, senderName: 'Me'), isFalse);
  });
}
