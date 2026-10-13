/// A channel can send under a name of its own instead of the node's: the
/// *Sender* line of the channel header, stored per channel by
/// `ChannelSettingsStore.saveSenderName` and inherited from the owner's other
/// nodes like every channel setting. The name goes into the `"Name: text"`
/// prefix of a plain packet, which the app then builds itself (see
/// `ChannelRawPacket`), and into the name field of the binary envelopes,
/// which the app writes anyway.
///
/// Three things hold it back, in this order. A channel that signs its MCMP
/// v3 bodies cannot carry it: receivers verify the signature against the
/// contact bearing the sender name, so a name they do not know as ours
/// verifies as nobody's, and switching signing on resets the name. A plain
/// packet under the name needs `CMD_SEND_RAW_PACKET`, which stock firmware
/// has from version code 13 (it arrived at 12, on 2026-05-13, so 12 may or
/// may not have it). And a private `$` region keeps its key on the repeater,
/// so the app cannot compute the transport code the raw packet has to carry.
library;

enum ChannelSenderNameLock {
  /// The channel's own name is taken.
  none,

  /// The channel signs MCMP v3 bodies, which verify by the node's own name.
  signedMcmp,

  /// The node's firmware cannot send a packet the app built.
  firmware,

  /// The channel floods under a private region whose key the app lacks.
  privateRegion,
}

ChannelSenderNameLock resolveChannelSenderNameLock({
  required bool signsMcmp,
  required bool firmwareSendsRawPackets,
  required String scope,
}) {
  if (signsMcmp) return ChannelSenderNameLock.signedMcmp;
  if (!firmwareSendsRawPackets) return ChannelSenderNameLock.firmware;
  if (scope.trim().startsWith(r'$')) {
    return ChannelSenderNameLock.privateRegion;
  }
  return ChannelSenderNameLock.none;
}

/// The stored setting read as a name: null for none. The empty string means
/// none as well, and is what a cleared name is stored as rather than the key
/// removed: a missing value is read from the owner's other nodes, and a name
/// cleared here has to shadow theirs, not uncover it.
String? channelSenderNameFromSetting(String? stored) {
  final name = stored?.trim();
  if (name == null || name.isEmpty) return null;
  return name;
}
