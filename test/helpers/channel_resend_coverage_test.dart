import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_resend_coverage.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/channel_message.dart';

ChannelMessage _echoed(
  List<List<int>> paths, {
  int width = 1,
  int? pathLength,
}) {
  final variants = [for (final p in paths) Uint8List.fromList(p)];
  return ChannelMessage(
    senderName: 'me',
    text: 'hello',
    timestamp: DateTime(2026, 10, 11),
    isOutgoing: true,
    pathHashWidth: width,
    pathLength:
        pathLength ??
        variants.fold<int>(
          0,
          (m, p) => p.length ~/ width > m ? p.length ~/ width : m,
        ),
    pathBytes: variants.isEmpty ? null : variants.first,
    pathVariants: variants,
  );
}

void main() {
  group('channelResendSatisfied', () {
    test('two distinct first-hop repeaters satisfy N=2 only when on', () {
      final message = _echoed([
        [0xAA],
        [0xBB],
      ]);
      expect(
        channelResendSatisfied(
          message,
          minHops: 2,
          countDistinctRepeaters: false,
        ),
        isFalse,
      );
      expect(
        channelResendSatisfied(
          message,
          minHops: 2,
          countDistinctRepeaters: true,
        ),
        isTrue,
      );
    });

    test('the same repeater heard twice does not count twice', () {
      final message = _echoed([
        [0xAA],
        [0xAA],
      ]);
      expect(distinctFirstHopRepeaters(message), {'aa'});
      expect(
        channelResendSatisfied(
          message,
          minHops: 2,
          countDistinctRepeaters: true,
        ),
        isFalse,
      );
    });

    test('consecutive hops still satisfy with the toggle off', () {
      final message = _echoed([
        [0xAA, 0xCC],
      ]);
      expect(
        channelResendSatisfied(
          message,
          minHops: 2,
          countDistinctRepeaters: false,
        ),
        isTrue,
      );
    });

    test('a long enough route satisfies even with only one first-hop repeater', () {
      final message = _echoed([
        [0xAA, 0xBB, 0xCC],
      ]);
      expect(distinctFirstHopRepeaters(message), {'aa'});
      expect(
        channelResendSatisfied(
          message,
          minHops: 3,
          countDistinctRepeaters: true,
        ),
        isTrue,
      );
    });

    test('different later hops do not increase the nearby repeater count', () {
      final message = _echoed([
        [0xAA, 0xBB],
        [0xAA, 0xCC],
      ]);
      expect(distinctFirstHopRepeaters(message), {'aa'});
      expect(
        channelResendSatisfied(
          message,
          minHops: 3,
          countDistinctRepeaters: true,
        ),
        isFalse,
      );
    });

    test('first hop uses the path hash width', () {
      // Same first byte, different 2-byte hashes: two distinct repeaters.
      final message = _echoed([
        [0xAA, 0x01],
        [0xAA, 0x02],
      ], width: 2);
      expect(distinctFirstHopRepeaters(message), {'aa01', 'aa02'});
    });

    test('our own key prefix and zero-hop echoes are ignored', () {
      final self = Uint8List.fromList(List.filled(32, 0x11));
      final message = _echoed([
        [0x11],
        [0xAA],
        [],
      ], pathLength: 1);
      expect(distinctFirstHopRepeaters(message, selfPublicKey: self), {'aa'});
      expect(
        channelResendSatisfied(
          message,
          minHops: 2,
          countDistinctRepeaters: true,
          selfPublicKey: self,
        ),
        isFalse,
      );
    });

    test('three-byte first hops stay distinct and exclude our complete prefix', () {
      final self = Uint8List.fromList([
        0xAA, 0x01, 0x01, ...List<int>.filled(29, 0),
      ]);
      final message = _echoed([
        [0xAA, 0x01, 0x01],
        [0xAA, 0x01, 0x02],
        [0xAA, 0x01, 0x03],
        [0xAA, 0x01, 0x02],
        [],
      ], width: 3);
      expect(
        distinctFirstHopRepeaters(message, selfPublicKey: self),
        {'aa0102', 'aa0103'},
      );
      expect(
        channelResendSatisfied(
          message,
          minHops: 2,
          countDistinctRepeaters: true,
          selfPublicKey: self,
        ),
        isTrue,
      );
    });

    test('an unechoed message is not satisfied', () {
      final message = _echoed([]);
      expect(
        channelResendSatisfied(
          message,
          minHops: 1,
          countDistinctRepeaters: true,
        ),
        isFalse,
      );
    });

    test('nearby repeaters use their own target with a higher hop target', () {
      final message = _echoed([
        [0xAA],
        [0xBB],
      ]);
      expect(
        channelResendSatisfied(
          message,
          minHops: 8,
          countDistinctRepeaters: true,
          minRepeaters: 2,
        ),
        isTrue,
      );
      expect(
        channelResendSatisfied(
          message,
          minHops: 8,
          countDistinctRepeaters: false,
          minRepeaters: 2,
        ),
        isFalse,
      );
    });

    test('meeting the hop number with nearby repeaters alone is insufficient', () {
      final message = _echoed([
        [0xAA],
        [0xBB],
        [0xCC],
      ]);
      expect(
        channelResendSatisfied(
          message,
          minHops: 3,
          countDistinctRepeaters: true,
          minRepeaters: 5,
        ),
        isFalse,
      );
      expect(
        channelResendSatisfied(
          _echoed([
            [0xAA, 0xBB, 0xCC],
          ]),
          minHops: 3,
          countDistinctRepeaters: true,
          minRepeaters: 5,
        ),
        isTrue,
      );
    });

    test('ten nearby repeaters require all ten distinct first hops', () {
      for (final count in [9, 10]) {
        expect(
          channelResendSatisfied(
            _echoed(List.generate(count, (i) => [i + 1])),
            minHops: 8,
            countDistinctRepeaters: true,
            minRepeaters: 10,
          ),
          count == 10,
        );
      }
    });
  });

  group('channelMinHopsCountRepeaters setting', () {
    test('defaults off, including for old saved settings', () {
      expect(AppSettings().channelMinHopsCountRepeaters, isFalse);
      expect(AppSettings.fromJson({}).channelMinHopsCountRepeaters, isFalse);
    });

    test('round-trips through JSON and copyWith', () {
      final on = AppSettings().copyWith(channelMinHopsCountRepeaters: true);
      expect(on.channelMinHopsCountRepeaters, isTrue);
      expect(
        AppSettings.fromJson(on.toJson()).channelMinHopsCountRepeaters,
        isTrue,
      );
    });

    test('saved resend controls survive changing the hop target', () {
      final saved = AppSettings(
        channelMinHopsEnabled: true,
        channelMinHops: 7,
        channelMinHopsRetries: 3,
        channelMinHopsDelaySeconds: 60,
        channelMinHopsCountRepeaters: true,
      );
      final restored = AppSettings.fromJson(saved.toJson());
      expect(restored.channelMinHops, 7);
      final changed = AppSettings.fromJson(
        restored.copyWith(channelMinHops: 4).toJson(),
      );
      expect(changed.channelMinHops, 4);
      expect(changed.channelMinHopsEnabled, isTrue);
      expect(changed.channelMinHopsRetries, 3);
      expect(changed.channelMinHopsDelaySeconds, 60);
      expect(changed.channelMinHopsCountRepeaters, isTrue);
    });
  });

  group('independent nearby-repeater target', () {
    test('defaults to two for new settings and empty legacy JSON', () {
      expect(AppSettings().channelMinHopsRepeaterCount, 2);
      expect(AppSettings.fromJson({}).channelMinHopsRepeaterCount, 2);
    });

    test('legacy JSON inherits its hop target within the new range', () {
      for (final (oldTarget, expected) in [(1, 2), (7, 7), (20, 10)]) {
        final restored = AppSettings.fromJson({
          'channel_min_hops': oldTarget,
          'channel_min_hops_count_repeaters': true,
        });
        expect(restored.channelMinHopsRepeaterCount, expected);
        expect(restored.channelMinHops, oldTarget);
        expect(
          AppSettings.fromJson(
            restored.copyWith(channelMinHops: 4).toJson(),
          ).channelMinHopsRepeaterCount,
          expected,
        );
      }
    });

    test('explicit targets round-trip independently through copyWith and JSON', () {
      final original = AppSettings(
        channelMinHops: 3,
        channelMinHopsRepeaterCount: 9,
        channelMinHopsCountRepeaters: true,
      );
      final restored = AppSettings.fromJson(original.toJson());
      expect(restored.channelMinHops, 3);
      expect(restored.channelMinHopsRepeaterCount, 9);
      final changed = restored.copyWith(
        channelMinHopsRepeaterCount: 5,
        channelMinHopsCountRepeaters: false,
      );
      expect(changed.channelMinHops, 3);
      expect(changed.channelMinHopsRepeaterCount, 5);
      expect(
        AppSettings.fromJson(changed.toJson())
            .copyWith(channelMinHopsCountRepeaters: true)
            .channelMinHopsRepeaterCount,
        5,
      );
    });

    test('imported explicit repeater targets are clamped without changing hops', () {
      for (final (input, expected) in [(0, 2), (2, 2), (10, 10), (99, 10)]) {
        final restored = AppSettings.fromJson({
          'channel_min_hops': 3,
          'channel_min_hops_repeater_count': input,
        });
        expect(restored.channelMinHopsRepeaterCount, expected);
        expect(restored.channelMinHops, 3);
      }
    });
  });
}
