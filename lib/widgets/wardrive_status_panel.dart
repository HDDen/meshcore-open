import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../connector/meshcore_protocol.dart';
import '../helpers/wardrive_coverage_helper.dart';
import '../l10n/l10n.dart';
import '../services/wardrive_service.dart';

enum WardriveDataAction {
  start,
  stop,
  upload,
  uploadSites,
  autoUpload,
  screenWakelock,
  coverageResolution,
  exportSamples,
  importSamples,
  clear,
}

class WardriveStatusPanel extends StatelessWidget {
  final WardriveService wardrive;
  final bool collapsed;
  final bool autoUploadEnabled;
  final bool screenWakelockEnabled;
  final Map<String, String> repeaterNames;
  final Key? panelKey;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<WardriveDataAction> onDataAction;
  final ValueChanged<WardriveDiscoveryResult> onResultSelected;
  final ValueChanged<String> onIntervalSubmitted;
  final String Function(DateTime) formatLastSeen;

  const WardriveStatusPanel({
    super.key,
    required this.wardrive,
    required this.collapsed,
    required this.autoUploadEnabled,
    required this.screenWakelockEnabled,
    required this.repeaterNames,
    this.panelKey,
    required this.onToggleCollapsed,
    required this.onDataAction,
    required this.onResultSelected,
    required this.onIntervalSubmitted,
    required this.formatLastSeen,
  });

