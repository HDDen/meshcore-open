import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../l10n/l10n.dart';
import '../models/additional_identity_message.dart';
import '../models/contact.dart';
import '../services/additional_identity_inbox.dart';
import '../services/chat_text_scale_service.dart';
import '../widgets/additional_identity_sender_picker.dart';
import '../widgets/chat_route_activity.dart';
import '../widgets/contact_chat_title.dart';
import '../widgets/radio_stats_entry.dart';
import '../widgets/routing_sheet.dart';
import '../widgets/sync_progress_overlay.dart';
import 'chat_screen.dart' show ContactMessageBubble;

class AdditionalIdentityChatScreen extends StatefulWidget {
  const AdditionalIdentityChatScreen({
    super.key,
    required this.inbox,
    required this.connector,
    required this.peer,
    required this.recipientKey,
    required this.recipientName,
    required this.senderKey,
    required this.senderName,
  });

  final AdditionalIdentityInbox inbox;
  final MeshCoreConnector connector;
  final Contact peer;
  final String recipientKey;
  final String recipientName;
  final String senderKey;
  final String senderName;

  @override
  State<AdditionalIdentityChatScreen> createState() =>
      _AdditionalIdentityChatScreenState();
}

class _AdditionalIdentityChatScreenState extends State<AdditionalIdentityChatScreen> {
  static const _pageSize = 100;

  final _route = ChatRouteActivity();
  final _composer = TextEditingController();
  bool _sending = false;
  List<AdditionalIdentityMessage>? _latest;
  final _older = <AdditionalIdentityMessage>[];
  bool _readingOlder = false;
  bool _hasOlder = true;
  bool _readFailed = false;
  int _revision = 0;
  int _deletionRevision = 0;

