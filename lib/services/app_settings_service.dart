import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/app_settings.dart';
import '../models/translation_support.dart';
import '../storage/prefs_manager.dart';
import '../utils/app_logger.dart';
import '../helpers/channel_binary_data_helper.dart';
import '../helpers/cyr2lat.dart';

class AppSettingsService extends ChangeNotifier {
  static const String _settingsKey = 'app_settings';

  AppSettings _settings = AppSettings();

  AppSettings get settings => _settings;

  String batteryChemistryForDevice(String deviceId) {
    final stored = _settings.batteryChemistryByDeviceId[deviceId];
    if (stored == 'liion') return 'nmc';
    return stored ?? 'nmc';
  }

  String batteryChemistryForRepeater(String repeaterPubKeyHex) {
    final stored = _settings.batteryChemistryByRepeaterId[repeaterPubKeyHex];
    if (stored == 'liion') return 'nmc';
    return stored ?? 'nmc';
  }

  Future<void> loadSettings() async {
    final prefs = PrefsManager.instance;
    final jsonStr = prefs.getString(_settingsKey);

    if (jsonStr != null) {
      try {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        final loadedSettings = AppSettings.fromJson(json);
        _settings = _normalizeRuntimeDependentSettings(loadedSettings);
        _applyRuntimeSettings();
        if (_settings.channelsSendAsBinary !=
            loadedSettings.channelsSendAsBinary) {
          await _saveSettings();
        }
        notifyListeners();
      } catch (e) {
        // If parsing fails, use defaults
        _settings = _normalizeRuntimeDependentSettings(AppSettings());
        _applyRuntimeSettings();
      }
    } else {
      _settings = _normalizeRuntimeDependentSettings(AppSettings());
      _applyRuntimeSettings();
    }
  }

  Future<void> updateSettings(AppSettings newSettings) async {
    _settings = _normalizeRuntimeDependentSettings(newSettings);
    _applyRuntimeSettings();
    notifyListeners();

    await _saveSettings();
  }

  Future<void> _saveSettings() async {
    final prefs = PrefsManager.instance;
    final jsonStr = jsonEncode(_settings.toJson());
    await prefs.setString(_settingsKey, jsonStr);
  }

  AppSettings _normalizeRuntimeDependentSettings(AppSettings settings) {
    if (!ChannelBinaryDataHelper.isAvailable && settings.channelsSendAsBinary) {
      return settings.copyWith(channelsSendAsBinary: false);
    }
    return settings;
  }

  void _applyRuntimeSettings() {
    Cyr2Lat.setCharMap(_settings.cyr2latCharMap);
    ChannelBinaryDataHelper.sendEnabled = _settings.channelsSendAsBinary;
  }

  Future<void> setClearPathOnMaxRetry(bool value) async {
    await updateSettings(_settings.copyWith(clearPathOnMaxRetry: value));
  }

  Future<void> setMapShowRepeaters(bool value) async {
    await updateSettings(_settings.copyWith(mapShowRepeaters: value));
  }

  Future<void> setMapShowChatNodes(bool value) async {
    await updateSettings(_settings.copyWith(mapShowChatNodes: value));
  }

  Future<void> setMapShowOtherNodes(bool value) async {
    await updateSettings(_settings.copyWith(mapShowOtherNodes: value));
  }

  Future<void> setPathTraceHighTimeoutEnabled(bool value) async {
    await updateSettings(
      _settings.copyWith(pathTraceHighTimeoutEnabled: value),
    );
  }

  Future<void> setMapShowOverlaps(bool value) async {
    await updateSettings(_settings.copyWith(mapShowOverlaps: value));
  }

  Future<void> setMapTimeFilterHours(double value) async {
    await updateSettings(_settings.copyWith(mapTimeFilterHours: value));
  }

  Future<void> setMapKeyPrefixEnabled(bool value) async {
    await updateSettings(_settings.copyWith(mapKeyPrefixEnabled: value));
  }

  Future<void> setMapKeyPrefix(String value) async {
    await updateSettings(_settings.copyWith(mapKeyPrefix: value));
  }

  Future<void> setMapShowMarkers(bool value) async {
    await updateSettings(_settings.copyWith(mapShowMarkers: value));
  }

  Future<void> setMapShowGuessedLocations(bool value) async {
    await updateSettings(_settings.copyWith(mapShowGuessedLocations: value));
  }

