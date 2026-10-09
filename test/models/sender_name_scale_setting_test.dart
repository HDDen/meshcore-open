import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/app_settings.dart';

// The size of sender names in channel and room bubbles: a percentage the
// bubbles multiply their sender-name font size by, kept with the settings,
// offered on a slider over fifteen sizes and snapped to one of them.

void main() {
  test('sender names are drawn at their own size by default', () {
    expect(AppSettings().senderNameScalePercent, 100);
    expect(AppSettings().senderNameScale, 1.0);
    expect(AppSettings.fromJson(const {}).senderNameScalePercent, 100);
  });

  test('the gap under the name grows a third more than the name above the '
      'default size, and just with the name at it and below', () {
    expect(AppSettings().senderNameGapScale, 1.0);
    expect(AppSettings(senderNameScalePercent: 200).senderNameGapScale, 2.6);
    expect(AppSettings(senderNameScalePercent: 50).senderNameGapScale, 0.5);
    expect(AppSettings(senderNameScalePercent: 25).senderNameGapScale, 0.25);
  });

  test('the size survives JSON persistence', () {
    final restored = AppSettings.fromJson(
      AppSettings(senderNameScalePercent: 250).toJson(),
    );

    expect(restored.senderNameScalePercent, 250);
    expect(restored.senderNameScale, 2.5);
  });

  test('a stored value is snapped to the nearest size the slider offers', () {
    int restored(int stored) => AppSettings.fromJson({
      'sender_name_scale_percent': stored,
    }).senderNameScalePercent;

    expect(restored(110), 100);
    expect(restored(115), 125);
    expect(restored(0), 25);
    expect(restored(999), 400);
    // Halfway between two sizes, the smaller one.
    expect(AppSettings.snapSenderNameScalePercent(75), 50);
  });

  test('the sizes offered run 25, 50, then 100 to 400 by 25', () {
    expect(AppSettings.senderNameScaleOptions, [
      25,
      50,
      for (var percent = 100; percent <= 400; percent += 25) percent,
    ]);
  });
}