  @override
  void initState() {
    super.initState();
    widget.inbox.addListener(_reload);
    _reload();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _route.attach(
        register: (isCurrent) => widget.inbox.trackChat(
          widget.recipientKey,
          widget.senderKey,
          () => isCurrent() &&
              WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
        ),
        activate: _markRead,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route.updateRoute(ModalRoute.of(context));
  }

  Future<void> _reload() async {
    final revision = ++_revision;
    final deletionRevision = widget.inbox.deletionRevision;
    try {
      final rows = await widget.inbox.messages(widget.recipientKey, widget.senderKey);
      if (!mounted || revision != _revision) return;
      setState(() {
        _readFailed = false;
        // When live rows push a previously visible row out of the newest
        // page, keep the rows already paged into this screen.
        if (deletionRevision != _deletionRevision) {
          _deletionRevision = deletionRevision;
          _older.clear();
          _hasOlder = true;
        } else if (_older.isNotEmpty && _latest != null && rows.isNotEmpty) {
          final floor = rows.last.rowId;
          final olderIds = {for (final message in _older) message.rowId};
          _older.insertAll(0, [
            for (final message in _latest!)
              if (message.rowId < floor && !olderIds.contains(message.rowId))
                message,
          ]);
        }
        _latest = rows;
      });
    } catch (_) {
      if (mounted && revision == _revision) setState(() => _readFailed = true);
    }
  }

  Future<void> _markRead() async {
    try {
      await widget.inbox.markRead(widget.recipientKey, widget.senderKey);
    } catch (_) {
      if (mounted) setState(() => _readFailed = true);
    }
  }

  Future<void> _loadOlder(AdditionalIdentityMessage oldest) async {
    if (_readingOlder) return;
    setState(() => _readingOlder = true);
    final deletionRevision = widget.inbox.deletionRevision;
    try {
      final rows = await widget.inbox.messages(
        widget.recipientKey,
        widget.senderKey,
        before: (oldest.receivedAtMs, oldest.rowId),
      );
      if (!mounted || deletionRevision != widget.inbox.deletionRevision) return;
      setState(() {
        _older.addAll(rows);
        _hasOlder = rows.length == _pageSize;
      });
    } catch (_) {
      if (mounted) setState(() => _readFailed = true);
    } finally {
      if (mounted) setState(() => _readingOlder = false);
    }
  }

  Future<void> _send() async {
    if (_sending) return;
    final draft = _composer.text;
    final text = draft.trim();
    if (text.isEmpty) return;
    final connector = widget.connector;
    final l10n = context.l10n;
    if (!connector.isConnected || connector.isOfflineMode) {
      _showError(l10n.settings_notConnectedError);
      return;
    }
    final peer = _currentContact(connector);
    final maxBytes = connector.additionalIdentityMaxTextBytes(peer);
    if (maxBytes == 0) {
      _showError(l10n.extraKeys_actionError);
      return;
    }
    final outboundText = connector.prepareAdditionalIdentityOutboundText(
      peer, widget.recipientKey, text,
    );
    if (utf8.encode(outboundText).length > maxBytes) {
      _showError(l10n.chat_messageTooLong(maxBytes));
      return;
    }

    setState(() => _sending = true);
    try {
      if (!await ensureAdditionalIdentityRoomAccess(
        context, connector, widget.recipientKey, peer,
      ) || !mounted) {
        return;
      }
      await connector.sendAdditionalIdentityMessage(widget.recipientKey, peer, text);
      if (mounted && _composer.text == draft) _composer.clear();
    } catch (_) {
      if (mounted) _showError(l10n.extraKeys_actionError);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Contact _currentContact(MeshCoreConnector connector) =>
      connector.getContactByPubKeyHex(widget.senderKey) ?? widget.peer;

  Future<void> _openRouting(Contact contact) => ContactRoutingSheet.show(
    context,
    contact: contact,
    ensureContactBeforeWriting: true,
  );

  void _showError(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    _composer.dispose();
    widget.inbox.removeListener(_reload);
    _route.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textScale = context.select<ChatTextScaleService, double>(
      (service) => service.scale,
    );
    final latestIds = {for (final message in _latest ?? const <AdditionalIdentityMessage>[]) message.rowId};
    final rows = [
      ...?_latest,
      for (final message in _older)
        if (!latestIds.contains(message.rowId)) message,
    ];
    final canPage = rows.isNotEmpty &&
        _hasOlder &&
        (_older.isNotEmpty || (_latest?.length ?? 0) >= _pageSize);
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        toolbarHeight: ContactChatTitle.senderToolbarHeight(context),
        title: Consumer<MeshCoreConnector>(
          builder: (context, connector, _) {
            final contact = _currentContact(connector);
            return ContactChatTitle(
              connector: connector,
              contact: contact,
              senderName: widget.inbox.entryFor(widget.recipientKey)?.name ??
                  widget.recipientName,
              onOpenRouting: () => _openRouting(contact),
            );
          },
        ),
        bottom: const SyncProgressAppBarBottom(),
        actions: [
          Consumer<MeshCoreConnector>(
            builder: (context, connector, _) {
              final contact = _currentContact(connector);
              return ContactChatRoutingButton(
                contact: contact,
                onPressed: () => _openRouting(contact),
              );
            },
          ),
          const RadioStatsIconButton(),
        ],
      ),
      body: SafeArea(
        child: rows.isEmpty
            ? Center(
                child: _readFailed
                    ? Text(l10n.extraKeys_actionError)
                    : _latest == null
                    ? const CircularProgressIndicator()
                    : Text(l10n.chat_noMessages),
              )
            : ListView.builder(
                reverse: true,
                itemCount: rows.length + (canPage ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == rows.length) {
                    return TextButton(
                      onPressed: _readingOlder ? null : () => _loadOlder(rows.last),
                      child: Text(l10n.extraKeys_loadOlder),
                    );
                  }
                  final row = rows[index];
                  final message = row.toChatMessage(
                    identityName: widget.recipientName,
                  );
                  final roomAuthor = row.roomAuthorHex;
                  return Padding(
                    key: ValueKey(row.rowId),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ContactMessageBubble(
                      message: message,
                      senderName: roomAuthor == null
                          ? widget.senderName
                          : '${widget.senderName} [${roomAuthor.toUpperCase()}]',
                      sourceId: widget.senderKey,
                      isRoomChat: widget.peer.type == advTypeRoom,
                      textScale: textScale,
                    ),
                  );
                },
              ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            12, 4, 8, 8 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _composer,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: l10n.chat_typeMessage),
                ),
              ),
              IconButton(
                onPressed: _sending ? null : _send,
                tooltip: l10n.chat_sendMessage,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
