import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';
import '../utils/contact_search.dart';

/// The rows of the discovery screen, in the order it lists them: the nodes
/// the app has heard that the node does not hold, a node it holds only when
/// it answered the last discovery request ([responders]), never the node
/// itself, narrowed by [typeFilter] and [query], heard most recently first
/// or by name.
///
/// The screen keeps the result per input: the connector notifies on every
/// advert and every answer to a discovery request, and a thousand nodes
/// filtered and sorted by name cost milliseconds on a phone each time.
List<Contact> discoveryRows(
  Iterable<Contact> discovered, {
  required Set<String> knownKeys,
  required Set<String> responders,
  required String? selfKeyHex,
  required String query,
  required ContactTypeFilter typeFilter,
  required ContactSortOption sortOption,
}) {
  final rows = <Contact>[
    for (final contact in discovered)
      if ((query.isEmpty || matchesDiscoveryContactQuery(contact, query)) &&
          // Known contacts belong to the contacts list, unless they answered
          // the last discovery request.
          (!knownKeys.contains(contact.publicKeyHex) ||
              responders.contains(contact.publicKeyHex)) &&
          contact.publicKeyHex != selfKeyHex &&
          _matchesType(contact, typeFilter))
        contact,
  ];
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
