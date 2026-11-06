import 'package:flutter/material.dart';

import '../helpers/repeater_extra_settings.dart';
import '../l10n/app_localizations.dart';

String repeaterExtraSettingLabel(
  RepeaterExtraSetting setting, AppLocalizations l10n,
) => switch (setting) {
  RepeaterExtraSetting.floodMaxAdvert => l10n.repeater_floodMaxAdvert,
  RepeaterExtraSetting.floodMaxUnscoped => l10n.repeater_floodMaxUnscoped,
  RepeaterExtraSetting.rxDelay => l10n.repeater_rxDelay,
  RepeaterExtraSetting.cad => l10n.repeater_cad,
  RepeaterExtraSetting.adcMultiplier => l10n.repeater_adcMultiplier,
  RepeaterExtraSetting.extraSf => l10n.repeater_extraSf,
};

String _description(RepeaterExtraSetting setting, AppLocalizations l10n) =>
    switch (setting) {
      RepeaterExtraSetting.floodMaxAdvert => l10n.repeater_floodMaxAdvertHelper,
      RepeaterExtraSetting.floodMaxUnscoped => l10n.repeater_floodMaxUnscopedHelper,
      RepeaterExtraSetting.rxDelay => l10n.repeater_rxDelayHelper,
      RepeaterExtraSetting.cad => l10n.repeater_cadHelper,
      RepeaterExtraSetting.adcMultiplier =>
        '${l10n.repeater_adcMultiplierHelper}\n${l10n.repeater_boardSupportNote}',
      RepeaterExtraSetting.extraSf =>
        '${l10n.repeater_extraSfHelper}\n${l10n.repeater_lr2021Only}',
    };

/// A GET-gated control only. The screen retains ownership of the command
/// queue, controllers and per-field dirty/edited-during-save tracking.
class RepeaterExtraSettingControl extends StatelessWidget {
  final RepeaterExtraSetting setting;
  final AppLocalizations l10n;
  final TextEditingController? controller;
  final bool loaded;
  final bool refreshing;
  final bool canRefresh;
  final bool toggleValue;
  final bool inherited;
  final VoidCallback onRefresh;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool> onToggle;

  const RepeaterExtraSettingControl({
    super.key,
    required this.setting,
    required this.l10n,
    this.controller,
    required this.loaded,
    required this.refreshing,
    required this.canRefresh,
    this.toggleValue = false,
    this.inherited = false,
    required this.onRefresh,
    required this.onChanged,
    required this.onToggle,
  }) : assert(setting == RepeaterExtraSetting.cad || controller != null);

  @override
  Widget build(BuildContext context) {
    final label = repeaterExtraSettingLabel(setting, l10n);
    final description = _description(setting, l10n);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: setting.isToggle
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: Text(label, softWrap: true)),
                        Semantics(
                          label: label,
                          child: Switch(
                            key: const ValueKey('repeater-extra-toggle:cad'),
                            value: loaded && toggleValue,
                            onChanged: loaded ? onToggle : null,
                          ),
                        ),
                      ]),
                      Text(description, softWrap: true,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Keep labels outside InputDecorator so all text can
                      // wrap at large font sizes without ellipsis.
                      Text(label, softWrap: true),
                      if (inherited)
                        Text(l10n.repeater_floodMaxUnscopedUnset,
                            softWrap: true),
                      const SizedBox(height: 4),
                      Semantics(
                        label: label,
                        child: TextField(
                          key: ValueKey('repeater-extra-input:${setting.cliKey}'),
                          controller: controller,
                          enabled: loaded,
                          decoration: const InputDecoration(),
                          keyboardType: setting == RepeaterExtraSetting.extraSf
                              ? TextInputType.text
                              : TextInputType.numberWithOptions(
                                  decimal: setting.isDecimal,
                                ),
                          onChanged: onChanged,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(description, softWrap: true,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
          ),
          IconButton(
            key: ValueKey('repeater-extra-refresh:${setting.cliKey}'),
            tooltip: label,
            onPressed: refreshing || !canRefresh ? null : onRefresh,
            icon: refreshing
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
    );
  }
}
