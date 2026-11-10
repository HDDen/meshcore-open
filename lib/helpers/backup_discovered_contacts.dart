import '../models/contact.dart';
import '../storage/contact_discovery_store.dart';

class BackupDiscoveredContactsPreview {
  BackupDiscoveredContactsPreview({
    required String sourceJson,
    required Iterable<Contact> current,
    required Set<String> knownContactKeys,
    required String nodeKey,
    required int capacity,
    required this.session,
    DateTime? now,
  }) {
    final contacts = List<Contact>.of(current);
    final before = contacts.length;
    final store = ContactDiscoveryStore();
    final result = store.importContactsJson(
      json: sourceJson,
      existingContacts: contacts,
      knownContactKeys: knownContactKeys,
      selfPublicKeyHex: nodeKey,
      now: now,
    );
    final free = (capacity - before).clamp(0, capacity);
    final accepted = contacts.skip(before).take(free).map(
      (contact) => contact.copyWith(
        isActive: false,
        hasMessages: false,
        lastMessageAt: contact.lastSeen,
      ),
    ).toList();
    this.contacts = List<Contact>.unmodifiable(accepted);
    skipped = result.skipped;
    invalid = result.invalid;
    noRoom = result.imported - accepted.length;
    json = store.exportContactsJson(accepted);
  }

  final Object session;
  late final List<Contact> contacts;
  late final String json;
  late final int skipped;
  late final int invalid;
  late final int noRoom;
}
