import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../helpers/mcoa_theme_options.dart';
import '../l10n/l10n.dart';
import '../models/custom_theme.dart';
import '../services/app_settings_service.dart';
import '../theme/mesh_theme.dart';
import 'mcoa_theme_editor_section.dart';
import 'mcoa_theme_color_control.dart';
import 'mcoa_theme_palette.dart';
import 'mesh_ui.dart';
import 'mcoa_chat_list_style.dart';

class McoaThemeEditor extends StatefulWidget {
  const McoaThemeEditor({
    super.key,
    required this.theme,
    required this.onChanged,
  });
  final CustomTheme theme;
  final ValueChanged<McoaThemeOptions> onChanged;

  @override
  State<McoaThemeEditor> createState() => McoaThemeEditorState();
}

class McoaThemeEditorState extends State<McoaThemeEditor> {
  final _expanded = <String>{};
  final _form = GlobalKey<FormState>();

  bool validate() {
    final valid = _form.currentState?.validate() ?? true;
    if (!valid) {
      setState(() {
        _expanded.add('preferences');
      });
    }
    return valid;
  }

  Widget _section(String id, String title, List<Widget> children) =>
      McoaThemeEditorSection(
        id: 'mcoa-$id',
        title: title,
        expanded: _expanded.contains(id),
        onToggle: () => setState(() {
          if (!_expanded.add(id)) {
            _expanded.remove(id);
          }
        }),
        child: MeshCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: children),
        ),
      );

  Color _defaultColor(String key) {
    final base = MeshTheme.fromCustom(widget.theme.copyWith(mcoa: const McoaThemeOptions()));
    final scheme = base.colorScheme;
    if (key == 'chats_search_contacts_background') {
      return widget.theme.mcoa.colors['chats_search_background'] ??
          McoaChatListStyle.fallback(base, 'search_background');
    }
    if (key.startsWith('chats_')) {
      return McoaChatListStyle.fallback(base, key.substring(6));
    }
    final outgoing = key.startsWith('outgoing_');
    final bubble = base.extension<MeshBubbleTheme>()!;
    final ink = outgoing ? bubble.meInk : scheme.onSurface;
    if (key == 'status_bar' || key == 'header') return scheme.surface;
    if (key == 'header_text') return scheme.onSurface;
    if (key == 'attention') return MeshPalette.warn;
    if (key == 'warning') return MeshPalette.alert;
    if (key.startsWith('composer_')) {
      return switch (key) {
        'composer_background' => scheme.surface,
        'composer_action_icon' => base.iconTheme.color ?? scheme.onSurfaceVariant,
        'composer_input_border' => scheme.outlineVariant,
        'composer_input_background' => scheme.surfaceContainerLow,
        'composer_input_hint' || 'composer_counter' => scheme.onSurfaceVariant,
        'composer_input_text' => scheme.onSurface,
        'composer_send_background' => scheme.primary,
        'composer_send_icon' => scheme.onPrimary,
        'composer_counter_warning' => scheme.tertiary,
        'composer_counter_error' => scheme.error,
        _ => Colors.transparent,
      };
    }
    final part = key.substring(key.indexOf('_') + 1);
    return switch (part) {
      'border' => outgoing ? bubble.meBorder : scheme.outlineVariant,
      'background' => outgoing ? bubble.me : scheme.surfaceContainerLow,
      'sender_name' => scheme.onSurface,
      'link' => base.brightness == Brightness.dark
          ? const Color(0xFFFFB74D) : const Color(0xFFE65100),
      'signal' => MeshPalette.signal,
      'text' => ink,
      'badges' => ink.withValues(alpha: 0.65),
      'quote_background' => scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      'quote_text' => scheme.onSurface.withValues(alpha: 0.7),
      'mention_border' || 'mention_text' => MeshPalette.blue,
      'hop_border' => scheme.outlineVariant,
      'hop_background' => scheme.surfaceContainerHigh,
      'hop_text' => scheme.onSurfaceVariant,
      'metadata_background' => scheme.surface,
      _ => Colors.transparent,
    };
  }

  Widget _color(String key, String label) {
    final value = widget.theme.mcoa.colors[key] ?? _defaultColor(key);
    Future<void> pick() async {
      final result = await showDialog<({bool reset, Color? color})>(
        context: context,
        builder: (_) => _McoaColorDialog(
          label: label,
          initial: value,
        ),
      );
      if (!mounted || result == null) {
        return;
      }
      final colors = Map<String, Color>.of(widget.theme.mcoa.colors);
      if (result.reset) {
        colors.remove(key);
      } else {
        colors[key] = result.color!;
      }
      widget.onChanged(widget.theme.mcoa.copyWith(colors: colors));
    }
    return Padding(
      key: ValueKey('mcoa-color-$key'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: pick,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(label),
              ),
            ),
          ),
          const SizedBox(width: 12),
          McoaThemeColorControl(
            key: ValueKey('mcoa-color-control-$key'),
            id: key,
            label: label,
            color: widget.theme.mcoa.colors[key],
            fallback: _defaultColor(key),
            onPick: pick,
            onChanged: (color) {
              final colors = Map<String, Color>.of(widget.theme.mcoa.colors);
              if (color == null) {
                colors.remove(key);
              } else {
                colors[key] = color;
              }
              widget.onChanged(widget.theme.mcoa.copyWith(colors: colors));
            },
          ),
        ],
      ),
    );
  }

  Widget _senderNameBrightness() {
    final options = widget.theme.mcoa;
    final explicit = options.colors.containsKey('incoming_sender_name');
    return Padding(
      key: const ValueKey('mcoa-sender-name-brightness'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l10n.themes_mcoaSenderNameBrightness),
          Slider(
            value: options.incomingSenderNameBrightness.toDouble(),
            min: -100,
            max: 100,
            divisions: 200,
            label: '${options.incomingSenderNameBrightness}%',
            onChanged: explicit ? null : (value) => widget.onChanged(
              options.copyWith(incomingSenderNameBrightness: value.round()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metadataTopPadding(String direction) {
    final options = widget.theme.mcoa;
    final outgoing = direction == 'outgoing';
    final value = outgoing ? options.outgoingMetadataTopPadding : options.incomingMetadataTopPadding;
    return Padding(
      key: ValueKey('mcoa-$direction-metadata-top-padding'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l10n.themes_mcoaMetadataTopPadding),
          Slider(
            value: value.toDouble(),
            min: 0,
            max: McoaThemeOptions.maxMetadataTopPadding.toDouble(),
            divisions: McoaThemeOptions.maxMetadataTopPadding,
            label: '$value px',
            onChanged: !options.separateMetadataFor(outgoing) ? null : (value) => widget.onChanged(
              outgoing
                  ? options.copyWith(outgoingMetadataTopPadding: value.round())
                  : options.copyWith(incomingMetadataTopPadding: value.round()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metadataSpacing() {
    final options = widget.theme.mcoa;
    return Padding(
      key: const ValueKey('mcoa-incoming-metadata-spacing'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l10n.themes_mcoaMetadataSpacing),
          Slider(
            value: options.incomingMetadataSpacing.toDouble(),
            min: 0,
            max: McoaThemeOptions.maxIncomingMetadataSpacing.toDouble(),
            divisions: McoaThemeOptions.maxIncomingMetadataSpacing,
            label: '${options.incomingMetadataSpacing} px',
            onChanged: (value) => widget.onChanged(
              options.copyWith(incomingMetadataSpacing: value.round()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _percent(String key, String label, int value, int min, int max,
      ValueChanged<int> onChanged) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: TextFormField(
      key: ValueKey('mcoa-percent-$key'),
      initialValue: '$value',
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength: 3,
      decoration: InputDecoration(
        labelText: label,
        suffixText: '%',
        helperText: '$min–$max%',
        counterText: '',
      ),
      validator: (text) {
        final number = int.tryParse(text ?? '');
        return number == null || number < min || number > max ? '$min–$max%' : null;
      },
      onChanged: (text) {
        final number = int.tryParse(text);
        if (number != null && number >= min && number <= max) {
          onChanged(number);
        }
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final options = widget.theme.mcoa;
    final settings = context.read<AppSettingsService>().settings;
    List<Widget> messageColors(String direction) => [
      _color('${direction}_border', direction == 'incoming' ? l10n.themes_mcoaIncomingBorder : l10n.themes_mcoaOutgoingBorder),
      _color('${direction}_background', direction == 'incoming' ? l10n.themes_mcoaIncomingBackground : l10n.themes_mcoaOutgoingBackground),
      if (direction == 'incoming') ...[
        _senderNameBrightness(),
        _color('incoming_sender_name', l10n.themes_mcoaIncomingSenderName),
      ],
      _color('${direction}_text', direction == 'incoming' ? l10n.themes_mcoaIncomingText : l10n.themes_mcoaOutgoingText),
      _color('${direction}_badges', direction == 'incoming' ? l10n.themes_mcoaIncomingBadges : l10n.themes_mcoaOutgoingBadges),
      _color('${direction}_quote_background', l10n.themes_mcoaQuoteBackground),
      _color('${direction}_quote_text', l10n.themes_mcoaQuoteText),
      _color('${direction}_mention_border', l10n.themes_mcoaMentionBorder),
      _color('${direction}_mention_background', l10n.themes_mcoaMentionBackground),
      _color('${direction}_mention_text', l10n.themes_mcoaMentionText),
      _color('${direction}_hop_border', l10n.themes_mcoaHopBorder),
      _color('${direction}_hop_background', l10n.themes_mcoaHopBackground),
      _color('${direction}_hop_text', l10n.themes_mcoaHopText),
      _color('${direction}_link', l10n.themes_mcoaLink),
      _color('${direction}_signal', l10n.themes_mcoaSignal),
      _color('${direction}_metadata_background', l10n.themes_mcoaMetadataBackground),
      if (direction == 'incoming') _metadataSpacing(),
      _metadataTopPadding(direction),
      SwitchListTile(
        key: ValueKey('mcoa-separate-$direction-metadata'),
        title: Text(l10n.themes_mcoaSeparateMetadata),
        value: widget.theme.mcoa.separateMetadataFor(direction == 'outgoing'),
        onChanged: (value) => widget.onChanged(
          direction == 'incoming'
              ? widget.theme.mcoa.copyWith(separateIncomingMetadata: value)
              : widget.theme.mcoa.copyWith(separateOutgoingMetadata: value),
        ),
      ),
    ];
    return Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SectionHeader(l10n.themes_mcoaHeading),
          _section('interface', l10n.themes_mcoaInterface, [
            _color('status_bar', l10n.themes_mcoaStatusBar),
            _color('header', l10n.themes_mcoaHeader),
            _color('header_text', l10n.themes_mcoaHeaderText),
            _color('composer_background', l10n.themes_mcoaComposerBackground),
            _color('composer_action_icon', l10n.themes_mcoaComposerActionIcon),
            _color('composer_input_border', l10n.themes_mcoaComposerInputBorder),
            _color('composer_input_background', l10n.themes_mcoaComposerInputBackground),
            _color('composer_input_hint', l10n.themes_mcoaComposerInputHint),
            _color('composer_input_text', l10n.themes_mcoaComposerInputText),
            _color('composer_send_background', l10n.themes_mcoaComposerSendBackground),
            _color('composer_send_icon', l10n.themes_mcoaComposerSendIcon),
            _color('composer_counter', l10n.themes_mcoaComposerCounter),
            _color('composer_counter_warning', l10n.themes_mcoaComposerCounterWarning),
            _color('composer_counter_error', l10n.themes_mcoaComposerCounterError),
            _color('attention', l10n.themes_mcoaAttention),
            _color('warning', l10n.themes_mcoaWarning),
          ]),
          _section('incoming', l10n.themes_mcoaIncoming, messageColors('incoming')),
          _section('outgoing', l10n.themes_mcoaOutgoing, messageColors('outgoing')),
          _section('chats', l10n.themes_mcoaChats, [
            _color('chats_border', l10n.themes_mcoaChatBorder),
            _color('chats_background', l10n.themes_mcoaChatBackground),
            _color('chats_title', l10n.themes_mcoaChatTitle),
            _color('chats_preview', l10n.themes_mcoaChatPreview),
            _color('chats_icons', l10n.themes_mcoaChatIcons),
            _color('chats_index_border', l10n.themes_mcoaIndexBorder),
            _color('chats_index_background', l10n.themes_mcoaIndexBackground),
            _color('chats_index_text', l10n.themes_mcoaIndexText),
            _color('chats_index_dot', l10n.themes_mcoaIndexDot),
            _color('chats_unread_background', l10n.themes_mcoaUnreadBackground),
            _color('chats_unread_text', l10n.themes_mcoaUnreadText),
            _color('chats_search_border', l10n.themes_mcoaSearchBorder),
            _color('chats_search_background', l10n.themes_mcoaSearchBackground),
            _color('chats_search_contacts_background', l10n.themes_mcoaSearchContactsBackground),
            _color('chats_search_text', l10n.themes_mcoaSearchText),
            _color('chats_search_hint_icons', l10n.themes_mcoaSearchHintIcons),
            _color('chats_key', l10n.themes_mcoaContactKey),
            _color('chats_prefix_border', l10n.themes_mcoaPrefixBorder),
            _color('chats_prefix_background', l10n.themes_mcoaPrefixBackground),
            _color('chats_prefix_text', l10n.themes_mcoaPrefixText),
          ]),
          _section('preferences', l10n.themes_mcoaOptions, [
            _percent('dpi', l10n.themes_mcoaDpi,
              options.uiScalePercent ?? (settings.uiScale * 100).round(), 50, 200,
              (value) => widget.onChanged(options.copyWith(uiScalePercent: value))),
            _percent('sender', l10n.themes_mcoaSenderSize,
              options.senderNameScalePercent ?? settings.senderNameScalePercent, 25, 400,
              (value) => widget.onChanged(options.copyWith(senderNameScalePercent: value))),
            SwitchListTile(
              title: Text(l10n.settings_modSettingsSimplifiedMentions),
              value: options.simplifiedMentions ?? settings.simplifiedMentions,
              onChanged: (value) => widget.onChanged(options.copyWith(simplifiedMentions: value)),
            ),
            SwitchListTile(
              key: const ValueKey('mcoa-channel-indices'),
              title: Text(l10n.themes_mcoaChannelIndices),
              value: options.showChannelIndices ?? !settings.hideChannelIndexIndicator,
              onChanged: (value) => widget.onChanged(options.copyWith(showChannelIndices: value)),
            ),
          ]),
        ],
      ),
    );
  }
}

class _McoaColorDialog extends StatefulWidget {
  const _McoaColorDialog({required this.label, required this.initial});
  final String label;
  final Color initial;

  @override
  State<_McoaColorDialog> createState() => _McoaColorDialogState();
}

class _McoaColorDialogState extends State<_McoaColorDialog> {
  late Color _color = widget.initial;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.label),
    scrollable: true,
    content: SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          McoaThemePalette(
            color: _color,
            onChanged: (value) => setState(() => _color = value),
          ),
          Text(context.l10n.themes_mcoaOpacity),
          Slider(
            value: _color.a,
            divisions: 100,
            label: '${(_color.a * 100).round()}%',
            onChanged: (value) => setState(() => _color = _color.withValues(alpha: value)),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, (reset: true, color: null)),
        child: Text(context.l10n.themes_default),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.common_cancel),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, (reset: false, color: _color)),
        child: Text(context.l10n.common_save),
      ),
    ],
  );
}
