import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mco_service/mco_service.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/companion_cli_protocol.dart';
import '../l10n/l10n.dart';
import '../models/quick_actions_settings.dart';
import '../screens/additional_identity_screen.dart';
import '../screens/companion_cli_screen.dart';
import '../screens/discovery_screen.dart';
import '../screens/quick_actions_settings_screen.dart';
import '../services/app_settings_service.dart';
import 'quick_action_presentation.dart';

typedef _QuickActionsDestination = Future<void> Function(BuildContext);

enum QuickActionsHeader { main, channel, contact }

class QuickActionsHeaderButton extends StatelessWidget {
  const QuickActionsHeaderButton({super.key, required this.header});

  final QuickActionsHeader header;

  @override
  Widget build(BuildContext context) {
    final visible = context.select<AppSettingsService, bool>((service) {
      final settings = service.settings;
      return switch (header) {
        QuickActionsHeader.main => settings.showQuickActionsInMainHeader,
        QuickActionsHeader.channel => settings.showQuickActionsInChannelHeader,
        QuickActionsHeader.contact => settings.showQuickActionsInContactHeader,
      };
    });
    final connected = context.select<MeshCoreConnector, bool>(
      (connector) => connector.isConnected && !connector.isOfflineMode,
    );
    if (!visible || !connected) return const SizedBox.shrink();
    return QuickActionsButton(connector: context.read<MeshCoreConnector>());
  }
}

class QuickActionsButton extends StatelessWidget {
  const QuickActionsButton({super.key, required this.connector});

  final MeshCoreConnector connector;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.l10n.quickActions_title,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 48),
      icon: const Icon(Icons.widgets_outlined, size: 20),
      onPressed: () async {
        final settings = context.read<AppSettingsService>();
        final sections = context.read<SettingsSectionsService?>();
        final destination = await showDialog<_QuickActionsDestination>(
          context: context,
          builder: (_) => _QuickActionsDialog(
            connector: connector,
            service: settings,
            sections: sections,
          ),
        );
        if (destination != null && context.mounted) {
          await destination(context);
        }
      },
    );
  }
}

class _QuickActionsDialog extends StatefulWidget {
  const _QuickActionsDialog({
    required this.connector,
    required this.service,
    required this.sections,
  });

  final MeshCoreConnector connector;
  final AppSettingsService service;
  final SettingsSectionsService? sections;

  @override
  State<_QuickActionsDialog> createState() => _QuickActionsDialogState();
}

class _QuickActionsDialogState extends State<_QuickActionsDialog> {
  QuickAction? _pending;
  String? _error;

  bool get _online => widget.connector.isConnected && !widget.connector.isOfflineMode;

  bool _available(QuickActionItem item) {
    final connector = widget.connector;
    final sections = widget.sections;
    final proxyAllowed = sections?.companionProxySupported == true &&
        sections?.allowsCompanionProxy == true;
    if (!item.isConfigured) return false;
    return switch (item.action) {
      QuickAction.adaptiveTxPower => widget.service.settings.channelMinHopsEnabled,
      QuickAction.channelRetries => true,
      QuickAction.companionCli || QuickAction.cliCommand1 ||
        QuickAction.cliCommand2 => _online && connector.supportsCompanionCli,
      QuickAction.floodAdvert || QuickAction.zeroHopAdvert || QuickAction.discover =>
        _online,
      QuickAction.companionProxy => proxyAllowed,
      // The labels describe the proxy side. Each setting names its transport.
      QuickAction.tcpProxy => proxyAllowed &&
          sections?.allowsCompanionProxyBle == true &&
          sections?.companionProxyEnabled == true,
      QuickAction.bleProxy => proxyAllowed &&
          sections?.allowsCompanionProxyTcp == true &&
          sections?.companionProxyEnabled == true,
      QuickAction.manageKeys => connector.additionalIdentityInbox != null,
      QuickAction.channelMessage1 || QuickAction.channelMessage2 =>
        _online && connector.isSessionReady,
    };
  }

  bool _active(QuickAction action) => switch (action) {
    QuickAction.adaptiveTxPower => widget.service.settings.adaptiveTxPower.enabled,
    QuickAction.channelRetries => widget.service.settings.channelMinHopsEnabled,
    QuickAction.companionProxy => widget.sections?.companionProxyEnabled == true,
    QuickAction.tcpProxy => widget.sections?.companionProxyBleEnabled == true,
    QuickAction.bleProxy => widget.sections?.companionProxyTcpEnabled == true,
    _ => false,
  };

