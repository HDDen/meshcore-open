import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/quick_action_header_lifecycle.dart';

void main() {
  test('Android and iOS keep visible inactive and split-screen headers polling', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final state in <AppLifecycleState?>[null, ...AppLifecycleState.values]) {
        expect(quickActionHeaderAllowsPolling(state, platform: platform),
            state == null || state == AppLifecycleState.resumed || state == AppLifecycleState.inactive,
            reason: '$platform / $state');
      }
    }
  });

  test('Windows Linux and macOS have no lifecycle pause policy for headers', () {
    for (final platform in [TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.macOS]) {
      for (final state in <AppLifecycleState?>[null, ...AppLifecycleState.values]) {
        expect(quickActionHeaderAllowsPolling(state, platform: platform), isTrue,
            reason: '$platform / $state');
      }
    }
  });

  test('web preserves its existing lifecycle policy', () {
    expect(quickActionHeaderAllowsPolling(AppLifecycleState.inactive,
        platform: TargetPlatform.windows, isWeb: true), isFalse);
    expect(quickActionHeaderAllowsPolling(AppLifecycleState.resumed,
        platform: TargetPlatform.windows, isWeb: true), isTrue);
  });
}
