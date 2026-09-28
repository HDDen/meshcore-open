import '../models/channel_message.dart';

/// Finds the message a reply points at, by id, without scanning the
/// conversation for every reply bubble.
///
/// The transcript hands every bubble the same merged list until something in
/// it changes (`MeshCoreConnector.getChannelMergedMessages` returns a new
/// object only when the timeline is rebuilt), so the index is built once per
/// list object and reused while that object stays the same. A list mutated in
/// place is not seen as new: the contract is identity, which the timeline
/// cache keeps. The first message carrying an id wins, as the linear scan this
/// replaces did.
class ReplyTargetIndex {
  List<ChannelMessage>? _source;
  Map<String, ChannelMessage>? _byId;

  ChannelMessage? find(List<ChannelMessage> source, String messageId) {
    var byId = _byId;
    if (byId == null || !identical(source, _source)) {
      byId = <String, ChannelMessage>{};
      for (final message in source) {
        byId.putIfAbsent(message.messageId, () => message);
      }
      _source = source;
      _byId = byId;
    }
    return byId[messageId];
  }
}
