import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/quick_actions_settings.dart';

void main() {
  test('quick actions keep their order and independent presets in settings', () {
    final defaults = AppSettings.fromJson({}).quickActions;
    expect(defaults.items.map((item) => item.action), QuickAction.values);
    expect(defaults.items.where((item) => item.visible), hasLength(10));

    final custom = defaults
        .update(const QuickActionItem(
          QuickAction.cliCommand1, visible: true, name: 'Version', text: 'ver',
        ))
        .update(const QuickActionItem(
          QuickAction.cliCommand2, visible: false, name: 'Board', text: 'board',
        ))
        .update(const QuickActionItem(
          QuickAction.channelMessage1,
          visible: true,
          name: 'Check in',
          text: 'Here',
          channelName: '#test',
        ))
        .reorder(QuickAction.channelMessage1.index, 0);
    final data = jsonDecode(jsonEncode(
      AppSettings().copyWith(quickActions: custom).toJson(),
    )) as Map<String, dynamic>;
    final restored = AppSettings.fromJson(data).quickActions;
    expect(restored.toJson(), custom.toJson());
    expect(restored.items.first.action, QuickAction.channelMessage1);
    expect(restored.items.first.channelName, '#test');
  });

  test('old and malformed settings keep a single copy of each action', () {
    final restored = QuickActionsSettings.fromJson([
      null,
      {'action': 'unknown'},
      {'action': 'channelRetries', 'visible': false},
      {'action': 'channelRetries', 'visible': true},
      {'action': 'channelMessage2', 'visible': true, 'text': 42},
    ]);
    expect(restored.items.map((item) => item.action).toSet(), QuickAction.values.toSet());
    expect(restored.items, hasLength(14));
    expect(restored.items.first.action, QuickAction.channelRetries);
    expect(restored.items.first.visible, isFalse);
    expect(restored.items[1].isConfigured, isFalse);
  });
}
