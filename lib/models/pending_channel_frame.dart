import 'dart:typed_data';

/// A received frame awaiting its channel or sender metadata.
/// The full node key is used here, independently of historical storage prefixes.
class PendingChannelFrame {
  /// Radio channel indices are unsigned bytes. This value reserves rows
  /// for direct and room messages awaiting the initial contact list.
  static const contactMessageIndex = -1;

  const PendingChannelFrame({
    required this.id,
    required this.nodeKey,
    required this.channelIndex,
    required this.frame,
    required this.receivedAt,
    this.channelName,
    this.channelKey,
  });

  final String id;
  final String nodeKey;
  final int channelIndex;
  final Uint8List frame;
  final DateTime receivedAt;
  final String? channelName;
  final String? channelKey;

  PendingChannelFrame bind(String name, String? key) => PendingChannelFrame(
    id: id,
    nodeKey: nodeKey,
    channelIndex: channelIndex,
    frame: frame,
    receivedAt: receivedAt,
    channelName: name,
    channelKey: key,
  );
}
