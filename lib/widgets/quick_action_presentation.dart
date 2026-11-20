import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/quick_actions_settings.dart';

extension QuickActionPresentation on QuickAction {
  IconData get icon => switch (this) {
    QuickAction.adaptiveTxPower => Icons.bolt_outlined,
    QuickAction.channelRetries => Icons.repeat,
    QuickAction.companionCli => Icons.terminal,
    QuickAction.floodAdvert => Icons.waves,
    QuickAction.zeroHopAdvert => Icons.cell_tower,
    QuickAction.discover => Icons.travel_explore,
    QuickAction.companionProxy => Icons.hub_outlined,
    QuickAction.tcpProxy => Icons.lan_outlined,
    QuickAction.bleProxy => Icons.bluetooth_connected,
    QuickAction.manageKeys => Icons.key_outlined,
    QuickAction.radioStats => Icons.insights_outlined,
    QuickAction.sensors => Icons.sensors_outlined,
    QuickAction.readChannels => Icons.playlist_add_check,
    QuickAction.readDirect => Icons.mark_chat_read_outlined,
    QuickAction.readAll => Icons.done_all,
    QuickAction.channelIndices => Icons.tag_outlined,
    QuickAction.radioNoise => Icons.noise_aware,
    QuickAction.radioTxPower => Icons.settings_input_antenna,
    QuickAction.cliCommand1 || QuickAction.cliCommand2 => Icons.code,
    QuickAction.channelMessage1 || QuickAction.channelMessage2 =>
      Icons.send_outlined,
  };
}

extension QuickActionItemPresentation on QuickActionItem {
  String label(AppLocalizations l10n) {
    if (action.isCustom && name.trim().isNotEmpty) return name.trim();
    return switch (action) {
      QuickAction.adaptiveTxPower => l10n.adaptiveTxPower,
      QuickAction.channelRetries => l10n.quickActions_retries,
      QuickAction.companionCli => l10n.companionCli_title,
      QuickAction.floodAdvert => l10n.contacts_floodAdvert,
      QuickAction.zeroHopAdvert => l10n.contacts_zeroHopAdvert,
      QuickAction.discover => l10n.quickActions_discover,
      QuickAction.companionProxy => l10n.quickActions_companionProxy,
      QuickAction.tcpProxy => l10n.quickActions_tcpProxy,
      QuickAction.bleProxy => l10n.quickActions_bleProxy,
      QuickAction.manageKeys => l10n.quickActions_keys,
      QuickAction.radioStats => l10n.quickActions_radioStats,
      QuickAction.sensors => l10n.quickActions_sensors,
      QuickAction.readChannels => l10n.quickActions_readChannels,
      QuickAction.readDirect => l10n.quickActions_readDirect,
      QuickAction.readAll => l10n.quickActions_readAll,
      QuickAction.channelIndices => l10n.quickActions_channelIndices,
      QuickAction.radioNoise => l10n.quickActions_radioNoise,
      QuickAction.radioTxPower => l10n.quickActions_radioTxPower,
      QuickAction.cliCommand1 => '${l10n.quickActions_cliCommand} 1',
      QuickAction.cliCommand2 => '${l10n.quickActions_cliCommand} 2',
      QuickAction.channelMessage1 => '${l10n.quickActions_sendChannel} 1',
      QuickAction.channelMessage2 => '${l10n.quickActions_sendChannel} 2',
    };
  }
}
