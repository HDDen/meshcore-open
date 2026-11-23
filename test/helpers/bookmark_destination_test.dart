import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/bookmark_destination.dart';
import 'package:meshcore_open/models/bookmarked_message.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/storage/channel_identity_store.dart';
import 'package:meshcore_open/storage/contact_identity_store.dart';
import '../support/history_test_environment.dart';

BookmarkedMessage entry(BookmarkSourceType type, String source, String name) =>
    BookmarkedMessage(
      sourceType: type,
      sourceId: source,
      sourceName: name,
      messageId: 'original',
      senderName: 'Sender',
      text: 'Saved text',
      timestamp: DateTime(2026),
      receivedAt: DateTime(2026),
      isOutgoing: false,
    );
Contact peer(int key) => Contact(
  publicKey: Uint8List(32)..fillRange(0, 32, key),
  name: 'Peer',
  type: 1,
  pathLength: -1,
  path: Uint8List(0),
  lastSeen: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final history = HistoryTestEnvironment();
  setUp(() async {
    await history.setUp();
    ContactIdentities.instance.resetForTesting();
    await ContactIdentities.instance.load();
  });
  tearDown(() async {
    ContactIdentities.instance.resetForTesting();
    await history.tearDown();
  });

  test('channel slot moves do not change the bookmark destination', () {
    final channel = Channel(
      index: 7,
      name: 'Chat',
      psk: Uint8List(16)..fillRange(0, 16, 1),
    );
    final result = bookmarkDestination(
      entry(BookmarkSourceType.channel, channel.storageId!, 'Chat'),
      channels: [channel],
      contacts: [],
    );
    expect(result!.channel, same(channel));
  });

  test('linked channel history resolves an old key and name', () async {
    final old = Channel(
      index: 1,
      name: 'Old',
      psk: Uint8List(16)..fillRange(0, 16, 1),
    );
    final current = Channel(
      index: 5,
      name: 'New',
      psk: Uint8List(16)..fillRange(0, 16, 2),
    );
    await ChannelIdentities.instance.link(
      ChannelIdentity.of(old)!,
      ChannelIdentity.of(current)!,
    );
    final result = bookmarkDestination(
      entry(BookmarkSourceType.channel, old.storageId!, old.name),
      channels: [current],
      contacts: [],
    );
    expect(result!.channel, same(current));
  });

  test('a reused legacy slot cannot open another channel', () {
    final replaced = Channel(
      index: 1,
      name: 'Replacement',
      psk: Uint8List(16)..fillRange(0, 16, 1),
    );
    expect(
      bookmarkDestination(
        entry(BookmarkSourceType.channel, 'slot:1', 'Old'),
        channels: [replaced],
        contacts: [],
      ),
      isNull,
    );
  });

  test('linked contact keys resolve to the current contact', () async {
    final old = peer(1);
    final current = peer(2);
    await ContactIdentities.instance.link(
      old.publicKeyHex,
      current.publicKeyHex,
    );
    final result = bookmarkDestination(
      entry(BookmarkSourceType.contact, old.publicKeyHex, old.name),
      channels: [],
      contacts: [current],
    );
    expect(result!.contact, same(current));
    expect(
      bookmarkDestination(
        entry(BookmarkSourceType.contact, peer(3).publicKeyHex, 'Peer'),
        channels: [],
        contacts: [current],
      ),
      isNull,
      reason: 'Names alone do not identify contacts',
    );
  });

  test('duplicate PSKs prefer the original named channel', () {
    final psk = Uint8List(16)..fillRange(0, 16, 1);
    final first = Channel(index: 1, name: 'One', psk: psk);
    final second = Channel(index: 2, name: 'Two', psk: psk);
    expect(
      bookmarkDestination(
        entry(BookmarkSourceType.channel, first.storageId!, 'Two'),
        channels: [first, second],
        contacts: [],
      )!.channel,
      same(second),
    );
    expect(
      bookmarkDestination(
        entry(BookmarkSourceType.channel, first.storageId!, 'Deleted'),
        channels: [first, second],
        contacts: [],
      ),
      isNull,
    );
  });
}
