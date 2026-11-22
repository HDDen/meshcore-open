import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/app_settings.dart';

void main() {
  const defaults = <String, Object>{
    'clear_path_on_max_retry': true,
    'enable_time_seconds': true,
    'notify_on_new_advert': false,
    'jump_to_oldest_unread': true,
    'hide_channel_mute_button': true,
    'hide_radio_stats_button': true,
    'show_message_region': true,
    'channels_unread_sorting': true,
    'show_compression_ratio': true,
    'monochrome_sender_names': false,
    'incoming_quote_as_mentions': true,
    'room_server_disable_room_and_contacts_sorting': false,
    'no_retransmission_warning_seconds': 12,
    'sending_delay_for_cancellation_seconds': 5,
  };

  void expectValues(AppSettings settings, Map<String, Object> expected) {
    final json = settings.toJson();
    for (final entry in expected.entries) {
      expect(json[entry.key], entry.value, reason: entry.key);
    }
  }

  test('fresh and missing settings use the same requested defaults', () {
    expectValues(AppSettings(), defaults);
    expectValues(AppSettings.fromJson({}), defaults);
    expectValues(AppSettings().copyWith(), defaults);
  });

  test('explicit saved values survive loading and serialization without migration', () {
    final saved = <String, Object>{
      for (final entry in defaults.entries)
        entry.key: entry.value is bool ? !(entry.value as bool) : 7,
    };
    final loaded = AppSettings.fromJson(saved);
    expectValues(loaded, saved);
    expectValues(loaded.copyWith(), saved);
    expectValues(AppSettings.fromJson(loaded.toJson()), saved);
  });

  test('zero and explicit cancellation delays remain unchanged', () {
    for (final seconds in [0, 1, 5, 7, 30, 300]) {
      expect(AppSettings.fromJson({
        'sending_delay_for_cancellation_seconds': seconds,
      }).sendingDelayForCancellationSeconds, seconds);
    }
  });

  test('disabled and explicit warning intervals keep their existing meaning', () {
    for (final seconds in [0, 5, 7, 12, 15]) {
      expect(AppSettings.fromJson({
        'no_retransmission_warning_seconds': seconds,
      }).noRetransmissionWarningSeconds, seconds);
    }
  });
}
