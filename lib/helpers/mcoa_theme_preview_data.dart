import 'package:flutter/foundation.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../models/app_settings.dart';
import '../models/channel.dart';
import '../models/channel_message.dart';
import '../models/contact.dart';
import '../models/message.dart';
import '../models/message_compression.dart';
import '../services/app_settings_service.dart';

/// Synthetic fixtures only. Never construct a live connector for a preview:
/// its constructor attaches shared history and notification services.
class McoaThemePreviewData extends ChangeNotifier implements MeshCoreConnector {
  McoaThemePreviewData({
    required DateTime openedAt,
    required String incomingText,
    required String outgoingText,
    required String defaultSender,
  }) {
    final time = DateTime(openedAt.year, openedAt.month, openedAt.day - 2, 18, 30);
    final replyTime = time.add(const Duration(minutes: 1));
    final path = Uint8List.fromList([0xaa, 0xaa, 0xaa, 0xaa]);
    alice = Contact(
      publicKey: _key('abcdef0123456789'),
      name: 'Alice',
      type: advTypeChat,
      pathLength: 0,
      path: Uint8List(0),
      lastSeen: time,
    );
    bob = Contact(
      publicKey: _key('fedcba9876543210'),
      name: 'Bob',
      type: advTypeRepeater,
      pathLength: -1,
      path: Uint8List(0),
      latitude: 50,
      longitude: 30,
      lastSeen: time,
    );
    chatChannel = Channel(
      index: 0,
      name: '#channel0',
      psk: Uint8List.fromList(List.filled(16, 0x42)),
    );
    channels = [
      Channel(
        index: 0,
        name: 'Public',
        psk: _hex(Channel.publicChannelPsk),
        unreadCount: 1,
      ),
      Channel(
        index: 7,
        name: 'Echo',
        psk: Uint8List.fromList(List.filled(16, 0x43)),
      ),
    ];
    channelMessages = [
      ChannelMessage(
        messageId: 'theme-channel-incoming',
        senderName: 'senderName',
        text: incomingText,
        timestamp: time,
        receivedAt: time,
        isOutgoing: false,
        status: ChannelMessageStatus.sent,
        channelIndex: 0,
        pathLength: 2,
        pathHashWidth: 2,
        pathBytes: path,
        snr: 4.8,
        rssi: -89,
        repeatCount: 1,
        packetRegion: 'any-region',
        packetRegionInfoAvailable: true,
      ),
      ChannelMessage(
        messageId: 'theme-channel-outgoing',
        senderName: defaultSender,
        text: outgoingText,
        timestamp: replyTime,
        receivedAt: replyTime,
        sentByRadioAt: replyTime,
        sentByRadioWaitSeconds: const [0],
        isOutgoing: true,
        status: ChannelMessageStatus.sent,
        channelIndex: 0,
        pathLength: 2,
        pathHashWidth: 2,
        pathBytes: path,
        snr: -1.3,
        rssi: -98,
        repeatCount: 2,
        resendCount: 2,
        sentWithTxPowerBoost: true,
        packetRegion: 'any-region',
        packetRegionInfoAvailable: true,
        compressionType: MessageCompressionType.mcmp,
        compressionSavingsPercent: 65,
        containerTimestamp: replyTime.millisecondsSinceEpoch ~/ 1000,
        wasBinaryTransport: true,
      ),
    ];
    directMessages = [
      Message(
        messageId: 'theme-direct-incoming',
        senderKey: alice.publicKey,
        text: incomingText,
        timestamp: time,
        receivedAt: time,
        isOutgoing: false,
        status: MessageStatus.delivered,
        compressionType: MessageCompressionType.mcmp,
        compressionSavingsPercent: 85,
        containerTimestamp: time.millisecondsSinceEpoch ~/ 1000,
      ),
      Message(
        messageId: 'theme-direct-outgoing',
        senderKey: alice.publicKey,
        text: outgoingText,
        timestamp: replyTime,
        receivedAt: replyTime,
        isOutgoing: true,
        status: MessageStatus.delivered,
        deliveredAt: replyTime.add(const Duration(milliseconds: 1200)),
        tripTimeMs: 1200,
        airtimeMs: 549,
        sentByRadioAt: replyTime,
        sentByRadioWaitSeconds: const [0],
        repeatCount: 1,
        sentWithTxPowerBoost: true,
        packetRegion: 'any-region',
        packetRegionInfoAvailable: true,
        compressionType: MessageCompressionType.mcotxt,
        compressionSavingsPercent: 55,
      ),
    ];
    previews = [
      ChannelMessage(
        senderName: 'Alice',
        text: incomingText,
        timestamp: time,
        receivedAt: time,
        isOutgoing: false,
        status: ChannelMessageStatus.sent,
      ),
      ChannelMessage(
        senderName: 'Bob',
        text: outgoingText,
        timestamp: replyTime,
        receivedAt: replyTime,
        isOutgoing: false,
        status: ChannelMessageStatus.sent,
      ),
    ];
    selfName = defaultSender;
  }

  static Uint8List _key(String alphabet) => _hex(List.filled(4, alphabet).join());

  static Uint8List _hex(String value) => Uint8List.fromList([
    for (var i = 0; i < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ]);

  late final Contact alice;
  late final Contact bob;
  late final Channel chatChannel;
  @override
  late final List<Channel> channels;
  late final List<ChannelMessage> channelMessages;
  late final List<ChannelMessage> previews;
  late final List<Message> directMessages;
  @override
  late final String? selfName;

  // A deliberately closed, render-only interface. Unexpected commands fail
  // locally instead of reaching a radio or touching application storage.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final member = invocation.memberName;
    if (member == #pathHashByteWidth) return 2;
    if (member == #currentSf) return 7;
    if (member == #isOfflineMode) return true;
    if (member == #channelDisplayName) return chatChannel.name;
    if (member == #getChannelRegion) return 'any-region';
    if (member == #hasChannelRegion || member == #isChannelCyr2LatEnabled) {
      return true;
    }
    if (member == #getUnreadCountForChannel) {
      return (invocation.positionalArguments.first as Channel).unreadCount;
    }
    if (member == #latestChannelPreviewMessage) {
      final channel = invocation.positionalArguments.first as Channel;
      return previews[channel.index == 0 ? 0 : 1];
    }
    if (const {
      #canStopChannelSending,
      #isChannelFilterEnabled,
      #isContactUrlImagesEnabled,
      #isChannelMcmpEnabled,
      #isChannelSmazEnabled,
      #isChannelExplicitlyUnscoped,
      #channelUsesRadioDefaultScope,
      #supportsExplicitUnscopedFlood,
    }.contains(member)) {
      return false;
    }
    if (const {
      #channelResendProgress,
      #channelHopShortfall,
      #pendingChannelSendAt,
      #pendingChannelSendDelaySeconds,
      #getChannelWidgetColor,
      #getChannelWidgetTextColor,
      #defaultRegionScopeLabel,
    }.contains(member)) {
      return null;
    }
    throw UnsupportedError('Theme preview cannot call $member');
  }
}

/// Settings snapshot: never load or update persisted preferences.
class McoaThemePreviewSettings extends AppSettingsService {
  McoaThemePreviewSettings(AppSettings source)
    : _preview = source.copyWith(
        enableMessageTracing: true,
        enableTimeSeconds: true,
        showCompressionRatio: true,
        showHops: true,
        showLastHopSignal: true,
        showMessageRegion: true,
        regionOnHopsLine: true,
        showChannelPreviewSender: true,
        noRetransmissionWarningSeconds: 0,
      );

  final AppSettings _preview;

  @override
  AppSettings get settings => _preview;
}
