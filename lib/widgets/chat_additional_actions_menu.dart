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
  final VoidCallback onSendSelfContact;
  final VoidCallback onSendMyLocation;
  final VoidCallback onSendContact;
  final VoidCallback onPickLocationFromMap;
  final VoidCallback onSendGif;
  final VoidCallback onOpenCanvas;
  final VoidCallback onOpenMcoImageGallery;

  const ChatAdditionalActionsButton({
    super.key,
    required this.canvasActive,
    required this.onSendSelfContact,
    required this.onSendMyLocation,
    required this.onSendContact,
    required this.onPickLocationFromMap,
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
      isScrollControlled: true,
      builder: (sheetContext) => ChatAdditionalActionsMenu(
        canvasActive: canvasActive,
        onSendSelfContact: () {
          Navigator.pop(sheetContext);
          onSendSelfContact();
        },
        onSendMyLocation: () {
          Navigator.pop(sheetContext);
          onSendMyLocation();
        },
        onSendContact: () {
          Navigator.pop(sheetContext);
          onSendContact();
        },
        onPickLocationFromMap: () {
          Navigator.pop(sheetContext);
          onPickLocationFromMap();
        },
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
  final VoidCallback onSendSelfContact;
  final VoidCallback onSendMyLocation;
  final VoidCallback onSendContact;
  final VoidCallback onPickLocationFromMap;
  final VoidCallback onSendGif;
  final VoidCallback onOpenCanvas;
  final VoidCallback onOpenMcoImageGallery;

  const ChatAdditionalActionsMenu({
    super.key,
    required this.canvasActive,
    required this.onSendSelfContact,
    required this.onSendMyLocation,
    required this.onSendContact,
    required this.onPickLocationFromMap,
    required this.onSendGif,
    required this.onOpenCanvas,
    required this.onOpenMcoImageGallery,
  });

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: Text(context.l10n.chat_sendSelfContact),
                  onTap: onSendSelfContact,
                ),
                ListTile(
                  leading: const Icon(Icons.contact_page_outlined),
                  title: Text(context.l10n.chat_sendContact),
                  onTap: onSendContact,
                ),
                ListTile(
                  leading: const Icon(Icons.my_location),
                  title: Text(context.l10n.chat_myLocation),
                  onTap: onSendMyLocation,
                ),
                ListTile(
                  leading: const Icon(Icons.add_location_alt_outlined),
                  title: Text(context.l10n.chat_locationFromMap),
                  onTap: onPickLocationFromMap,
                ),
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
        ),
      ),
    );
  }
}
