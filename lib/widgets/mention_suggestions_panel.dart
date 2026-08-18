import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../theme/mesh_theme.dart';

/// Contact picker that rises from behind the composer while an `@name` is
/// being typed. It is only as tall as it needs to be — a couple of matches
/// take a couple of rows, not half the screen.
class MentionSuggestionsPanel extends StatelessWidget {
  const MentionSuggestionsPanel({
    super.key,
    required this.contacts,
    required this.onSelected,
  });

  final List<Contact> contacts;
  final ValueChanged<Contact> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.35;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      // The composer must keep the caret while the user picks a name: taking
      // focus here would close the picker before the tap is delivered.
      child: ExcludeFocus(
        child: Material(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(MeshRadii.md),
          clipBehavior: Clip.antiAlias,
          elevation: 3,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: contacts.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, indent: 12, endIndent: 12),
              itemBuilder: (context, index) {
                final contact = contacts[index];
                // Pointer-down, not a tap: touching the panel pulls focus out
                // of the composer, which closes the panel and would cancel a
                // tap that has not finished yet.
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => onSelected(contact),
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    leading: const Icon(Icons.alternate_email, size: 20),
                    title: Text(
                      contact.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
