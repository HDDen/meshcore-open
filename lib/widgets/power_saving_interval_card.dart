import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'mesh_ui.dart';

/// Числовая настройка: движение ползунка не записывает preferences на каждый шаг.
class PowerSavingIntervalCard extends StatefulWidget {
  const PowerSavingIntervalCard({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.minimum,
    required this.maximum,
    this.step = 1,
    this.milliseconds = false,
    this.onSaved,
  });

  final String title;
  final String description;
  final int value;
  final int minimum;
  final int maximum;
  final int step;
  final bool milliseconds;
  final Future<void> Function(int)? onSaved;

  @override
  State<PowerSavingIntervalCard> createState() => _PowerSavingIntervalCardState();
}

class _PowerSavingIntervalCardState extends State<PowerSavingIntervalCard> {
  int? _dragValue;

  @override
  void didUpdateWidget(covariant PowerSavingIntervalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value || widget.onSaved == null) {
      _dragValue = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _dragValue ?? widget.value;
    final label = widget.milliseconds
        ? context.l10n.powerSaving_milliseconds(value)
        : context.l10n.powerSaving_seconds(value);
    return MeshCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title),
          const SizedBox(height: 8),
          Text(label),
          Slider(
            value: value.toDouble(),
            min: widget.minimum.toDouble(),
            max: widget.maximum.toDouble(),
            divisions: (widget.maximum - widget.minimum) ~/ widget.step,
            label: label,
            onChanged: widget.onSaved == null ? null : (next) {
              setState(() => _dragValue = next.round());
            },
            onChangeEnd: widget.onSaved == null ? null : (value) {
              final save = widget.onSaved;
              setState(() => _dragValue = null);
              // Профиль мог смениться во время незавершённого жеста.
              if (save != null) {
                unawaited(save(value.round()));
              }
            },
          ),
          Text(widget.description),
        ],
      ),
    );
  }
}
