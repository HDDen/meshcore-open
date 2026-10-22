import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_resend_warning.dart';
import 'package:meshcore_open/models/channel_message.dart';

ChannelMessage _message(List<List<int>> paths) => ChannelMessage(
  senderName: 'synthetic', text: 'test', timestamp: DateTime.utc(2026),
  sentByRadioAt: DateTime.utc(2026), isOutgoing: true,
  status: ChannelMessageStatus.sent, repeatCount: paths.length,
  pathHashWidth: 2,
  pathLength: paths.fold<int>(0, (count, path) =>
      path.length ~/ 2 > count ? path.length ~/ 2 : count),
  pathBytes: paths.isEmpty ? null : Uint8List.fromList(paths.first),
  pathVariants: [for (final path in paths) Uint8List.fromList(path)],
);

void main() {
  const previous = (hops: 1, required: 2);
  test('one or two nearby repeaters retain shortfall until the third distinct hop', () {
    for (final paths in [
      [[0x81, 0x30]],
      [[0x81, 0x30], [0x81, 0x30]],
      [[0x81, 0x30], [0x81, 0x40]],
    ]) {
      expect(channelResendShortfallAfterEcho(_message(paths), previous,
          countDistinctRepeaters: true, minRepeaters: 3), previous);
    }
    expect(channelResendShortfallAfterEcho(_message([
      [0x81, 0x30], [0x81, 0x40], [0x81, 0x50],
    ]), previous, countDistinctRepeaters: true, minRepeaters: 3), isNull);
  });

  test('a long enough route clears shortfall with the nearby toggle on or off', () {
    for (final enabled in [false, true]) {
      expect(channelResendShortfallAfterEcho(_message([
        [0x81, 0x30, 0x99, 0x99],
      ]), previous, countDistinctRepeaters: enabled, minRepeaters: 3), isNull);
    }
  });

  test('nearby toggle off and our own prefix cannot satisfy nearby coverage', () {
    final message = _message([
      [0x81, 0x30], [0x81, 0x40], [0x81, 0x50],
    ]);
    expect(channelResendShortfallAfterEcho(message, previous,
        countDistinctRepeaters: false, minRepeaters: 3), previous);
    expect(channelResendShortfallAfterEcho(message, previous,
        countDistinctRepeaters: true, minRepeaters: 3,
        selfPublicKey: Uint8List.fromList([0x81, 0x30])), previous);
  });

  test('shortfall reports new progress while the required distance is retained', () {
    expect(channelResendShortfallAfterEcho(_message([
      [0x81, 0x30, 0x99, 0x99],
    ]), (hops: 1, required: 3), countDistinctRepeaters: false, minRepeaters: 3),
        (hops: 2, required: 3));
  });

  test('one echo suppresses only the ordinary warning and guards remain in force', () {
    final message = _message([[0x81, 0x30]]);
    expect(channelNeedsRetransmissionWarning(message, hasCoverageShortfall: false), isFalse);
    expect(channelNeedsRetransmissionWarning(message, hasCoverageShortfall: true), isTrue);
    for (final invalid in [
      message.copyWith(isOutgoing: false),
      message.copyWith(status: ChannelMessageStatus.failed),
      ChannelMessage(senderName: 'synthetic', text: 'unsent',
          timestamp: DateTime.utc(2026), isOutgoing: true),
    ]) {
      expect(channelNeedsRetransmissionWarning(invalid, hasCoverageShortfall: true), isFalse);
    }
    expect(channelNeedsRetransmissionWarning(_message([]), hasCoverageShortfall: false), isTrue);
  });
}
