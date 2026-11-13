enum QuickAction {
  adaptiveTxPower,
  channelRetries,
  companionCli,
  floodAdvert,
  zeroHopAdvert,
  discover,
  companionProxy,
  tcpProxy,
  bleProxy,
  manageKeys,
  cliCommand1,
  cliCommand2,
  channelMessage1,
  channelMessage2;

  bool get isCliCommand => this == cliCommand1 || this == cliCommand2;
  bool get isChannelMessage => this == channelMessage1 || this == channelMessage2;
  bool get isCustom => isCliCommand || isChannelMessage;
}

class QuickActionItem {
  const QuickActionItem(
    this.action, {
    required this.visible,
    this.name = '',
    this.text = '',
    this.channelName = '',
  });

  final QuickAction action;
  final bool visible;
  final String name;
  final String text;
  final String channelName;

  QuickActionItem copyWith({
    bool? visible,
    String? name,
    String? text,
    String? channelName,
  }) => QuickActionItem(
    action,
    visible: visible ?? this.visible,
    name: name ?? this.name,
    text: text ?? this.text,
    channelName: channelName ?? this.channelName,
  );

  bool get isConfigured => !action.isCustom ||
      (text.trim().isNotEmpty &&
          (!action.isChannelMessage || channelName.trim().isNotEmpty));

  Map<String, Object> toJson() => {
    'action': action.name,
    'visible': visible,
    if (action.isCustom) ...{
      'name': name,
      'text': text,
      if (action.isChannelMessage) 'channel': channelName,
    },
  };
}

class QuickActionsSettings {
  const QuickActionsSettings.defaults() : _items = null;

  QuickActionsSettings(Iterable<QuickActionItem> items)
    : _items = List.unmodifiable(_complete(items));

  final List<QuickActionItem>? _items;
  static final _defaults = List<QuickActionItem>.unmodifiable(
    _complete(const []),
  );

  List<QuickActionItem> get items => _items ?? _defaults;

  static Iterable<QuickActionItem> _complete(Iterable<QuickActionItem> items) sync* {
    final used = <QuickAction>{};
    for (final item in items) {
      if (used.add(item.action)) yield item;
    }
    for (final action in QuickAction.values) {
      if (used.add(action)) {
        yield QuickActionItem(action, visible: !action.isCustom);
      }
    }
  }

  factory QuickActionsSettings.fromJson(Object? json) {
    if (json is! List) return const QuickActionsSettings.defaults();
    return QuickActionsSettings([
      for (final item in json)
        if (item is Map)
          for (final action in QuickAction.values)
            if (item['action'] == action.name)
              QuickActionItem(
                action,
                visible: item['visible'] is bool
                    ? item['visible'] as bool
                    : !action.isCustom,
                name: item['name'] is String ? item['name'] as String : '',
                text: item['text'] is String ? item['text'] as String : '',
                channelName: item['channel'] is String
                    ? item['channel'] as String
                    : '',
              ),
    ]);
  }

  List<Map<String, Object>> toJson() => [
    for (final item in items) item.toJson(),
  ];

  QuickActionsSettings update(QuickActionItem item) => QuickActionsSettings([
    for (final current in items)
      if (current.action == item.action) item else current,
  ]);

  QuickActionsSettings reorder(int oldIndex, int newIndex) {
    final ordered = items.toList();
    final moved = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, moved);
    return QuickActionsSettings(ordered);
  }
}
