import 'package:flutter/material.dart';

import '../helpers/channel_sender_name.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n.dart';

/// The *Sender* line of the channel header: the name the channel sends under,
/// or *default* for the node's own. The value is underlined dotted while it
/// can be changed, and the tap area is the text itself, not the row, so the
/// header around it keeps opening the region dialog. A tap under a lock
/// shows why instead of the dialog.
class ChannelSenderNameLine extends StatelessWidget {
  const ChannelSenderNameLine({
    super.key,
    required this.name,
    required this.lock,
    required this.onEdit,
    this.fontSize = 11,
  });

  /// The name in effect, null for the node's own.
  final String? name;
  final ChannelSenderNameLock lock;

  /// Called by a tap while nothing holds the name back.
  final VoidCallback onEdit;
  final double fontSize;

  static String lockMessage(AppLocalizations l10n, ChannelSenderNameLock lock) {
    switch (lock) {
      case ChannelSenderNameLock.none:
        return '';
      case ChannelSenderNameLock.signedMcmp:
        return l10n.channels_senderNameLockedBySign;
      case ChannelSenderNameLock.firmware:
        return l10n.channels_senderNameNeedsFirmware;
      case ChannelSenderNameLock.privateRegion:
        return l10n.channels_senderNamePrivateRegion;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final editable = lock == ChannelSenderNameLock.none;
    final style = TextStyle(fontSize: fontSize, fontWeight: FontWeight.normal);
    return GestureDetector(
      onTap: () {
        if (editable) {
          onEdit();
          return;
        }
        showDismissibleSnackBar(
          context,
          content: Text(lockMessage(l10n, lock)),
        );
      },
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '${l10n.channels_senderNameLabel}: '),
            TextSpan(
              text: name ?? l10n.channels_senderNameDefault,
              style: editable
                  ? const TextStyle(
                      decoration: TextDecoration.underline,
                      decorationStyle: TextDecorationStyle.dotted,
                    )
                  : null,
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}
