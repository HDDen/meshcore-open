/// Add the author only to an actual, visible message preview. Empty channels
/// retain their channel description; a blocked preview never reveals a name.
String formatChannelPreview(
  String preview, {
  required String? senderName,
  required bool showSender,
  bool blocked = false,
}) {
  final sender = senderName?.trim() ?? '';
  if (!showSender || blocked || preview.isEmpty || sender.isEmpty) {
    return preview;
  }
  return '$sender: $preview';
}
