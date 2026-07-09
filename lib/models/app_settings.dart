import 'translation_support.dart';
import '../helpers/cyr2lat.dart';

enum UnitSystem { metric, imperial }

enum SharedMessageHistoryMode { disabled, channels, contacts, all }

extension UnitSystemValue on UnitSystem {
  String get value {
    switch (this) {
      case UnitSystem.imperial:
        return 'imperial';
      case UnitSystem.metric:
        return 'metric';
    }
  }
}

extension SharedMessageHistoryModeValue on SharedMessageHistoryMode {
  String get value {
    switch (this) {
      case SharedMessageHistoryMode.channels:
        return 'channels';
      case SharedMessageHistoryMode.contacts:
        return 'contacts';
      case SharedMessageHistoryMode.all:
        return 'all';
      case SharedMessageHistoryMode.disabled:
        return 'disabled';
    }
  }

  bool get includesChannels =>
      this == SharedMessageHistoryMode.channels ||
      this == SharedMessageHistoryMode.all;

  bool get includesContacts =>
      this == SharedMessageHistoryMode.contacts ||
      this == SharedMessageHistoryMode.all;
}

class Cyr2LatProfile {
  final String id;
  final String name;
  final Map<String, String> charMap;

  Cyr2LatProfile({required this.id, required this.name, required this.charMap});

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'char_map': charMap};
  }

  factory Cyr2LatProfile.fromJson(Map<String, dynamic> json) {
    return Cyr2LatProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      charMap:
          (json['char_map'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ) ??
          {},
    );
  }

  Cyr2LatProfile copyWith({
    String? id,
    String? name,
    Map<String, String>? charMap,
  }) {
    return Cyr2LatProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      charMap: charMap ?? this.charMap,
    );
  }
}

class TcpConnectionBookmark {
  final String host;
  final int port;
  final DateTime lastConnectedAt;
  final String name;
  final bool isFavorite;

  TcpConnectionBookmark({
    required this.host,
    required this.port,
    required this.lastConnectedAt,
    this.name = '',
    this.isFavorite = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'last_connected_at': lastConnectedAt.toIso8601String(),
      'name': name,
      'is_favorite': isFavorite,
    };
  }

