import '../models/channel.dart';
import '../storage/channel_identity_store.dart';

/// Two identities that are one channel: [from] went away and [to] took its
/// place with the other parameter kept.
class ChannelIdentityLink {
  final ChannelIdentity from;
  final ChannelIdentity to;

  const ChannelIdentityLink(this.from, this.to);

  @override
  bool operator ==(Object other) =>
      other is ChannelIdentityLink && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => '$from -> $to';
}

/// The rules that tell a renamed or rekeyed channel from a new one. Pure, so
/// the tests pin them without a connector.
class ChannelIdentityReconciler {
  const ChannelIdentityReconciler._();

  /// The link one edit makes: [previous] became [next] with exactly one of
  /// name and key changed. Both changed, or nothing, or an empty slot on
  /// either side: null.
  static ChannelIdentityLink? linkFor(Channel? previous, Channel next) {
    if (previous == null) return null;
    final from = ChannelIdentity.of(previous);
    final to = ChannelIdentity.of(next);
    if (from == null || to == null || from == to) return null;
    final sameKey = from.pskId == to.pskId;
    final sameName = from.name == to.name;
    if (sameKey == sameName) return null;
    return ChannelIdentityLink(from, to);
  }

  /// The links between the node's channel list before a sync and the list
  /// the sync read, compared as sets of pairs: slots play no part, so a
  /// channel moved to another slot is nothing. A pair that vanished links to
  /// every pair that appeared with its key (a rename); failing that, and only
  /// when its key vanished altogether, to every pair that appeared with its
  /// name (a new key). A pair whose key and name both went elsewhere is a
  /// channel removed and another added.
  static List<ChannelIdentityLink> diff(
    Iterable<Channel> previous,
    Iterable<Channel> current,
  ) {
    final before = _identities(previous);
    final after = _identities(current);
    final vanished = before.difference(after);
    final appeared = after.difference(before);
    if (vanished.isEmpty || appeared.isEmpty) return const [];
    final keysAfter = {for (final identity in after) identity.pskId};
    final links = <ChannelIdentityLink>[];
    for (final gone in vanished) {
      final byKey = appeared.where((id) => id.pskId == gone.pskId).toList();
      if (byKey.isNotEmpty) {
        for (final id in byKey) {
          links.add(ChannelIdentityLink(gone, id));
        }
        continue;
      }
      // The key is still there under another name that was there before:
      // nothing of this channel moved.
      if (keysAfter.contains(gone.pskId)) continue;
      for (final id in appeared.where((id) => id.name == gone.name)) {
        links.add(ChannelIdentityLink(gone, id));
      }
    }
    return links;
  }

  static Set<ChannelIdentity> _identities(Iterable<Channel> channels) => {
    for (final channel in channels) ?ChannelIdentity.of(channel),
  };
}
