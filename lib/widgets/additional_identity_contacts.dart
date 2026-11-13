import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../l10n/l10n.dart';
import '../models/additional_identity_message.dart';
import '../models/contact.dart';
import '../screens/additional_identity_chat_screen.dart';
import '../services/additional_identity_inbox.dart';
import '../theme/mesh_theme.dart';
import 'mesh_ui.dart';
import 'middle_ellipsis_text.dart';
import 'unread_badge.dart';

class AdditionalIdentityContacts extends StatefulWidget {
  const AdditionalIdentityContacts({
    super.key,
    required this.inbox,
    required this.connector,
  });

  final AdditionalIdentityInbox inbox;
  final MeshCoreConnector connector;

  @override
  State<AdditionalIdentityContacts> createState() =>
      _AdditionalIdentityContactsState();
}

class _AdditionalIdentityContactsState extends State<AdditionalIdentityContacts> {
  final _expanded = <String>{};
  late Future<Map<String, List<AdditionalIdentityThread>>> _threads;

  @override
  void initState() {
    super.initState();
    widget.inbox.addListener(_refresh);
    _threads = _load();
  }

  @override
  void didUpdateWidget(AdditionalIdentityContacts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inbox == widget.inbox) return;
    oldWidget.inbox.removeListener(_refresh);
    widget.inbox.addListener(_refresh);
    _threads = _load();
  }

  Future<Map<String, List<AdditionalIdentityThread>>> _load() async => {
    for (final entry in widget.inbox.entries)
      entry.identity.publicKeyHex: await widget.inbox.threads(
        entry.identity.publicKeyHex,
      ),
  };

  void _refresh() {
    if (mounted) setState(() => _threads = _load());
  }

  @override
  void dispose() {
    widget.inbox.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mono = MeshTheme.mono(
      fontSize: 9,
      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
    );
    return FutureBuilder(
      future: _threads,
      builder: (context, snapshot) => Column(
        children: [
          for (final entry in widget.inbox.entries)
            Builder(builder: (context) {
              final key = entry.identity.publicKeyHex;
              final contacts = snapshot.data?[key] ?? const [];
              final unread = contacts.fold<int>(0, (total, item) => total + item.unread);
              final expanded = _expanded.contains(key);
              final prefixLength = widget.connector.pathHashByteWidth.clamp(1, 3) * 2;
              return Column(
                children: [
                  MeshCard(
                    key: ValueKey('additional-identity:$key'),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    onTap: () => setState(() {
                      if (!_expanded.remove(key)) _expanded.add(key);
                    }),
                    child: Row(
                      children: [
                        AvatarCircle(name: entry.name, size: 42, icon: Icons.key_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                              MiddleEllipsisText(text: key.toUpperCase(), style: mono),
                              const SizedBox(height: 3),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(MeshRadii.xs),
                                  border: Border.all(color: scheme.outline),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  child: Text(
                                    key.substring(0, prefixLength).toUpperCase(),
                                    style: MeshTheme.mono(fontSize: 13, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (unread > 0) ...[
                          const SizedBox(width: 8),
                          UnreadBadge(count: unread),
                        ],
                        const SizedBox(width: 8),
                        Icon(expanded ? Icons.remove : Icons.add),
                      ],
                    ),
                  ),
                  if (expanded && contacts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        snapshot.hasError
                            ? context.l10n.extraKeys_actionError
                            : snapshot.connectionState == ConnectionState.waiting
                            ? context.l10n.common_loading
                            : context.l10n.chat_noMessages,
                      ),
                    ),
                  if (expanded)
                    for (final contact in contacts)
                      MeshCard(
                        key: ValueKey((key, contact.senderKey)),
                        margin: const EdgeInsets.fromLTRB(32, 2, 16, 2),
                        padding: EdgeInsets.zero,
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => AdditionalIdentityChatScreen(
                              inbox: widget.inbox,
                              connector: widget.connector,
                              peer: widget.connector.getContactByPubKeyHex(contact.senderKey) ??
                                  Contact(
                                    publicKey: hexToPubKey(contact.senderKey),
                                    name: contact.senderName,
                                    type: contact.peerType,
                                    pathLength: -1,
                                    path: Uint8List(0),
                                    lastSeen: DateTime.fromMillisecondsSinceEpoch(0),
                                  ),
                              recipientKey: key,
                              recipientName: entry.name,
                              senderKey: contact.senderKey,
                              senderName: widget.connector
                                  .getContactByPubKeyHex(contact.senderKey)?.name
                                  ?? contact.senderName,
                            ),
                          ),
                        ),
                        child: ListTile(
                          title: Text(
                            widget.connector.getContactByPubKeyHex(contact.senderKey)?.name
                                ?? contact.senderName,
                          ),
                          subtitle: MiddleEllipsisText(
                            text: contact.senderKey.toUpperCase(),
                            style: mono,
                          ),
                          trailing: contact.unread > 0
                              ? UnreadBadge(count: contact.unread)
                              : null,
                        ),
                      ),
                ],
              );
            }),
        ],
      ),
    );
  }
}
