import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/chrome_required_screen.dart';
import 'screens/channel_chat_screen.dart';
import 'screens/chat_screen.dart';
import 'utils/platform_info.dart';

import 'connector/meshcore_connector.dart';
import 'screens/scanner_screen.dart';
import 'services/storage_service.dart';
import 'services/message_retry_service.dart';
import 'services/path_history_service.dart';
import 'services/app_settings_service.dart';
import 'services/notification_service.dart';
import 'services/ble_debug_log_service.dart';
import 'services/app_debug_log_service.dart';
import 'services/background_service.dart';
import 'services/window_activation_service.dart';
import 'services/map_tile_cache_service.dart';
import 'services/chat_text_scale_service.dart';
import 'services/translation_service.dart';
import 'services/ui_view_state_service.dart';
import 'services/timeout_prediction_service.dart';
import 'services/wardrive_service.dart';
import 'storage/prefs_manager.dart';
import 'helpers/mesh_compressor.dart';
import 'theme/mesh_theme.dart';
import 'utils/app_logger.dart';
import 'utils/app_route_observer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // On desktop, debugPrint is not suppressed in release builds and every
  // call is a synchronous stdout write. The connector logs heavily on hot
  // paths (frame handling, queue/channel sync), which shows up as syscall
  // overhead on low-end Linux machines (issue #202). The in-app debug log
  // screens are unaffected — they store entries themselves.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // Initialize SharedPreferences cache
  await PrefsManager.initialize();
  await MeshCompressor.instance.initialize();

  // Initialize services
  final storage = StorageService();
  final connector = MeshCoreConnector();
  final pathHistoryService = PathHistoryService(storage);
  final retryService = MessageRetryService();
  final appSettingsService = AppSettingsService();
  final bleDebugLogService = BleDebugLogService();
  final appDebugLogService = AppDebugLogService();
  final backgroundService = BackgroundService();
  final mapTileCacheService = MapTileCacheService();
  final chatTextScaleService = ChatTextScaleService();
  final translationService = TranslationService(appSettingsService);
  final uiViewStateService = UiViewStateService();
  final timeoutPredictionService = TimeoutPredictionService(storage);
  final wardriveService = WardriveService(
    connector,
    backgroundService: backgroundService,
  );

  // Load settings
  await appSettingsService.loadSettings();

  // Initialize app logger
  appLogger.initialize(
    appDebugLogService,
    enabled: appSettingsService.settings.appDebugLogEnabled,
  );

  // Initialize notification service
  final notificationService = NotificationService();
  await notificationService.initialize();
  if (PlatformInfo.isAndroid &&
      appSettingsService.settings.notificationsEnabled &&
      (appSettingsService.settings.notifyOnNewMessage ||
          appSettingsService.settings.notifyOnNewChannelMessage)) {
    try {
      final notificationsGranted = await notificationService
          .areNotificationsEnabled();
      if (!notificationsGranted) {
        await notificationService.openAppNotificationSettings();
      }
    } catch (error) {
      debugPrint('Failed to open notification settings: $error');
    }
  }
  await backgroundService.initialize();
  backgroundService.setLanguageOverrideProvider(
    () => appSettingsService.settings.languageOverride,
  );
  _registerThirdPartyLicenses();

  await chatTextScaleService.initialize();
  await translationService.refreshDownloadedModels();
  await uiViewStateService.initialize();
  await timeoutPredictionService.initialize();

  // Wire up connector with services
  connector.initialize(
    retryService: retryService,
    pathHistoryService: pathHistoryService,
    appSettingsService: appSettingsService,
    translationService: translationService,
    bleDebugLogService: bleDebugLogService,
    appDebugLogService: appDebugLogService,
    backgroundService: backgroundService,
    timeoutPredictionService: timeoutPredictionService,
  );

  await connector.loadContactCache();
  await connector.loadChannelSettings();
  await connector.loadCachedChannels();

  // Load persisted channel messages
  await connector.loadAllChannelMessages();
  await connector.loadUnreadState();

  runApp(
    MeshCoreApp(
      connector: connector,
      retryService: retryService,
      pathHistoryService: pathHistoryService,
      storage: storage,
      appSettingsService: appSettingsService,
      bleDebugLogService: bleDebugLogService,
      appDebugLogService: appDebugLogService,
      mapTileCacheService: mapTileCacheService,
      chatTextScaleService: chatTextScaleService,
      translationService: translationService,
      uiViewStateService: uiViewStateService,
      timeoutPredictionService: timeoutPredictionService,
      wardriveService: wardriveService,
    ),
  );
}

void _registerThirdPartyLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      <String>['Open-Meteo Elevation API Data'],
      '''
Data used by LOS elevation lookups is provided by Open-Meteo.

Open-Meteo terms and attribution:
https://open-meteo.com/en/terms

Elevation API:
https://open-meteo.com/en/docs/elevation-api

Attribution license reference:
Creative Commons Attribution 4.0 International (CC BY 4.0)
https://creativecommons.org/licenses/by/4.0/
''',
    );
  });
}

class MeshCoreApp extends StatefulWidget {
  static final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();

  final MeshCoreConnector connector;
  final MessageRetryService retryService;
  final PathHistoryService pathHistoryService;
  final StorageService storage;
  final AppSettingsService appSettingsService;
  final BleDebugLogService bleDebugLogService;
  final AppDebugLogService appDebugLogService;
  final MapTileCacheService mapTileCacheService;
  final ChatTextScaleService chatTextScaleService;
  final TranslationService translationService;
  final UiViewStateService uiViewStateService;
  final TimeoutPredictionService timeoutPredictionService;
  final WardriveService wardriveService;

