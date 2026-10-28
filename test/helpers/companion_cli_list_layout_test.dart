import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/companion_cli_list_layout.dart';
import 'package:meshcore_open/helpers/companion_cli_protocol.dart';

void main() {
  test('service can move between channels without becoming a channel or group', () {
    final layout = CompanionCliListLayout<String>(items: ['channel:2', 'group:a', 'channel:1'],
      keyOf: (key) => key, previousOrder: [], visible: true);
    expect(layout.entries, [null, 'channel:2', 'group:a', 'channel:1']);
    final moved = layout.moved(0, 2);
    final normal = moved.whereType<String>().toList();
    expect(normal, ['channel:2', 'group:a', 'channel:1']);
    expect(layout.order(moved, normal), ['channel:2', 'group:a', companionCliOrderKey, 'channel:1']);
  });

  test('hidden service position and detached peer order are preserved in legacy lists', () {
    final previous = ['peer:x', 'channel:2', companionCliOrderKey, 'channel:1'];
    final visible = CompanionCliListLayout<String>(items: ['channel:2', 'channel:1'],
      keyOf: (key) => key, previousOrder: previous, visible: true, retainPeerKeys: true);
    expect(visible.entries, ['channel:2', null, 'channel:1']);
    final hidden = CompanionCliListLayout<String>(items: ['channel:2', 'channel:1'],
      keyOf: (key) => key, previousOrder: previous, visible: false, retainPeerKeys: true);
    final order = hidden.order(hidden.entries, ['channel:2', 'channel:1']);
    expect(order, previous);
  });

  test('unread prefix stays ahead of a service item even after drag', () {
    final layout = CompanionCliListLayout<String>(items: ['unread', 'read'],
      keyOf: (key) => key, previousOrder: [], visible: true, minimumPosition: 1);
    expect(layout.entries, ['unread', null, 'read']);
    expect(layout.moved(1, 0), ['unread', null, 'read']);
  });
}
