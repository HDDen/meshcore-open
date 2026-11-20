import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mco_service/mco_service.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/companion_cli_protocol.dart';
import '../helpers/quick_action_radio_polling.dart';
import '../l10n/l10n.dart';
import '../models/quick_actions_settings.dart';
import '../models/quick_actions_header_settings.dart';
import '../screens/additional_identity_screen.dart';
import '../screens/companion_cli_screen.dart';
import '../screens/discovery_screen.dart';
import '../screens/companion_radio_stats_screen.dart';
import '../screens/telemetry_screen.dart';
import '../screens/settings_screen.dart';
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
    return _QuickActionsHeaderIndicator(connector: context.read<MeshCoreConnector>());
  }
}

class _QuickActionsHeaderIndicator extends StatefulWidget {
  const _QuickActionsHeaderIndicator({required this.connector});
  final MeshCoreConnector connector;

  @override
  State<_QuickActionsHeaderIndicator> createState() => _QuickActionsHeaderIndicatorState();
}

class _QuickActionsHeaderIndicatorState extends State<_QuickActionsHeaderIndicator> {
  QuickActionRadioPolling? _polling;
  ModalRoute<dynamic>? _route;
  bool _tickerEnabled = false;

  void _configurePolling() {
    final service = context.read<AppSettingsService>();
    final current = _polling;
    if (current == null || !identical(current.connector, widget.connector) ||
        !identical(current.settings, service)) {
      current?.dispose();
      _polling = QuickActionRadioPolling(
        widget.connector, service, source: QuickActionPollingSource.header,
        isVisible: () => mounted && _tickerEnabled && _route?.isCurrent == true,
      );
    }
    _polling!.update();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _configurePolling();
  }

  @override
  void didUpdateWidget(covariant _QuickActionsHeaderIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.connector, widget.connector)) _configurePolling();
  }

  @override
  void dispose() {
    _polling?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final display = context.select<AppSettingsService, QuickActionsHeaderDisplay>(
      (service) => service.settings.quickActionsHeader.display,
    );
    if (display == QuickActionsHeaderDisplay.icon || !display.selectable) {
      return QuickActionsButton(connector: widget.connector);
    }
    return ValueListenableBuilder(
      valueListenable: widget.connector.radioStatsNotifier,
      builder: (context, stats, _) {
        final noise = widget.connector.supportsCompanionRadioStats ? stats?.noiseFloorDbm : null;
        return QuickActionsButton(
          connector: widget.connector,
          icon: SizedBox(
            key: const ValueKey('quick-actions-header-reading'),
            width: 36, height: 40,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('${noise ?? '—'}\ndBm',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall),
            ),
          ),
        );
      },
    );
  }
}

class QuickActionsButton extends StatelessWidget {
  const QuickActionsButton({super.key, required this.connector, this.icon});

