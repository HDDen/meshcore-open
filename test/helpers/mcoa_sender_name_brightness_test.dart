import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/mcoa_sender_name_brightness.dart';
import 'package:meshcore_open/helpers/mcoa_theme_options.dart';

void main() {
  test('neutral is exact and brightness changes lightness without changing hue or alpha', () {
    final original = const HSLColor.fromAHSL(0.5, 210, 0.6, 0.4).toColor();
    expect(adjustSenderNameBrightness(original, 0), same(original));
    final darker = adjustSenderNameBrightness(original, -50);
    final lighter = adjustSenderNameBrightness(original, 50);
    expect(darker.computeLuminance(), lessThan(original.computeLuminance()));
    expect(lighter.computeLuminance(), greaterThan(original.computeLuminance()));
    for (final adjusted in [darker, lighter]) {
      final hsl = HSLColor.fromColor(adjusted);
      final before = HSLColor.fromColor(original);
      expect(hsl.hue, closeTo(before.hue, 1.5));
      expect(hsl.saturation, closeTo(before.saturation, 0.02));
      expect(adjusted.a, original.a);
    }
  });

  test('brightness survives storage; explicit sender color resets it permanently', () {
    const original = McoaThemeOptions(incomingSenderNameBrightness: 60);
    expect(original.isEmpty, isFalse);
    expect(McoaThemeOptions.fromJson(original.toJson()), original);
    expect(const McoaThemeOptions().incomingSenderNameBrightness, 0);
    final fixed = original.copyWith(colors: {'incoming_sender_name': const Color(0xFFAA55BB)});
    expect(fixed.incomingSenderNameBrightness, 0);
    expect(fixed.toJson(), isNot(contains('incoming_sender_name_brightness')));
    final cleared = fixed.copyWith(colors: {});
    expect(cleared.incomingSenderNameBrightness, 0);
    expect(cleared.isEmpty, isTrue);
    expect(McoaThemeOptions.fromJson({
      'version': 1,
      'incoming_sender_name_brightness': 500,
    }).incomingSenderNameBrightness, 0);
  });
}
