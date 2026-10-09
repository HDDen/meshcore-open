import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';
import '../utils/contact_search.dart';

/// The rows of the discovery screen, in the order it lists them: the nodes
/// the app has heard that the node does not hold, never the node itself,
/// narrowed by [typeFilter] and [query], heard most recently first or by
/// name.
///
/// The screen keeps the result per input: the connector notifies on every
/// advert and every answer to a discovery request, and a thousand nodes
/// filtered and sorted by name cost milliseconds on a phone each time.
List<Contact> discoveryRows(
  Iterable<Contact> discovered, {
  required Set<String> knownKeys,
  required String? selfKeyHex,
  required String query,
  required ContactTypeFilter typeFilter,
  required ContactSortOption sortOption,
}) => _sorted(
  [
    for (final contact in discovered)
      // Known contacts belong to the contacts list.
      if (!knownKeys.contains(contact.publicKeyHex) &&
          _listed(contact, selfKeyHex, query, typeFilter))
        contact,
  ],
  sortOption,
);

/// The two parts of the discovery screen once a request was sent from it.
typedef DiscoverySections = ({List<Contact> answered, List<Contact> earlier});

/// The list split by a discovery request. [answered] are the nodes that
/// answered the latest one, [responders], a node the node holds included,
/// since the request reached it. [earlier] is the list as it was before the
/// request: [discoveryRows] less the nodes first heard through their answer,
/// [heardBefore] being the keys of the discovered list as the request went
/// out. A node listed before that answered again stands in both parts; one
/// heard only through its answer stands among the answered alone. Both parts
/// take the same filters and order.
DiscoverySections discoverySections(
  Iterable<Contact> discovered, {
  required Set<String> knownKeys,
  required Set<String> responders,
  required Set<String> heardBefore,
  required String? selfKeyHex,
  required String query,
  required ContactTypeFilter typeFilter,
  required ContactSortOption sortOption,
}) => (
  answered: _sorted(
    [
      for (final contact in discovered)
        if (responders.contains(contact.publicKeyHex) &&
            _listed(contact, selfKeyHex, query, typeFilter))
          contact,
    ],
    sortOption,
  ),
  earlier: discoveryRows(
    [
      for (final contact in discovered)
        if (!responders.contains(contact.publicKeyHex) ||
            heardBefore.contains(contact.publicKeyHex))
          contact,
    ],
    knownKeys: knownKeys,
    selfKeyHex: selfKeyHex,
    query: query,
    typeFilter: typeFilter,
    sortOption: sortOption,
  ),
);

bool _listed(
  Contact contact,
  String? selfKeyHex,
  String query,
  ContactTypeFilter typeFilter,
) =>
    contact.publicKeyHex != selfKeyHex &&
    (query.isEmpty || matchesDiscoveryContactQuery(contact, query)) &&
    _matchesType(contact, typeFilter);

List<Contact> _sorted(List<Contact> rows, ContactSortOption sortOption) {
  switch (sortOption) {
    case ContactSortOption.lastSeen:
      rows.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    case ContactSortOption.name:
      rows.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    case ContactSortOption.recentMessages:
      break;
  }
  return rows;
}

bool _matchesType(Contact contact, ContactTypeFilter filter) {
  switch (filter) {
    case ContactTypeFilter.all:
      return true;
    case ContactTypeFilter.users:
      return contact.type == advTypeChat;
    case ContactTypeFilter.repeaters:
      return contact.type == advTypeRepeater;
    case ContactTypeFilter.rooms:
      return contact.type == advTypeRoom;
    case ContactTypeFilter.favorites:
      return false;
  }
}
