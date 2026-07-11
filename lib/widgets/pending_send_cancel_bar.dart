import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

class PendingSendCancelBar extends StatefulWidget {
  final DateTime sendAt;
  final int delaySeconds;
  final VoidCallback onCancel;
  final Color foregroundColor;
  final EdgeInsetsGeometry contentPadding;

  const PendingSendCancelBar({
    super.key,
    required this.sendAt,
    required this.delaySeconds,
    required this.onCancel,
    required this.foregroundColor,
    this.contentPadding = EdgeInsets.zero,
  });

  @override
  State<PendingSendCancelBar> createState() => _PendingSendCancelBarState();
}

class _PendingSendCancelBarState extends State<PendingSendCancelBar> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remainingMs = widget.sendAt
        .difference(DateTime.now())
        .inMilliseconds
        .clamp(0, widget.delaySeconds * 1000)
        .toInt();
    final remainingSeconds = (remainingMs / 1000).ceil();
    final progress = widget.delaySeconds <= 0
        ? 0.0
        : remainingMs / (widget.delaySeconds * 1000);
    final textStyle = DefaultTextStyle.of(
      context,
    ).style.copyWith(color: widget.foregroundColor);

    return InkWell(
      onTap: widget.onCancel,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Container(height: 1, color: Colors.black.withValues(alpha: 0.5)),
            Padding(
              padding: widget.contentPadding.add(
                const EdgeInsets.fromLTRB(0, 8, 0, 6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$remainingSeconds', style: textStyle),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 11,
                    height: 11,
                    child: Transform.scale(
                      scaleX: -1,
                      child: CircularProgressIndicator(
                        value: math.max(0, math.min(1, progress)).toDouble(),
                        strokeWidth: 2,
                        color: widget.foregroundColor,
                        backgroundColor: widget.foregroundColor.withValues(
                          alpha: 0.22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(context.l10n.chat_cancelSend, style: textStyle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
