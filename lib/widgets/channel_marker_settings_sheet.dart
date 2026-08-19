import 'package:flutter/material.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/channel_marker_styles.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../models/channel_marker_style.dart';
import '../theme/mesh_theme.dart';

/// Lets the user pick which channels put markers on the map, and how those
/// markers look.
///
/// Takes the connector rather than a channel list so the caller stays a single
/// line: ordering, the empty case and the repaint all live here. The sheet
/// reads styles back from [styles], which is also what the map draws from, so
/// the two cannot disagree.
Future<void> showChannelMarkerSettings(
  BuildContext context,
  MeshCoreConnector connector,
  ChannelMarkerStyles styles,
) async {
  final channels = ChannelMarkerStyles.orderChannels(connector.channels);
  styles.trackChannels(connector.channels);
  if (channels.isEmpty) {
    showDismissibleSnackBar(
      context,
      content: Text(context.l10n.map_noChannelsAvailable),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
        ),
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.pin_drop_outlined,
                      size: 20,
                      color: Theme.of(sheetContext).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        sheetContext.l10n.map_showMarksFromChannels,
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: channels.length,
                  itemBuilder: (itemContext, index) {
                    final channel = channels[index];
                    final style = styles.styleFor(channel.name);

                    Future<void> apply(ChannelMarkerStyle updated) async {
                      await styles.update(channel.name, updated);
                      setSheetState(() {});
                    }

                    return SwitchListTile(
                      value: style.enabled,
                      onChanged: (value) =>
                          apply(style.copyWith(enabled: value)),
                      title: Text(ChannelMarkerStyles.displayName(channel)),
                      secondary: _MarkerPreviewButton(
                        style: style,
                        onTap: () async {
                          final updated = await _showStyleDialog(
                            itemContext,
                            style,
                          );
                          if (updated == null) return;
                          await apply(updated);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<ChannelMarkerStyle?> _showStyleDialog(
  BuildContext context,
  ChannelMarkerStyle style,
) {
  var colorKey = style.colorKey;
  var iconKey = style.iconKey;
  return showDialog<ChannelMarkerStyle>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(dialogContext.l10n.map_markerStyleTitle),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dialogContext.l10n.map_markerStyleColor,
                  style: Theme.of(dialogContext).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Every swatch is drawn as the finished marker, so the
                    // choice is previewed rather than described.
                    for (final entry in ChannelMarkerPalette.colors.entries)
                      _MarkerChoice(
                        selected: entry.key == colorKey,
                        color: entry.value,
                        icon: ChannelMarkerPalette.iconFor(iconKey),
                        onTap: () => setDialogState(() => colorKey = entry.key),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  dialogContext.l10n.map_markerStyleIcon,
                  style: Theme.of(dialogContext).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in ChannelMarkerPalette.icons.entries)
                      _MarkerChoice(
                        selected: entry.key == iconKey,
                        color: ChannelMarkerPalette.colorFor(colorKey),
                        icon: entry.value,
                        onTap: () => setDialogState(() => iconKey = entry.key),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              style.copyWith(colorKey: colorKey, iconKey: iconKey),
            ),
            child: Text(dialogContext.l10n.common_save),
          ),
        ],
      ),
    ),
  );
}

/// The channel's marker as it appears on the map, tappable to restyle it.
class _MarkerPreviewButton extends StatelessWidget {
  const _MarkerPreviewButton({required this.style, required this.onTap});

  final ChannelMarkerStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: style.color,
          border: Border.all(color: MapPalette.markerOutline, width: 2),
        ),
        alignment: Alignment.center,
        child: Icon(style.icon, color: Colors.white, size: 18),
      ),
    );
  }
}

class _MarkerChoice extends StatelessWidget {
  const _MarkerChoice({
    required this.selected,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final bool selected;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? scheme.onSurface : Colors.transparent,
            width: 3,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
