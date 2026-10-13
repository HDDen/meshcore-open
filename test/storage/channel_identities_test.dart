import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/storage/channel_identity_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// What the identity table promises, pinned on its preference form: a pair
// with no row is a group of itself, a link makes two pairs one channel and
// chains through further links, two groups that meet become one, a name
// alone finds the names it was linked to, a channel is found among a node's
// list by any pair of its group, the rows survive a reload, and a forget
// removes the whole group.

Uint8List _psk(int fill) =>
    Uint8List.fromList(List<int>.generate(16, (i) => (fill + i) & 0xFF));

String _id(int fill) => Channel.storageIdForPsk(_psk(fill))!;

Channel _channel(int index, String name, int fill) =>
    Channel(index: index, name: name, psk: _psk(fill));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final identities = ChannelIdentities.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    identities.resetForTesting();
    await identities.load();
  });

  tearDown(() {
    identities.resetForTesting();
    PrefsManager.reset();
  });

  test('a pair without a row is a group of itself', () {
    final a = ChannelIdentity(_id(1), 'Горы');
    expect(identities.groupIdOf(a), isNull);
    expect(identities.membersOf(a), {a});
    expect(identities.namesOf(a), ['Горы']);
    expect(identities.isEmpty, isTrue);
  });

  test('the identity of a channel trims the name and refuses an empty slot', () {
    expect(
      ChannelIdentity.of(Channel(index: 0, name: '', psk: Uint8List(16))),
      isNull,
    );
    expect(ChannelIdentity.of(_channel(0, '   ', 1)), isNull);
    expect(
      ChannelIdentity.of(_channel(0, ' Горы ', 1)),
      ChannelIdentity(_id(1), 'Горы'),
    );
  });

  test('a rename and then a new key chain into one channel', () async {
    final a = ChannelIdentity(_id(1), 'Горы');
    final b = ChannelIdentity(_id(1), 'Горы-2026');
    final c = ChannelIdentity(_id(2), 'Горы-2026');
    final revision = identities.revision;

    expect(await identities.link(a, b), isTrue);
    expect(identities.revision, greaterThan(revision));
    expect(await identities.link(a, b), isFalse);
    expect(await identities.link(b, c), isTrue);

    expect(identities.namesOf(c), ['Горы-2026', 'Горы']);
    expect(identities.namesOf(a).toSet(), {'Горы', 'Горы-2026'});
    expect(identities.membersOf(a), {a, b, c});
    expect(identities.sameChannel(a, c), isTrue);
    expect(identities.sameChannel(a, ChannelIdentity(_id(3), 'Горы')), isFalse);
  });

  test('two groups that meet become one', () async {
    final a = ChannelIdentity(_id(1), 'A');
    final b = ChannelIdentity(_id(1), 'B');
    final c = ChannelIdentity(_id(2), 'C');
    final d = ChannelIdentity(_id(2), 'D');
    await identities.link(a, b);
    await identities.link(c, d);
    expect(identities.sameChannel(a, c), isFalse);

    await identities.link(b, c);

    expect(identities.membersOf(d), {a, b, c, d});
    expect(identities.groupIdOf(a), identities.groupIdOf(d));
  });

  test('a name alone finds the names it was linked to', () async {
    await identities.link(
      ChannelIdentity(_id(1), 'A'),
      ChannelIdentity(_id(1), 'B'),
    );
    expect(identities.namesLinkedTo('B'), ['B', 'A']);
    expect(identities.namesLinkedTo(' B '), ['B', 'A']);
    expect(identities.namesLinkedTo('C'), ['C']);
  });

  test('a channel is found in a list by its own pair, else by its group', () async {
    final old = ChannelIdentity(_id(1), 'Горы');
    final renamed = ChannelIdentity(_id(1), 'Горы-2026');
    final list = [_channel(3, 'Горы-2026', 1), _channel(5, 'Поля', 7)];

    expect(identities.findInGroup(list, old), isNull);
    await identities.link(old, renamed);
    expect(identities.findInGroup(list, old)?.index, 3);
    // The pair itself wins over another member of the group.
    expect(
      identities
          .findInGroup([_channel(3, 'Горы-2026', 1), _channel(4, 'Горы', 1)], old)
          ?.index,
      4,
    );
  });

  test('the rows survive a reload and a forget removes the group', () async {
    final a = ChannelIdentity(_id(1), 'Горы');
    final b = ChannelIdentity(_id(1), 'Горы-2026');
    await identities.link(a, b);

    identities.resetForTesting();
    expect(identities.namesOf(a), ['Горы']);
    await identities.load();
    expect(identities.namesOf(a), ['Горы', 'Горы-2026']);

    await identities.forget(a);
    expect(identities.namesOf(b), ['Горы-2026']);
    identities.resetForTesting();
    await identities.load();
    expect(identities.namesOf(b), ['Горы-2026']);
    expect(identities.isEmpty, isTrue);
  });
}
