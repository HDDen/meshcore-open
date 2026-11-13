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
      QuickAction.cliCommand1 => '${l10n.quickActions_cliCommand} 1',
      QuickAction.cliCommand2 => '${l10n.quickActions_cliCommand} 2',
      QuickAction.channelMessage1 => '${l10n.quickActions_sendChannel} 1',
      QuickAction.channelMessage2 => '${l10n.quickActions_sendChannel} 2',
    };
  }
}
