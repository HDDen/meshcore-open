import 'package:flutter/material.dart';

import '../helpers/companion_cli_commands.dart';
import '../l10n/l10n.dart';
import '../theme/mesh_theme.dart';

/// Оформление справки CLI репитера; каталог CompanionCLI хранится отдельно.
class CompanionCliCommandHelpSheet extends StatefulWidget {
  final List<CompanionCliHelpSection> sections;
  final ValueChanged<String> onSelect;

  const CompanionCliCommandHelpSheet({super.key, required this.sections, required this.onSelect});

  @override
  State<CompanionCliCommandHelpSheet> createState() => _CompanionCliCommandHelpSheetState();
}

class _CompanionCliCommandHelpSheetState extends State<CompanionCliCommandHelpSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Заголовки категорий и подходящие под поиск команды строятся лениво.
  List<Object> _rows() {
    final q = _query.trim().toLowerCase();
    final rows = <Object>[];
    for (final section in widget.sections) {
      final matches = q.isEmpty
          ? section.commands
          : section.commands
                .where(
                  (e) =>
                      e.command.toLowerCase().contains(q) ||
                      e.description.toLowerCase().contains(q),
                )
                .toList();
      if (matches.isEmpty) continue;
      rows.add(section);
      rows.addAll(matches);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final rows = _rows();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 1,
        builder: (context, scrollController) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.repeater_commandsListTitle,
                    style: textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.companionCli_helpNote,
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('companion-cli-help-search'),
                    controller: _searchController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: l10n.repeater_cliSearchCommands,
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: l10n.common_clearSearch,
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ],
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text(
                        l10n.repeater_cliNoMatchingCommands,
                        style: textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        if (row is CompanionCliHelpSection) {
                          return _buildHeader(row, isFirst: index == 0);
                        }
                        return _buildCommandCard(row as CompanionCliHelpEntry);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(CompanionCliHelpSection section, {required bool isFirst}) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 4 : 16, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (section.note != null) ...[
            const SizedBox(height: 4),
            Text(
              section.note!,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCommandCard(CompanionCliHelpEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MeshRadii.sm),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        key: ValueKey('companion-cli-help:${entry.command}'),
        borderRadius: BorderRadius.circular(MeshRadii.sm),
        onTap: () => widget.onSelect(entry.command),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.command,
                style: MeshTheme.mono(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                entry.description,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

