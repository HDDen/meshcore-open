import 'dart:async';

import 'package:flutter/material.dart';

import '../helpers/mco_image_file_saver.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../models/mco_image_gallery_item.dart';
import '../storage/mco_image_gallery_store.dart';
import '../widgets/mco_image_message.dart';

enum MCOImageGalleryAction { send, edit }

class MCOImageGalleryResult {
  final MCOImageGalleryAction action;
  final MCOImageGalleryItem item;

  const MCOImageGalleryResult({required this.action, required this.item});
}

class MCOImageGalleryScreen extends StatefulWidget {
  const MCOImageGalleryScreen({super.key});

  @override
  State<MCOImageGalleryScreen> createState() => _MCOImageGalleryScreenState();
}

class _MCOImageGalleryScreenState extends State<MCOImageGalleryScreen> {
  final MCOImageGalleryStore _store = MCOImageGalleryStore();
  List<MCOImageGalleryItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadItems());
  }

  Future<void> _loadItems() async {
    final items = await _store.loadItems();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _saveItems() async {
    await _store.saveItems(_items);
  }

  void _selectItem(MCOImageGalleryItem item) {
    final action = item.showPngFallback || item.tryDecodeImage() == null
        ? MCOImageGalleryAction.edit
        : MCOImageGalleryAction.send;
    Navigator.pop(context, MCOImageGalleryResult(action: action, item: item));
  }

  Future<void> _showItemActions(MCOImageGalleryItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                item.showPngFallback
                    ? Icons.data_object_outlined
                    : Icons.image_outlined,
              ),
              title: Text(
                item.showPngFallback
                    ? context.l10n.chat_canvasGalleryShowBIN
                    : context.l10n.chat_canvasGalleryShowPNG,
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _toggleItemDisplay(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(context.l10n.chat_canvasSendToEdit),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.pop(
                  context,
                  MCOImageGalleryResult(
                    action: MCOImageGalleryAction.edit,
                    item: item,
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.save_alt_outlined),
              title: Text(context.l10n.chat_canvasSave),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_saveItem(item));
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                context.l10n.chat_canvasGalleryRemove,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_confirmRemove(item));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _toggleItemDisplay(MCOImageGalleryItem item) {
    setState(() {
      _items = [
        for (final entry in _items)
          if (entry.id == item.id)
            entry.copyWith(showPngFallback: !entry.showPngFallback)
          else
            entry,
      ];
    });
    unawaited(_saveItems());
  }

  Future<void> _saveItem(MCOImageGalleryItem item) async {
    try {
      if (item.showPngFallback) {
        await MCOImageFileSaver.savePngBytes(item.pngBytes);
      } else {
        await MCOImageFileSaver.saveBinaryPayload(item.binaryPayload);
      }
    } catch (error) {
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(error.toString()),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  Future<void> _confirmRemove(MCOImageGalleryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.chat_canvasGalleryRemoveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(context.l10n.common_delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _items = _items.where((entry) => entry.id != item.id).toList();
    });
    await _saveItems();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.photo_library_outlined, size: 28),
              const SizedBox(width: 8),
              const Text(
                'MCOimg',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                ? Center(child: Text(context.l10n.channels_changeGroupEmpty))
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.78,
                        ),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      return _GalleryTile(
                        item: _items[index],
                        onTap: () => _selectItem(_items[index]),
                        onLongPress: () => _showItemActions(_items[index]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  final MCOImageGalleryItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _GalleryTile({
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final image = item.tryDecodeImage();
    final showPng = item.showPngFallback || image == null;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: showPng
                      ? Image.memory(item.pngBytes, fit: BoxFit.contain)
                      : FittedBox(
                          fit: BoxFit.contain,
                          child: MCOImageMessage(image: image, maxSize: 96),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  _Badge('${item.byteLength} B', color: scheme.primary),
                  _Badge('${item.width}x${item.height}', color: scheme.primary),
                  _Badge('v${item.codecVersion}', color: scheme.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge(this.text, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
