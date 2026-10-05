import 'dart:async';
import 'dart:ui' show AppExitType;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n.dart';
import '../storage/data_root.dart';
import '../utils/byte_size.dart';

/// Offers the copy of an earlier installation's data into a new data folder
/// and runs it, each screen put up before the settings load. Returns false
/// when the app must not go on: the copy failed and its screen stays up.
/// "Start with empty data" and an app without old data go on at once.
Future<bool> offerDataTransfer() async {
  final offer = await findDataTransferOffer();
  if (offer == null) return true;

  final decision = Completer<bool>();
  runApp(
    DataTransferOfferApp(
      offer: offer,
      size: measureDataTransfer(offer),
      onDecided: (copy) {
        if (!decision.isCompleted) decision.complete(copy);
      },
    ),
  );
  if (!await decision.future) return true;

  final progress = ValueNotifier<(int, int)>((0, 0));
  runApp(DataTransferProgressApp(progress: progress));
  try {
    await transferData(
      offer,
      onProgress: (copied, total) => progress.value = (copied, total),
    );
    return true;
  } on Object catch (error) {
    runApp(DataTransferFailedApp(error: error));
    return false;
  }
}

/// The question: copy the old data, or start with none.
class DataTransferOfferApp extends StatefulWidget {
  const DataTransferOfferApp({
    super.key,
    required this.offer,
    required this.size,
    required this.onDecided,
  });

  final DataTransferOffer offer;

  /// The bytes to copy, counted while the question is on screen.
  final Future<int> size;

  /// True for the copy, false for empty data.
  final void Function(bool copy) onDecided;

  @override
  State<DataTransferOfferApp> createState() => _DataTransferOfferAppState();
}

class _DataTransferOfferAppState extends State<DataTransferOfferApp> {
  bool _decided = false;

  void _decide(bool copy) {
    if (_decided) return;
    setState(() => _decided = true);
    widget.onDecided(copy);
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    return _StartupFrame(
      icon: Icons.drive_file_move_outline,
      builder: (context, l10n, theme) => [
        Text(
          l10n.dataTransfer_offerTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        Text(l10n.dataTransfer_offerBody(offer.target)),
        const SizedBox(height: 12),
        Text(l10n.dataTransfer_offerSources),
        for (final source in offer.sources) Text(source),
        const SizedBox(height: 12),
        FutureBuilder<int>(
          future: widget.size,
          builder: (context, snapshot) {
            final size = snapshot.data;
            if (size != null) {
              return Text(l10n.dataTransfer_offerSize(formatByteSize(size)));
            }
            if (snapshot.hasError) return const SizedBox.shrink();
            return Text(l10n.dataTransfer_offerSizeCounting);
          },
        ),
        if (offer.copiedBefore.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(l10n.dataTransfer_offerCopiedBefore),
          for (final record in offer.copiedBefore)
            Text('${_formatTime(record.at)}  ${record.target}'),
        ],
        const SizedBox(height: 12),
        Text(l10n.dataTransfer_offerNote, style: theme.textTheme.bodySmall),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton(
              onPressed: _decided ? null : () => _decide(false),
              child: Text(l10n.dataTransfer_startEmpty),
            ),
            FilledButton(
              onPressed: _decided ? null : () => _decide(true),
              child: Text(l10n.dataTransfer_copy),
            ),
          ],
        ),
      ],
    );
  }
}

/// The copy running: bytes copied of the total.
class DataTransferProgressApp extends StatelessWidget {
  const DataTransferProgressApp({super.key, required this.progress});

  /// Copied and total bytes.
  final ValueListenable<(int, int)> progress;

