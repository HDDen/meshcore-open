import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

class ChatComposerSideAction extends StatelessWidget {
  static const double counterReserveHeight = 18;

  final Widget child;

  const ChatComposerSideAction({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: counterReserveHeight),
      child: child,
    );
  }
}

class ChatAdditionalActionsButton extends StatelessWidget {
  final bool canvasActive;
  final VoidCallback onSendGif;
  final VoidCallback onOpenCanvas;
  final VoidCallback onOpenMcoImageGallery;

  const ChatAdditionalActionsButton({
    super.key,
    required this.canvasActive,
    required this.onSendGif,
    required this.onOpenCanvas,
    required this.onOpenMcoImageGallery,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.add_circle_outline),
      tooltip: context.l10n.chat_additionalActions,
      onPressed: () => _showActions(context),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => ChatAdditionalActionsMenu(
        canvasActive: canvasActive,
        onSendGif: () {
          Navigator.pop(sheetContext);
          onSendGif();
        },
        onOpenCanvas: () {
          Navigator.pop(sheetContext);
          onOpenCanvas();
        },
        onOpenMcoImageGallery: () {
          Navigator.pop(sheetContext);
          onOpenMcoImageGallery();
        },
      ),
    );
  }
}

class ChatAdditionalActionsMenu extends StatelessWidget {
  final bool canvasActive;
  final VoidCallback onSendGif;
  final VoidCallback onOpenCanvas;
  final VoidCallback onOpenMcoImageGallery;

  const ChatAdditionalActionsMenu({
    super.key,
    required this.canvasActive,
    required this.onSendGif,
    required this.onOpenCanvas,
    required this.onOpenMcoImageGallery,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.gif_box_outlined),
              title: Text(context.l10n.chat_sendGif),
              onTap: onSendGif,
            ),
            if (canvasActive) ...[
              ListTile(
                leading: const Icon(Icons.brush_outlined),
                title: Text(context.l10n.chat_canvas),
                onTap: onOpenCanvas,
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(context.l10n.chat_MCOimgOpenGallery),
                onTap: onOpenMcoImageGallery,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
