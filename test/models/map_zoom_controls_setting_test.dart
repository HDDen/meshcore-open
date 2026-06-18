import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/app_settings.dart';

void main() {
  test('map zoom controls are visible by default', () {
    expect(AppSettings().hideMapZoomControls, isFalse);
    expect(AppSettings.fromJson(const {}).hideMapZoomControls, isFalse);
  });

  test('hide map zoom controls setting survives JSON persistence', () {
    final restored = AppSettings.fromJson(
      AppSettings(hideMapZoomControls: true).toJson(),
    );

    expect(restored.hideMapZoomControls, isTrue);
  });
}