  Future<void> setEnableMessageTracing(bool value) async {
    await updateSettings(_settings.copyWith(enableMessageTracing: value));
  }

  Future<void> setEnableTimeSeconds(bool value) async {
    await updateSettings(_settings.copyWith(enableTimeSeconds: value));
  }

  Future<void> setShowKeyboardHidingButton(bool value) async {
    await updateSettings(_settings.copyWith(showKeyboardHidingButton: value));
  }

  Future<void> setCanvasActive(bool value) async {
    await updateSettings(_settings.copyWith(canvasActive: value));
  }

  Future<void> setCanvasShowLockButton(bool value) async {
    await updateSettings(_settings.copyWith(canvasShowLockButton: value));
  }

  Future<void> setShowHops(bool value) async {
    await updateSettings(_settings.copyWith(showHops: value));
  }

  Future<void> setHideChannelIndexIndicator(bool value) async {
    await updateSettings(_settings.copyWith(hideChannelIndexIndicator: value));
  }

  Future<void> setHideRadioStatsButton(bool value) async {
    await updateSettings(_settings.copyWith(hideRadioStatsButton: value));
  }

  Future<void> setSnrIndicatorAllRepActivity(bool value) async {
    await updateSettings(
      _settings.copyWith(snrIndicatorAllRepActivity: value),
    );
  }

  Future<void> setHideMapZoomControls(bool value) async {
    await updateSettings(_settings.copyWith(hideMapZoomControls: value));
  }

  Future<void> setShowMcoImageResolution(bool value) async {
    await updateSettings(_settings.copyWith(showMcoImageResolution: value));
  }

  Future<void> setShowMcoImageFormat(bool value) async {
    await updateSettings(_settings.copyWith(showMcoImageFormat: value));
  }

  Future<void> setShowMcoImageAlgorithm(bool value) async {
    await updateSettings(_settings.copyWith(showMcoImageAlgorithm: value));
  }

  Future<void> setShowMcoImageBytes(bool value) async {
    await updateSettings(_settings.copyWith(showMcoImageBytes: value));
  }

  Future<void> setShowMcoImagePackReplacements(bool value) async {
    await updateSettings(
      _settings.copyWith(showMcoImagePackReplacements: value),
    );
  }

  Future<void> setUiScale(double value) async {
    await updateSettings(_settings.copyWith(uiScale: value));
  }

  Future<void> setUiScaleApplyToIcons(bool value) async {
    await updateSettings(_settings.copyWith(uiScaleApplyToIcons: value));
  }

  Future<void> setShowCompressionRatio(bool value) async {
    await updateSettings(_settings.copyWith(showCompressionRatio: value));
  }

  Future<void> setCompressionRatioWithSenderName(bool value) async {
    await updateSettings(
      _settings.copyWith(compressionRatioWithSenderName: value),
    );
  }

  Future<void> setShowMessageRegion(bool value) async {
    await updateSettings(_settings.copyWith(showMessageRegion: value));
  }

  Future<void> setChannelsUnreadSorting(bool value) async {
    await updateSettings(_settings.copyWith(channelsUnreadSorting: value));
  }

  Future<void> setIncomingQuoteAsMentions(bool value) async {
    await updateSettings(_settings.copyWith(incomingQuoteAsMentions: value));
  }

  Future<void> setSimplifiedMentions(bool value) async {
    await updateSettings(_settings.copyWith(simplifiedMentions: value));
  }

  Future<void> setSharedMessageHistoryMode(
    SharedMessageHistoryMode value,
  ) async {
    await updateSettings(_settings.copyWith(sharedMessageHistoryMode: value));
  }

  Future<void> setNoRetransmissionWarningSeconds(int value) async {
    await updateSettings(
      _settings.copyWith(noRetransmissionWarningSeconds: value),
    );
  }

  Future<void> setBackgroundTcpEnabled(bool value) async {
    await updateSettings(_settings.copyWith(backgroundTcpEnabled: value));
  }

  Future<void> setMapCacheBounds(Map<String, double>? value) async {
    await updateSettings(_settings.copyWith(mapCacheBounds: value));
  }

  Future<void> setMapCacheZoomRange(int minZoom, int maxZoom) async {
    final safeMin = minZoom <= maxZoom ? minZoom : maxZoom;
    final safeMax = minZoom <= maxZoom ? maxZoom : minZoom;
    await updateSettings(
      _settings.copyWith(mapCacheMinZoom: safeMin, mapCacheMaxZoom: safeMax),
    );
  }