  final MeshCoreConnector connector;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.l10n.quickActions_title,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 48),
      icon: icon ?? const Icon(Icons.widgets_outlined, size: 20),
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
  ModalRoute<dynamic>? _route;
  late final QuickActionRadioPolling _radioPolling;

  @override
  void initState() {
    super.initState();
    _radioPolling = QuickActionRadioPolling(
      widget.connector, widget.service,
      isVisible: () => mounted && _route?.isCurrent == true,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _radioPolling.update();
  }

  @override
  void dispose() {
    _radioPolling.dispose();
    super.dispose();
  }

  void _close([_QuickActionsDestination? destination]) {
    _radioPolling.dispose();
    Navigator.pop<_QuickActionsDestination>(context, destination);
  }

  String? _reading(QuickAction action) {
    if (action == QuickAction.radioNoise) {
      final stats = _online && widget.connector.supportsCompanionRadioStats
          ? widget.connector.radioStatsNotifier.value : null;
      return '${stats?.noiseFloorDbm ?? '—'}\ndBm';
    }
    if (action == QuickAction.radioTxPower) {
      final power = _online ? widget.connector.currentTxPower : null;
      return '${power ?? '—'}\ndBm';
    }
    return null;
  }

  bool get _online => widget.connector.isConnected && !widget.connector.isOfflineMode;

  bool _available(QuickActionItem item) {
    final connector = widget.connector;
    final sections = widget.sections;
    final proxyAllowed = sections?.companionProxySupported == true &&
        sections?.allowsCompanionProxy == true;
    if (!item.isConfigured) return false;
    return switch (item.action) {
      QuickAction.adaptiveTxPower => widget.service.settings.channelMinHopsEnabled,
      QuickAction.channelRetries || QuickAction.channelIndices => true,
      QuickAction.radioStats || QuickAction.radioNoise =>
          _online && connector.supportsCompanionRadioStats,
      QuickAction.radioTxPower => _online && connector.isSessionReady,
      QuickAction.sensors => _online && connector.selfPublicKey?.isNotEmpty == true,
      QuickAction.readChannels || QuickAction.readDirect || QuickAction.readAll =>
          !connector.isOfflineMode,
      QuickAction.companionCli || QuickAction.cliCommand1 ||
        QuickAction.cliCommand2 => _online && connector.supportsCompanionCli,
      QuickAction.floodAdvert || QuickAction.zeroHopAdvert || QuickAction.discover =>
        _online,
      QuickAction.companionProxy => proxyAllowed,
      QuickAction.tcpProxy => proxyAllowed &&
          sections?.allowsCompanionProxyTcp == true &&
          sections?.companionProxyEnabled == true,
      QuickAction.bleProxy => proxyAllowed &&
          sections?.allowsCompanionProxyBle == true &&
          sections?.companionProxyEnabled == true,
      QuickAction.manageKeys => connector.additionalIdentityInbox != null,
      QuickAction.channelMessage1 || QuickAction.channelMessage2 =>
        _online && connector.isSessionReady,
    };
  }

  bool _active(QuickAction action) => switch (action) {
    QuickAction.adaptiveTxPower => widget.service.settings.adaptiveTxPower.enabled,
    QuickAction.channelRetries => widget.service.settings.channelMinHopsEnabled,
    QuickAction.channelIndices => !widget.service.settings.hideChannelIndexIndicator,
    QuickAction.companionProxy => widget.sections?.companionProxyEnabled == true,
    QuickAction.tcpProxy => widget.sections?.companionProxyTcpEnabled == true,
    QuickAction.bleProxy => widget.sections?.companionProxyBleEnabled == true,
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
      QuickAction.radioStats || QuickAction.radioNoise => (context) => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const CompanionRadioStatsScreen()),
      ),
      QuickAction.radioTxPower => (context) => SettingsScreen.openRadioSettings(
        context, connector: connector,
      ),
      QuickAction.sensors => (context) async { pushSelfTelemetryScreen(context); },
      _ => null,
    };
    if (destination != null) {
      _close(destination);
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
        case QuickAction.channelIndices:
          await service.setHideChannelIndexIndicator(!enable);
        case QuickAction.readChannels:
          await connector.markChatsRead(channels: true);
        case QuickAction.readDirect:
          await connector.markChatsRead(contacts: true);
        case QuickAction.readAll:
          await connector.markChatsRead(channels: true, contacts: true);
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
          await sections!.setCompanionProxyTcpEnabled(enable);
          if (_active(action) != enable) throw StateError('Proxy state unchanged');
        case QuickAction.bleProxy:
          await sections!.setCompanionProxyBleEnabled(enable);
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
        case QuickAction.radioStats:
        case QuickAction.radioNoise:
        case QuickAction.radioTxPower:
        case QuickAction.sensors:
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
      reading: _reading(item.action),
      onTap: _pending == null && available ? () => _activate(item) : null,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.service, widget.connector, widget.sections,
      widget.connector.radioStatsNotifier,
    ]),
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
      return PopScope<_QuickActionsDestination>(
        onPopInvokedWithResult: (didPop, _) { if (didPop) _radioPolling.dispose(); },
        child: AlertDialog(
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
            onPressed: () => _close(QuickActionsSettingsScreen.open),
            child: Text(l10n.quickActions_configure),
          ),
          FilledButton(
            onPressed: () => _close(),
            child: Text(l10n.common_close),
          ),
        ],
      ));
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
    required this.reading,
  });

  final QuickActionItem item;
  final double width;
  final double diameter;
  final double iconSize;
  final bool active;
  final bool available;
  final bool pending;
  final VoidCallback? onTap;
  final String? reading;

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
                  child: reading == null ? Icon(
                    item.action.icon,
                    size: math.min(iconSize, diameter),
                    color: active ? scheme.onPrimary : scheme.primary,
                    applyTextScaling: false,
                  ) : Padding(
                    padding: const EdgeInsets.all(4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        reading!, textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: active ? scheme.onPrimary : scheme.primary,
                        ),
                      ),
                    ),
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
