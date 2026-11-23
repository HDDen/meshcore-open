import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/received_image_store.dart';
import '../theme/mcoa_theme_style.dart';

/// AEIC entries live outside the text-message store and need their own actions.
class ReceivedImageActions extends StatelessWidget {
  const ReceivedImageActions({
    super.key,
    required this.entry,
    required this.store,
    required this.child,
  });

  final ReceivedImageEntry entry;
  final ReceivedImageStore store;
  final Widget child;

  Future<void> _showActions(BuildContext context) async {
    final current = store.entryFor(entry.streamId);
    if (current == null) return;
    final l10n = context.l10n;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.receivedImage_packetInfo),
              onTap: () => Navigator.pop(context, 'info'),
            ),
            if (current.canRetryDecode &&
                current.state != ReceivedImageState.decoding)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: Text(l10n.receivedImage_decodeAgain),
                onTap: () => Navigator.pop(context, 'decode'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              iconColor: McoaThemeStyle.of(context).colors['warning'],
              textColor: McoaThemeStyle.of(context).colors['warning'],
              title: Text(l10n.common_delete),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || store.entryFor(entry.streamId) == null) return;
    switch (action) {
      case 'decode':
        await store.requestDecode(entry.streamId);
      case 'delete':
        await store.deleteImage(entry.streamId);
      case 'info':
        final latest = store.entryFor(entry.streamId)!;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.receivedImage_packetInfo),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.receivedImage_incoming(
                      latest.receivedChunks,
                      latest.totalChunks,
                    ),
                  ),
                  for (var i = 0; i < latest.chunkRepeats.length; i++)
                    Text(
                      i < latest.totalChunks
                          ? l10n.receivedImage_packetEchoes(
                              i + 1,
                              latest.chunkRepeats[i],
                            )
                          : l10n.receivedImage_recoveryPacketEchoes(
                              latest.chunkRepeats[i],
                            ),
                    ),
                  if (latest.recoveredWithParity)
                    Text(l10n.receivedImage_parityRecovered),
                  if (latest.decodeMs != null)
                    Text(l10n.receivedImage_decodeTime(latest.decodeMs!)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.common_close),
              ),
            ],
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onLongPress: () => unawaited(_showActions(context)),
    onSecondaryTapUp: (_) => unawaited(_showActions(context)),
    child: child,
  );
}