  @override
  Widget build(BuildContext context) {
    return _StartupFrame(
      icon: Icons.drive_file_move_outline,
      builder: (context, l10n, theme) => [
        Text(
          l10n.dataTransfer_progressTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 24),
        ValueListenableBuilder<(int, int)>(
          valueListenable: progress,
          builder: (context, value, _) {
            final (copied, total) = value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(
                  value: total == 0 ? null : (copied / total).clamp(0.0, 1.0),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.dataTransfer_progress(
                    formatByteSize(copied),
                    formatByteSize(total),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          l10n.dataTransfer_progressNote,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// The copy failed; the old folders are as they were.
class DataTransferFailedApp extends StatelessWidget {
  const DataTransferFailedApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return _StartupFrame(
      icon: Icons.error_outline,
      alert: true,
      builder: (context, l10n, theme) => [
        Text(
          l10n.dataTransfer_failedTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        Text(l10n.dataTransfer_failedBody),
        const SizedBox(height: 12),
        Text(
          l10n.dataFolder_details('$error'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        Align(
          child: FilledButton(
            onPressed: () => unawaited(
              ServicesBinding.instance.exitApplication(AppExitType.required),
            ),
            child: Text(l10n.common_close),
          ),
        ),
      ],
    );
  }
}

/// Asks whether the old data copied into this data folder at an earlier start
/// may go from the system folders, and deletes them while a screen says so,
/// all before the settings load. Asked before the app rather than over it:
/// the connection to the last node starts with the app and moves its screens
/// over any dialog. A window closed on the question decides nothing, and the
/// question comes again at the next start.
Future<void> offerDataCleanup() async {
  final offer = await findDataCleanupOffer();
  if (offer == null) return;

  final decision = Completer<bool>();
  runApp(
    DataCleanupOfferApp(
      offer: offer,
      size: measureDataCleanup(offer),
      onDecided: (delete) {
        if (!decision.isCompleted) decision.complete(delete);
      },
    ),
  );
  if (!await decision.future) {
    await declineDataCleanup(offer);
    return;
  }

  runApp(const DataCleanupProgressApp());
  final remaining = await deleteOldData(offer);
  if (remaining.isEmpty) return;

  final acknowledged = Completer<void>();
  runApp(
    DataCleanupPartialApp(
      remaining: remaining,
      onContinue: () {
        if (!acknowledged.isCompleted) acknowledged.complete();
      },
    ),
  );
  await acknowledged.future;
}

/// The question: which old folders, how much they hold, delete or keep.
class DataCleanupOfferApp extends StatefulWidget {
  const DataCleanupOfferApp({
    super.key,
    required this.offer,
    required this.size,
    required this.onDecided,
  });

  final DataCleanupOffer offer;

  /// The bytes the deletion frees, counted while the question is on screen.
  final Future<int> size;

  /// True for deleting, false for keeping.
  final void Function(bool delete) onDecided;

  @override
  State<DataCleanupOfferApp> createState() => _DataCleanupOfferAppState();
}

class _DataCleanupOfferAppState extends State<DataCleanupOfferApp> {
  bool _decided = false;

  void _decide(bool delete) {
    if (_decided) return;
    setState(() => _decided = true);
    widget.onDecided(delete);
  }

  @override
  Widget build(BuildContext context) {
    return _StartupFrame(
      icon: Icons.delete_sweep_outlined,
      builder: (context, l10n, theme) => [
        Text(
          l10n.dataCleanup_title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        Text(l10n.dataCleanup_body),
        const SizedBox(height: 12),
        for (final item in widget.offer.items) Text(item),
        const SizedBox(height: 12),
        FutureBuilder<int>(
          future: widget.size,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes != null) {
              return Text(l10n.dataTransfer_offerSize(formatByteSize(bytes)));
            }
            if (snapshot.hasError) return const SizedBox.shrink();
            return Text(l10n.dataTransfer_offerSizeCounting);
          },
        ),
        const SizedBox(height: 12),
        Text(l10n.dataCleanup_note, style: theme.textTheme.bodySmall),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton(
              onPressed: _decided ? null : () => _decide(false),
              child: Text(l10n.dataCleanup_keep),
            ),
            FilledButton(
              onPressed: _decided ? null : () => _decide(true),
              child: Text(l10n.common_delete),
            ),
          ],
        ),
      ],
    );
  }
}

/// The deletion running.
class DataCleanupProgressApp extends StatelessWidget {
  const DataCleanupProgressApp({super.key});

  @override
  Widget build(BuildContext context) {
    return _StartupFrame(
      icon: Icons.delete_sweep_outlined,
      builder: (context, l10n, theme) => [
        Text(
          l10n.dataCleanup_progress,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 24),
        const LinearProgressIndicator(),
      ],
    );
  }
}

/// What the deletion could not remove; the app goes on when the user has
/// seen it, and the question comes again at the next start.
class DataCleanupPartialApp extends StatelessWidget {
  const DataCleanupPartialApp({
    super.key,
    required this.remaining,
    required this.onContinue,
  });

  final List<String> remaining;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return _StartupFrame(
      icon: Icons.warning_amber_outlined,
      alert: true,
      builder: (context, l10n, theme) => [
        Text(l10n.dataCleanup_partial(remaining.length)),
        const SizedBox(height: 12),
        for (final folder in remaining) Text(folder),
        const SizedBox(height: 24),
        Align(
          child: FilledButton(
            onPressed: onContinue,
            child: Text(l10n.common_continue),
          ),
        ),
      ],
    );
  }
}

/// The app shell of a screen shown before the settings load: the system's
/// language, a dark theme, and one centred column.
class _StartupFrame extends StatelessWidget {
  const _StartupFrame({
    required this.icon,
    required this.builder,
    this.alert = false,
  });

  final IconData icon;

  /// The icon in the error colour.
  final bool alert;
  final List<Widget> Function(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  )
  builder;

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
      home: Builder(
        builder: (context) {
          final theme = Theme.of(context);
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
                          Icon(
                            icon,
                            size: 56,
                            color: alert
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          ...builder(context, context.l10n, theme),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

String _formatTime(DateTime at) {
  final local = at.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
