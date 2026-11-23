import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/message_url_image_helper.dart';
import '../helpers/bookmark_destination.dart';
import 'channel_chat_screen.dart';
import 'chat_screen.dart';
import '../l10n/l10n.dart';
import '../models/bookmarked_message.dart';
import '../services/app_settings_service.dart';
import 'package:flutter/services.dart';
import '../widgets/empty_state.dart';
import '../widgets/translated_message_content.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  late Future<List<BookmarkedMessage>> _bookmarks;

  String? _nodeKey;
  int _revision = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final connector = context.watch<MeshCoreConnector>();
    if (_nodeKey != connector.storageKeyHex ||
        _revision != connector.bookmarkRevision) {
      _nodeKey = connector.storageKeyHex;
      _revision = connector.bookmarkRevision;
      _bookmarks = connector.loadBookmarkedMessages();
    }
  }

  void _reload() {
    setState(() {
      _bookmarks = context.read<MeshCoreConnector>().loadBookmarkedMessages();
    });
  }

  Future<void> _remove(BookmarkedMessage bookmark) async {
    try {
      await context.read<MeshCoreConnector>().setBookmarkedMessage(
        bookmark,
        isBookmarked: false,
        expectedNodeKey: _nodeKey,
      );
      if (mounted) _reload();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.bookmarks_saveFailed)),
        );
      }
    }
  }

  void _openOriginal(BookmarkedMessage bookmark) {
    final connector = context.read<MeshCoreConnector>();
    if (_nodeKey != connector.storageKeyHex) return;
    final destination = bookmarkDestination(
      bookmark,
      channels: connector.channels,
      contacts: connector.contacts,
    );
    if (destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.chat_originalMessageNotFound)),
      );
      return;
    }
    final channel = destination.channel;
    final contact = destination.contact;
    final Widget chat;
    if (channel != null) {
      final unread = connector.getUnreadCountForChannelIndex(channel.index);
      connector.markChannelRead(channel.index);
      chat = ChannelChatScreen(
        channel: channel,
        initialUnreadCount: unread,
        initialMessageId: bookmark.messageId,
      );
    } else {
      chat = ChatScreen(
        contact: contact!,
        initialUnreadCount: connector.getUnreadCountForContactKey(
          contact.publicKeyHex,
        ),
        initialMessageId: bookmark.messageId,
        showRadioHistoryInitially: true,
      );
    }
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => chat));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final publicIpfsGateway = context
        .watch<AppSettingsService>()
        .settings
        .publicIpfsGateway;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.bookmarks_title), centerTitle: true),
      body: FutureBuilder<List<BookmarkedMessage>>(
        future: _bookmarks,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(l10n.bookmarks_saveFailed));
          }
          final bookmarks = snapshot.data ?? const <BookmarkedMessage>[];
          if (bookmarks.isEmpty) {
            return EmptyState(
              icon: Icons.bookmark_border,
              title: l10n.bookmarks_empty,
            );
          }
          bookmarks.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
          return ListView.builder(
            reverse: true,
            padding: const EdgeInsets.all(12),
            itemCount: bookmarks.length,
            itemBuilder: (context, index) {
              final bookmark = bookmarks[bookmarks.length - 1 - index];
              final sourceType =
                  bookmark.sourceType == BookmarkSourceType.channel
                  ? l10n.bookmarks_channel
                  : l10n.bookmarks_contact;
              final receivedAt = bookmark.receivedAt.toLocal();
              final localizations = MaterialLocalizations.of(context);
              final time = localizations.formatTimeOfDay(
                TimeOfDay.fromDateTime(receivedAt),
                alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(
                  context,
                ),
              );
              final dateTime =
                  '${localizations.formatShortDate(receivedAt)} $time';
              final translation = bookmark.translatedText?.trim();
              final displayText = translation?.isNotEmpty == true
                  ? translation!
                  : bookmark.text;
              final textStyle =
                  Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
              final textContent = TranslatedMessageContent(
                displayText: displayText,
                originalText: displayText == bookmark.text
                    ? null
                    : bookmark.text,
                style: textStyle,
                originalStyle: textStyle.copyWith(fontStyle: FontStyle.italic),
              );
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: () => _openOriginal(bookmark),
                  borderRadius:
                      Theme.of(context).cardTheme.shape
                          is RoundedRectangleBorder
                      ? (Theme.of(context).cardTheme.shape!
                                as RoundedRectangleBorder)
                            .borderRadius
                            .resolve(Directionality.of(context))
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2, right: 8),
                              child: Icon(
                                Icons.bookmark,
                                size: 20,
                                color: Color(0xFFFFE54A),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$sourceType · ${bookmark.sourceName}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${bookmark.senderName} · $dateTime',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.common_copy,
                              onPressed: () => Clipboard.setData(
                                ClipboardData(text: bookmark.text),
                              ),
                              icon: const Icon(Icons.copy),
                            ),
                            IconButton(
                              tooltip: l10n.bookmarks_remove,
                              onPressed: () => _remove(bookmark),
                              icon: const Icon(Icons.bookmark_remove_outlined),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (MessageUrlImageHelper.hasPotentialImageUrl(
                          bookmark.text,
                        ))
                          MessageUrlImageFutureBuilder(
                            messageId: bookmark.messageId,
                            text: bookmark.text,
                            publicGateway: publicIpfsGateway,
                            builder: (context, snapshot) {
                              final imageUrl = snapshot.data;
                              if (imageUrl == null) {
                                return textContent;
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: MessageUrlImagePreview(
                                      imageUrl: imageUrl,
                                    ),
                                  ),
                                  textContent,
                                ],
                              );
                            },
                          )
                        else
                          textContent,
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
