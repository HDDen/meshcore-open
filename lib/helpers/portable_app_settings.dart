import '../models/app_settings.dart';

/// Settings that can be moved between profiles. Device bindings, downloaded
/// files, consent state and credentials are kept out of the general selection.
class PortableAppSettings {
  const PortableAppSettings._(this.values);

  static const extension = 'mcoaAppSettings';
  static const shared = 'appSettings';
  static const ipfsKey = 'ipfsKey';
  static const stadiaKey = 'stadiaMapKey';

  static const _sharedKeys = {
    'active_theme_id',
    'app_debug_log_enabled',
    'auto_route_rotation_enabled',
    'auto_send_zero_hop_advert_on_gps_update',
    'auto_translate_incoming_messages',
    'channel_min_hops',
    'channel_min_hops_count_repeaters',
    'channel_min_hops_enabled',
    'channel_min_hops_retries',
    'clear_path_on_max_retry',
    'composer_translation_enabled',
    'custom_themes',
    'cyr2lat_profiles',
    'enable_message_tracing',
    'evict_discovered_contacts_enabled',
    'gps_interval_seconds',
    'holiday_animations_enabled',
    'holiday_auto_switch',
    'image_codec_enabled',
    'image_codec_rate_point',
    'image_messages_enabled',
    'image_process_automatically',
    'initial_route_weight',
    'jump_to_oldest_unread',
    'language_override',
    'load_link_images',
    'map_cache_bounds',
    'map_cache_max_zoom',
    'map_cache_min_zoom',
    'map_cluster_nodes',
    'map_key_prefix',
    'map_key_prefix_enabled',
    'map_raster_source_id',
    'map_show_chat_nodes',
    'map_show_discovery_contacts',
    'map_show_guessed_locations',
    'map_show_markers',
    'map_show_online_links',
    'map_show_other_nodes',
    'map_show_overlaps',
    'map_show_repeaters',
    'map_tile_endpoint_id',
    'map_time_filter_hours',
    'max_message_retries',
    'max_route_weight',
    'notifications_enabled',
    'notify_on_new_advert',
    'notify_on_new_channel_message',
    'notify_on_new_message',
    'public_ipfs_gateway',
    'region_on_hops_line',
    'route_weight_failure_decrement',
    'route_weight_success_increment',
    'selected_cyr2lat_profile_id',
    'show_link_images_by_default',
    'theme_mode',
    'translation_enabled',
    'translation_target_language_code',
    'unit_system',
    'upload_ipfs_endpoint',
    'upload_ipfs_gateway',
  };

  static const _forkKeys = {
    'adaptive_tx_power',
    'always_request_map_location',
    'automatic_direct_flood_retries',
    'background_tcp_enabled',
    'canvas_active',
    'canvas_show_lock_button',
    'channel_maxbytes_outgoing',
    'channel_min_hops_delay_seconds',
    'channel_min_hops_repeater_count',
    'channel_resend_timeout_seconds',
    'channels_send_as_binary',
    'channels_unread_sorting',
    'check_github_updates',
    'compression_ratio_with_sender_name',
    'copy_msg_path_final_template',
    'copy_msg_path_template',
    'direct_echo_recovery',
    'do_not_filter_messages_on_channels',
    'enable_time_seconds',
    'exact_quote',
    'exact_quote_latest',
    'exact_quote_limit',
    'experimental_route_ranking',
    'hide_channel_index_indicator',
    'hide_channel_mute_button',
    'hide_map_zoom_controls',
    'hide_radio_stats_button',
    'incoming_quote_as_mentions',
    'low_battery_alerts',
    'map_yandex_tile_scale',
    'mcmp_text_limit',
    'mco_image_replacements_lottie_scale_percent',
    'mco_image_replacements_scale',
    'mco_image_replacements_sharpness',
    'mco_image_scale_nearest_neighbor',
    'monochrome_sender_names',
    'no_retransmission_warning_seconds',
    'path_trace_high_timeout_enabled',
    'power_saving',
    'quick_actions',
    'quick_actions_in_channel_header',
    'quick_actions_in_contact_header',
    'quick_actions_in_main_header',
    'quick_answers',
    'recover_long_packet_echoes',
    'room_server_disable_room_and_contacts_sorting',
    'room_server_show_notempty_contacts_on_chatscreen',
    'room_server_show_notempty_on_chatscreen',
    'sender_name_scale_percent',
    'sending_delay_for_cancellation_seconds',
    'shared_message_history_mode',
    'show_channel_preview_sender',
    'show_compression_ratio',
    'show_hops',
    'show_keyboard_hiding_button',
    'show_last_hop_signal',
    'show_mco_image_algorithm',
    'show_mco_image_bytes',
    'show_mco_image_format',
    'show_mco_image_pack_replacements',
    'show_mco_image_resolution',
    'show_message_region',
    'simplified_mentions',
    'snr_indicator_all_rep_activity',
    'suppress_phantom_channels',
    'ui_scale',
    'ui_scale_apply_to_icons',
  };

  static const secretKeys = {
    ipfsKey: 'upload_ipfs_api_key',
    stadiaKey: 'map_tile_api_key',
  };

  final Map<String, Object?> values;

  static Set<String> _keysFor(String item) => switch (item) {
    shared => _sharedKeys,
    extension => _forkKeys,
    _ => {?secretKeys[item]},
  };

  factory PortableAppSettings.read(String item, Map<String, Object?> json) =>
      PortableAppSettings._(Map.unmodifiable({
        for (final key in _keysFor(item))
          if (json.containsKey(key)) key: json[key],
      }));

  factory PortableAppSettings.capture(String item, AppSettings settings) =>
      PortableAppSettings.read(item, {
        'active_theme_id': null,
        'custom_themes': const [],
        'holiday_auto_switch': false,
        'holiday_animations_enabled': false,
        ...settings.toJson(),
      });

  bool get isEmpty => values.isEmpty;

  AppSettings mergeInto(AppSettings settings) => AppSettings.fromJson({
    ...settings.toJson(),
    ...values,
  });
}
