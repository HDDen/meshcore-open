import 'package:flutter/material.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/models/companion_radio_stats.dart';
import 'package:meshcore_open/l10n/l10n.dart';
import 'package:meshcore_open/screens/companion_radio_stats_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:provider/provider.dart';

import '../theme/mesh_theme.dart';
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
  MeshCoreConnector? _connector;

  @override
  void initState() {
    super.initState();
    final c = context.read<MeshCoreConnector>();
    _connector = c;
    c.acquireRadioStatsPolling();
  }

  @override
  void dispose() {
    _connector?.releaseRadioStatsPolling();
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

class AirActivityDotState extends State<AirActivityDot>
    with SingleTickerProviderStateMixin {
  /// One blink: on for the first half of the period, off for the second.
  static const Duration _period = Duration(milliseconds: 800);

  // A ticker, not a periodic timer with setState: a timer kept scheduling a
  // frame every 400 ms for the app bar of every route in the stack, seen or
  // not, while TickerMode mutes a ticker under a route that is not on top.
  // Created in initState, as PulseDot's is: a lazy initializer would run on
  // first access, which can be dispose(), where creating a ticker throws.
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _period);
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant AirActivityDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.repeat();
    } else if (!widget.active && oldWidget.active) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Which half of the period this is, read a hair past the frame time:
        // `repeat` takes the phase as a fraction of the period, and that
        // division can come out a hair under a half, or under a whole, where
        // it should land on it, which would show the wrong half for a frame.
        final half = ((_controller.value + 1e-6) * 2).floor();
        final on = widget.active && half.isEven;
        return PulseDot(
          color: on ? MeshPalette.blue : scheme.outline,
          size: 11,
          animate: false,
        );
      },
    );
  }
}