  @override
  Widget build(BuildContext context) {
    final recent = wardrive.recentDiscoveries;
    return Positioned(
      left: 16,
      bottom: 16,
      child: ConstrainedBox(
        key: panelKey,
        constraints: const BoxConstraints(maxWidth: 300),
        child: Material(
          elevation: 4,
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: collapsed
                ? _buildCollapsedPanel(context)
                : _buildExpandedPanel(context, recent),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedPanel(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.directions_car_filled,
          size: 18,
          color: wardrive.isRunning
              ? Colors.green
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Text(
          context.l10n.map_wardrive,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        _WardriveCountdownText(wardrive: wardrive),
        if (wardrive.isSendingDiscovery) ...[
          const SizedBox(width: 8),
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
        if (wardrive.isUpdatingLocation) ...[
          const SizedBox(width: 8),
          const Icon(Icons.my_location, size: 16),
        ],
        const SizedBox(width: 8),
        _buildCollapseButton(),
      ],
    );
  }

  Widget _buildExpandedPanel(
    BuildContext context,
    List<WardriveDiscoveryResult> recent,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.directions_car_filled,
              size: 18,
              color: wardrive.isRunning
                  ? Colors.green
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              context.l10n.map_wardrive,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            _WardriveCountdownText(wardrive: wardrive),
            if (wardrive.isSendingDiscovery) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
            if (wardrive.isUpdatingLocation) ...[
              const SizedBox(width: 8),
              const Icon(Icons.my_location, size: 16),
            ],
            const Spacer(),
            _buildDataMenu(context),
            const SizedBox(width: 4),
            _buildCollapseButton(),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.map_wardriveRequests(
            wardrive.discoveryRequestsSent,
            wardrive.discoveryResponsesReceived,
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          context.l10n.map_wardriveSamplesSaved(wardrive.savedSamplesCount),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (wardrive.hasMapState && wardrive.recentSamples.isNotEmpty)
          _buildCoverageSummary(context),
        _buildAutoDiscoveryIntervalInput(context),
        if (wardrive.lastAutoDiscoveryError != null)
          Text(
            context.l10n.map_wardriveAutoDiscoveryError(
              wardrive.lastAutoDiscoveryError!,
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        Text(
          _formatLocationStatus(context),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: wardrive.lastLocationError == null
                ? null
                : Theme.of(context).colorScheme.error,
          ),
        ),
        if (wardrive.lastDiscoveryRequestAt != null)
          Text(
            context.l10n.map_wardriveLastRequest(
              formatLastSeen(wardrive.lastDiscoveryRequestAt!),
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (wardrive.lastSampleError != null)
          Text(
            context.l10n.map_wardriveSampleSaveError(wardrive.lastSampleError!),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        if (wardrive.hasDiscoveryRequestWithoutResponses) ...[
          const SizedBox(height: 8),
          Text(
            context.l10n.map_wardriveDiscoverySent,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ] else if (recent.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: Scrollbar(
              thumbVisibility: recent.length > 4,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...recent.map((result) => _buildResultRow(context, result)),
                  ],
                ),
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 8),
          Text(
            context.l10n.map_wardriveNoResponses,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDataMenu(BuildContext context) {
    return PopupMenuButton<WardriveDataAction>(
      tooltip: context.l10n.map_wardriveDataTooltip,
      icon: const Icon(Icons.more_horiz, size: 18),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 160),
      onSelected: onDataAction,
      itemBuilder: (context) {
        final errorColor = Theme.of(context).colorScheme.error;
        return [
          PopupMenuItem(
            value: wardrive.isRunning
                ? WardriveDataAction.stop
                : WardriveDataAction.start,
            child: Row(
              children: [
                Icon(
                  wardrive.isRunning ? Icons.stop : Icons.play_arrow,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  wardrive.isRunning
                      ? context.l10n.map_wardriveStop
                      : context.l10n.map_wardriveStart,
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: WardriveDataAction.upload,
            child: Row(
              children: [
                const Icon(Icons.cloud_upload, size: 18),
                const SizedBox(width: 8),
                Text(context.l10n.map_wardriveUploadData),
              ],
            ),
          ),
          PopupMenuItem(
            value: WardriveDataAction.uploadSites,
            child: Row(
              children: [
                const Icon(Icons.cloud_queue, size: 18),
                const SizedBox(width: 8),
                Text(context.l10n.map_wardriveManageUploadSites),
              ],
            ),
          ),
          PopupMenuItem(
            value: WardriveDataAction.autoUpload,
            child: Row(
              children: [
                _buildMenuCheckbox(autoUploadEnabled),
                const SizedBox(width: 4),
                Text(context.l10n.map_wardriveAutoUpload),
              ],
            ),
          ),
          PopupMenuItem(
            value: WardriveDataAction.screenWakelock,
            child: Row(
              children: [
                _buildMenuCheckbox(screenWakelockEnabled),
                const SizedBox(width: 4),
                Text(context.l10n.map_wardriveScreenWakelock),
              ],
            ),
          ),
          PopupMenuItem(
            value: WardriveDataAction.coverageResolution,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.grid_on, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(context.l10n.map_wardriveCoverageResolution),
                      Text(
                        _coverageResolutionDescription(context),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: WardriveDataAction.exportSamples,
            child: Row(
              children: [
                const Icon(Icons.ios_share, size: 18),
                const SizedBox(width: 8),
                Text(context.l10n.map_wardriveExport),
              ],
            ),
          ),
          PopupMenuItem(
            value: WardriveDataAction.importSamples,
            child: Row(
              children: [
                const Icon(Icons.input, size: 18),
                const SizedBox(width: 8),
                Text(context.l10n.map_wardriveImport),
              ],
            ),
          ),
          PopupMenuItem(
            value: WardriveDataAction.clear,
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 18, color: errorColor),
                const SizedBox(width: 8),
                Text(
                  context.l10n.common_clear,
                  style: TextStyle(color: errorColor),
                ),
              ],
            ),
          ),
        ];
      },
    );
  }

  Widget _buildMenuCheckbox(bool value) {
    return IgnorePointer(
      child: SizedBox(
        width: 20,
        height: 20,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Checkbox(
            value: value,
            onChanged: (_) {},
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }

  String _coverageResolutionDescription(BuildContext context) {
    switch (wardrive.coveragePrecision) {
      case 4:
        return context.l10n.map_wardriveCoverageRegionalSubtitle;
      case 5:
        return context.l10n.map_wardriveCoverageCitySubtitle;
      case 6:
        return context.l10n.map_wardriveCoverageNeighborhoodSubtitle;
      case 7:
        return context.l10n.map_wardriveCoverageStreetSubtitle;
      case 8:
        return context.l10n.map_wardriveCoverageBuildingSubtitle;
      default:
        return context.l10n.map_wardriveCoverageStreetSubtitle;
    }
  }

  Widget _buildAutoDiscoveryIntervalInput(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.map_wardriveAutoDiscovery,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            height: 32,
            child: _WardriveIntervalInput(
              seconds: wardrive.autoDiscoveryIntervalSeconds,
              onSubmitted: onIntervalSubmitted,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            context.l10n.map_wardriveSecondsSuffix,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildCoverageSummary(BuildContext context) {
    final summary = WardriveCoverageHelper.buildSummary(
      wardrive.recentSamples,
      coveragePrecision: wardrive.coveragePrecision,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            context.l10n.map_wardriveCoverageCells(summary.total),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          _buildCoverageLegendItem(context, Colors.green, summary.good),
          _buildCoverageLegendItem(context, Colors.amber, summary.fair),
          _buildCoverageLegendItem(context, Colors.redAccent, summary.weak),
          _buildDeadZoneLegendItem(context, summary.dead),
        ],
      ),
    );
  }

  Widget _buildCoverageLegendItem(
    BuildContext context,
    Color color,
    int count,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 3),
        Text(count.toString(), style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildDeadZoneLegendItem(BuildContext context, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.close, size: 10, color: Colors.redAccent),
        const SizedBox(width: 3),
        Text(count.toString(), style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildCollapseButton() {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onToggleCollapsed,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(collapsed ? Icons.add : Icons.remove, size: 16),
      ),
    );
  }

  String _formatLocationStatus(BuildContext context) {
    final error = wardrive.lastLocationError;
    if (error != null) {
      return context.l10n.map_wardrivePhoneGpsError(error);
    }
    final lat = wardrive.lastPhoneLatitude;
    final lon = wardrive.lastPhoneLongitude;
    if (lat == null || lon == null) {
      return context.l10n.map_wardrivePhoneGpsNotUpdated;
    }
    return context.l10n.map_wardrivePhoneGps(
      lat.toStringAsFixed(5),
      lon.toStringAsFixed(5),
    );
  }

  Widget _buildResultRow(BuildContext context, WardriveDiscoveryResult result) {
    final responseTime = result.responseTimeMs == null
        ? ''
        : ' / ${result.responseTimeMs} ms';
    final repeaterName = _repeaterNameFor(result);
    return InkWell(
      onTap: () => onResultSelected(result),
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (repeaterName != null)
              Text(
                repeaterName,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getNodeIcon(result.nodeType),
                  size: 16,
                  color: _getNodeColor(result.nodeType),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: Text(
                    result.publicKeyPrefix,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'SNR ${result.snr} / RSSI ${result.rssi}$responseTime',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _repeaterNameFor(WardriveDiscoveryResult result) {
    final resultKey = result.publicKeyHex.toUpperCase();
    final name = repeaterNames[resultKey];
    if (name != null && name.isNotEmpty) return name;

    for (final entry in repeaterNames.entries) {
      final contactKey = entry.key.toUpperCase();
      final shortest = contactKey.length < resultKey.length
          ? contactKey.length
          : resultKey.length;
      if (shortest < 8) continue;
      if (contactKey.startsWith(resultKey) ||
          resultKey.startsWith(contactKey)) {
        return entry.value;
      }
    }

    return null;
  }

  Color _getNodeColor(int type) {
    switch (type) {
      case advTypeChat:
        return Colors.blue;
      case advTypeRepeater:
        return Colors.green;
      case advTypeRoom:
        return Colors.purple;
      case advTypeSensor:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getNodeIcon(int type) {
    switch (type) {
      case advTypeChat:
        return Icons.person;
      case advTypeRepeater:
        return Icons.router;
      case advTypeRoom:
        return Icons.meeting_room;
      case advTypeSensor:
        return Icons.sensors;
      default:
        return Icons.device_unknown;
    }
  }
}

class _WardriveCountdownText extends StatefulWidget {
  final WardriveService wardrive;

  const _WardriveCountdownText({required this.wardrive});

  @override
  State<_WardriveCountdownText> createState() => _WardriveCountdownTextState();
}

class _WardriveCountdownTextState extends State<_WardriveCountdownText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(_WardriveCountdownText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncTimer() {
    _timer?.cancel();
    if (!widget.wardrive.isRunning) return;

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final nextAt = widget.wardrive.nextAutoDiscoveryAt;
    if (!widget.wardrive.isRunning || nextAt == null) {
      return const SizedBox.shrink();
    }

    final remaining = nextAt.difference(DateTime.now()).inSeconds;
    final seconds = remaining < 0 ? 0 : remaining;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        '(${seconds}s)',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _WardriveIntervalInput extends StatefulWidget {
  final int seconds;
  final ValueChanged<String> onSubmitted;

  const _WardriveIntervalInput({
    required this.seconds,
    required this.onSubmitted,
  });

  @override
  State<_WardriveIntervalInput> createState() => _WardriveIntervalInputState();
}

class _WardriveIntervalInputState extends State<_WardriveIntervalInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.seconds.toString());
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(_WardriveIntervalInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && oldWidget.seconds != widget.seconds) {
      _controller.text = widget.seconds.toString();
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _submit();
    }
  }

  void _submit() {
    final value = _controller.text;
    if (value.isEmpty) return;
    widget.onSubmitted(value);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(),
      ),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (value) {
        if (value.isNotEmpty) {
          widget.onSubmitted(value);
        }
      },
      onEditingComplete: () {
        _submit();
        FocusScope.of(context).unfocus();
      },
      onFieldSubmitted: (_) => _submit(),
      onTapOutside: (_) {
        _submit();
        FocusScope.of(context).unfocus();
      },
    );
  }
}
