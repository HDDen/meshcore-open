import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/app_settings.dart';

void main() {
  test('legacy muted list retains its mentions-only meaning', () {
    final settings = AppSettings.fromJson({'muted_channels': ['Old']});
    expect(settings.channelNotificationModeFor('Old'), ChannelNotificationMode.mentionsOnly);
    expect(settings.channelNotificationModeFor('Other'), ChannelNotificationMode.all);
    expect(settings.silencedChannels, isEmpty);
  });

  test('both restrictions survive JSON round trip and unrelated copyWith', () {
    final settings = AppSettings(mutedChannels: {'Mentions'}, silencedChannels: {'Silent'});
    final restored = AppSettings.fromJson(settings.toJson()).copyWith(notificationsEnabled: false);
    expect(restored.mutedChannels, {'Mentions'});
    expect(restored.silencedChannels, {'Silent'});
    expect(restored.channelNotificationModeFor('Mentions'), ChannelNotificationMode.mentionsOnly);
    expect(restored.channelNotificationModeFor('Silent'), ChannelNotificationMode.muted);
    expect(restored.toJson()['muted_channels'], ['Mentions']);
  });

  test('full silence wins malformed overlapping legacy state', () {
    final settings = AppSettings(mutedChannels: {'Both'}, silencedChannels: {'Both'});
    expect(settings.channelNotificationModeFor('Both'), ChannelNotificationMode.muted);
  });
}
