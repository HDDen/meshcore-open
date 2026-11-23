import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// Compact controls shared by the map's trace and region-request drafts.
class PathTraceControls extends StatelessWidget {
  const PathTraceControls({
    super.key,
    required this.onClose,
    this.onRemove,
    this.onClear,
    this.onRegions,
    this.onLastResult,
    this.onRun,
    this.regionRequest = false,
    this.roundTrip = true,
    this.onRoundTrip,
    this.onAsEntered,
  });

  final VoidCallback onClose;
  final VoidCallback? onRemove;
  final VoidCallback? onClear;
  final VoidCallback? onRegions;
  final VoidCallback? onLastResult;
  final VoidCallback? onRun;
  final bool regionRequest;
  final bool roundTrip;
  final VoidCallback? onRoundTrip;
  final VoidCallback? onAsEntered;

  Widget _editAction(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback action, {
    bool? selected,
  }) => Expanded(
    child: Semantics(
      selected: selected,
      child: Tooltip(
        message: label,
        child: TextButton(
          onPressed: action,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(fontSize: 11),
            alignment: Alignment.topCenter,
            backgroundColor: selected == true
                ? Theme.of(context).colorScheme.secondaryContainer
                : null,
            foregroundColor: selected == true
                ? Theme.of(context).colorScheme.onSecondaryContainer
                : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _mainAction(String label, IconData icon, VoidCallback action) {
    final style = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 11),
    );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
    return Flexible(
      fit: FlexFit.loose,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: TextButton(onPressed: action, style: style, child: content),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            key: const ValueKey('path-trace-edit-actions'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (onRoundTrip != null)
                _editAction(
                  context,
                  l10n.map_pathTraceModeRoundTrip,
                  Icons.sync_alt,
                  onRoundTrip!,
                  selected: roundTrip,
                ),
              if (onAsEntered != null)
                _editAction(
                  context,
                  l10n.map_pathTraceModeAsEntered,
                  Icons.arrow_forward,
                  onAsEntered!,
                  selected: !roundTrip,
                ),
              if (onRemove != null)
                _editAction(context, l10n.common_delete, Icons.undo, onRemove!),
              if (onClear != null)
                _editAction(
                  context,
                  l10n.common_clear,
                  Icons.delete_outline,
                  onClear!,
                ),
              _editAction(context, l10n.common_close, Icons.close, onClose),
            ],
          ),
        ),
        if (onRun != null || onRegions != null || onLastResult != null) ...[
          const SizedBox(height: 4),
          Row(
            key: const ValueKey('path-trace-main-actions'),
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (onRegions != null)
                _mainAction(
                  l10n.contacts_requestRegions,
                  Icons.travel_explore,
                  onRegions!,
                ),
              if (onLastResult != null)
                _mainAction(
                  l10n.map_pathTraceViewLast,
                  Icons.history,
                  onLastResult!,
                ),
              if (onRun != null)
                _mainAction(
                  regionRequest
                      ? l10n.contacts_requestRegions
                      : l10n.map_runTrace,
                  regionRequest ? Icons.travel_explore : Icons.radar,
                  onRun!,
                ),
            ],
          ),
        ],
      ],
    );
  }
}