  Future<void> setNotificationsEnabled(bool value) async {
    await updateSettings(_settings.copyWith(notificationsEnabled: value));
  }

  Future<void> setNotifyOnNewMessage(bool value) async {
    await updateSettings(_settings.copyWith(notifyOnNewMessage: value));
  }

  Future<void> setNotifyOnNewChannelMessage(bool value) async {
    await updateSettings(_settings.copyWith(notifyOnNewChannelMessage: value));
  }

  Future<void> setNotifyOnNewAdvert(bool value) async {
    await updateSettings(_settings.copyWith(notifyOnNewAdvert: value));
  }

  Future<void> setAutoRouteRotationEnabled(bool value) async {
    await updateSettings(_settings.copyWith(autoRouteRotationEnabled: value));
  }

  Future<void> setMaxRouteWeight(double value) async {
    await updateSettings(_settings.copyWith(maxRouteWeight: value));
  }

  Future<void> setInitialRouteWeight(double value) async {
    await updateSettings(_settings.copyWith(initialRouteWeight: value));
  }

  Future<void> setRouteWeightSuccessIncrement(double value) async {
    await updateSettings(
      _settings.copyWith(routeWeightSuccessIncrement: value),
    );
  }

  Future<void> setRouteWeightFailureDecrement(double value) async {
    await updateSettings(
      _settings.copyWith(routeWeightFailureDecrement: value),
    );
  }

  Future<void> setMaxMessageRetries(int value) async {
    await updateSettings(_settings.copyWith(maxMessageRetries: value));
  }

  Future<void> setChannelResendTimeoutSeconds(int value) async {
    await updateSettings(
      _settings.copyWith(
        channelResendTimeoutSeconds:
            AppSettings.normalizeChannelResendTimeoutSeconds(value),
      ),
    );
  }

  Future<void> setThemeMode(String value) async {
    await updateSettings(_settings.copyWith(themeMode: value));
  }

  Future<void> setLanguageOverride(String? value) async {
    await updateSettings(_settings.copyWith(languageOverride: value));
  }

  Future<void> setAppDebugLogEnabled(bool value) async {
    await updateSettings(_settings.copyWith(appDebugLogEnabled: value));
    // Update the global logger
    appLogger.setEnabled(value);
  }

  Future<void> setMapShowDiscoveryContacts(bool value) async {
    await updateSettings(_settings.copyWith(mapShowDiscoveryContacts: value));
  }

  Future<void> setBatteryChemistryForDevice(
    String deviceId,
    String chemistry,
  ) async {
    final updated = Map<String, String>.from(
      _settings.batteryChemistryByDeviceId,
    );
    updated[deviceId] = chemistry;
    await updateSettings(
      _settings.copyWith(batteryChemistryByDeviceId: updated),
    );
  }

  Future<void> setBatteryChemistryForRepeater(
    String repeaterPubKeyHex,
    String chemistry,
  ) async {
    final updated = Map<String, String>.from(
      _settings.batteryChemistryByRepeaterId,
    );
    updated[repeaterPubKeyHex] = chemistry;
    await updateSettings(
      _settings.copyWith(batteryChemistryByRepeaterId: updated),
    );
  }

  Future<void> setUnitSystem(UnitSystem value) async {
    await updateSettings(_settings.copyWith(unitSystem: value));
  }

  bool isChannelMuted(String channelName) {
    return _settings.mutedChannels.contains(channelName);
  }

  Future<void> muteChannel(String channelName) async {
    final updated = Set<String>.from(_settings.mutedChannels)..add(channelName);
    await updateSettings(_settings.copyWith(mutedChannels: updated));
  }

  Future<void> unmuteChannel(String channelName) async {
    final updated = Set<String>.from(_settings.mutedChannels)
      ..remove(channelName);
    await updateSettings(_settings.copyWith(mutedChannels: updated));
  }

  Future<void> setTcpServerAddress(String value) async {
    await updateSettings(_settings.copyWith(tcpServerAddress: value));
  }

  Future<void> setTcpServerPort(int value) async {
    await updateSettings(_settings.copyWith(tcpServerPort: value));
  }

