import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_region_filter.dart';
import 'package:meshcore_open/models/channel_message.dart';

ChannelMessage _post(String id, {String? region, bool available = true,
  bool unknown = false, bool outgoing = false, String? shared}) => ChannelMessage(
  messageId: id, senderName: 'Alice', text: 'Message $id',
  timestamp: DateTime.utc(2026), receivedAt: DateTime.utc(2026),
  isOutgoing: outgoing, packetRegion: region,
  packetRegionInfoAvailable: available, packetRegionNotMatched: unknown,
  sharedHistorySourceName: shared,
);

void main() {
  test('denylist normalizes names and stores only explicitly disabled categories', () {
    final encoded = ChannelRegionFilter.encode(['#north', 'north', '!unscoped', ChannelRegionFilter.unknown]);
    expect(ChannelRegionFilter.decode(encoded), {'north', '', ChannelRegionFilter.unknown});
    expect(ChannelRegionFilter.canonical('[1]'), isNull);
    expect(ChannelRegionFilter.canonical('broken'), isNull);
    expect(ChannelRegionFilter.choices(['#south', 'north'], {'removed'}),
      ['', ChannelRegionFilter.unknown, 'north', 'removed', 'south']);
  });

  test('unscoped and unknown messages have independent switches', () {
    final unscoped = _post('unscoped');
    final unknown = _post('unknown', unknown: true);
    final legacyUnknown = _post('legacy', available: false);
    expect(ChannelRegionFilter.allows(unscoped, {''}), isFalse);
    expect(ChannelRegionFilter.allows(unknown, {''}), isTrue);
    expect(ChannelRegionFilter.allows(legacyUnknown, {''}), isTrue);
    expect(ChannelRegionFilter.allows(unscoped, {ChannelRegionFilter.unknown}), isTrue);
    expect(ChannelRegionFilter.allows(unknown, {ChannelRegionFilter.unknown}), isFalse);
    expect(ChannelRegionFilter.allows(legacyUnknown, {ChannelRegionFilter.unknown}), isFalse);
    expect(ChannelRegionFilter.allows(_post('empty', region: '', available: false),
      {ChannelRegionFilter.unknown}), isFalse);
  });

  test('only disabled regions hide local, shared and outgoing posts; new regions pass', () {
    for (final message in [
      _post('incoming', region: 'north'),
      _post('outgoing', region: '#north', outgoing: true),
      _post('shared', region: 'north', shared: 'Other node'),
    ]) {
      expect(ChannelRegionFilter.allows(message, {'north'}), isFalse);
      expect(ChannelRegionFilter.allows(message, {}), isTrue);
    }
    expect(ChannelRegionFilter.allows(_post('new', region: 'new-region'), {'north'}), isTrue);
  });

  test('filtered timeline is stable and never mutates or deletes history', () {
    final source = [_post('north', region: 'north'), _post('south', region: 'south')];
    final cache = ChannelRegionFilterTimeline();
    final filtered = cache.resolve(source, {'north'});
    expect(filtered, [source.last]);
    expect(identical(filtered, cache.resolve(source, {'north'})), isTrue);
    expect(cache.resolve(source, {'south'}), [source.first]);
    expect(identical(cache.resolve(source, {}), source), isTrue);
    expect(source.map((message) => message.messageId), ['north', 'south']);
  });
}
