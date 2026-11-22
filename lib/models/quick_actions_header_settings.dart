enum QuickActionsHeaderDisplay {
  icon,
  noise,
  extraHops;

  bool get selectable => this != extraHops;
  bool get hasPolling => this == noise;
}

/// Header-only presentation. Each live display keeps its own cadence, leaving
/// popup action visibility/order and its one-second cadence independent.
class QuickActionsHeaderSettings {
  const QuickActionsHeaderSettings.defaults()
      : display = QuickActionsHeaderDisplay.noise, _intervals = null;

  QuickActionsHeaderSettings({
    QuickActionsHeaderDisplay display = QuickActionsHeaderDisplay.noise,
    Map<QuickActionsHeaderDisplay, int> intervalsMs = const {},
  }) : display = display.selectable ? display : QuickActionsHeaderDisplay.noise,
       _intervals = Map.unmodifiable({
         for (final entry in intervalsMs.entries)
           if (entry.key.hasPolling && allowedIntervalsMs.contains(entry.value))
             entry.key: entry.value,
       });

  static const allowedIntervalsMs = [500, 1000, 2000, 3000, 5000, 7000, 10000];
  static const defaultIntervalMs = 10000;
  final QuickActionsHeaderDisplay display;
  final Map<QuickActionsHeaderDisplay, int>? _intervals;

  int intervalMsFor(QuickActionsHeaderDisplay mode) =>
      _intervals?[mode] ?? defaultIntervalMs;

  QuickActionsHeaderSettings copyWith({QuickActionsHeaderDisplay? display}) =>
      QuickActionsHeaderSettings(display: display ?? this.display,
        intervalsMs: _intervals ?? const {});

  QuickActionsHeaderSettings withInterval(QuickActionsHeaderDisplay mode, int milliseconds) =>
      QuickActionsHeaderSettings(display: display, intervalsMs: {
        ...?_intervals,
        if (mode.hasPolling && allowedIntervalsMs.contains(milliseconds)) mode: milliseconds,
      });

  Map<String, Object> toJson() {
    final intervals = _intervals;
    return {
      'display': display.name,
      if (intervals != null && intervals.isNotEmpty) 'intervals_ms': {
        for (final entry in intervals.entries) entry.key.name: entry.value,
      },
    };
  }

  factory QuickActionsHeaderSettings.fromJson(Object? raw) {
    if (raw is! Map) return const QuickActionsHeaderSettings.defaults();
    var display = QuickActionsHeaderDisplay.noise;
    for (final mode in QuickActionsHeaderDisplay.values) {
      if (mode.selectable && mode.name == raw['display']) {
        display = mode;
        break;
      }
    }
    final intervals = raw['intervals_ms'];
    return QuickActionsHeaderSettings(display: display, intervalsMs: {
      if (intervals is Map)
        for (final mode in QuickActionsHeaderDisplay.values)
          if (mode.hasPolling && intervals[mode.name] is int &&
              allowedIntervalsMs.contains(intervals[mode.name]))
            mode: intervals[mode.name] as int,
    });
  }
}
