import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/models/companion_radio_stats.dart';
import 'package:meshcore_open/l10n/l10n.dart';
import 'package:meshcore_open/screens/companion_radio_stats_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:provider/provider.dart';

import '../theme/mesh_theme.dart';
import '../helpers/radio_stats_indicator_polling.dart';
import 'mesh_ui.dart';

void pushCompanionRadioStatsScreen(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (context) => const CompanionRadioStatsScreen(),
    ),
  );
}

class RadioStatsIconButton extends StatefulWidget {
  final bool compact;

  const RadioStatsIconButton({super.key, this.compact = false});

  @override
  State<RadioStatsIconButton> createState() => _RadioStatsIconButtonState();
}

class _RadioStatsIconButtonState extends State<RadioStatsIconButton> {
  RadioStatsIndicatorPolling? _polling;

  @override
  void initState() {
    super.initState();
    final c = context.read<MeshCoreConnector>();
    _polling = RadioStatsIndicatorPolling(
      c,
      context.read<AppSettingsService>(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _polling?.updateRoute(context);
  }

  @override
  void dispose() {
    _polling?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hidden = context.select<AppSettingsService, bool>(
      (s) => s.settings.hideRadioStatsButton,
    );
    if (hidden) return const SizedBox.shrink();
    return Selector<MeshCoreConnector, ({bool connected, bool supported})>(
      selector: (_, c) =>
          (connected: c.isConnected, supported: c.supportsCompanionRadioStats),
      builder: (context, state, _) {
        if (!state.connected || !state.supported) {
          return const SizedBox.shrink();
        }
        final connector = context.read<MeshCoreConnector>();
        return ValueListenableBuilder<CompanionRadioStats?>(
          valueListenable: connector.radioStatsNotifier,
          builder: (context, _, child) {
            final dot = AirActivityDot(
              active: connector.radioStatsAirActivityPulse,
            );
            if (widget.compact) {
              return Semantics(
                label: context.l10n.radioStats_tooltip,
                button: true,
                child: GestureDetector(
                  onTap: () => pushCompanionRadioStatsScreen(context),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: dot,
                  ),
                ),
              );
            }
            return Tooltip(
              message: context.l10n.radioStats_tooltip,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => pushCompanionRadioStatsScreen(context),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(child: dot),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class AirActivityDot extends StatefulWidget {
  final bool active;

  const AirActivityDot({super.key, required this.active});

  @override
  State<AirActivityDot> createState() => AirActivityDotState();
}

class AirActivityDotState extends State<AirActivityDot> {
  /// One blink: on for one half-period, off for the next.
  static const Duration _half = Duration(milliseconds: 400);

  // A timer, not a ticker: a repeating AnimationController runs the whole
  // frame pipeline sixty times a second for a dot that changes 2.5 times a
  // second, and kept the UI thread busy for every poll window after a send.
  // The timer runs only while TickerMode allows frames, the signal that
  // muted the ticker under a route that is not on top, so a covered app bar
  // asks for no frames either.
  Timer? _timer;
  bool _on = false;
  ValueListenable<TickerModeData>? _tickerMode;

  @override
  void initState() {
    super.initState();
    _on = widget.active;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mode = TickerMode.getValuesNotifier(context);
    if (!identical(mode, _tickerMode)) {
      _tickerMode?.removeListener(_syncTimer);
      _tickerMode = mode..addListener(_syncTimer);
    }
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant AirActivityDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      _on = widget.active;
      _syncTimer();
    }
  }

  @override
  void dispose() {
    _tickerMode?.removeListener(_syncTimer);
    _timer?.cancel();
    super.dispose();
  }

  /// Runs the timer while the dot is active and frames are allowed. The
  /// phase is kept across a pause, so nothing here rebuilds: the TickerMode
  /// notifier fires during another widget's build, where setState is not
  /// allowed, and a paused dot is not on screen anyway.
  void _syncTimer() {
    final run = widget.active && (_tickerMode?.value.enabled ?? true);
    if (run) {
      _timer ??= Timer.periodic(_half, (_) => setState(() => _on = !_on));
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PulseDot(
      color: widget.active && _on ? MeshPalette.blue : scheme.outline,
      size: 11,
      animate: false,
    );
  }
}
