import '../models/channel_message.dart';

// An ID can appear in more than one history scope.
typedef ChannelPostIdentity = (String, DateTime, String, String, String?);

ChannelPostIdentity channelPostIdentity(ChannelMessage message) => (
  message.messageId,
  message.timestamp,
  message.senderName,
  message.text,
  message.sharedHistorySourceName,
);
