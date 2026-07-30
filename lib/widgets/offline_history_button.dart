import 'dart:async';

import 'package:flutter/material.dart';

import '../connector/meshcore_connector.dart';
import '../l10n/l10n.dart';
import '../screens/channels_screen.dart';
import '../utils/app_route_observer.dart';

class OfflineHistoryButton extends StatefulWidget {
  final MeshCoreConnector connector;
  final ValueChanged<bool>? onLoadingChanged;
  final VoidCallback? onOpened;
  final VoidCallback? onClosed;

  const OfflineHistoryButton({
    super.key,
    required this.connector,
    this.onLoadingChanged,
    this.onOpened,
    this.onClosed,
  });

  @override
  State<OfflineHistoryButton> createState() => _OfflineHistoryButtonState();
}

class _OfflineHistoryButtonState extends State<OfflineHistoryButton>
    with RouteAware {
  static const String _sharedSelection = '__shared__';
  static const double _maxButtonWidth = 240;
  bool _isLoading = false;
  bool _offlineSessionActive = false;
  bool _isClosingOfflineSession = false;
  PageRoute<dynamic>? _observedRoute;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && _observedRoute != route) {
      if (_observedRoute != null) {
        appRouteObserver.unsubscribe(this);
      }
      _observedRoute = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    if (_offlineSessionActive) {
      unawaited(_finishOfflineSession());
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sources = widget.connector.offlineHistorySources;
    return SizedBox(
      height: 56,
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxButtonWidth),
          child: SizedBox(
            height: 56,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: sources.isEmpty || _isLoading
                  ? null
                  : () => _openOfflineHistory(sources),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isLoading)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.cloud_off_outlined),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      context.l10n.app_offline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openOfflineHistory(List<OfflineHistorySource> sources) async {
    final selection = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.hub_outlined),
              title: Text(context.l10n.app_offline_sharedMode),
              onTap: () => Navigator.pop(context, _sharedSelection),
            ),
            const Divider(height: 1),
            for (final source in sources)
              ListTile(
                leading: const Icon(Icons.memory_outlined),
                title: Text(source.name),
                subtitle: Text(source.scope.toUpperCase()),
                onTap: () => Navigator.pop(context, source.scope),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selection == null) return;

    _setLoading(true);
    final bool entered;
    try {
      entered = await widget.connector.enterOfflineHistory(
        shared: selection == _sharedSelection,
        scope: selection == _sharedSelection ? null : selection,
      );
    } finally {
      _setLoading(false);
    }
    if (!mounted || !entered) return;

    _offlineSessionActive = true;
    widget.onOpened?.call();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ChannelsScreen()));
    if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
      await _finishOfflineSession();
    }
  }

  Future<void> _finishOfflineSession() async {
    if (_isClosingOfflineSession) return;
    _isClosingOfflineSession = true;
    _offlineSessionActive = false;
    try {
      if (widget.connector.isOfflineMode) {
        await widget.connector.exitOfflineHistory();
      }
      if (mounted) widget.onClosed?.call();
    } finally {
      _isClosingOfflineSession = false;
    }
  }

  void _setLoading(bool value) {
    if (mounted) setState(() => _isLoading = value);
    widget.onLoadingChanged?.call(value);
  }
}