  factory TcpConnectionBookmark.fromJson(Map<String, dynamic> json) {
    return TcpConnectionBookmark(
      host: json['host'] as String? ?? '',
      port: json['port'] as int? ?? 0,
      lastConnectedAt:
          DateTime.tryParse(json['last_connected_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      name: json['name'] as String? ?? '',
      isFavorite: json['is_favorite'] as bool? ?? false,
    );
  }

  TcpConnectionBookmark copyWith({
    String? host,
    int? port,
    DateTime? lastConnectedAt,
    String? name,
    bool? isFavorite,
  }) {
    return TcpConnectionBookmark(
      host: host ?? this.host,
      port: port ?? this.port,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      name: name ?? this.name,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}

class QuickAnswer {
  final String id;
  final String text;
  final bool sendAtSelect;

  const QuickAnswer({
    required this.id,
    required this.text,
    this.sendAtSelect = false,
  });

  Map<String, dynamic> toJson() {
    return {'id': id, 'text': text, 'sendAtSelect': sendAtSelect};
  }

  factory QuickAnswer.fromJson(Map<String, dynamic> json) {
    return QuickAnswer(
      id: json['id']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      sendAtSelect: json['sendAtSelect'] == true,
    );
  }

  QuickAnswer copyWith({String? id, String? text, bool? sendAtSelect}) {
    return QuickAnswer(
      id: id ?? this.id,
      text: text ?? this.text,
      sendAtSelect: sendAtSelect ?? this.sendAtSelect,
    );
  }
}

class AppSettings {
  static const Object _unset = Object();
  static const List<String> _standardCyr2LatProfileIds = [
    'default',
    'cyrillic_extended',
    'cyrillic_transliteration',
  ];

  final bool clearPathOnMaxRetry;
  final bool mapShowRepeaters;
  final bool mapShowChatNodes;
  final bool mapShowOtherNodes;
  final bool pathTraceHighTimeoutEnabled;
  final bool mapShowOverlaps;
  final double mapTimeFilterHours; // 0 = all time
  final bool mapKeyPrefixEnabled;
  final String mapKeyPrefix;
  final bool mapShowMarkers;
  final bool mapShowGuessedLocations;
  final bool enableMessageTracing;
  final bool enableTimeSeconds;
  final bool showKeyboardHidingButton;
  final bool canvasActive;
  final bool canvasShowLockButton;
  final bool showHops;
  final bool hideChannelIndexIndicator;
  final bool hideRadioStatsButton;
  final bool hideMapZoomControls;
  final bool showMcoImageResolution;
  final bool showMcoImageFormat;
  final bool showMcoImageAlgorithm;
  final bool showMcoImageBytes;
  final bool showMcoImagePackReplacements;

  /// Global UI scale multiplier applied on top of the system text scale
  /// (affects fonts, and icons when [uiScaleApplyToIcons] is enabled).
  final double uiScale;

  /// When true, the [uiScale] multiplier also scales icons (via
  /// IconThemeData.applyTextScaling), not only text.
  final bool uiScaleApplyToIcons;
  final bool showCompressionRatio;
  final bool compressionRatioWithSenderName;
  final bool showMessageRegion;
  final bool channelsUnreadSorting;
  final bool incomingQuoteAsMentions;
  final bool simplifiedMentions;
  final SharedMessageHistoryMode sharedMessageHistoryMode;
  final int noRetransmissionWarningSeconds;
  final bool backgroundTcpEnabled;
  final Map<String, double>? mapCacheBounds;
  final int mapCacheMinZoom;
  final int mapCacheMaxZoom;
  final bool notificationsEnabled;
  final bool notifyOnNewMessage;
  final bool notifyOnNewChannelMessage;
  final bool notifyOnNewAdvert;
  final bool autoRouteRotationEnabled;
  final double maxRouteWeight;
  final double initialRouteWeight;
  final double routeWeightSuccessIncrement;
  final double routeWeightFailureDecrement;
  final int maxMessageRetries;
  final int channelResendTimeoutSeconds;
  final String themeMode;
  final String? languageOverride; // null = system default
  final bool appDebugLogEnabled;
  final Map<String, String> batteryChemistryByDeviceId;
  final Map<String, String> batteryChemistryByRepeaterId;
  final UnitSystem unitSystem;
  final Set<String> mutedChannels;
  final bool mapShowDiscoveryContacts;
  final String tcpServerAddress;
  final int tcpServerPort;
  final List<TcpConnectionBookmark> tcpConnectionBookmarks;
  final bool jumpToOldestUnread;
  final bool translationEnabled;
  final bool autoTranslateIncomingMessages;
  final String? translationTargetLanguageCode;
  final bool composerTranslationEnabled;
  final String? translationModelSourceUrl;
  final String? translationSelectedModelId;
  final List<TranslationModelRecord> translationDownloadedModels;
  final int mcmpTextLimit;
  final int channelMaxbytesOutgoing;
  final List<QuickAnswer> quickAnswers;
  final String copyMsgPathTemplate;
  final String copyMsgPathFinalTemplate;
  final bool channelsSendAsBinary;
  final String doNotFilterMessagesOnChannels;
  final List<Cyr2LatProfile> cyr2latProfiles;
  final String selectedCyr2latProfileId;
  static const int defaultMcmpTextLimit = 600;
  static const int maxMcmpTextLimit = 10000;
  static const int maxChannelMaxbytesOutgoing = 1000;
  static const String defaultCopyMsgPathTemplate =
      r'%collisionMarker%%hopKey%: %hopName%%div%';
  static const String defaultCopyMsgPathFinalTemplate =
      r'@%senderName% - %hops% hops: %path%';
  static const int minChannelResendTimeoutSeconds = 10;
  static const int defaultChannelResendTimeoutSeconds = 30;
  static const int maxChannelResendTimeoutSeconds = 30;
  static const int defaultNoRetransmissionWarningSeconds = 7;
  static const int minNoRetransmissionWarningSeconds = 5;
  static const int maxNoRetransmissionWarningSeconds = 15;
  final int sendingDelayForCancellationSeconds;
  static const int maxSendingDelayForCancellationSeconds = 300;
  static const String defaultDoNotFilterMessagesOnChannels =
      'TerminalCLI\nSomethingElse';

  static List<Cyr2LatProfile> get standardCyr2LatProfiles => [
    Cyr2LatProfile(
      id: 'default',
      name: 'Cyrillic standard',
      charMap: Cyr2Lat.defaultCharMap,
    ),
    Cyr2LatProfile(
      id: 'cyrillic_extended',
      name: 'Cyrillic extended',
      charMap: Cyr2Lat.extendedCharMap,
    ),
    Cyr2LatProfile(
      id: 'cyrillic_transliteration',
      name: 'Cyrillic transliteration',
      charMap: Cyr2Lat.transliterationCharMap,
    ),
  ];

  static List<Cyr2LatProfile> _withStandardCyr2LatProfiles(
    List<Cyr2LatProfile>? profiles,
  ) {
    final merged = <Cyr2LatProfile>[
      for (final profile in profiles ?? const <Cyr2LatProfile>[]) profile,
    ];
    for (final standard in standardCyr2LatProfiles) {
      final index = merged.indexWhere((profile) => profile.id == standard.id);
      if (index >= 0) {
        merged[index] = standard;
      } else {
        merged.add(standard);
      }
    }
    merged.sort((a, b) {
      final aIndex = _standardCyr2LatProfileIds.indexOf(a.id);
      final bIndex = _standardCyr2LatProfileIds.indexOf(b.id);
      if (aIndex >= 0 && bIndex >= 0) return aIndex.compareTo(bIndex);
      if (aIndex >= 0) return -1;
      if (bIndex >= 0) return 1;
      return 0;
    });
    return merged;
  }

  static int normalizeMcmpTextLimit(dynamic value) {
    int? parsed;
    if (value is int) {
      parsed = value;
    } else if (value is num) {
      parsed = value.toInt();
    } else if (value is String) {
      parsed = int.tryParse(value);
    }
    return (parsed ?? defaultMcmpTextLimit).clamp(1, maxMcmpTextLimit).toInt();
  }

  static int normalizeChannelMaxbytesOutgoing(dynamic value) {
    int? parsed;
    if (value is int) {
      parsed = value;
    } else if (value is num) {
      parsed = value.toInt();
    } else if (value is String) {
      parsed = int.tryParse(value);
    }
    return (parsed ?? 0).clamp(0, maxChannelMaxbytesOutgoing).toInt();
  }

  static List<QuickAnswer> normalizeQuickAnswers(dynamic value) {
    if (value is! List) return const [];
    final usedIds = <String>{};
    final answers = <QuickAnswer>[];
    for (var index = 0; index < value.length; index++) {
      final answer = _quickAnswerFrom(value[index], index);
      if (answer.text.trim().isEmpty) continue;
      final id = answer.id.trim().isEmpty
          ? _legacyQuickAnswerId(answer.text, index)
          : answer.id;
      if (!usedIds.add(id)) continue;
      // Preserve meaningful trailing spaces for command templates.
      answers.add(answer.copyWith(id: id));
    }
    return List.unmodifiable(answers);
  }

  static QuickAnswer _quickAnswerFrom(dynamic entry, int index) {
    if (entry is QuickAnswer) return entry;
    if (entry is Map) {
      return QuickAnswer.fromJson(Map<String, dynamic>.from(entry));
    }
    final text = entry?.toString() ?? '';
    // Local dev builds stored plain strings before quick answers received
    // stable ids. Keep this tolerant without writing a migration.
    return QuickAnswer(id: _legacyQuickAnswerId(text, index), text: text);
  }

  static List<String> normalizeQuickAnswerIds(dynamic value) {
    if (value is! List) return const [];
    final usedIds = <String>{};
    final ids = <String>[];
    for (final entry in value) {
      final id = entry?.toString() ?? '';
      if (id.trim().isEmpty || !usedIds.add(id)) continue;
      ids.add(id);
    }
    return List.unmodifiable(ids);
  }

  static String normalizeCopyMsgPathTemplate(dynamic value) {
    if (value is! String || value.isEmpty) {
      return defaultCopyMsgPathTemplate;
    }
    return value;
  }

  static String normalizeCopyMsgPathFinalTemplate(dynamic value) {
    if (value is! String || value.isEmpty) {
      return defaultCopyMsgPathFinalTemplate;
    }
    return value;
  }

  static String _legacyQuickAnswerId(String text, int index) {
    var hash = 0x811c9dc5;
    for (final codeUnit in text.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return 'qa_${index}_${hash.toRadixString(16).padLeft(8, '0')}';
  }

  static int normalizeSendingDelayForCancellation(dynamic value) {
    int? parsed;
    if (value is int) {
      parsed = value;
    } else if (value is num) {
      parsed = value.toInt();
    } else if (value is String) {
      parsed = int.tryParse(value);
    }
    return (parsed ?? 0)
        .clamp(0, maxSendingDelayForCancellationSeconds)
        .toInt();
  }

  static int normalizeChannelResendTimeoutSeconds(dynamic value) {
    int? parsed;
    if (value is int) {
      parsed = value;
    } else if (value is num) {
      parsed = value.toInt();
    } else if (value is String) {
      parsed = int.tryParse(value);
    }
    return (parsed ?? defaultChannelResendTimeoutSeconds)
        .clamp(minChannelResendTimeoutSeconds, maxChannelResendTimeoutSeconds)
        .toInt();
  }

  static int normalizeNoRetransmissionWarningSeconds(dynamic value) {
    int? parsed;
    if (value is int) {
      parsed = value;
    } else if (value is num) {
      parsed = value.toInt();
    } else if (value is String) {
      parsed = int.tryParse(value);
    }
    if (parsed == null) return defaultNoRetransmissionWarningSeconds;
    if (parsed <= 0) return 0;
    return parsed
        .clamp(
          minNoRetransmissionWarningSeconds,
          maxNoRetransmissionWarningSeconds,
        )
        .toInt();
  }

  Map<String, String> get cyr2latCharMap {
    final profile = cyr2latProfiles.firstWhere(
      (p) => p.id == selectedCyr2latProfileId,
      orElse: () => cyr2latProfiles.first,
    );
    return profile.charMap;
  }

  AppSettings({
    this.clearPathOnMaxRetry = false,
    this.mapShowRepeaters = true,
    this.mapShowChatNodes = true,
    this.mapShowOtherNodes = true,
    this.pathTraceHighTimeoutEnabled = false,
    this.mapShowOverlaps = false,
    this.mapTimeFilterHours = 0, // Default to all time
    this.mapKeyPrefixEnabled = false,
    this.mapKeyPrefix = '',
    this.mapShowMarkers = true,
    this.mapShowGuessedLocations = true,
    this.enableMessageTracing = true,
    this.enableTimeSeconds = false,
    this.showKeyboardHidingButton = true,
    this.canvasActive = true,
    this.canvasShowLockButton = true,
    this.showHops = true,
    this.hideChannelIndexIndicator = false,
    this.hideRadioStatsButton = false,
    this.hideMapZoomControls = false,
    this.showMcoImageResolution = false,
    this.showMcoImageFormat = true,
    this.showMcoImageAlgorithm = true,
    this.showMcoImageBytes = true,
    this.showMcoImagePackReplacements = true,
    this.uiScale = 1.0,
    this.uiScaleApplyToIcons = true,
    this.showCompressionRatio = false,
    this.compressionRatioWithSenderName = false,
    this.showMessageRegion = false,
    this.channelsUnreadSorting = false,
    this.incomingQuoteAsMentions = false,
    this.simplifiedMentions = false,
    this.sharedMessageHistoryMode = SharedMessageHistoryMode.disabled,
    int? noRetransmissionWarningSeconds,
    this.backgroundTcpEnabled = false,
    this.mapCacheBounds,
    this.mapCacheMinZoom = 10,
    this.mapCacheMaxZoom = 15,
    this.notificationsEnabled = true,
    this.notifyOnNewMessage = true,
    this.notifyOnNewChannelMessage = true,
    this.notifyOnNewAdvert = true,
    this.autoRouteRotationEnabled = true,
    this.maxRouteWeight = 5.0,
    this.initialRouteWeight = 3.0,
    this.routeWeightSuccessIncrement = 0.5,
    this.routeWeightFailureDecrement = 0.2,
    this.maxMessageRetries = 5,
    int? channelResendTimeoutSeconds,
    this.themeMode = 'system',
    this.languageOverride,
    this.appDebugLogEnabled = false,
    Map<String, String>? batteryChemistryByDeviceId,
    Map<String, String>? batteryChemistryByRepeaterId,
    this.unitSystem = UnitSystem.metric,
    Set<String>? mutedChannels,
    this.mapShowDiscoveryContacts = true,
    this.tcpServerAddress = '',
    this.tcpServerPort = 0,
    List<TcpConnectionBookmark>? tcpConnectionBookmarks,
    this.jumpToOldestUnread = false,
    this.translationEnabled = false,
    this.autoTranslateIncomingMessages = true,
    this.translationTargetLanguageCode,
    this.composerTranslationEnabled = false,
    this.translationModelSourceUrl,
    this.translationSelectedModelId,
    List<TranslationModelRecord>? translationDownloadedModels,
    int? mcmpTextLimit,
    int? channelMaxbytesOutgoing,
    List<QuickAnswer>? quickAnswers,
    String? copyMsgPathTemplate,
    String? copyMsgPathFinalTemplate,
    this.channelsSendAsBinary = true,
    int? sendingDelayForCancellationSeconds,
    this.doNotFilterMessagesOnChannels = defaultDoNotFilterMessagesOnChannels,
    List<Cyr2LatProfile>? cyr2latProfiles,
    String? selectedCyr2latProfileId,
  }) : batteryChemistryByDeviceId = batteryChemistryByDeviceId ?? {},
       batteryChemistryByRepeaterId = batteryChemistryByRepeaterId ?? {},
       mutedChannels = mutedChannels ?? {},
       tcpConnectionBookmarks = tcpConnectionBookmarks ?? const [],
       translationDownloadedModels = translationDownloadedModels ?? const [],
       channelResendTimeoutSeconds = normalizeChannelResendTimeoutSeconds(
         channelResendTimeoutSeconds,
       ),
       mcmpTextLimit = normalizeMcmpTextLimit(mcmpTextLimit),
       channelMaxbytesOutgoing = normalizeChannelMaxbytesOutgoing(
         channelMaxbytesOutgoing,
       ),
       quickAnswers = normalizeQuickAnswers(quickAnswers),
       copyMsgPathTemplate = normalizeCopyMsgPathTemplate(copyMsgPathTemplate),
       copyMsgPathFinalTemplate = normalizeCopyMsgPathFinalTemplate(
         copyMsgPathFinalTemplate,
       ),
       noRetransmissionWarningSeconds = normalizeNoRetransmissionWarningSeconds(
         noRetransmissionWarningSeconds,
       ),
       sendingDelayForCancellationSeconds =
           normalizeSendingDelayForCancellation(
             sendingDelayForCancellationSeconds,
           ),
       cyr2latProfiles = _withStandardCyr2LatProfiles(cyr2latProfiles),
       selectedCyr2latProfileId = selectedCyr2latProfileId ?? 'default';

  Map<String, dynamic> toJson() {
    return {
      'clear_path_on_max_retry': clearPathOnMaxRetry,
      'map_show_repeaters': mapShowRepeaters,
      'map_show_chat_nodes': mapShowChatNodes,
      'map_show_other_nodes': mapShowOtherNodes,
      'path_trace_high_timeout_enabled': pathTraceHighTimeoutEnabled,
      'map_show_overlaps': mapShowOverlaps,
      'map_time_filter_hours': mapTimeFilterHours,
      'map_key_prefix_enabled': mapKeyPrefixEnabled,
      'map_key_prefix': mapKeyPrefix,
      'map_show_markers': mapShowMarkers,
      'map_show_guessed_locations': mapShowGuessedLocations,
      'enable_message_tracing': enableMessageTracing,
      'enable_time_seconds': enableTimeSeconds,
      'show_keyboard_hiding_button': showKeyboardHidingButton,
      'canvas_active': canvasActive,
      'canvas_show_lock_button': canvasShowLockButton,
      'show_hops': showHops,
      'hide_channel_index_indicator': hideChannelIndexIndicator,
      'hide_radio_stats_button': hideRadioStatsButton,
      'hide_map_zoom_controls': hideMapZoomControls,
      'show_mco_image_resolution': showMcoImageResolution,
      'show_mco_image_format': showMcoImageFormat,
      'show_mco_image_algorithm': showMcoImageAlgorithm,
      'show_mco_image_bytes': showMcoImageBytes,
      'show_mco_image_pack_replacements': showMcoImagePackReplacements,
      'ui_scale': uiScale,
      'ui_scale_apply_to_icons': uiScaleApplyToIcons,
      'show_compression_ratio': showCompressionRatio,
      'compression_ratio_with_sender_name': compressionRatioWithSenderName,
      'show_message_region': showMessageRegion,
      'channels_unread_sorting': channelsUnreadSorting,
      'incoming_quote_as_mentions': incomingQuoteAsMentions,
      'simplified_mentions': simplifiedMentions,
      'shared_message_history_mode': sharedMessageHistoryMode.value,
      'no_retransmission_warning_seconds': noRetransmissionWarningSeconds,
      'background_tcp_enabled': backgroundTcpEnabled,
      'map_cache_bounds': mapCacheBounds,
      'map_cache_min_zoom': mapCacheMinZoom,
      'map_cache_max_zoom': mapCacheMaxZoom,
      'notifications_enabled': notificationsEnabled,
      'notify_on_new_message': notifyOnNewMessage,
      'notify_on_new_channel_message': notifyOnNewChannelMessage,
      'notify_on_new_advert': notifyOnNewAdvert,
      'auto_route_rotation_enabled': autoRouteRotationEnabled,
      'max_route_weight': maxRouteWeight,
      'initial_route_weight': initialRouteWeight,
      'route_weight_success_increment': routeWeightSuccessIncrement,
      'route_weight_failure_decrement': routeWeightFailureDecrement,
      'max_message_retries': maxMessageRetries,
      'channel_resend_timeout_seconds': channelResendTimeoutSeconds,
      'theme_mode': themeMode,
      'language_override': languageOverride,
      'app_debug_log_enabled': appDebugLogEnabled,
      'battery_chemistry_by_device_id': batteryChemistryByDeviceId,
      'battery_chemistry_by_repeater_id': batteryChemistryByRepeaterId,
      'unit_system': unitSystem.value,
      'muted_channels': mutedChannels.toList(),
      'map_show_discovery_contacts': mapShowDiscoveryContacts,
      'tcp_server_address': tcpServerAddress,
      'tcp_server_port': tcpServerPort,
      'tcp_connection_bookmarks': tcpConnectionBookmarks
          .map((bookmark) => bookmark.toJson())
          .toList(),
      'jump_to_oldest_unread': jumpToOldestUnread,
      'translation_enabled': translationEnabled,
      'auto_translate_incoming_messages': autoTranslateIncomingMessages,
      'translation_target_language_code': translationTargetLanguageCode,
      'composer_translation_enabled': composerTranslationEnabled,
      'translation_model_source_url': translationModelSourceUrl,
      'translation_selected_model_id': translationSelectedModelId,
      'translation_downloaded_models': translationDownloadedModels
          .map((model) => model.toJson())
          .toList(),
      'mcmp_text_limit': mcmpTextLimit,
      'channel_maxbytes_outgoing': channelMaxbytesOutgoing,
      'quick_answers': quickAnswers.map((answer) => answer.toJson()).toList(),
      'copy_msg_path_template': copyMsgPathTemplate,
      'copy_msg_path_final_template': copyMsgPathFinalTemplate,
      'channels_send_as_binary': channelsSendAsBinary,
      'sending_delay_for_cancellation_seconds':
          sendingDelayForCancellationSeconds,
      'do_not_filter_messages_on_channels': doNotFilterMessagesOnChannels,
      'cyr2lat_profiles': cyr2latProfiles
          .map((profile) => profile.toJson())
          .toList(),
      'selected_cyr2lat_profile_id': selectedCyr2latProfileId,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    UnitSystem parseUnitSystem(dynamic value) {
      if (value is String && value.toLowerCase() == 'imperial') {
        return UnitSystem.imperial;
      }
      return UnitSystem.metric;
    }

    SharedMessageHistoryMode parseSharedMessageHistoryMode(dynamic value) {
      if (value is String) {
        switch (value.toLowerCase()) {
          case 'channels':
            return SharedMessageHistoryMode.channels;
          case 'contacts':
            return SharedMessageHistoryMode.contacts;
          case 'all':
            return SharedMessageHistoryMode.all;
        }
      }
      return SharedMessageHistoryMode.disabled;
    }

    return AppSettings(
      clearPathOnMaxRetry: json['clear_path_on_max_retry'] as bool? ?? false,
      mapShowRepeaters: json['map_show_repeaters'] as bool? ?? true,
      mapShowChatNodes: json['map_show_chat_nodes'] as bool? ?? true,
      mapShowOtherNodes: json['map_show_other_nodes'] as bool? ?? true,
      pathTraceHighTimeoutEnabled:
          json['path_trace_high_timeout_enabled'] as bool? ?? false,
      mapShowOverlaps: json['map_show_overlaps'] as bool? ?? false,
      mapTimeFilterHours:
          (json['map_time_filter_hours'] as num?)?.toDouble() ?? 0,
      mapKeyPrefixEnabled: json['map_key_prefix_enabled'] as bool? ?? false,
      mapKeyPrefix: json['map_key_prefix'] as String? ?? '',
      mapShowMarkers: json['map_show_markers'] as bool? ?? true,
      mapShowGuessedLocations:
          json['map_show_guessed_locations'] as bool? ?? true,
      enableMessageTracing: json['enable_message_tracing'] as bool? ?? true,
      enableTimeSeconds: json['enable_time_seconds'] as bool? ?? false,
      showKeyboardHidingButton:
          json['show_keyboard_hiding_button'] as bool? ?? true,
      canvasActive: json['canvas_active'] as bool? ?? true,
      canvasShowLockButton: json['canvas_show_lock_button'] as bool? ?? true,
      showHops: json['show_hops'] as bool? ?? true,
      hideChannelIndexIndicator:
          json['hide_channel_index_indicator'] as bool? ?? false,
      hideRadioStatsButton: json['hide_radio_stats_button'] as bool? ?? false,
      hideMapZoomControls: json['hide_map_zoom_controls'] as bool? ?? false,
      showMcoImageResolution:
          json['show_mco_image_resolution'] as bool? ?? false,
      showMcoImageFormat: json['show_mco_image_format'] as bool? ?? true,
      showMcoImageAlgorithm: json['show_mco_image_algorithm'] as bool? ?? true,
      showMcoImageBytes: json['show_mco_image_bytes'] as bool? ?? true,
      showMcoImagePackReplacements:
          json['show_mco_image_pack_replacements'] as bool? ?? true,
      uiScale: (json['ui_scale'] as num?)?.toDouble() ?? 1.0,
      uiScaleApplyToIcons: json['ui_scale_apply_to_icons'] as bool? ?? true,
      showCompressionRatio: json['show_compression_ratio'] as bool? ?? false,
      compressionRatioWithSenderName:
          json['compression_ratio_with_sender_name'] as bool? ?? false,
      showMessageRegion: json['show_message_region'] as bool? ?? false,
      channelsUnreadSorting: json['channels_unread_sorting'] as bool? ?? false,
      incomingQuoteAsMentions:
          json['incoming_quote_as_mentions'] as bool? ?? false,
      simplifiedMentions: json['simplified_mentions'] as bool? ?? false,
      sharedMessageHistoryMode: parseSharedMessageHistoryMode(
        json['shared_message_history_mode'],
      ),
      noRetransmissionWarningSeconds: json['no_retransmission_warning_seconds'],
      backgroundTcpEnabled: json['background_tcp_enabled'] as bool? ?? false,
      mapCacheBounds: (json['map_cache_bounds'] as Map?)?.map(
        (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
      ),
      mapCacheMinZoom: json['map_cache_min_zoom'] as int? ?? 10,
      mapCacheMaxZoom: json['map_cache_max_zoom'] as int? ?? 15,
      notificationsEnabled: json['notifications_enabled'] as bool? ?? true,
      notifyOnNewMessage: json['notify_on_new_message'] as bool? ?? true,
      notifyOnNewChannelMessage:
          json['notify_on_new_channel_message'] as bool? ?? true,
      notifyOnNewAdvert: json['notify_on_new_advert'] as bool? ?? true,
      autoRouteRotationEnabled:
          json['auto_route_rotation_enabled'] as bool? ?? true,
      maxRouteWeight: (json['max_route_weight'] as num?)?.toDouble() ?? 5.0,
      initialRouteWeight:
          (json['initial_route_weight'] as num?)?.toDouble() ?? 3.0,
      routeWeightSuccessIncrement:
          (json['route_weight_success_increment'] as num?)?.toDouble() ?? 0.5,
      routeWeightFailureDecrement:
          (json['route_weight_failure_decrement'] as num?)?.toDouble() ?? 0.2,
      maxMessageRetries: json['max_message_retries'] as int? ?? 5,
      channelResendTimeoutSeconds: json['channel_resend_timeout_seconds'],
      themeMode: json['theme_mode'] as String? ?? 'system',
      languageOverride: json['language_override'] as String?,
      appDebugLogEnabled: json['app_debug_log_enabled'] as bool? ?? false,
      batteryChemistryByDeviceId:
          (json['battery_chemistry_by_device_id'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ) ??
          {},
      batteryChemistryByRepeaterId:
          (json['battery_chemistry_by_repeater_id'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ) ??
          {},
      unitSystem: parseUnitSystem(json['unit_system']),
      mutedChannels:
          ((json['muted_channels'] as List?)
              ?.map((e) => e.toString())
              .toSet()) ??
          {},
      mapShowDiscoveryContacts:
          json['map_show_discovery_contacts'] as bool? ?? true,
      tcpServerAddress: json['tcp_server_address'] as String? ?? '',
      tcpServerPort: json['tcp_server_port'] as int? ?? 0,
      tcpConnectionBookmarks:
          (json['tcp_connection_bookmarks'] as List<dynamic>?)
              ?.map(
                (entry) => TcpConnectionBookmark.fromJson(
                  Map<String, dynamic>.from(entry as Map),
                ),
              )
              .where(
                (bookmark) => bookmark.host.isNotEmpty && bookmark.port > 0,
              )
              .toList() ??
          const [],
      jumpToOldestUnread: json['jump_to_oldest_unread'] as bool? ?? false,
      translationEnabled: json['translation_enabled'] as bool? ?? false,
      autoTranslateIncomingMessages:
          json['auto_translate_incoming_messages'] as bool? ?? true,
      translationTargetLanguageCode:
          json['translation_target_language_code'] as String?,
      composerTranslationEnabled:
          json['composer_translation_enabled'] as bool? ?? false,
      translationModelSourceUrl:
          json['translation_model_source_url'] as String?,
      translationSelectedModelId:
          json['translation_selected_model_id'] as String?,
      translationDownloadedModels:
          (json['translation_downloaded_models'] as List<dynamic>?)
              ?.map(
                (entry) => TranslationModelRecord.fromJson(
                  Map<String, dynamic>.from(entry as Map),
                ),
              )
              .toList() ??
          const [],
      mcmpTextLimit: json['mcmp_text_limit'],
      channelMaxbytesOutgoing: json['channel_maxbytes_outgoing'],
      quickAnswers: normalizeQuickAnswers(json['quick_answers']),
      copyMsgPathTemplate: json['copy_msg_path_template'] as String?,
      copyMsgPathFinalTemplate: json['copy_msg_path_final_template'] as String?,
      channelsSendAsBinary: json['channels_send_as_binary'] as bool? ?? true,
      sendingDelayForCancellationSeconds:
          json['sending_delay_for_cancellation_seconds'],
      doNotFilterMessagesOnChannels:
          json['do_not_filter_messages_on_channels'] as String? ??
          defaultDoNotFilterMessagesOnChannels,
      cyr2latProfiles:
          (json['cyr2lat_profiles'] as List<dynamic>?)
              ?.map(
                (entry) => Cyr2LatProfile.fromJson(
                  Map<String, dynamic>.from(entry as Map),
                ),
              )
              .toList() ??
          // Backward compatibility: if old cyr2lat_char_map exists, create a profile from it
          (json['cyr2lat_char_map'] != null
              ? [
                  Cyr2LatProfile(
                    id: 'migrated',
                    name: 'Migrated Profile',
                    charMap:
                        (json['cyr2lat_char_map'] as Map?)?.map(
                          (key, value) =>
                              MapEntry(key.toString(), value.toString()),
                        ) ??
                        Cyr2Lat.defaultCharMap,
                  ),
                ]
              : standardCyr2LatProfiles),
      selectedCyr2latProfileId:
          json['selected_cyr2lat_profile_id'] as String? ??
          (json['cyr2lat_char_map'] != null ? 'migrated' : 'default'),
    );
  }

  AppSettings copyWith({
    bool? clearPathOnMaxRetry,
    bool? mapShowRepeaters,
    bool? mapShowChatNodes,
    bool? mapShowOtherNodes,
    bool? pathTraceHighTimeoutEnabled,
    bool? mapShowOverlaps,
    double? mapTimeFilterHours,
    bool? mapKeyPrefixEnabled,
    String? mapKeyPrefix,
    bool? mapShowMarkers,
    bool? mapShowGuessedLocations,
    bool? enableMessageTracing,
    bool? enableTimeSeconds,
    bool? showKeyboardHidingButton,
    bool? canvasActive,
    bool? canvasShowLockButton,
    bool? showHops,
    bool? hideChannelIndexIndicator,
    bool? hideRadioStatsButton,
    bool? hideMapZoomControls,
    bool? showMcoImageResolution,
    bool? showMcoImageFormat,
    bool? showMcoImageAlgorithm,
    bool? showMcoImageBytes,
    bool? showMcoImagePackReplacements,
    double? uiScale,
    bool? uiScaleApplyToIcons,
    bool? showCompressionRatio,
    bool? compressionRatioWithSenderName,
    bool? showMessageRegion,
    bool? channelsUnreadSorting,
    bool? incomingQuoteAsMentions,
    bool? simplifiedMentions,
    SharedMessageHistoryMode? sharedMessageHistoryMode,
    int? noRetransmissionWarningSeconds,
    bool? backgroundTcpEnabled,
    Object? mapCacheBounds = _unset,
    int? mapCacheMinZoom,
    int? mapCacheMaxZoom,
    bool? notificationsEnabled,
    bool? notifyOnNewMessage,
    bool? notifyOnNewChannelMessage,
    bool? notifyOnNewAdvert,
    bool? autoRouteRotationEnabled,
    double? maxRouteWeight,
    double? initialRouteWeight,
    double? routeWeightSuccessIncrement,
    double? routeWeightFailureDecrement,
    int? maxMessageRetries,
    int? channelResendTimeoutSeconds,
    String? themeMode,
    Object? languageOverride = _unset,
    bool? appDebugLogEnabled,
    Map<String, String>? batteryChemistryByDeviceId,
    Map<String, String>? batteryChemistryByRepeaterId,
    UnitSystem? unitSystem,
    Set<String>? mutedChannels,
    bool? mapShowDiscoveryContacts,
    String? tcpServerAddress,
    int? tcpServerPort,
    List<TcpConnectionBookmark>? tcpConnectionBookmarks,
    bool? jumpToOldestUnread,
    bool? translationEnabled,
    bool? autoTranslateIncomingMessages,
    Object? translationTargetLanguageCode = _unset,
    bool? composerTranslationEnabled,
    Object? translationModelSourceUrl = _unset,
    Object? translationSelectedModelId = _unset,
    List<TranslationModelRecord>? translationDownloadedModels,
    int? mcmpTextLimit,
    int? channelMaxbytesOutgoing,
    List<QuickAnswer>? quickAnswers,
    String? copyMsgPathTemplate,
    String? copyMsgPathFinalTemplate,
    bool? channelsSendAsBinary,
    int? sendingDelayForCancellationSeconds,
    String? doNotFilterMessagesOnChannels,
    List<Cyr2LatProfile>? cyr2latProfiles,
    String? selectedCyr2latProfileId,
  }) {
    return AppSettings(
      clearPathOnMaxRetry: clearPathOnMaxRetry ?? this.clearPathOnMaxRetry,
      mapShowRepeaters: mapShowRepeaters ?? this.mapShowRepeaters,
      mapShowChatNodes: mapShowChatNodes ?? this.mapShowChatNodes,
      mapShowOtherNodes: mapShowOtherNodes ?? this.mapShowOtherNodes,
      pathTraceHighTimeoutEnabled:
          pathTraceHighTimeoutEnabled ?? this.pathTraceHighTimeoutEnabled,
      mapShowOverlaps: mapShowOverlaps ?? this.mapShowOverlaps,
      mapTimeFilterHours: mapTimeFilterHours ?? this.mapTimeFilterHours,
      mapKeyPrefixEnabled: mapKeyPrefixEnabled ?? this.mapKeyPrefixEnabled,
      mapKeyPrefix: mapKeyPrefix ?? this.mapKeyPrefix,
      mapShowMarkers: mapShowMarkers ?? this.mapShowMarkers,
      mapShowGuessedLocations:
          mapShowGuessedLocations ?? this.mapShowGuessedLocations,
      enableMessageTracing: enableMessageTracing ?? this.enableMessageTracing,
      enableTimeSeconds: enableTimeSeconds ?? this.enableTimeSeconds,
      showKeyboardHidingButton:
          showKeyboardHidingButton ?? this.showKeyboardHidingButton,
      canvasActive: canvasActive ?? this.canvasActive,
      canvasShowLockButton: canvasShowLockButton ?? this.canvasShowLockButton,
      showHops: showHops ?? this.showHops,
      hideChannelIndexIndicator:
          hideChannelIndexIndicator ?? this.hideChannelIndexIndicator,
      hideRadioStatsButton: hideRadioStatsButton ?? this.hideRadioStatsButton,
      hideMapZoomControls: hideMapZoomControls ?? this.hideMapZoomControls,
      showMcoImageResolution:
          showMcoImageResolution ?? this.showMcoImageResolution,
      showMcoImageFormat: showMcoImageFormat ?? this.showMcoImageFormat,
      showMcoImageAlgorithm:
          showMcoImageAlgorithm ?? this.showMcoImageAlgorithm,
      showMcoImageBytes: showMcoImageBytes ?? this.showMcoImageBytes,
      showMcoImagePackReplacements:
          showMcoImagePackReplacements ?? this.showMcoImagePackReplacements,
      uiScale: uiScale ?? this.uiScale,
      uiScaleApplyToIcons: uiScaleApplyToIcons ?? this.uiScaleApplyToIcons,
      showCompressionRatio: showCompressionRatio ?? this.showCompressionRatio,
      compressionRatioWithSenderName:
          compressionRatioWithSenderName ?? this.compressionRatioWithSenderName,
      showMessageRegion: showMessageRegion ?? this.showMessageRegion,
      channelsUnreadSorting:
          channelsUnreadSorting ?? this.channelsUnreadSorting,
      incomingQuoteAsMentions:
          incomingQuoteAsMentions ?? this.incomingQuoteAsMentions,
      simplifiedMentions: simplifiedMentions ?? this.simplifiedMentions,
      sharedMessageHistoryMode:
          sharedMessageHistoryMode ?? this.sharedMessageHistoryMode,
      noRetransmissionWarningSeconds:
          noRetransmissionWarningSeconds ?? this.noRetransmissionWarningSeconds,
      backgroundTcpEnabled: backgroundTcpEnabled ?? this.backgroundTcpEnabled,
      mapCacheBounds: mapCacheBounds == _unset
          ? this.mapCacheBounds
          : mapCacheBounds as Map<String, double>?,
      mapCacheMinZoom: mapCacheMinZoom ?? this.mapCacheMinZoom,
      mapCacheMaxZoom: mapCacheMaxZoom ?? this.mapCacheMaxZoom,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      notifyOnNewMessage: notifyOnNewMessage ?? this.notifyOnNewMessage,
      notifyOnNewChannelMessage:
          notifyOnNewChannelMessage ?? this.notifyOnNewChannelMessage,
      notifyOnNewAdvert: notifyOnNewAdvert ?? this.notifyOnNewAdvert,
      autoRouteRotationEnabled:
          autoRouteRotationEnabled ?? this.autoRouteRotationEnabled,
      maxRouteWeight: maxRouteWeight ?? this.maxRouteWeight,
      initialRouteWeight: initialRouteWeight ?? this.initialRouteWeight,
      routeWeightSuccessIncrement:
          routeWeightSuccessIncrement ?? this.routeWeightSuccessIncrement,
      routeWeightFailureDecrement:
          routeWeightFailureDecrement ?? this.routeWeightFailureDecrement,
      maxMessageRetries: maxMessageRetries ?? this.maxMessageRetries,
      channelResendTimeoutSeconds:
          channelResendTimeoutSeconds ?? this.channelResendTimeoutSeconds,
      themeMode: themeMode ?? this.themeMode,
      languageOverride: languageOverride == _unset
          ? this.languageOverride
          : languageOverride as String?,
      appDebugLogEnabled: appDebugLogEnabled ?? this.appDebugLogEnabled,
      batteryChemistryByDeviceId:
          batteryChemistryByDeviceId ?? this.batteryChemistryByDeviceId,
      batteryChemistryByRepeaterId:
          batteryChemistryByRepeaterId ?? this.batteryChemistryByRepeaterId,
      unitSystem: unitSystem ?? this.unitSystem,
      mutedChannels: mutedChannels ?? this.mutedChannels,
      mapShowDiscoveryContacts:
          mapShowDiscoveryContacts ?? this.mapShowDiscoveryContacts,
      tcpServerAddress: tcpServerAddress ?? this.tcpServerAddress,
      tcpServerPort: tcpServerPort ?? this.tcpServerPort,
      tcpConnectionBookmarks:
          tcpConnectionBookmarks ?? this.tcpConnectionBookmarks,
      jumpToOldestUnread: jumpToOldestUnread ?? this.jumpToOldestUnread,
      translationEnabled: translationEnabled ?? this.translationEnabled,
      autoTranslateIncomingMessages:
          autoTranslateIncomingMessages ?? this.autoTranslateIncomingMessages,
      translationTargetLanguageCode: translationTargetLanguageCode == _unset
          ? this.translationTargetLanguageCode
          : translationTargetLanguageCode as String?,
      composerTranslationEnabled:
          composerTranslationEnabled ?? this.composerTranslationEnabled,
      translationModelSourceUrl: translationModelSourceUrl == _unset
          ? this.translationModelSourceUrl
          : translationModelSourceUrl as String?,
      translationSelectedModelId: translationSelectedModelId == _unset
          ? this.translationSelectedModelId
          : translationSelectedModelId as String?,
      translationDownloadedModels:
          translationDownloadedModels ?? this.translationDownloadedModels,
      mcmpTextLimit: mcmpTextLimit ?? this.mcmpTextLimit,
      channelMaxbytesOutgoing:
          channelMaxbytesOutgoing ?? this.channelMaxbytesOutgoing,
      quickAnswers: quickAnswers ?? this.quickAnswers,
      copyMsgPathTemplate: copyMsgPathTemplate ?? this.copyMsgPathTemplate,
      copyMsgPathFinalTemplate:
          copyMsgPathFinalTemplate ?? this.copyMsgPathFinalTemplate,
      channelsSendAsBinary: channelsSendAsBinary ?? this.channelsSendAsBinary,
      sendingDelayForCancellationSeconds:
          sendingDelayForCancellationSeconds ??
          this.sendingDelayForCancellationSeconds,
      doNotFilterMessagesOnChannels:
          doNotFilterMessagesOnChannels ?? this.doNotFilterMessagesOnChannels,
      cyr2latProfiles: cyr2latProfiles ?? this.cyr2latProfiles,
      selectedCyr2latProfileId:
          selectedCyr2latProfileId ?? this.selectedCyr2latProfileId,
    );
  }
}
