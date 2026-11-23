import '../models/bookmarked_message.dart';
import '../models/channel.dart';
import '../models/contact.dart';
import '../storage/channel_identity_store.dart';
import '../storage/contact_identity_store.dart';

/// Resolve stable identities before considering legacy slot-based bookmarks.
({Channel? channel, Contact? contact})? bookmarkDestination(
  BookmarkedMessage bookmark, {
  required Iterable<Channel> channels,
  required Iterable<Contact> contacts,
}) {
  if (bookmark.sourceType == BookmarkSourceType.contact) {
    final key = ContactIdentities.normalizeKey(bookmark.sourceId);
    final exact = contacts
        .where((contact) => contact.publicKeyHex == key)
        .firstOrNull;
    final linkedKeys = ContactIdentities.instance.keysOf(key);
    final linked =
        exact ??
        contacts
            .where((contact) => linkedKeys.contains(contact.publicKeyHex))
            .firstOrNull;
    return linked == null ? null : (channel: null, contact: linked);
  }
  final source = bookmark.sourceId;
  if (source.startsWith('slot:')) {
    final slot = int.tryParse(source.substring(5));
    final match = channels
        .where(
          (channel) =>
              channel.index == slot &&
              channel.storageId == null &&
              channel.name == bookmark.sourceName,
        )
        .firstOrNull;
    return match == null ? null : (channel: match, contact: null);
  }
  final linked = ChannelIdentities.instance.findInGroup(
    channels,
    ChannelIdentity(source, bookmark.sourceName.trim()),
  );
  if (linked != null) return (channel: linked, contact: null);
  final sameKey = channels
      .where((channel) => channel.storageId == source)
      .toList();
  return sameKey.length == 1 ? (channel: sameKey.single, contact: null) : null;
}
