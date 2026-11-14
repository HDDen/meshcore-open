import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../helpers/composer_draft_cache.dart';
import '../l10n/l10n.dart';
import '../models/additional_identity_message.dart';
import '../models/contact.dart';
import '../services/additional_identity_inbox.dart';
import '../services/app_settings_service.dart';
import '../services/chat_text_scale_service.dart';
import '../widgets/additional_identity_sender_picker.dart';
import '../widgets/chat_route_activity.dart';
import '../widgets/contact_chat_composer.dart';
import '../widgets/contact_chat_title.dart';
import '../widgets/contact_composer_actions.dart';
import '../widgets/markup_text_editing_controller.dart';
import '../widgets/quick_actions_button.dart';
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
  final _composer = MarkupTextEditingController();
  final _composerFocus = FocusNode();
  bool _sending = false;
  List<AdditionalIdentityMessage>? _latest;
  final _older = <AdditionalIdentityMessage>[];
  bool _readingOlder = false;
  bool _hasOlder = true;
  bool _readFailed = false;
  int _revision = 0;
  int _deletionRevision = 0;

  String get _draftKey => ComposerDraftCache.additionalIdentityKey(
    widget.recipientKey,
    widget.senderKey,
  );

  @override
  void initState() {
    super.initState();
    final draft = ComposerDraftCache.read(_draftKey);
    if (draft != null) {
      _lastDraft = draft;
      _composer.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
    }
    _composer.addListener(_saveDraft);
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

  String _lastDraft = '';

  void _saveDraft() {
    final text = _composer.text;
    if (text == _lastDraft) return;
    _lastDraft = text;
    ComposerDraftCache.write(_draftKey, text);
  }

  Future<void> _send({String? quickAnswerText}) async {
    if (_sending) return;
    final draft = _composer.text;
    final text = quickAnswerText ?? draft.trim();
    if (text.trim().isEmpty) return;
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
      if (mounted && quickAnswerText == null && _composer.text == draft) {
        _composer.clear();
        _composerFocus.requestFocus();
      }
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
    _composer.removeListener(_saveDraft);
    _composer.dispose();
    _composerFocus.dispose();
    widget.inbox.removeListener(_reload);
    _route.dispose();
    super.dispose();
  }

  Widget _buildComposer(BuildContext context, MeshCoreConnector connector) {
    final contact = _currentContact(connector);
    final settings = context.watch<AppSettingsService>().settings;
    final offline = connector.isOfflineMode;
    final maxBytes = connector.additionalIdentityMaxTextBytes(contact);
    String encode(String text) => connector.prepareAdditionalIdentityOutboundText(
      contact, widget.recipientKey, text,
    );

    return ContactChatComposer(
      contactName: contact.name,
      controller: _composer,
      focusNode: _composerFocus,
      maxBytes: maxBytes,
      encoder: encode,
      enabled: !offline && maxBytes > 0,
      showRetryLimit: false,
      insertedTextLimit: connector.isContactMcmpEnabled(contact.publicKeyHex)
          ? settings.mcmpTextLimit
          : null,
      onSend: _sending || offline ? null : () => unawaited(_send()),
      onQuickAnswers: _sending || offline
          ? null
          : () => unawaited(ContactComposerActions.showQuickAnswers(
                context,
                connector: connector,
                contact: contact,
                controller: _composer,
                focusNode: _composerFocus,
                send: (text) => _send(quickAnswerText: text),
              )),
      actions: ContactComposerActions(
        connector: connector,
        contact: contact,
        controller: _composer,
        focusNode: _composerFocus,
        maxBytes: maxBytes,
        identityKey: widget.recipientKey,
        encoder: encode,
        onSend: ({quickAnswerText, standalone = false}) =>
            _send(quickAnswerText: quickAnswerText),
      ),
    );
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
          const QuickActionsHeaderButton(header: QuickActionsHeader.contact),
          const RadioStatsIconButton(),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
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
          ),
          Consumer<MeshCoreConnector>(builder: (context, connector, _) => _buildComposer(context, connector)),
        ],
      ),
    );
  }
}
