import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../services/app_debug_log_service.dart';
import '../theme/mesh_theme.dart';
import '../widgets/adaptive_app_bar_title.dart';
import '../helpers/snack_bar_builder.dart';

class AppDebugLogScreen extends StatelessWidget {
  const AppDebugLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppDebugLogService>(
      builder: (context, logService, _) {
        final entries = logService.entries.reversed.toList();
        final hasEntries = entries.isNotEmpty;

        return Scaffold(
          appBar: AppBar(
            title: AdaptiveAppBarTitle(context.l10n.debugLog_appTitle),
            centerTitle: true,
            actions: [
              IconButton(
                tooltip: context.l10n.debugLog_copyLog,
                icon: const Icon(Icons.copy),
                onPressed: hasEntries
                    ? () async {
                        final text = entries
                            .map(
                              (entry) =>
                                  '[${entry.formattedTime}] [${entry.levelLabel}] [${entry.tag}] ${entry.message}',
                            )
                            .join('\n');
                        await Clipboard.setData(ClipboardData(text: text));
                        if (!context.mounted) return;
                        showDismissibleSnackBar(
                          context,
                          content: Text(context.l10n.debugLog_copied),
                        );
                      }
                    : null,
              ),
              IconButton(
                tooltip: context.l10n.debugLog_clearLog,
                icon: const Icon(Icons.delete_outline),
                onPressed: hasEntries
                    ? () {
                        logService.clear();
                      }
                    : null,
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: hasEntries
                ? ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: MeshPalette.line),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return Container(
                        color: MeshPalette.bg,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLevelIcon(context, entry.level),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '[${entry.tag}] ',
                                          style: MeshTheme.mono(
                                            fontSize: 11.5,
                                            color: _levelColor(entry.level),
                                          ),
                                        ),
                                        TextSpan(
                                          text: entry.message,
                                          style: MeshTheme.mono(
                                            fontSize: 11.5,
                                            color: MeshPalette.ink2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    entry.formattedTime,
                                    style: MeshTheme.mono(
                                      fontSize: 9.5,
                                      color: MeshPalette.ink4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.bug_report_outlined,
                          size: 64,
                          color: MeshPalette.ink3,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          context.l10n.debugLog_noEntries,
                          style: const TextStyle(
                            fontSize: 16,
                            color: MeshPalette.ink3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.l10n.debugLog_enableInSettings,
                          style: const TextStyle(
                            fontSize: 12,
                            color: MeshPalette.ink3,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }

  Color _levelColor(AppDebugLogLevel level) {
    switch (level) {
      case AppDebugLogLevel.info:
        return MeshPalette.blue;
      case AppDebugLogLevel.warning:
        return MeshPalette.warn;
      case AppDebugLogLevel.error:
        return MeshPalette.alert;
    }
  }

  Widget _buildLevelIcon(BuildContext context, AppDebugLogLevel level) {
    switch (level) {
      case AppDebugLogLevel.info:
        return const Icon(
          Icons.info_outline,
          size: 18,
          color: MeshPalette.blue,
        );
      case AppDebugLogLevel.warning:
        return const Icon(
          Icons.warning_amber_outlined,
          size: 18,
          color: MeshPalette.warn,
        );
      case AppDebugLogLevel.error:
        return const Icon(
          Icons.error_outline,
          size: 18,
          color: MeshPalette.alert,
        );
    }
  }
}
