import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import 'connect_sheet.dart';

/// Stands in for the composer while no radio is connected.
class OfflineComposerBar extends StatelessWidget {
  const OfflineComposerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant, width: 1)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final message = Row(
                children: [
                  Icon(
                    Icons.cloud_off,
                    color: scheme.onSurfaceVariant,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.l10n.chat_composerOffline,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
                    ),
                  ),
                ],
              );
              // Side by side when there is room; otherwise the button goes
              // under the message so large text never squeezes it.
              final roomy =
                  constraints.maxWidth /
                      MediaQuery.textScalerOf(context).scale(1) >=
                  420;
              if (roomy) {
                return Row(
                  children: [
                    Expanded(child: message),
                    const SizedBox(width: 8),
                    const ConnectButton(),
                  ],
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  message,
                  const SizedBox(height: 8),
                  const ConnectButton(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