  Future<void> recordTcpConnection(String host, int port) async {
    final normalizedHost = host.trim();
    if (normalizedHost.isEmpty || port <= 0) return;
    final existing = _settings.tcpConnectionBookmarks
        .cast<TcpConnectionBookmark?>()
        .firstWhere(
          (item) =>
              item?.host.toLowerCase() == normalizedHost.toLowerCase() &&
              item?.port == port,
          orElse: () => null,
        );

    final bookmark = TcpConnectionBookmark(
      host: normalizedHost,
      port: port,
      lastConnectedAt: DateTime.now(),
      name: existing?.name ?? '',
      isFavorite: existing?.isFavorite ?? false,
    );

    // Move this endpoint to the top, drop duplicates, and keep only recent ones.
    final bookmarks = _limitTcpBookmarks([
      bookmark,
      ..._settings.tcpConnectionBookmarks.where(
        (item) =>
            item.host.toLowerCase() != normalizedHost.toLowerCase() ||
            item.port != port,
      ),
    ]);

    await updateSettings(
      _settings.copyWith(
        tcpServerAddress: normalizedHost,
        tcpServerPort: port,
        tcpConnectionBookmarks: bookmarks.take(5).toList(),
      ),
    );
  }

  Future<void> setTcpConnectionBookmarkName(
    TcpConnectionBookmark bookmark,
    String name,
  ) async {
    await setTcpConnectionBookmarkDetails(
      bookmark,
      name: name,
      isFavorite: bookmark.isFavorite,
    );
  }

  Future<void> setTcpConnectionBookmarkDetails(
    TcpConnectionBookmark bookmark, {
    required String name,
    required bool isFavorite,
  }) async {
    final bookmarks = _settings.tcpConnectionBookmarks.map((item) {
      if (item.host.toLowerCase() == bookmark.host.toLowerCase() &&
          item.port == bookmark.port) {
        return item.copyWith(name: name.trim(), isFavorite: isFavorite);
      }
      return item;
    }).toList();

    await updateSettings(
      _settings.copyWith(tcpConnectionBookmarks: _sortTcpBookmarks(bookmarks)),
    );
  }

  Future<void> removeTcpConnectionBookmark(
    TcpConnectionBookmark bookmark,
  ) async {
    final bookmarks = _settings.tcpConnectionBookmarks
        .where(
          (item) =>
              item.host.toLowerCase() != bookmark.host.toLowerCase() ||
              item.port != bookmark.port,
        )
        .toList();

    await updateSettings(_settings.copyWith(tcpConnectionBookmarks: bookmarks));
  }

  List<TcpConnectionBookmark> _limitTcpBookmarks(
    List<TcpConnectionBookmark> bookmarks,
  ) {
    final limited = List<TcpConnectionBookmark>.from(bookmarks);
    while (limited.length > 5) {
      final removable =
          limited.where((bookmark) => !bookmark.isFavorite).toList()
            ..sort((a, b) => a.lastConnectedAt.compareTo(b.lastConnectedAt));
      if (removable.isEmpty) break;
      limited.remove(removable.first);
    }
    return _sortTcpBookmarks(limited.take(5).toList());
  }

  List<TcpConnectionBookmark> _sortTcpBookmarks(
    List<TcpConnectionBookmark> bookmarks,
  ) {
    return List<TcpConnectionBookmark>.from(bookmarks)..sort((a, b) {
      if (a.isFavorite != b.isFavorite) {
        return a.isFavorite ? -1 : 1;
      }
      return b.lastConnectedAt.compareTo(a.lastConnectedAt);
    });
  }

  Future<void> setJumpToOldestUnread(bool value) async {
    await updateSettings(_settings.copyWith(jumpToOldestUnread: value));
  }

  Future<void> setTranslationEnabled(bool value) async {
    await updateSettings(_settings.copyWith(translationEnabled: value));
  }

  Future<void> setAutoTranslateIncomingMessages(bool value) async {
    await updateSettings(
      _settings.copyWith(autoTranslateIncomingMessages: value),
    );
  }

  Future<void> setTranslationTargetLanguageCode(String? value) async {
    await updateSettings(
      _settings.copyWith(translationTargetLanguageCode: value),
    );
  }

  Future<void> setComposerTranslationEnabled(bool value) async {
    await updateSettings(_settings.copyWith(composerTranslationEnabled: value));
  }

  Future<void> setTranslationModelSourceUrl(String? value) async {
    await updateSettings(_settings.copyWith(translationModelSourceUrl: value));
  }

