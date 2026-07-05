import 'package:flutter/material.dart';

import '../connector/meshcore_protocol.dart';
import '../helpers/contact_share_helper.dart';
import '../helpers/contact_ui.dart';
import '../l10n/l10n.dart';
import '../theme/mesh_theme.dart';

class SharedContactMessage extends StatelessWidget {
  final SharedContactInfo contact;
  final TextStyle textStyle;
  final Color metaColor;
  final double textScale;
  final VoidCallback onAddContact;

  const SharedContactMessage({
    super.key,
    required this.contact,
    required this.textStyle,
    required this.metaColor,
    required this.textScale,
    required this.onAddContact,
  });

  @override
  Widget build(BuildContext context) {
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
            style: MeshTheme.mono(
              fontSize: 12 * textScale,
              color: metaColor,
            ),
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
          FilledButton.tonalIcon(
            onPressed: onAddContact,
            icon: const Icon(Icons.person_add_alt_1, size: 18),
            label: Text(l10n.chat_addContact),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: scheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 5),
        ],
      ),
    );
  }
}
