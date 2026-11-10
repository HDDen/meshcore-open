import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../helpers/contact_share_helper.dart';
import '../helpers/contact_ui.dart';
import '../l10n/l10n.dart';
import '../theme/mesh_theme.dart';

class SharedContactMessage extends StatefulWidget {
  final SharedContactInfo contact;
  final TextStyle textStyle;
  final Color metaColor;
  final double textScale;
  final Future<void> Function()? onAddContact;

  const SharedContactMessage({
    super.key,
    required this.contact,
    required this.textStyle,
    required this.metaColor,
    required this.textScale,
    required this.onAddContact,
  });

  @override
  State<SharedContactMessage> createState() => _SharedContactMessageState();
}

class _SharedContactMessageState extends State<SharedContactMessage> {
  bool _adding = false;

  Future<void> _addContact() async {
    final add = widget.onAddContact;
    if (add == null || _adding) return;
    setState(() => _adding = true);
    try {
      await add();
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contact = widget.contact;
    final textStyle = widget.textStyle;
    final metaColor = widget.metaColor;
    final textScale = widget.textScale;
    final key = contact.publicKeyHex;
    final status = context.select((MeshCoreConnector connector) => (
      isSelf: connector.selfPublicKeyHex == key,
      saved: connector.getContactByPubKeyHex(key) != null,
      canWrite: connector.isConnected && !connector.isOfflineMode,
    ));
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final typeColor = contactTypeColor(contact.type);
    final typeLabel = switch (contact.type) {
      advTypeRepeater => l10n.chat_contactTypeRepeater,
      advTypeRoom => l10n.chat_contactTypeRoom,
      advTypeSensor => l10n.chat_contactTypeSensor,
      _ => l10n.chat_contactTypeNode,
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 190),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(contactTypeIcon(contact.type), size: 17, color: typeColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  contact.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            contact.shortPublicKey,
            style: MeshTheme.mono(fontSize: 12 * textScale, color: metaColor),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.chat_contactType(typeLabel),
            style: textStyle.copyWith(
              fontSize: 12 * textScale,
              color: typeColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          if (status.isSelf)
            Text(l10n.chat_contactIsYou, style: TextStyle(color: metaColor))
          else ...[
            if (status.saved)
              Text(
                l10n.discoveredContacts_alreadyAdded,
                style: TextStyle(color: metaColor),
              ),
            if (widget.onAddContact != null)
              FilledButton.tonalIcon(
                onPressed: status.canWrite && !_adding ? _addContact : null,
                icon: _adding
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        status.saved ? Icons.refresh : Icons.person_add_alt_1,
                        size: 18,
                      ),
                label: Text(
                  status.saved
                      ? l10n.chat_updateSharedContact
                      : l10n.chat_addContact,
                ),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: scheme.onSecondaryContainer,
                ),
              ),
          ],
          const SizedBox(height: 5),
        ],
      ),
    );
  }
}
