import 'package:mco_service/mco_service.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../models/channel.dart';
import '../models/channel_message.dart';
import '../storage/shared_message_history_helper.dart';
import 'channel_path_signal_helper.dart';

class ContactActionDataHelper {
  const ContactActionDataHelper._();

  /// What the connector holds in memory, the window of each channel's newest
  /// messages, plus shared history. The estimates of named repeaters are built
  /// on exactly this: routes from further back pull in anchors of a mesh that
  /// has since changed and of far-off repeaters sharing a hop prefix, and the
  /// averaged position drifts away. So this is never widened; a caller that
  /// needs a period of time adds [loadStoredChannelRecordsSince] to it.
  static Future<List<McoContactActionMessage>> loadChannelRecords(
    MeshCoreConnector connector, {
    required bool includeSharedHistory,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;

    final records = <McoContactActionMessage>[];
    final helper = SharedMessageHistoryHelper();
    final seenChannels = <String>{};

    for (final channel in connector.channels) {
      if (cancelled()) return const [];
      if (channel.isEmpty) continue;
      final channelKey = '${channel.name.trim()}|${channel.pskHex}';
      if (!seenChannels.add(channelKey)) continue;

      final primary = connector.getLoadedChannelMessages(channel);
      final secondary =
          includeSharedHistory &&
              !connector.isOfflineMode &&
              connector.selfPublicKeyHex.isNotEmpty
          ? await helper.loadSecondaryChannelMessages(
              currentPublicKeyHex: connector.selfPublicKeyHex,
              channel: channel,
              isCancelled: isCancelled,
            )
          : const <ChannelMessage>[];
      if (cancelled()) return const [];
      final messages = primary.isEmpty && secondary.isNotEmpty
          ? MeshCoreConnector.mergeChannelMessagesPreservingPrimaryOrder(
              [secondary.first],
              secondary.skip(1).toList(growable: false),
            )
          : MeshCoreConnector.mergeChannelMessagesPreservingPrimaryOrder(
              primary,
              secondary,
            );

      var processedMessages = 0;
      for (final message in messages) {
        if (cancelled()) return const [];
        final record = _recordOf(message, connector);
        if (record != null) records.add(record);
        if (++processedMessages % 200 == 0) {
          await Future<void>.delayed(Duration.zero);
          if (cancelled()) return const [];
        }
      }
      await Future<void>.delayed(Duration.zero);
      if (cancelled()) return const [];
    }
    return records;
  }

  /// The current node's channel history that has left the connector's memory,
  /// no older than [since]. It never overlaps [loadChannelRecords], so a search
  /// over a period of time joins the two. An offline scope is synthetic and
  /// has nothing behind its window.
  static Future<List<McoContactActionMessage>> loadStoredChannelRecordsSince(
    MeshCoreConnector connector, {
    required DateTime since,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;
    if (connector.isOfflineMode) return const [];

    final records = <McoContactActionMessage>[];
    final seenChannels = <String>{};
    for (final channel in connector.channels) {
      if (cancelled()) return const [];
      if (channel.isEmpty) continue;
      if (!seenChannels.add('${channel.name.trim()}|${channel.pskHex}')) {
        continue;
      }
      final loaded = connector.getLoadedChannelMessages(channel);
      // The window already reaches that far back: nothing stored to add.
      if (loaded.isNotEmpty && !loaded.first.receivedAt.isAfter(since)) {
        continue;
      }
      final loadedIds = {for (final message in loaded) message.messageId};
      final stored = await _storedReachingBackTo(connector, channel, since);
      if (cancelled()) return const [];

      var processedMessages = 0;
      for (final message in stored) {
        if (message.receivedAt.isBefore(since) ||
            loadedIds.contains(message.messageId)) {
          continue;
        }
        final record = _recordOf(message, connector);
        if (record != null) records.add(record);
        if (++processedMessages % 200 == 0) {
          await Future<void>.delayed(Duration.zero);
          if (cancelled()) return const [];
        }
      }
    }
    return records;
  }

  static const int _firstStoredPage = 1000;
  static const int _largestStoredPage = 16000;

  /// The connector only offers "the newest N stored messages", so the page is
  /// doubled until its oldest message is old enough or the history runs out.
  static Future<List<ChannelMessage>> _storedReachingBackTo(
    MeshCoreConnector connector,
    Channel channel,
    DateTime moment,
  ) async {
    for (var limit = _firstStoredPage; ; limit *= 2) {
      final stored = await connector.loadLatestPersistedChannelMessages(
        channel.index,
        limit: limit,
      );
      if (stored.length < limit ||
          limit >= _largestStoredPage ||
          !stored.first.receivedAt.isAfter(moment)) {
        return stored;
      }
    }
  }

  /// Null for a message that carries no route.
  static McoContactActionMessage? _recordOf(
    ChannelMessage message,
    MeshCoreConnector connector,
  ) {
    final paths = <McoContactActionPath>[];
    final seenPaths = <String>{};
    final variants = message.pathVariants.isNotEmpty
        ? message.pathVariants
        : [message.pathBytes];
    final width = (message.pathHashWidth ?? connector.pathHashByteWidth)
        .clamp(1, 4)
        .toInt();
    for (final variant in variants) {
      if (variant.isEmpty) continue;
      final key = variant.join(',');
      if (!seenPaths.add(key)) continue;
      final reading = ChannelPathSignalHelper.find(
        message.pathObservations,
        variant,
      );
      paths.add(
        McoContactActionPath(
          bytes: List<int>.unmodifiable(variant),
          hashByteWidth: width,
          snr: reading?.snr,
          rssi: reading?.rssi,
        ),
      );
    }
    if (paths.isEmpty) return null;
    return McoContactActionMessage(
      senderName: message.senderName,
      receivedAt: message.receivedAt,
      isOutgoing: message.isOutgoing,
      paths: List<McoContactActionPath>.unmodifiable(paths),
    );
  }

  /// [repeatersOnly] leaves the nodes a route hop can be: a hop is the hash of
  /// a repeater or a room server, never of a chat node that shares the prefix.
  static List<McoContactActionNode> nodes(
    MeshCoreConnector connector, {
    bool repeatersOnly = false,
  }) => [
    for (final node in connector.allContactsUnfiltered)
      if (node.hasLocation && (!repeatersOnly || _canBeHop(node.type)))
        McoContactActionNode(
          publicKey: List<int>.unmodifiable(node.publicKey),
          latitude: node.latitude!,
          longitude: node.longitude!,
          lastSeen: node.lastSeen,
        ),
  ];

  /// Every key a route hop may already belong to, which is what makes any
  /// other hop prefix an unknown repeater: the same two node types
  /// `PathHopResolver` names hops from, and this node itself.
  static List<List<int>> knownHopKeys(MeshCoreConnector connector) => [
    for (final node in connector.allContactsUnfiltered)
      if (_canBeHop(node.type)) List<int>.unmodifiable(node.publicKey),
    if (connector.selfPublicKey != null)
      List<int>.unmodifiable(connector.selfPublicKey!),
  ];

  static bool _canBeHop(int type) =>
      type == advTypeRepeater || type == advTypeRoom;
}
