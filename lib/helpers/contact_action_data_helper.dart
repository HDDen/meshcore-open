import 'package:mco_service/mco_service.dart';

import '../connector/meshcore_connector.dart';
import '../models/channel_message.dart';
import '../storage/shared_message_history_helper.dart';
import 'channel_path_signal_helper.dart';

class ContactActionDataHelper {
  const ContactActionDataHelper._();

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
        if (paths.isNotEmpty) {
          records.add(
            McoContactActionMessage(
              senderName: message.senderName,
              receivedAt: message.receivedAt,
              isOutgoing: message.isOutgoing,
              paths: List<McoContactActionPath>.unmodifiable(paths),
            ),
          );
        }
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

  static List<McoContactActionNode> nodes(MeshCoreConnector connector) => [
    for (final node in connector.allContactsUnfiltered)
      if (node.hasLocation)
        McoContactActionNode(
          publicKey: List<int>.unmodifiable(node.publicKey),
          latitude: node.latitude!,
          longitude: node.longitude!,
          lastSeen: node.lastSeen,
        ),
  ];
}
