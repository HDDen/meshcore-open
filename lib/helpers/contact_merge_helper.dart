import '../models/contact.dart';

int findAndRepairContactIndex({
  required List<Contact> contacts,
  required Map<String, int>? indexesByPublicKey,
  required String publicKeyHex,
}) {
  final indexedPosition = indexesByPublicKey?[publicKeyHex];
  if (indexedPosition != null &&
      indexedPosition >= 0 &&
      indexedPosition < contacts.length &&
      contacts[indexedPosition].publicKeyHex == publicKeyHex) {
    return indexedPosition;
  }

  final actualPosition = contacts.indexWhere(
    (contact) => contact.publicKeyHex == publicKeyHex,
  );
  if (actualPosition >= 0) {
    indexesByPublicKey?[publicKeyHex] = actualPosition;
  }
  return actualPosition;
}

List<Contact> deduplicateContactsByPublicKey(Iterable<Contact> contacts) {
  final byPublicKey = <String, Contact>{};
  for (final contact in contacts) {
    final key = contact.publicKeyHex;
    final existing = byPublicKey[key];
    byPublicKey[key] = existing == null
        ? contact
        : mergeDuplicateContacts(existing, contact);
  }
  return byPublicKey.values.toList();
}

Contact mergeDuplicateContacts(Contact existing, Contact incoming) {
  final existingFreshness = existing.lastModified ?? existing.lastSeen;
  final incomingFreshness = incoming.lastModified ?? incoming.lastSeen;
  final preferred = incomingFreshness.isAfter(existingFreshness)
      ? incoming
      : existing;
  final fallback = identical(preferred, incoming) ? existing : incoming;
  final pathOverride = preferred.pathOverride ?? fallback.pathOverride;
  final pathOverrideBytes = preferred.pathOverride != null
      ? preferred.pathOverrideBytes
      : fallback.pathOverrideBytes;
  final latestMessageAt = incoming.lastMessageAt.isAfter(existing.lastMessageAt)
      ? incoming.lastMessageAt
      : existing.lastMessageAt;
  final latestLastSeen = incoming.lastSeen.isAfter(existing.lastSeen)
      ? incoming.lastSeen
      : existing.lastSeen;
  DateTime? latestLastModified = existing.lastModified;
  if (latestLastModified == null ||
      (incoming.lastModified?.isAfter(latestLastModified) ?? false)) {
    latestLastModified = incoming.lastModified;
  }

  return preferred.copyWith(
    name: preferred.name.isNotEmpty ? preferred.name : fallback.name,
    pathOverride: pathOverride,
    pathOverrideBytes: pathOverrideBytes,
    latitude: preferred.latitude ?? fallback.latitude,
    longitude: preferred.longitude ?? fallback.longitude,
    lastSeen: latestLastSeen,
    lastModified: latestLastModified,
    lastMessageAt: latestMessageAt,
    hasMessages: existing.hasMessages || incoming.hasMessages,
    isActive: existing.isActive || incoming.isActive,
    rawPacket: preferred.rawPacket ?? fallback.rawPacket,
  );
}
