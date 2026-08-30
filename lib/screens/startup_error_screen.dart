import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../storage/message_history_database.dart';

class MessageHistoryMigrationApp extends StatelessWidget {
  const MessageHistoryMigrationApp({super.key, required this.progress});

  final ValueListenable<LegacyMessageHistoryProgress> progress;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF03A9E6),
      ),
      home: _MessageHistoryMigrationScreen(progress: progress),
    );
  }
}

class _MessageHistoryMigrationScreen extends StatelessWidget {
  const _MessageHistoryMigrationScreen({required this.progress});

  final ValueListenable<LegacyMessageHistoryProgress> progress;

  @override
  Widget build(BuildContext context) {
    final isRussian =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'ru';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ValueListenableBuilder<LegacyMessageHistoryProgress>(
              valueListenable: progress,
              builder: (context, value, _) {
                final total = value.totalHistories;
                final completed = value.completedHistories;
                final current = total == 0
                    ? 0
                    : (completed < total ? completed + 1 : total);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      value: total == 0 ? null : completed / total,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      isRussian
                          ? 'Перенос истории сообщений…'
                          : 'Migrating message history…',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (total > 0)
                      Text(
                        isRussian
                            ? 'Диалог $current из $total · сообщений: '
                                  '${value.processedMessages}'
                            : 'Conversation $current of $total · messages: '
                                  '${value.processedMessages}',
                        textAlign: TextAlign.center,
                      ),
                    if (value.skippedHistories > 0 ||
                        value.skippedMessages > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        isRussian
                            ? 'Пропущено диалогов: '
                                  '${value.skippedHistories}, сообщений: '
                                  '${value.skippedMessages}'
                            : 'Skipped conversations: '
                                  '${value.skippedHistories}, messages: '
                                  '${value.skippedMessages}',
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      isRussian
                          ? 'Приложение перезапустится автоматически.'
                          : 'The application will restart automatically.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class StartupFailureReport {
  StartupFailureReport({
    required this.code,
    required this.stage,
    required this.error,
    required this.stackTrace,
    this.dataPath,
  }) : occurredAt = DateTime.now().toUtc();

  final String code;
  final String stage;
  final Object error;
  final StackTrace stackTrace;
  final String? dataPath;
  final DateTime occurredAt;

  String get platform => defaultTargetPlatform.name;

  String get buildMode => kReleaseMode
      ? 'release'
      : kProfileMode
      ? 'profile'
      : 'debug';

  String get text =>
      '''
MCO startup failure
Code: $code
Stage: $stage
Platform: $platform
Build mode: $buildMode
Time (UTC): ${occurredAt.toIso8601String()}
Error type: ${error.runtimeType}
Error: $error
${dataPath == null ? '' : 'Application data: $dataPath\n'}Stack trace:
$stackTrace
''';
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.report});

  final StartupFailureReport report;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF03A9E6),
      ),
      home: StartupErrorScreen(report: report),
    );
  }
}

class StartupErrorScreen extends StatefulWidget {
  const StartupErrorScreen({super.key, required this.report});

  final StartupFailureReport report;

  @override
  State<StartupErrorScreen> createState() => _StartupErrorScreenState();
}

class _StartupErrorScreenState extends State<StartupErrorScreen> {
  bool _copied = false;

  bool get _isRussian =>
      WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'ru';

  Future<void> _copyReport() async {
    await Clipboard.setData(ClipboardData(text: widget.report.text));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final colors = Theme.of(context).colorScheme;
    final title = _isRussian
        ? 'Не удалось запустить приложение'
        : 'The application could not start';
    final description = _isRussian
        ? 'Скопируйте отчёт и приложите его к сообщению об ошибке.'
        : 'Copy this report and attach it to the bug report.';

    return Scaffold(
      body: SafeArea(
        child: SelectionArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.error_outline, size: 56, color: colors.error),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(description, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    _ReportRow(
                      label: _isRussian ? 'Код ошибки' : 'Error code',
                      value: report.code,
                    ),
                    _ReportRow(
                      label: _isRussian ? 'Этап запуска' : 'Startup stage',
                      value: report.stage,
                    ),
                    _ReportRow(
                      label: _isRussian ? 'Платформа' : 'Platform',
                      value: '${report.platform} / ${report.buildMode}',
                    ),
                    _ReportRow(
                      label: _isRussian ? 'Тип ошибки' : 'Error type',
                      value: report.error.runtimeType.toString(),
                    ),
                    if (report.dataPath != null)
                      _ReportRow(
                        label: _isRussian
                            ? 'Данные приложения'
                            : 'Application data',
                        value: report.dataPath!,
                      ),
                    _ReportRow(
                      label: _isRussian ? 'Сообщение' : 'Message',
                      value: report.error.toString(),
                    ),
                    const SizedBox(height: 16),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 16),
                      title: Text(
                        _isRussian
                            ? 'Технические подробности'
                            : 'Technical details',
                      ),
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            report.stackTrace.toString(),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.center,
                      child: FilledButton.icon(
                        onPressed: _copyReport,
                        icon: Icon(_copied ? Icons.check : Icons.copy),
                        label: Text(
                          _copied
                              ? (_isRussian ? 'Отчёт скопирован' : 'Copied')
                              : (_isRussian
                                    ? 'Скопировать отчёт'
                                    : 'Copy report'),
                        ),
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

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
