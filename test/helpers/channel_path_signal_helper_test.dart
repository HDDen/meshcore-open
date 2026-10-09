import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_path_signal_helper.dart';

// The route a bubble draws for a flood packet: the longest route among the
// copies heard, the first of them when several are as long, and nothing when
// no copy was heard.

ChannelPathObservation _route(List<int> hops, {double? snr}) =>
    ChannelPathObservation(pathBytes: Uint8List.fromList(hops), snr: snr);

void main() {
  test('the longest route wins', () {
    final longest = ChannelPathSignalHelper.longest([
      _route([0x10]),
      _route([0x10, 0x20, 0x30], snr: 4),
      _route([0x40, 0x50]),
    ]);

    expect(longest?.pathBytes, [0x10, 0x20, 0x30]);
    expect(longest?.snr, 4);
  });

  test('among routes as long as each other the first one wins', () {
    final longest = ChannelPathSignalHelper.longest([
      _route([0x10, 0x20], snr: 1),
      _route([0x30, 0x40], snr: 2),
    ]);

    expect(longest?.pathBytes, [0x10, 0x20]);
  });

  test('a copy heard with no repeater is a route too', () {
    final longest = ChannelPathSignalHelper.longest([_route([], snr: 7)]);

    expect(longest?.pathBytes, isEmpty);
    expect(longest?.snr, 7);
  });

  test('no copies, no route', () {
    expect(ChannelPathSignalHelper.longest(const []), isNull);
  });
}
