import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../models/custom_theme.dart';
import '../services/app_settings_service.dart';
import '../services/chat_background_service.dart';
import '../theme/mesh_theme.dart';
import '../theme/theme_icons.dart';
import '../utils/theme_file.dart';
import '../widgets/adaptive_app_bar_title.dart';
import '../widgets/mesh_ui.dart';
import '../widgets/themed_icon.dart';
import 'theme_editor_screen.dart';

/// Lists the stock theme, the built-in presets and the user's own themes.
/// Tapping a theme applies it immediately.
class ThemesScreen extends StatelessWidget {
  const ThemesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settingsService = context.watch<AppSettingsService>();
    final activeId = settingsService.activeCustomTheme?.id;
    final automatic = settingsService.autoHolidayTheme;
    final myThemes = settingsService.settings.customThemes;

    return Scaffold(
      appBar: AppBar(
        title: AdaptiveAppBarTitle(l10n.themes_title),
        centerTitle: true,
        actions: [
          PopupMenuButton<void>(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (_) => [
              PopupMenuItem(
                onTap: () => _importFile(context, settingsService),
                child: _MenuRow(
                  Icons.file_open_outlined,
                  l10n.themes_importFile,
                ),
              ),
              PopupMenuItem(
                onTap: () => _showImportDialog(context, settingsService),
                child: _MenuRow(
                  Icons.content_paste_go_outlined,
                  l10n.themes_pasteCode,
                ),
              ),
              PopupMenuItem(
                enabled: myThemes.isNotEmpty,
                onTap: () => _exportFile(context, myThemes, 'meshcore-themes'),
                child: _MenuRow(Icons.ios_share, l10n.themes_exportAll),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.themes_create),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
          children: [
            SectionHeader(l10n.themes_myThemes),
            if (myThemes.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  l10n.themes_myThemesEmpty,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final theme in myThemes)
                _ThemeTile(
                  name: theme.name,
                  background: theme.background,
                  accent: theme.accent,
                  selected: theme.id == activeId,
                  onTap: () => settingsService.setActiveTheme(theme.id),
                  menu: _myThemeMenu(context, settingsService, theme),
                ),
            SectionHeader(l10n.themes_builtIn),
            _ThemeTile(
              name: l10n.themes_default,
              subtitle: l10n.themes_defaultSubtitle,
              background: MeshPalette.bg,
              accent: MeshPalette.blue,
              selected: activeId == null,
              onTap: () => settingsService.setActiveTheme(null),
            ),
            for (final preset in CustomTheme.presets)
              _presetTile(context, settingsService, preset, activeId),
            SectionHeader(l10n.themes_holidays),
            SwitchListTile(
              secondary: const Icon(Icons.event_available_outlined),
              title: Text(l10n.themes_holidayAutoSwitch),
              subtitle: Text(l10n.themes_holidayAutoSwitchSubtitle),
              value: settingsService.settings.holidayAutoSwitch,
              onChanged: settingsService.setHolidayAutoSwitch,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.celebration_outlined),
              title: Text(l10n.appSettings_holidayAnimations),
              subtitle: Text(l10n.appSettings_holidayAnimationsSubtitle),
              value: settingsService.settings.holidayAnimationsEnabled,
              onChanged: settingsService.setHolidayAnimationsEnabled,
            ),
            if (automatic != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(l10n.themes_holidayAutoApplied(automatic.name)),
              ),
            for (final preset in CustomTheme.holidayPresets)
              _presetTile(
                context,
                settingsService,
                preset,
                activeId,
                subtitle: preset.id == automatic?.id
                    ? l10n.themes_holidayAutoAppliedTag
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  Widget _presetTile(
    BuildContext context,
    AppSettingsService settingsService,
    CustomTheme preset,
    String? activeId, {
    String? subtitle,
  }) {
    final l10n = context.l10n;
    return _ThemeTile(
      name: preset.name,
      subtitle: subtitle,
      background: preset.background,
      accent: preset.accent,
      preview: preset.id != activeId || preset.icons.isEmpty
          ? null
          : ThemedIcon.preview(
              ThemeIconSlot.channels,
              preset.icons[ThemeIconSlot.channels.key],
              size: 48,
            ),
      selected: preset.id == activeId,
      onTap: () => settingsService.setActiveTheme(preset.id),
      menu: PopupMenuButton<void>(
        icon: const Icon(Icons.more_vert),
        itemBuilder: (_) => [
          PopupMenuItem(
            onTap: () => _openEditor(
              context,
              startFrom: preset,
              copyName: l10n.themes_copyName(preset.name),
            ),
            child: _MenuRow(Icons.tune, l10n.themes_customize),
          ),
          PopupMenuItem(
            onTap: () => _copyCode(context, preset),
            child: _MenuRow(Icons.copy, l10n.themes_copyCode),
          ),
        ],
      ),
    );
  }

  Widget _myThemeMenu(
    BuildContext context,
    AppSettingsService settingsService,
    CustomTheme theme,
  ) {
    final l10n = context.l10n;
    return PopupMenuButton<void>(
      icon: const Icon(Icons.more_vert),
      itemBuilder: (_) => [
        PopupMenuItem(
          onTap: () => _openEditor(context, existing: theme),
          child: _MenuRow(Icons.edit_outlined, l10n.common_edit),
        ),
        PopupMenuItem(
          onTap: () => _copyCode(context, theme),
          child: _MenuRow(Icons.copy, l10n.themes_copyCode),
        ),
        PopupMenuItem(
          onTap: () => _exportFile(context, [theme], themeFileStem(theme.name)),
          child: _MenuRow(Icons.ios_share, l10n.themes_exportFile),
        ),
        PopupMenuItem(
          onTap: () => _confirmDelete(context, settingsService, theme),
          child: _MenuRow(Icons.delete_outline, l10n.common_delete),
        ),
      ],
    );
  }

  void _openEditor(
    BuildContext context, {
    CustomTheme? existing,
    CustomTheme? startFrom,
    String? copyName,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThemeEditorScreen(
          existing: existing,
          startFrom: startFrom,
          initialName: copyName,
        ),
      ),
    );
  }

  Future<void> _exportFile(
    BuildContext context,
    List<CustomTheme> themes,
    String fileStem,
  ) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final backgrounds = context.read<ChatBackgroundService>();
    try {
      final embedded = [
        for (final theme in themes) await backgrounds.embedThemeImages(theme),
      ];
      final result = await exportThemesFile(
        embedded,
        fileStem: fileStem,
        sharePositionOrigin: origin,
      );
      if (result != ThemeFileResult.failed) return;
    } catch (_) {
      // Missing local pictures and platform share errors use the same message.
    }
    if (context.mounted) _feedback(context, context.l10n.themes_exportFailed);
  }

  Future<void> _importFile(
    BuildContext context,
    AppSettingsService settingsService,
  ) async {
    final backgrounds = context.read<ChatBackgroundService>();
    try {
      final input = await pickThemesFile();
      if (input == null || !context.mounted) return;
      final themes = <CustomTheme>[];
      for (final theme in decodeThemesJsonl(
        input,
        newId: settingsService.newCustomThemeId,
      )) {
        try {
          themes.add(await backgrounds.storeThemeImages(theme));
        } on FormatException {
          // An invalid picture in one theme should not prevent importing others.
        }
      }
      final added = await settingsService.importCustomThemes(themes);
      unawaited(backgrounds.collectGarbage());
      if (!context.mounted) return;
      final l10n = context.l10n;
      _feedback(
        context,
        added == 0 ? l10n.themes_importFileNone : l10n.themes_importFileResult(added),
      );
    } catch (_) {
      if (context.mounted) _feedback(context, context.l10n.themes_importFileNone);
    }
  }

  Future<void> _copyCode(BuildContext context, CustomTheme theme) async {
    try {
      final embedded = await context
          .read<ChatBackgroundService>()
          .embedThemeImages(theme);
      await Clipboard.setData(ClipboardData(text: embedded.toShareCode()));
      if (context.mounted) _feedback(context, context.l10n.themes_codeCopied);
    } catch (_) {
      if (context.mounted) _feedback(context, context.l10n.themes_exportFailed);
    }
  }

  void _feedback(BuildContext context, String message) {
    showDismissibleSnackBar(context, content: Text(message));
  }

  void _confirmDelete(
    BuildContext context,
    AppSettingsService settingsService,
    CustomTheme theme,
  ) {
    final backgrounds = context.read<ChatBackgroundService>();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.themes_deleteConfirm(theme.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await settingsService.deleteCustomTheme(theme.id);
                unawaited(backgrounds.collectGarbage());
              } catch (_) {
                if (context.mounted) {
                  _feedback(context, context.l10n.themes_saveFailed);
                }
              }
            },
            child: Text(dialogContext.l10n.common_delete),
          ),
        ],
      ),
    );
  }

  Future<void> _showImportDialog(
    BuildContext context,
    AppSettingsService settingsService,
  ) async {
    String clipboard = '';
    try {
      clipboard = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    } catch (_) {
      // Manual paste is available even when direct clipboard access is denied.
    }
    if (!context.mounted) return;
    final seed = clipboard.length <= CustomTheme.maxShareCodeCharacters
        ? clipboard.trim()
        : '';
    final imported = await showDialog<CustomTheme>(
      context: context,
      builder: (_) => _ImportThemeDialog(
        initialText: seed.startsWith('{') ? seed : '',
        newId: settingsService.newCustomThemeId,
      ),
    );
    if (imported == null || !context.mounted) return;
    final backgrounds = context.read<ChatBackgroundService>();
    try {
      final stored = await backgrounds.storeThemeImages(imported);
      await settingsService.saveCustomTheme(stored, apply: true);
      unawaited(backgrounds.collectGarbage());
      if (context.mounted) {
        _feedback(context, context.l10n.themes_imported(stored.name));
      }
    } catch (_) {
      if (context.mounted) _feedback(context, context.l10n.themes_importInvalid);
    }
  }
}

