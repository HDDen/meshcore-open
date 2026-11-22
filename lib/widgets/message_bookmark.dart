import 'package:flutter/material.dart';
import '../connector/meshcore_connector.dart';
import '../models/bookmarked_message.dart';
import '../l10n/l10n.dart';

class MessageBookmarkAction extends StatelessWidget {
  const MessageBookmarkAction({super.key, required this.connector, required this.bookmark});
  final MeshCoreConnector connector;
  final BookmarkedMessage bookmark;

  @override
  Widget build(BuildContext context) {
    final marked = connector.isMessageBookmarked(bookmark.sourceType, bookmark.sourceId, bookmark.messageId);
    final nodeKey = connector.storageKeyHex;
    return ListTile(
      leading: Icon(marked ? Icons.bookmark_remove_outlined : Icons.bookmark_add_outlined),
      title: Text(marked ? context.l10n.chat_removeBookmark : context.l10n.chat_bookmark),
      enabled: nodeKey.isNotEmpty,
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        final failure = context.l10n.bookmarks_saveFailed;
        Navigator.pop(context);
        try {
          await connector.setBookmarkedMessage(bookmark, isBookmarked: !marked, expectedNodeKey: nodeKey);
        } on Object {
          if (messenger.mounted) {
            messenger.showSnackBar(SnackBar(content: Text(failure)));
          }
        }
      },
    );
  }
}

class MessageBookmarkBadge extends StatelessWidget {
  const MessageBookmarkBadge({super.key, required this.marked, required this.child, this.cornerRadius = 18});
  final bool marked;
  final double cornerRadius;
  final Widget child;
  @override
  Widget build(BuildContext context) => !marked ? child : Stack(
    clipBehavior: Clip.none,
    children: [child,
      Positioned(top: (cornerRadius - 2).clamp(0.0, double.infinity).toDouble(), left: -20, child: IgnorePointer(
      child: Icon(Icons.bookmark, size: 14, color: Theme.of(context).colorScheme.primary),
    ))],
  );
}
