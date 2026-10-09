import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/discovery_list.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/utils/contact_filter_types.dart';

// The rows of the discovery screen as a pure function of its inputs, which
// the screen now keeps per input instead of deriving on every notification
// of the connector. The screen-level tests pin the same rules through the
// widgets; here each rule is taken on its own, the split a discovery request
// makes included: the nodes that answered above, a known contact among them,
// and below the list as it was, without the nodes first heard through their
// answer.

Contact _node(
  int seed,
  String name, {
  int type = advTypeChat,
  int heardSecondsAgo = 0,
}) => Contact(
  publicKey: Uint8List.fromList(
    List<int>.generate(32, (i) => i == 0 ? seed : (seed * 7 + i) & 0xFF),
  ),
  name: name,
  type: type,
  pathLength: 0,
  path: Uint8List(0),
  lastSeen: DateTime(2026, 9, 29, 12).subtract(
    Duration(seconds: heardSecondsAgo),
  ),
);

List<String> _names(Iterable<Contact> rows) => [for (final c in rows) c.name];

List<Contact> _rows(
  List<Contact> discovered, {
  Set<String> knownKeys = const {},
  String? selfKeyHex,
  String query = '',
  ContactTypeFilter typeFilter = ContactTypeFilter.all,
  ContactSortOption sortOption = ContactSortOption.lastSeen,
}) => discoveryRows(
  discovered,
  knownKeys: knownKeys,
  selfKeyHex: selfKeyHex,
  query: query,
  typeFilter: typeFilter,
  sortOption: sortOption,
);

DiscoverySections _sections(
  List<Contact> discovered, {
  Set<String> knownKeys = const {},
  Set<String> responders = const {},
  Set<String> heardBefore = const {},
  String query = '',
  ContactTypeFilter typeFilter = ContactTypeFilter.all,
  ContactSortOption sortOption = ContactSortOption.lastSeen,
}) => discoverySections(
  discovered,
  knownKeys: knownKeys,
  responders: responders,
  heardBefore: heardBefore,
  selfKeyHex: null,
  query: query,
  typeFilter: typeFilter,
  sortOption: sortOption,
);

void main() {
  final alice = _node(2, 'Alice', heardSecondsAgo: 30);
  final bob = _node(3, 'bob', heardSecondsAgo: 3000);
  final relay = _node(4, 'Relay', type: advTypeRepeater, heardSecondsAgo: 300);
  final lounge = _node(5, 'Lounge', type: advTypeRoom, heardSecondsAgo: 60);
  final all = [alice, bob, relay, lounge];

  test('a node the node holds is not listed', () {
    expect(
      _names(_rows(all, knownKeys: {alice.publicKeyHex})),
      ['Lounge', 'Relay', 'bob'],
    );
  });

  test('the node itself is never listed', () {
    expect(
      _names(_rows(all, selfKeyHex: relay.publicKeyHex)),
      ['Alice', 'Lounge', 'bob'],
    );
    expect(_rows(all), hasLength(4), reason: 'no key, nothing hidden');
  });

  test('the type filter keeps the chosen type, and favourites nothing', () {
    expect(_names(_rows(all, typeFilter: ContactTypeFilter.users)), [
      'Alice',
      'bob',
    ]);
    expect(_names(_rows(all, typeFilter: ContactTypeFilter.repeaters)), [
      'Relay',
    ]);
    expect(_names(_rows(all, typeFilter: ContactTypeFilter.rooms)), [
      'Lounge',
    ]);
    expect(_rows(all, typeFilter: ContactTypeFilter.favorites), isEmpty);
  });

  test('the query matches a name without regard to case, or a key prefix', () {
    expect(_names(_rows(all, query: 'BO')), ['bob']);
    expect(
      _names(_rows(all, query: relay.publicKeyHex.substring(0, 6))),
      ['Relay'],
    );
    expect(_rows(all, query: 'nobody'), isEmpty);
  });

  test('the order is most recently heard first, by name without regard to '
      'case, or as heard', () {
    expect(_names(_rows(all)), ['Alice', 'Lounge', 'Relay', 'bob']);
    expect(_names(_rows(all, sortOption: ContactSortOption.name)), [
      'Alice',
      'bob',
      'Lounge',
      'Relay',
    ]);
    expect(
      _names(_rows(all, sortOption: ContactSortOption.recentMessages)),
      ['Alice', 'bob', 'Relay', 'Lounge'],
    );
  });

  test('the input list is left as it was', () {
    final input = [bob, alice];
    _rows(input, sortOption: ContactSortOption.name);
    expect(_names(input), ['bob', 'Alice']);
  });

  test('a request puts the nodes that answered above, a known contact among '
      'them, and leaves below the list as it was, without a node first heard '
      'through its answer', () {
    final sections = _sections(
      all,
      knownKeys: {relay.publicKeyHex},
      responders: {relay.publicKeyHex, bob.publicKeyHex, lounge.publicKeyHex},
      // Lounge is heard for the first time through its answer.
      heardBefore: {alice.publicKeyHex, bob.publicKeyHex, relay.publicKeyHex},
    );
    expect(_names(sections.answered), ['Lounge', 'Relay', 'bob']);
    expect(_names(sections.earlier), ['Alice', 'bob']);
  });

  test('without a request nothing has answered and the list is whole', () {
    final sections = _sections(all);
    expect(sections.answered, isEmpty);
    expect(_names(sections.earlier), ['Alice', 'Lounge', 'Relay', 'bob']);
  });

  test('both parts take the filters and the order', () {
    final heard = {for (final contact in all) contact.publicKeyHex};
    final sections = _sections(
      all,
      responders: {relay.publicKeyHex, bob.publicKeyHex},
      heardBefore: heard,
      typeFilter: ContactTypeFilter.users,
      sortOption: ContactSortOption.name,
    );
    expect(_names(sections.answered), ['bob']);
    expect(_names(sections.earlier), ['Alice', 'bob']);
    expect(
      _names(
        _sections(
          all,
          responders: {relay.publicKeyHex},
          heardBefore: heard,
          query: 'rel',
        ).answered,
      ),
      ['Relay'],
    );
  });
}