class _ImportThemeDialog extends StatefulWidget {
  const _ImportThemeDialog({required this.initialText, required this.newId});

  final String initialText;
  final String Function() newId;

  @override
  State<_ImportThemeDialog> createState() => _ImportThemeDialogState();
}

class _ImportThemeDialogState extends State<_ImportThemeDialog> {
  late final _controller = TextEditingController(text: widget.initialText);
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.themes_import),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 5,
        decoration: InputDecoration(
          hintText: l10n.themes_importHint,
          errorText: _invalid ? l10n.themes_importInvalid : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.common_cancel),
        ),
        FilledButton(
          onPressed: () {
            final theme = CustomTheme.fromShareCode(
              _controller.text,
              newId: widget.newId(),
            );
            if (theme == null) {
              setState(() => _invalid = true);
              return;
            }
            Navigator.pop(context, theme);
          },
          child: Text(l10n.themes_import),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MenuRow(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ],
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final String name;
  final String? subtitle;
  final Color background;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;
  final Widget? menu;

  /// Shown instead of the color swatch (holiday themes show an icon).
  final Widget? preview;

  const _ThemeTile({
    required this.name,
    this.subtitle,
    required this.background,
    required this.accent,
    required this.selected,
    required this.onTap,
    this.menu,
    this.preview,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      button: true,
      child: MeshCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        borderColor: selected ? scheme.primary : null,
        child: Row(
          children: [
            preview ?? ThemeSwatch(background: background, accent: accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.check_circle, color: scheme.primary),
              ),
            if (menu != null) menu! else const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

/// A small rounded square showing a theme's background with an accent dot
/// and a sample text bar, so themes can be told apart at a glance.
class ThemeSwatch extends StatelessWidget {
  final Color background;
  final Color accent;
  final double size;

  const ThemeSwatch({
    super.key,
    required this.background,
    required this.accent,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final ink = isDarkColor(background)
        ? MeshPalette.ink
        : MeshPalette.lightInk;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(MeshRadii.sm),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      padding: EdgeInsets.all(size * 0.18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            height: size * 0.1,
            width: size * 0.5,
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(size),
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Container(
              width: size * 0.32,
              height: size * 0.32,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}
