import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/ios_immortalizer_power_options.dart';
import 'mesh_ui.dart';
import 'power_saving_interval_card.dart';

/// Параметры аудио сохраняются, даже если эксперимент временно их не применяет.
class IosImmortalizerSettingsCard extends StatelessWidget {
  const IosImmortalizerSettingsCard({super.key, required this.options, this.onChanged});
  final IosImmortalizerPowerOptions options;
  final ValueChanged<IosImmortalizerPowerOptions>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final audioEnabled = onChanged != null && !options.withoutAudio;
    Widget choice(String key, String title, bool value, String off, String on,
        bool enabled, IosImmortalizerPowerOptions Function(bool) change) => Padding(
      padding: const EdgeInsets.all(16),
      child: InputDecorator(decoration: InputDecoration(labelText: title),
        child: DropdownButtonHideUnderline(child: DropdownButton<bool>(
          key: ValueKey('ios-immortalizer-$key'), value: value, isExpanded: true,
          items: [DropdownMenuItem(value: false, child: Text(off)),
            DropdownMenuItem(value: true, child: Text(on))],
          onChanged: !enabled ? null : (next) {
            if (next != null) {
              onChanged!(change(next));
            }
          },
        )),
      ),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MeshCard(padding: EdgeInsets.zero, child: Column(children: [
        ListTile(title: Text(l10n.powerSaving_iosImmortalizerTitle),
          subtitle: Text(l10n.powerSaving_iosImmortalizerDescription)),
        SwitchListTile(
          key: const ValueKey('ios-immortalizer-pause-frames'),
          title: Text(l10n.powerSaving_iosImmortalizerFrames),
          value: options.pauseUiFrames,
          onChanged: onChanged == null ? null : (value) => onChanged!(options.copyWith(pauseUiFrames: value)),
        ),
        SwitchListTile(
          key: const ValueKey('ios-immortalizer-lean-hooks'),
          title: Text(l10n.powerSaving_iosImmortalizerHooks),
          value: options.leanHooks,
          onChanged: onChanged == null ? null : (value) => onChanged!(options.copyWith(leanHooks: value)),
        ),
        choice('audio-mode', l10n.powerSaving_iosImmortalizerMode, options.withoutAudio,
          l10n.powerSaving_iosImmortalizerOriginal, l10n.powerSaving_iosImmortalizerWithoutAudio,
          onChanged != null, (value) => options.copyWith(withoutAudio: value)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(l10n.powerSaving_iosImmortalizerWithoutAudioDescription)),
        choice('sample-rate', l10n.powerSaving_iosImmortalizerSampleRate, options.useOutputSampleRate,
          l10n.powerSaving_iosImmortalizerEightKhz, l10n.powerSaving_iosImmortalizerOutputRate,
          audioEnabled, (value) => options.copyWith(useOutputSampleRate: value)),
      ])),
      const SizedBox(height: 12),
      PowerSavingIntervalCard(
        key: const ValueKey('ios-immortalizer-buffer'),
        title: l10n.powerSaving_iosImmortalizerBuffer,
        description: l10n.powerSaving_iosImmortalizerBufferDescription,
        value: options.audioBufferMilliseconds, minimum: 0, maximum: 200, step: 10,
        milliseconds: true,
        valueLabel: (value) => value == 0 ? l10n.powerSaving_iosImmortalizerSystem
            : l10n.powerSaving_milliseconds(value),
        onSaved: !audioEnabled ? null : (value) async {
          onChanged!(options.copyWith(audioBufferMilliseconds: value));
        },
      ),
      const SizedBox(height: 12),
      PowerSavingIntervalCard(
        key: const ValueKey('ios-immortalizer-loop'),
        title: l10n.powerSaving_iosImmortalizerLoop,
        description: l10n.powerSaving_iosImmortalizerLoopDescription,
        value: options.loopSeconds, minimum: 1, maximum: 10,
        onSaved: !audioEnabled ? null : (value) async {
          onChanged!(options.copyWith(loopSeconds: value));
        },
      ),
    ]);
  }
}