  Future<void> _activate(QuickActionItem item) async {
    if (_pending != null || !_available(item)) return;
    final connector = widget.connector;
    final service = widget.service;
    final sections = widget.sections;
    final action = item.action;
    final l10n = context.l10n;
    final _QuickActionsDestination? destination = switch (action) {
      QuickAction.companionCli => (context) => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => CompanionCliScreen(connector: connector)),
      ),
      QuickAction.discover => (context) => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const DiscoveryScreen(startDiscovery: true)),
      ),
      QuickAction.manageKeys => AdditionalIdentityScreen.open,
      _ => null,
    };
    if (destination != null) {
      Navigator.pop(context, destination);
      return;
    }

    final enable = !_active(action);
    setState(() {
      _pending = action;
      _error = null;
    });
    try {
      switch (action) {
        case QuickAction.adaptiveTxPower:
          final settings = service.settings;
          await service.updateSettings(settings.copyWith(
            adaptiveTxPower: settings.adaptiveTxPower.copyWith(enabled: enable),
          ));
        case QuickAction.channelRetries:
          await service.setChannelMinHopsEnabled(enable);
        case QuickAction.floodAdvert:
        case QuickAction.zeroHopAdvert:
          await connector.sendSelfAdvert(
            flood: action == QuickAction.floodAdvert,
            waitForAck: true,
          );
        case QuickAction.companionProxy:
          final proxy = sections!;
          await proxy.setCompanionProxyEnabled(enable, waitForBle: true);
          if (_active(action) != enable || proxy.companionProxyError != null) {
            throw StateError('Could not change proxy state');
          }
        case QuickAction.tcpProxy:
          await sections!.setCompanionProxyBleEnabled(enable);
          if (_active(action) != enable) throw StateError('Proxy state unchanged');
        case QuickAction.bleProxy:
          await sections!.setCompanionProxyTcpEnabled(enable);
          if (_active(action) != enable) throw StateError('Proxy state unchanged');
        case QuickAction.cliCommand1:
        case QuickAction.cliCommand2:
          await connector.companionCli.sendCommand(item.text, reportFailure: true);
        case QuickAction.channelMessage1:
        case QuickAction.channelMessage2:
          final channels = connector.channels.where(
            (channel) => !channel.isEmpty && channel.name == item.channelName,
          ).toList(growable: false);
          if (channels.length != 1 ||
              connector.unconfirmedChannelSlots.contains(channels.single.index)) {
            if (mounted) setState(() => _error = l10n.quickActions_channelMissing);
            return;
          }
          final channel = channels.single;
          await connector.sendChannelMessage(
            channel,
            item.text,
            reportFailure: true,
          );
        case QuickAction.companionCli:
        case QuickAction.discover:
        case QuickAction.manageKeys:
          return;
      }
    } on CompanionCliException catch (error) {
      if (!mounted) return;
      setState(() => _error = switch (error.code) {
        'busy' => l10n.companionCli_busy,
        'timeout' => l10n.companionCli_timeout,
        'unavailable' => l10n.companionCli_unavailable,
        'disconnected' => l10n.companionCli_disconnected,
        _ => l10n.quickActions_failed,
      });
    } catch (_) {
      if (mounted) setState(() => _error = l10n.quickActions_failed);
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  Widget _buildTile({
    required QuickActionItem item,
    required double width,
    required double diameter,
    required double iconSize,
  }) {
    final available = _available(item);
    return _QuickActionTile(
      item: item,
      width: width,
      diameter: diameter,
      iconSize: iconSize,
      active: _active(item.action),
      available: available,
      pending: _pending == item.action,
      onTap: _pending == null && available ? () => _activate(item) : null,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.service, widget.connector, widget.sections]),
    builder: (context, _) {
      final l10n = context.l10n;
      final scheme = Theme.of(context).colorScheme;
      final settings = widget.service.settings;
      final scale = settings.uiScale.clamp(0.5, 2.0).toDouble();
      final diameter = 42 * scale;
      final labelScale = MediaQuery.textScalerOf(context).scale(1);
      final items = settings.quickActions.items.where((item) => item.visible);
      const inset = EdgeInsets.symmetric(horizontal: 24, vertical: 24);
      const contentPadding = EdgeInsets.fromLTRB(16, 20, 16, 8);
      const gap = 8.0;
      final availableWidth = MediaQuery.sizeOf(context).width -
          MediaQuery.viewInsetsOf(context).horizontal -
          inset.horizontal;
      final dialogWidth = availableWidth.clamp(0.0, 412.0).toDouble();
      final width = math.max(0.0, dialogWidth - contentPadding.horizontal);
      final minimum = math.max(diameter, 70 * labelScale);
      final columns = ((width + gap) / (minimum + gap)).floor().clamp(1, 5);
      final tileWidth = (width - (columns - 1) * gap) / columns;
      return AlertDialog(
        semanticLabel: l10n.quickActions_title,
        scrollable: true,
        insetPadding: inset,
        constraints: BoxConstraints.tightFor(width: dialogWidth),
        contentPadding: contentPadding,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (items.isEmpty)
              Text(l10n.quickActions_empty)
            else
              Wrap(
                alignment: WrapAlignment.center,
                spacing: gap,
                runSpacing: 12,
                children: [
                  for (final item in items)
                    _buildTile(
                      item: item,
                      width: tileWidth,
                      diameter: math.min(diameter, tileWidth),
                      iconSize: settings.uiScaleApplyToIcons ? 22 * scale : 22,
                    ),
                ],
              ),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(error, style: TextStyle(color: scheme.error)),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop<_QuickActionsDestination>(
              context,
              QuickActionsSettingsScreen.open,
            ),
            child: Text(l10n.quickActions_configure),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.common_close),
          ),
        ],
      );
    },
  );
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.item,
    required this.width,
    required this.diameter,
    required this.iconSize,
    required this.active,
    required this.available,
    required this.pending,
    required this.onTap,
  });

  final QuickActionItem item;
  final double width;
  final double diameter;
  final double iconSize;
  final bool active;
  final bool available;
  final bool pending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = item.label(context.l10n);
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        selected: active,
        child: AnimatedOpacity(
          opacity: available && !pending ? 1 : 0.45,
          duration: const Duration(milliseconds: 120),
          child: InkWell(
            key: ValueKey(item.action),
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Column(
              children: [
                Container(
                  width: diameter,
                  height: diameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? scheme.primary : scheme.surfaceContainerHighest,
                    border: active ? null : Border.all(color: scheme.primary),
                  ),
                  child: Icon(
                    item.action.icon,
                    size: math.min(iconSize, diameter),
                    color: active ? scheme.onPrimary : scheme.primary,
                    applyTextScaling: false,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  softWrap: true,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