  Future<void> setTranslationSelectedModelId(String? value) async {
    await updateSettings(_settings.copyWith(translationSelectedModelId: value));
  }

  Future<void> setTranslationDownloadedModels(
    List<TranslationModelRecord> value,
  ) async {
    await updateSettings(
      _settings.copyWith(translationDownloadedModels: value),
    );
  }

  Future<void> setMcmpTextLimit(int value) async {
    await updateSettings(
      _settings.copyWith(
        mcmpTextLimit: AppSettings.normalizeMcmpTextLimit(value),
      ),
    );
  }

  Future<void> setChannelMaxbytesOutgoing(int value) async {
    await updateSettings(
      _settings.copyWith(
        channelMaxbytesOutgoing: AppSettings.normalizeChannelMaxbytesOutgoing(
          value,
        ),
      ),
    );
  }

  Future<void> setQuickAnswers(List<QuickAnswer> value) async {
    await updateSettings(
      _settings.copyWith(
        // Keep stored replies normalized so empty rows never leak into UI lists.
        quickAnswers: AppSettings.normalizeQuickAnswers(value),
      ),
    );
  }

  Future<void> setCopyMsgPathTemplate(String value) async {
    await updateSettings(
      _settings.copyWith(
        copyMsgPathTemplate: AppSettings.normalizeCopyMsgPathTemplate(value),
      ),
    );
  }

  Future<void> setCopyMsgPathTemplates({
    required String hopTemplate,
    required String finalTemplate,
  }) async {
    await updateSettings(
      _settings.copyWith(
        copyMsgPathTemplate: AppSettings.normalizeCopyMsgPathTemplate(
          hopTemplate,
        ),
        copyMsgPathFinalTemplate: AppSettings.normalizeCopyMsgPathFinalTemplate(
          finalTemplate,
        ),
      ),
    );
  }

  Future<void> setChannelsSendAsBinary(bool value) async {
    await updateSettings(_settings.copyWith(channelsSendAsBinary: value));
  }

  Future<void> setSendingDelayForCancellationSeconds(int value) async {
    await updateSettings(
      _settings.copyWith(
        sendingDelayForCancellationSeconds:
            AppSettings.normalizeSendingDelayForCancellation(value),
      ),
    );
  }

  Cyr2LatProfile getSelectedCyr2LatProfile() {
    return _settings.cyr2latProfiles.firstWhere(
      (p) => p.id == _settings.selectedCyr2latProfileId,
      orElse: () => _settings.cyr2latProfiles.first,
    );
  }

  Cyr2LatProfile? getCyr2LatProfileById(String profileId) {
    return _settings.cyr2latProfiles.cast<Cyr2LatProfile?>().firstWhere(
      (p) => p?.id == profileId,
      orElse: () => null,
    );
  }

  Future<void> setSelectedCyr2LatProfile(String profileId) async {
    await updateSettings(
      _settings.copyWith(selectedCyr2latProfileId: profileId),
    );
  }

  Future<void> addCyr2LatProfile(Cyr2LatProfile profile) async {
    final updated = List<Cyr2LatProfile>.from(_settings.cyr2latProfiles)
      ..add(profile);
    await updateSettings(_settings.copyWith(cyr2latProfiles: updated));
  }

  Future<void> updateCyr2LatProfile(Cyr2LatProfile updatedProfile) async {
    final updated = _settings.cyr2latProfiles
        .map((p) => p.id == updatedProfile.id ? updatedProfile : p)
        .toList();
    await updateSettings(_settings.copyWith(cyr2latProfiles: updated));
  }

  Future<void> removeCyr2LatProfile(String profileId) async {
    if (_settings.cyr2latProfiles.length <= 1) {
      return; // Don't remove the last profile
    }
    final updated = _settings.cyr2latProfiles
        .where((p) => p.id != profileId)
        .toList();
    var newSelectedId = _settings.selectedCyr2latProfileId;
    if (newSelectedId == profileId) {
      newSelectedId = updated.first.id;
    }
    await updateSettings(
      _settings.copyWith(
        cyr2latProfiles: updated,
        selectedCyr2latProfileId: newSelectedId,
      ),
    );
  }

  Future<void> setDoNotFilterMessagesOnChannels(String value) async {
    await updateSettings(
      _settings.copyWith(doNotFilterMessagesOnChannels: value),
    );
  }
}
