import 'dart:async';
import 'dart:ui' show AppExitType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n.dart';
import '../storage/data_root.dart';
import '../utils/platform_info.dart';

/// Shown instead of the app when its data folder cannot be used: another
/// running copy holds it, it cannot be created or written to, or
/// `--data-dir` named no folder. Put up before the settings load, so the
/// language is the system's.
class DataFolderProblemApp extends StatelessWidget {
  const DataFolderProblemApp({super.key, required this.problem});

  final DataRootProblem problem;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF03A9E6),
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _DataFolderProblemScreen(problem: problem),
    );
  }
}

class _DataFolderProblemScreen extends StatelessWidget {
  const _DataFolderProblemScreen({required this.problem});

  final DataRootProblem problem;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final (IconData icon, String title, String body, Object? error) =
        switch (problem) {
          DataRootInUse(:final path) => (
            Icons.lock_outline,
            l10n.dataFolder_inUseTitle,
            l10n.dataFolder_inUseBody(path),
            null,
          ),
          DataRootUnavailable(missingPath: true) => (
            Icons.folder_off_outlined,
            l10n.dataFolder_unavailableTitle,
            l10n.dataFolder_missingPath,
            null,
          ),
          DataRootUnavailable(:final path, :final error) => (
            Icons.folder_off_outlined,
            l10n.dataFolder_unavailableTitle,
            l10n.dataFolder_unavailableBody(path),
            error,
          ),
        };
    // Only Windows and Linux read --data-dir.
    final showHint = PlatformInfo.isWindows || PlatformInfo.isLinux;

    return Scaffold(
      body: SafeArea(
        child: SelectionArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(icon, size: 56, color: theme.colorScheme.error),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    Text(body),
                    if (showHint) ...[
                      const SizedBox(height: 12),
                      Text(l10n.dataFolder_otherFolderHint),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        l10n.dataFolder_details('$error'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 24),
                    Align(
                      child: FilledButton(
                        onPressed: () => unawaited(
                          ServicesBinding.instance.exitApplication(
                            AppExitType.required,
                          ),
                        ),
                        child: Text(l10n.common_close),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
