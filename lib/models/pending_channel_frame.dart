import 'dart:typed_data';

/// A received frame that must survive until its channel can be identified.
/// The full node key is used here, independently of historical storage prefixes.
class PendingChannelFrame {
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
