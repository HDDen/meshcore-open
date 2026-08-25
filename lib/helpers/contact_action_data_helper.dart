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
  }) async {
    final records = <McoContactActionMessage>[];
    final helper = SharedMessageHistoryHelper();
    final seenChannels = <String>{};

    for (final channel in connector.channels) {
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
            )
          : const <ChannelMessage>[];
      final messages = primary.isEmpty && secondary.isNotEmpty
          ? MeshCoreConnector.mergeChannelMessagesPreservingPrimaryOrder(
              [secondary.first],
              secondary.skip(1).toList(growable: false),
            )
          : MeshCoreConnector.mergeChannelMessagesPreservingPrimaryOrder(
              primary,
              secondary,
            );

      for (final message in messages) {
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
        if (paths.isEmpty) continue;
        records.add(
          McoContactActionMessage(
            senderName: message.senderName,
            receivedAt: message.receivedAt,
            isOutgoing: message.isOutgoing,
            paths: List<McoContactActionPath>.unmodifiable(paths),
          ),
        );
      }
      await Future<void>.delayed(Duration.zero);
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
