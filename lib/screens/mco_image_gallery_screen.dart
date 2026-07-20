import 'dart:async';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';

import '../helpers/mco_image_file_saver.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../models/mco_image_gallery_item.dart';
import '../models/mco_image_pack.dart';
import '../services/mco_image_pack_originals.dart';
import '../storage/mco_image_gallery_store.dart';
import '../widgets/mco_image_message.dart';
import '../widgets/mco_image_original.dart';

enum MCOImageGalleryAction { send, edit }

enum _GalleryMenuAction { addPack, removePack }

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
  final Set<String> _collapsedGroupIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadItems());
  }

  Future<void> _loadItems() async {
    final results = await Future.wait([
      _store.loadItems(),
      _store.loadCollapsedGroupIds(),
    ]);
    final items = results[0] as List<MCOImageGalleryItem>;
    final collapsedGroupIds = results[1] as Set<String>;
    if (!mounted) return;
    setState(() {
      _items = items;
      _collapsedGroupIds
        ..clear()
        ..addAll(collapsedGroupIds);
      _loading = false;
    });
  }

  Future<void> _saveItems() async {
    await _store.saveItems(_items);
  }

  Future<void> _selectItem(MCOImageGalleryItem item) async {
    final action = item.showPngFallback || item.tryDecodeImage() == null
        ? MCOImageGalleryAction.edit
        : MCOImageGalleryAction.send;
    final resultItem = action == MCOImageGalleryAction.edit
        ? await _itemForEdit(item)
        : item;
    if (!mounted) return;
    Navigator.pop(
      context,
      MCOImageGalleryResult(action: action, item: resultItem),
    );
  }

  Future<MCOImageGalleryItem?> _resolvePackOriginal(
    MCOImageGalleryItem item,
  ) async {
    if (!item.isPackItem || item.originalRelativePaths.isEmpty) return item;
    final resolved = await McoImagePackOriginals.instance
        .resolveOriginalCandidates(item.originalRelativePaths);
    if (resolved == null) return null;
    try {
      return item.copyWith(
        pngBytes: await resolved.file.readAsBytes(),
        originalFileName: resolved.file.path,
      );
    } catch (_) {
      return null;
    }
  }

  Future<MCOImageGalleryItem> _itemForEdit(
    MCOImageGalleryItem item,
  ) async {
    if (!item.showPngFallback) return item;
    final resolved = await _resolvePackOriginal(item);
    if (resolved == null || resolved.originalIsLottie) {
      return item.copyWith(showPngFallback: false);
    }
    return resolved;
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
                unawaited(_editItem(item));
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
            if (!item.isPackItem)
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

  Future<void> _editItem(MCOImageGalleryItem item) async {
    final resultItem = await _itemForEdit(item);
    if (!mounted) return;
    Navigator.pop(
      context,
      MCOImageGalleryResult(
        action: MCOImageGalleryAction.edit,
        item: resultItem,
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
        final resolved = await _resolvePackOriginal(item);
        if (resolved != null) {
          await MCOImageFileSaver.saveOriginalBytes(
            resolved.pngBytes,
            resolved.originalFileName,
          );
        } else {
          final image = item.tryDecodeImage();
          if (image != null) await MCOImageFileSaver.savePng(image);
        }
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

  Future<void> _importPack() async {
    try {
      final file = await file_selector.openFile(
        acceptedTypeGroups: const [
          file_selector.XTypeGroup(
            label: 'MCOimg pack',
            extensions: ['mcoimg.pack', 'pack', 'zip'],
            mimeTypes: ['application/zip', 'application/octet-stream'],
            uniformTypeIdentifiers: ['public.zip-archive', 'public.data'],
          ),
        ],
      );
      if (file == null) return;

      setState(() => _loading = true);
      final pack = await _store.importPack(await file.readAsBytes());
      await _loadItems();
      if (!mounted) return;
      showDismissibleSnackBar(context, content: Text(pack.groupTitle));
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      showDismissibleSnackBar(
        context,
        content: Text(error.toString()),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  Future<void> _showRemovePackSheet() async {
    final packs = await _store.loadPacks();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        var currentPacks = packs;
        return StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final pack in currentPacks)
                  ListTile(
                    title: Text(pack.groupTitle),
                    trailing: IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: () async {
                        final removed = await _confirmRemovePack(pack);
                        if (!removed || !context.mounted) return;
                        final nextPacks = await _store.loadPacks();
                        if (!context.mounted) return;
                        setSheetState(() => currentPacks = nextPacks);
                      },
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.close),
                  title: Text(context.l10n.common_cancel),
                  onTap: () => Navigator.pop(sheetContext),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _confirmRemovePack(MCOImagePackMetadata pack) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.mcogallery_removePackConfirm(pack.name)),
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
            child: Text(context.l10n.common_ok),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;

    try {
      await _store.removePack(pack);
      await _loadItems();
      return true;
    } catch (error) {
      if (!mounted) return false;
      showDismissibleSnackBar(
        context,
        content: Text(error.toString()),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _buildGroups(context);
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
              PopupMenuButton<_GalleryMenuAction>(
                icon: const Icon(Icons.more_vert),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _GalleryMenuAction.addPack,
                    child: Text(context.l10n.mcogallery_addPack),
                  ),
                  PopupMenuItem(
                    value: _GalleryMenuAction.removePack,
                    child: Text(context.l10n.mcogallery_removePack),
                  ),
                ],
                onSelected: (action) {
                  switch (action) {
                    case _GalleryMenuAction.addPack:
                      unawaited(_importPack());
                    case _GalleryMenuAction.removePack:
                      unawaited(_showRemovePackSheet());
                  }
                },
              ),
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
                : _buildGroupedGallery(groups),
          ),
        ],
      ),
    );
  }

  List<_GalleryGroup> _buildGroups(BuildContext context) {
    final byId = <String, List<MCOImageGalleryItem>>{
      MCOImageGalleryItem.commonGroupId: [],
    };
    final names = <String, String>{
      MCOImageGalleryItem.commonGroupId: context.l10n.mcogallery_common,
    };

    for (final item in _items) {
      final groupId = item.groupId.trim().isEmpty
          ? MCOImageGalleryItem.commonGroupId
          : item.groupId.trim();
      byId.putIfAbsent(groupId, () => []).add(item);
      if (groupId != MCOImageGalleryItem.commonGroupId) {
        final groupName = item.groupName?.trim();
        names[groupId] = groupName != null && groupName.isNotEmpty
            ? groupName
            : groupId;
      }
    }

    final groups = [
      _GalleryGroup(
        id: MCOImageGalleryItem.commonGroupId,
        title: names[MCOImageGalleryItem.commonGroupId]!,
        items: byId[MCOImageGalleryItem.commonGroupId]!,
      ),
      ...byId.entries
          .where((entry) => entry.key != MCOImageGalleryItem.commonGroupId)
          .map(
            (entry) => _GalleryGroup(
              id: entry.key,
              title: names[entry.key] ?? entry.key,
              items: entry.value,
            ),
          ),
    ];

    groups.sort((a, b) {
      if (a.id == MCOImageGalleryItem.commonGroupId) return -1;
      if (b.id == MCOImageGalleryItem.commonGroupId) return 1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return groups;
  }

  Widget _buildGroupedGallery(List<_GalleryGroup> groups) {
    if (_items.isEmpty) {
      return CustomScrollView(
        slivers: [
          for (final group in groups)
            SliverToBoxAdapter(
              child: _GalleryGroupHeader(
                title: group.title,
                count: group.items.length,
                collapsed: _collapsedGroupIds.contains(group.id),
                onToggle: () => _toggleGroup(group.id),
              ),
            ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text(context.l10n.channels_changeGroupEmpty)),
          ),
        ],
      );
    }

    return CustomScrollView(
      slivers: [
        for (final group in groups) ...[
          SliverToBoxAdapter(
            child: _GalleryGroupHeader(
              title: group.title,
              count: group.items.length,
              collapsed: _collapsedGroupIds.contains(group.id),
              onToggle: () => _toggleGroup(group.id),
            ),
          ),
          if (!_collapsedGroupIds.contains(group.id) && group.items.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.78,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final item = group.items[index];
                  return _GalleryTile(
                    item: item,
                    onTap: () => unawaited(_selectItem(item)),
                    onLongPress: () => _showItemActions(item),
                  );
                }, childCount: group.items.length),
              ),
            ),
        ],
      ],
    );
  }

  void _toggleGroup(String groupId) {
    setState(() {
      if (!_collapsedGroupIds.add(groupId)) {
        _collapsedGroupIds.remove(groupId);
      }
    });
    unawaited(_store.saveCollapsedGroupIds(_collapsedGroupIds));
  }
}

