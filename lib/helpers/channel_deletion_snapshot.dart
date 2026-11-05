import '../models/channel.dart';
import '../storage/channel_identity_store.dart';
import '../storage/channel_message_store.dart';
import '../storage/channel_region_store.dart';
import '../storage/channel_settings_store.dart';
import '../storage/channel_store.dart';

/// Deletion owns the node and names captured before the radio write. A refresh
/// may empty/reuse the slot, and another connection may rebind the live stores.
/// Neither is a reason to clear data belonging to that new slot or connection.
class ChannelDeletionSnapshot {
  ChannelDeletionSnapshot({
    required this.nodeKey,
    required this.index,
    required Channel? channel,
    required Iterable<String> otherScopes,
  }) : identity = channel == null ? null : ChannelIdentity.of(channel),
       otherScopes = Set.unmodifiable(otherScopes) {
    final original = identity;
    members = original == null
        ? const <ChannelIdentity>{}
        : Set.unmodifiable(ChannelIdentities.instance.membersOf(original));
    names = Set.unmodifiable(members.map((member) => member.name));
    imageIds = Set.unmodifiable(members.map((member) => member.pskId));
  }

  final String nodeKey;
  final int index;
  final ChannelIdentity? identity;
  final Set<String> otherScopes;
  late final Set<ChannelIdentity> members;
  late final Set<String> names;
  late final Set<String> imageIds;

  bool matches(Channel? channel) =>
      channel != null &&
      identity != null &&
      ChannelIdentity.of(channel) == identity;

  /// Names are storage identities in this fork. Even distinct keys with the
  /// same name share that data; a PSK-only comparison would erase it.
  bool sharesDataWith(Channel channel) {
    if (channel.isEmpty) {
      return false;
    }
    if (names.contains(channel.name.trim())) {
      return true;
    }
    final candidate = ChannelIdentity.of(channel);
    return candidate != null &&
        ChannelIdentities.instance.namesOf(candidate).any(names.contains);
  }

  bool heldByAnotherSlot(Iterable<Channel> channels) => channels.any(
    (channel) => channel.index != index && sharesDataWith(channel),
  );

  /// Called only after a successful radio write, including when refresh fails.
  /// The short-lived stores intentionally have no slot bindings: legacy index
  /// keys are cleared separately, then exactly the captured names are cleared.
  Future<void> clear({
    required bool allNodes,
    required bool keepLocalData,
  }) async {
    final history = ChannelMessageStore()..setPublicKeyHex = nodeKey;
    final settings = ChannelSettingsStore()..setPublicKeyHex = nodeKey;
    final regions = ChannelRegionStore()..setPublicKeyHex = nodeKey;
    await history.clearChannelMessages(index);
    await settings.clearChannelSettings(index);
    await regions.clearRegion(index);
    // Deleting a duplicate slot is not deleting the still-open channel.
    if (keepLocalData) {
      return;
    }

    await history.clearMessagesForNames(names);
    await settings.clearSettingsForNames(names);
    await regions.clearRegionsForNames(names);
    if (allNodes) {
      for (final scope in otherScopes) {
        await (ChannelMessageStore()..setPublicKeyHex = scope)
            .clearMessagesForNames(names);
        await (ChannelSettingsStore()..setPublicKeyHex = scope)
            .clearSettingsForNames(names);
        await (ChannelRegionStore()..setPublicKeyHex = scope)
            .clearRegionsForNames(names);
      }
    } else {
      for (final scope in otherScopes) {
        final channels = await (ChannelStore()..setPublicKeyHex = scope)
            .loadChannels(allowLegacyMigration: false);
        if (channels.any(
          (channel) => members.contains(ChannelIdentity.of(channel)),
        )) {
          return;
        }
      }
    }
    final original = identity;
    if (original != null &&
        // A concurrent rename/rekey can extend the group during refresh.
        // Keep the expanded group rather than forgetting its new aliases.
        ChannelIdentities.instance.membersOf(original).every(members.contains)) {
      await ChannelIdentities.instance.forget(original);
    }
  }
}
