import 'package:flutter/foundation.dart';

/// Stable, untranslated anchors shared by settings screens and entry points.
enum SettingsNavigationTarget {
  adaptiveTxPower,
  channelMinHops,
  companionProxy;

  ValueKey<String> get key => ValueKey('settings-target-$name');
}
