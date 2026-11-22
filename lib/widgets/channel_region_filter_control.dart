import 'package:flutter/material.dart';

import '../helpers/channel_region_filter.dart';
import '../l10n/l10n.dart';

String _regionLabel(BuildContext context, String region) => region.isEmpty
    ? context.l10n.chat_floodRegionNone
    : region == ChannelRegionFilter.unknown
        ? context.l10n.channelRegionFilter_unknown : region;

Future<Set<String>?> showChannelRegionFilterDialog(
  BuildContext context, {
  required List<String> knownRegions,
  required Set<String> hidden,
}) => showDialog<Set<String>>(
  context: context,
  builder: (_) => _RegionFilterDialog(known: knownRegions, hidden: hidden),
);

class _RegionFilterDialog extends StatefulWidget {
  const _RegionFilterDialog({required this.known, required this.hidden});
  final List<String> known;
  final Set<String> hidden;

  @override
  State<_RegionFilterDialog> createState() => _RegionFilterDialogState();
}

class _RegionFilterDialogState extends State<_RegionFilterDialog> {
  late final _hidden = {...widget.hidden};
  late final _choices = ChannelRegionFilter.choices(widget.known, widget.hidden);

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(context.l10n.channelRegionFilter_title,
      style: Theme.of(context).textTheme.titleMedium),
    content: SizedBox(
      width: 420,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final region in _choices)
          SwitchListTile(
            key: ValueKey('region-filter:$region'),
            title: Text(_regionLabel(context, region)),
            value: !_hidden.contains(region),
            onChanged: (enabled) => setState(() {
              if (enabled) {
                _hidden.remove(region);
              } else {
                _hidden.add(region);
              }
            }),
          ),
      ]),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.common_cancel)),
      FilledButton(onPressed: () => Navigator.pop(context, Set<String>.of(_hidden)),
        child: Text(context.l10n.common_save)),
    ],
  );
}

class ChannelRegionFilterLine extends StatelessWidget {
  const ChannelRegionFilterLine({super.key, required this.regionHeader,
    required this.unread, required this.knownRegions, required this.hidden,
    required this.onConfigure});
  final String regionHeader;
  final String unread;
  final List<String> knownRegions;
  final Set<String> hidden;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final active = hidden.isNotEmpty;
    final allowed = ChannelRegionFilter.choices(knownRegions, hidden)
        .where((region) => !hidden.contains(region)).toList();
    final first = allowed.isEmpty ? context.l10n.channelRegionFilter_noneAllowed
        : _regionLabel(context, allowed.first);
    final label = '$first${allowed.length > 1 ? ' +${allowed.length - 1}' : ''}';
    return DefaultTextStyle.merge(
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
      child: Row(children: [
        Flexible(child: Text('$regionHeader • ', overflow: TextOverflow.ellipsis)),
        Flexible(child: Tooltip(
          message: context.l10n.channelRegionFilter_title,
          child: InkWell(
            key: const ValueKey('channel-region-filter'),
            onTap: onConfigure,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(active ? Icons.filter_alt : Icons.filter_alt_outlined, size: 13),
              if (active) ...[
                const SizedBox(width: 3),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ]),
          ),
        )),
        Text(' • $unread'),
      ]),
    );
  }
}