class _GalleryGroup {
  final String id;
  final String title;
  final List<MCOImageGalleryItem> items;

  const _GalleryGroup({
    required this.id,
    required this.title,
    required this.items,
  });
}

class _GalleryGroupHeader extends StatelessWidget {
  final String title;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;

  const _GalleryGroupHeader({
    required this.title,
    required this.count,
    required this.collapsed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$title ($count)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(collapsed ? Icons.add : Icons.remove),
                  onPressed: onToggle,
                ),
              ],
            ),
          ),
        ),
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
    final Widget preview;
    if (!showPng) {
      preview = FittedBox(
        fit: BoxFit.contain,
        child: MCOImageMessage(
          image: image,
          maxSize: (item.previewMaxSize ?? 96).toDouble(),
        ),
      );
    } else if (image != null && item.isPackItem) {
      preview = MCOImageOriginalOrFallback(
        text: item.textPayload,
        image: image,
        maxSize: (item.previewMaxSize ?? 96).toDouble(),
        expandOriginalToMaxSize: true,
        originalRelativePaths: item.originalRelativePaths,
      );
    } else if (item.pngBytes.isNotEmpty) {
      preview = Image.memory(
        item.pngBytes,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.broken_image_outlined,
          color: scheme.onSurfaceVariant,
        ),
      );
    } else {
      preview = Icon(
        Icons.broken_image_outlined,
        color: scheme.onSurfaceVariant,
      );
    }

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
                  child: preview,
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
