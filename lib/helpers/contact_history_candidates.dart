import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';

/// A history the user may attach to a contact: another contact of the same
/// name under another key, on this node ([nodeScope] null) or on another
/// node of the owner.
class ContactHistoryCandidate {
  final String publicKeyHex;
  final String name;
  final DateTime lastMessageAt;

  /// The first ten hex characters of the node whose contact list holds the
  /// candidate, or null for the connected node.
  final String? nodeScope;

  const ContactHistoryCandidate({
    required this.publicKeyHex,
    required this.name,
    required this.lastMessageAt,
    this.nodeScope,
  });

  @override
  bool operator ==(Object other) =>
      other is ContactHistoryCandidate &&
      other.publicKeyHex == publicKeyHex &&
      other.nodeScope == nodeScope;

  @override
  int get hashCode => Object.hash(publicKeyHex, nodeScope);

  @override
  String toString() => '$name@${publicKeyHex.substring(0, 8)}'
      '${nodeScope == null ? '' : ' on $nodeScope'}';
}

/// Finds, among [contacts], the chat contacts named like [contact] under
/// another key that have a history: what a re-flashed node leaves behind.
/// Nothing is linked here; the user decides, the name proving nothing.
class ContactHistoryCandidates {
  const ContactHistoryCandidates._();

  static String normalizeName(String name) => name.trim().toLowerCase();

  static List<ContactHistoryCandidate> sameNameWithHistory(
    Contact contact,
    Iterable<Contact> contacts, {
    String? nodeScope,
    Set<String> excludedKeys = const {},
  }) {
    final name = normalizeName(contact.name);
    if (name.isEmpty || contact.type != advTypeChat) return const [];
    final ownKey = contact.publicKeyHex.toLowerCase();
    final result = <ContactHistoryCandidate>[];
    for (final other in contacts) {
      if (other.type != advTypeChat || !other.hasMessages) continue;
      final key = other.publicKeyHex.toLowerCase();
      if (key == ownKey || excludedKeys.contains(key)) continue;
      if (normalizeName(other.name) != name) continue;
      result.add(
        ContactHistoryCandidate(
          publicKeyHex: key,
          name: other.name,
          lastMessageAt: other.lastMessageAt,
          nodeScope: nodeScope,
        ),
      );
    }
    result.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    return result;
  }
}
