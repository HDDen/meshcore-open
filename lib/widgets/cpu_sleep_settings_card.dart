import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/cpu_sleep_options.dart';
import 'mesh_ui.dart';

class CpuSleepSettingsCard extends StatelessWidget {
  const CpuSleepSettingsCard({super.key, required this.options, this.onChanged});
  final CpuSleepOptions options;
  final ValueChanged<CpuSleepOptions>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget scenario(String key, String label, bool value,
        CpuSleepOptions Function(bool) change) => CheckboxListTile(
      key: ValueKey('power-saving-cpu-$key'), title: Text(label), value: value,
      onChanged: onChanged == null || options.always || options.unconditional ? null
          : (value) => onChanged!(change(value == true)),
    );
    return MeshCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(title: Text(l10n.powerSaving_cpuSleepTitle),
          subtitle: Text(l10n.powerSaving_cpuSleepDescription)),
        CheckboxListTile(
          key: const ValueKey('power-saving-cpu-unconditional'),
          title: Text(l10n.powerSaving_cpuSleepUnconditional),
          subtitle: Text(l10n.powerSaving_cpuSleepUnconditionalDescription),
          value: options.unconditional,
          onChanged: onChanged == null ? null
              : (value) => onChanged!(options.copyWith(unconditional: value == true)),
        ),
        CheckboxListTile(
          key: const ValueKey('power-saving-cpu-always'),
          title: Text(l10n.powerSaving_cpuSleepAlways), value: options.always,
          onChanged: onChanged == null || options.unconditional ? null
              : (value) => onChanged!(options.copyWith(always: value == true)),
        ),
        scenario('ble', l10n.powerSaving_cpuSleepBle, options.ble,
            (value) => options.copyWith(ble: value)),
        scenario('tcp', l10n.powerSaving_cpuSleepTcp, options.tcp,
            (value) => options.copyWith(tcp: value)),
        scenario('proxy', l10n.powerSaving_cpuSleepProxy, options.proxy,
            (value) => options.copyWith(proxy: value)),
        scenario('wardrive', l10n.powerSaving_cpuSleepWardrive, options.wardrive,
            (value) => options.copyWith(wardrive: value)),
      ]),
    );
  }
}