  const MeshCoreApp({
    super.key,
    required this.connector,
    required this.retryService,
    required this.pathHistoryService,
    required this.storage,
    required this.appSettingsService,
    required this.bleDebugLogService,
    required this.appDebugLogService,
    required this.mapTileCacheService,
    required this.chatTextScaleService,
    required this.translationService,
    required this.uiViewStateService,
    required this.timeoutPredictionService,
    required this.wardriveService,
  });

  @override
  State<MeshCoreApp> createState() => _MeshCoreAppState();
}

class _MeshCoreAppState extends State<MeshCoreApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNotificationPermissionState();
    }
  }

  void _refreshNotificationPermissionState() {
    if (!PlatformInfo.isAndroid) {
      return;
    }
    final settings = widget.appSettingsService.settings;
    if (!settings.notificationsEnabled ||
        (!settings.notifyOnNewMessage &&
            !settings.notifyOnNewChannelMessage)) {
      return;
    }
    unawaited(NotificationService().areNotificationsEnabled());
  }

  @override
  Widget build(BuildContext context) {
    NotificationService().setTapHandler(_handleNotificationTap);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.connector),
        ChangeNotifierProvider.value(value: widget.retryService),
        ChangeNotifierProvider.value(value: widget.pathHistoryService),
        ChangeNotifierProvider.value(value: widget.appSettingsService),
        ChangeNotifierProvider.value(value: widget.bleDebugLogService),
        ChangeNotifierProvider.value(value: widget.appDebugLogService),
        ChangeNotifierProvider.value(value: widget.chatTextScaleService),
        ChangeNotifierProvider.value(value: widget.translationService),
        ChangeNotifierProvider.value(value: widget.uiViewStateService),
        Provider.value(value: widget.storage),
        Provider.value(value: widget.mapTileCacheService),
        ChangeNotifierProvider.value(value: widget.timeoutPredictionService),
        ChangeNotifierProvider.value(value: widget.wardriveService),
      ],
      child: Consumer<AppSettingsService>(
        builder: (context, settingsService, child) {
          return MaterialApp(
            title: 'MeshCore Open (Advanced mod)',
            navigatorKey: MeshCoreApp._navigatorKey,
            navigatorObservers: [appRouteObserver],
            debugShowCheckedModeBanner: false,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: _localeFromSetting(
              settingsService.settings.languageOverride,
            ),
            theme: MeshTheme.light(),
            darkTheme: MeshTheme.dark(),
            themeMode: _themeModeFromSetting(
              settingsService.settings.themeMode,
            ),
            builder: (context, child) {
              // Update notification service with resolved locale
              final locale = Localizations.localeOf(context);
              NotificationService().setLocale(locale);
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: _systemUiOverlayStyle(context),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: (PlatformInfo.isWeb && !PlatformInfo.isChrome)
                ? const ChromeRequiredScreen()
                : const ScannerScreen(),
          );
        },
      ),
    );
  }

  ThemeMode _themeModeFromSetting(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  SystemUiOverlayStyle _systemUiOverlayStyle(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final iconBrightness = isDark ? Brightness.light : Brightness.dark;

    // Keep Android system bars aligned with the resolved Flutter theme.
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: iconBrightness,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: colorScheme.surface,
      systemNavigationBarIconBrightness: iconBrightness,
      systemNavigationBarDividerColor: colorScheme.surface,
      systemNavigationBarContrastEnforced: false,
    );
  }

  Future<void> _handleNotificationTap(String payload) {
    return _handleNotificationTapWithRetry(payload);
  }

  Future<void> _handleNotificationTapWithRetry(
    String payload, {
    int attempt = 0,
  }) async {
    final navigator = MeshCoreApp._navigatorKey.currentState;
    if (navigator == null ||
        MeshCoreApp._navigatorKey.currentContext == null) {
      if (attempt >= 20) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      return _handleNotificationTapWithRetry(payload, attempt: attempt + 1);
    }
    await WindowActivationService.restoreAndFocus();

    final separatorIndex = payload.indexOf(':');
    if (separatorIndex <= 0) return;
    final type = payload.substring(0, separatorIndex);
    final id = payload.substring(separatorIndex + 1);
    if (id.isEmpty || id == 'null') return;

    switch (type) {
      case 'message':
        final contacts = widget.connector.allContacts.where(
          (contact) => contact.publicKeyHex == id,
        );
        if (contacts.isEmpty) return;
        final contact = contacts.first;
        final unread = widget.connector.getUnreadCountForContact(contact);
        await navigator.push(
          MaterialPageRoute(
            builder: (_) =>
                ChatScreen(contact: contact, initialUnreadCount: unread),
          ),
        );
        break;
      case 'channel':
        final channelIndex = int.tryParse(id);
        if (channelIndex == null) return;
        final channels = widget.connector.channels.where(
          (channel) => channel.index == channelIndex,
        );
        if (channels.isEmpty) return;
        final channel = channels.first;
        final unread = widget.connector.getUnreadCountForChannelIndex(
          channel.index,
        );
        await navigator.push(
          MaterialPageRoute(
            builder: (_) =>
                ChannelChatScreen(channel: channel, initialUnreadCount: unread),
          ),
        );
        break;
    }
  }

  Locale? _localeFromSetting(String? languageCode) {
    if (languageCode == null) return null;
    return Locale(languageCode);
  }
}
