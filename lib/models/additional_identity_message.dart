import 'message.dart';

/// A message in a thread identified by the app-owned key and its peer.
/// Both keys are full public keys, independent of the connected radio.
typedef AdditionalIdentityMessage = ({
  String recipientKey,
  String senderKey,
  String senderName,
  int peerType,
  String? roomAuthorHex,
  int timestampSeconds,
  int receivedAtMs,
  String wireText,
  String text,
  bool isUnread,
  bool isOutgoing,
  MessageStatus status,
  int rowId,
});

typedef AdditionalIdentityThread = ({
  String senderKey,
  String senderName,
  int peerType,
  int unread,
});
