import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/visible_channel_notification.dart';

void main() {
  for (final state in <AppLifecycleState?>[null, ...AppLifecycleState.values]) {
    test('channel alerts follow visibility in $state', () {
      expect(
        suppressVisibleChannelNotification(
          isVisible: false,
          lifecycleState: state,
        ),
        isFalse,
      );
      expect(
        suppressVisibleChannelNotification(
          isVisible: true,
          lifecycleState: state,
        ),
        state == null ||
            state == AppLifecycleState.resumed ||
            state == AppLifecycleState.inactive,
      );
    });
  }
}
