import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';
import '../services/additional_identity_vault.dart';
import '../theme/mesh_theme.dart';
import 'mesh_ui.dart';
import 'middle_ellipsis_text.dart';

/// Selects a public contact card for an unlocked, app-managed key.
class AdditionalIdentityShareContacts extends StatelessWidget {
  const AdditionalIdentityShareContacts({super.key, required this.entries});

  final List<AdditionalIdentityEntry> entries;

  @override
  Widget build(BuildContext context) {
    final keyStyle = MeshTheme.mono(
      fontSize: 9,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Column(
      children: [
        for (final entry in entries)
          MeshCard(
            key: ValueKey(('share-identity', entry.identity.publicKeyHex)),
            padding: EdgeInsets.zero,
            onTap: () => Navigator.of(context).pop(
              Contact(
                publicKey: entry.identity.publicKey,
                name: entry.name,
                type: advTypeChat,
                pathLength: -1,
                path: Uint8List(0),
                lastSeen: DateTime.fromMillisecondsSinceEpoch(0),
              ),
            ),
            child: ListTile(
              leading: AvatarCircle(
                name: entry.name,
                size: 42,
                icon: Icons.key_outlined,
              ),
              title: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: MiddleEllipsisText(
                text: entry.identity.publicKeyHex.toUpperCase(),
                style: keyStyle,
              ),
            ),
          ),
      ],
    );
  }
}
