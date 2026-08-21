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
import 'models/image_codec_support.dart';
import 'screens/scanner_screen.dart';
import 'services/image_chunk_transport.dart';
import 'services/image_codec_backend.dart' show kImageCodecFeatureAvailable;
import 'services/image_codec_service.dart';
import 'services/image_codec_settings_store.dart';
import 'services/received_image_blob_store_factory.dart';
import 'services/received_image_store.dart';
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
import 'package:mco_service/mco_service.dart';
import 'services/ui_view_state_service.dart';
import 'services/timeout_prediction_service.dart';
import 'services/wardrive_service.dart';
import 'storage/prefs_manager.dart';
import 'storage/mco_image_gallery_store.dart';
import 'helpers/mesh_compressor.dart';
import 'theme/mesh_theme.dart';
import 'utils/app_logger.dart';
import 'utils/app_route_observer.dart';
import 'widgets/edge_swipe_pop.dart';
import 'widgets/image_send_codec_binding.dart';

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
  final backgroundService = BackgroundService(
    debugLogService: appDebugLogService,
  );
  final mapTileCacheService = MapTileCacheService(
    appSettingsService: appSettingsService,
  );
  final chatTextScaleService = ChatTextScaleService();
  final translationService = TranslationService(appSettingsService);
  final uiViewStateService = UiViewStateService();
  final settingsSectionsService = SettingsSectionsService();
  final timeoutPredictionService = TimeoutPredictionService(storage);
  final wardriveService = WardriveService(
    connector,
    backgroundService: backgroundService,
  );

  // Load settings before anything reads them. The image stack below takes its
  // model registry and its "process automatically" default straight off
  // `appSettingsService.settings`, so this cannot stay where it used to be
  // (after the constructions) without those two starting out wrong.
  await appSettingsService.loadSettings();
  await settingsSectionsService.initialize();
  appSettingsService.setExtraBatteryProfilesProvider(
    (deviceId) =>
        settingsSectionsService.batteryChemistryProfilesForDevice(deviceId),
  );
  settingsSectionsService.setBatteryProfileApplier((
    deviceKey,
    chemistry,
    minVolts,
    maxVolts,
  ) async {
    final batteryDeviceKey = connector.batteryDeviceKey ?? deviceKey;
    await appSettingsService.setBatteryChemistryForDevice(
      batteryDeviceKey,
      chemistry,
    );
    await appSettingsService.setBatteryCustomRangeForDevice(
      batteryDeviceKey,
      minVolts,
      maxVolts,
    );
  });

  // ---- image messages (AEIC over GRP_DATA) --------------------------------
  // The codec owns the ONNX decoder; the store owns received-image state and
  // the decode queue; the reassembler/transport pair is the receive path the
  // connector feeds raw frames into.
  final imageCodecService = ImageCodecService(
    appSettingsService,
    settingsStore: AppSettingsImageCodecStore(appSettingsService),
  );
  final receivedImageStore = ReceivedImageStore(
    // Without a file-backed store this silently falls back to memory and every
    // received image — sidecar included — is gone at the next launch.
    blobs: createReceivedImageBlobStore(),
    decoder: ImageCodecServiceDecoder(imageCodecService),
    processAutomatically: appSettingsService.settings.imageProcessAutomatically,
  );
  // A decode peaks around 2.16 GiB, so the setting is the user's consent to
  // spend it. Mirrored on every settings change; the store applies it to
  // future arrivals only, so turning it on does not decode a backlog.
  appSettingsService.addListener(() {
    receivedImageStore.processAutomatically =
        appSettingsService.settings.imageProcessAutomatically;
  });
  // Availability/isBusy changes are the only thing that un-parks a decode
  // queue that stopped because the codec was unusable or busy.
  imageCodecService.addListener(receivedImageStore.notifyDecoderChanged);
  final imageReassembler = ImageStreamReassembler(store: receivedImageStore);
  final imageTransport = ImageChunkTransport(
    reassembler: imageReassembler,
    // The UI sends whole chunk sets through connector.sendImageChunks so it
    // gets real inter-chunk pacing and per-chunk progress; this closure only
    // keeps ImageChunkTransport.sendImage() usable on its own.
    send: (blob, channelIndex) => connector.sendImageChunks(
      <Uint8List>[blob],
      channelIndex: channelIndex,
      interChunkDelay: Duration.zero,
    ),
    // Overwritten by onImageSenderPrefix as soon as SELF_INFO lands.
    senderPrefix: 0,
  );

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
  await imageCodecService.refreshDownloadedModels();
  await receivedImageStore.load();
  await uiViewStateService.initialize();
  await timeoutPredictionService.initialize();
  unawaited(MCOImageGalleryStore().ensureBundledPacksInstalled());

  // Wire up connector with services
  connector.initialize(
    retryService: retryService,
    pathHistoryService: pathHistoryService,
    appSettingsService: appSettingsService,
    settingsSectionsService: settingsSectionsService,
    translationService: translationService,
    bleDebugLogService: bleDebugLogService,
    appDebugLogService: appDebugLogService,
    backgroundService: backgroundService,
    timeoutPredictionService: timeoutPredictionService,
    imageCodecService: imageCodecService,
    imageTransport: kImageCodecFeatureAvailable ? imageTransport : null,
    // ImageStreamReassembler.addChunk already forwards every outcome to the
    // store together with the channel index (which ImageChunkOutcome itself
    // does not carry), so onImageChunk would be a second, channel-blind path.
    onImageSenderPrefix: kImageCodecFeatureAvailable
        ? (prefix) => imageReassembler.selfPrefix = prefix
        : null,
    // Repeats of our own image packets never reach `addChunk`: the firmware
    // surfaces them only in the RX log. This is that path, and it carries the
    // channel index the store needs to name the image.
    onImageChunkRepeat: kImageCodecFeatureAvailable
        ? (blob, channelIndex) => unawaited(
            receivedImageStore.noteOwnPacketRepeat(
              blob,
              channelIndex: channelIndex,
            ),
          )
        : null,
    deleteImagesForChannel: kImageCodecFeatureAvailable
        ? (channelIndex) async {
            await receivedImageStore.deleteImagesForChannel(channelIndex);
          }
        : null,
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
      backgroundService: backgroundService,
      mapTileCacheService: mapTileCacheService,
      chatTextScaleService: chatTextScaleService,
      translationService: translationService,
      uiViewStateService: uiViewStateService,
      settingsSectionsService: settingsSectionsService,
      timeoutPredictionService: timeoutPredictionService,
      wardriveService: wardriveService,
      imageCodecService: imageCodecService,
      receivedImageStore: receivedImageStore,
      imageReassembler: imageReassembler,
    ),
  );
}

/// [ReceivedImageDecoder] over [ImageCodecService].
///
/// Pure delegation. It exists so `received_image_store.dart` never imports
/// `image_codec_service.dart` (and so the store stays testable without an
/// 872 MB ONNX graph).
class ImageCodecServiceDecoder implements ReceivedImageDecoder {
  final ImageCodecService service;

  const ImageCodecServiceDecoder(this.service);

  @override
  ImageCodecAvailability get availability => service.availability;

  @override
  bool get isBusy => service.isBusy;

  @override
  Future<ImageCodecResult?> decodeBitstream({
    required Uint8List bitstream,
    required AeicRatePoint ratePoint,
    required int resolution,
  }) => service.decodeBitstream(
    bitstream: bitstream,
    ratePoint: ratePoint,
    resolution: resolution,
  );

  @override
  void cancelCodecJob() => service.cancelCodecJob();
}

/// [ImageCodecSettingsStore] backed by [AppSettingsService].
///
/// Replaces `PrefsImageCodecSettingsStore` now that the five `imageCodec*`
/// fields live on [AppSettings]; the JSON keys were already the same, so a
/// user upgrading keeps their model registry only if it was written through
/// this adapter — the old standalone `image_codec_settings` blob is not
/// migrated, because a placeholder-URL build cannot have produced one.
class AppSettingsImageCodecStore implements ImageCodecSettingsStore {
  final AppSettingsService _service;

  const AppSettingsImageCodecStore(this._service);

  @override
  ImageCodecPreferences get preferences => _service.settings.imageCodec;

  @override
  Future<void> load() async {
    // AppSettingsService.loadSettings() already ran in main().
  }

  @override
  Future<void> save(ImageCodecPreferences preferences) =>
      _service.setImageCodecPreferences(preferences);
}

/// An [ImageReassembler] that (a) learns the local sender prefix after
/// SELF_INFO and (b) forwards every outcome to [ReceivedImageStore] together
/// with the channel index.
///
/// Both exist because of upstream shapes this file cannot change:
///  * `ImageReassembler.selfPrefix` is `final`, but the local public key does
///    not exist until `RESP_CODE_SELF_INFO`, so a reassembler built here would
///    start with a null prefix and never be able to drop our own flood echo.
///    Overriding the getter is the smallest fix that does not touch the
///    transport; see the report's "needs from others".
///  * `ImageChunkOutcome` carries no channel index, so the connector's
///    `onImageChunk` callback cannot call `handleOutcome`, which requires one.
///    Intercepting `addChunk` — the only place the index is in scope — can.
class ImageStreamReassembler extends ImageReassembler {
  final ReceivedImageStore store;

  int? _selfPrefix;

  ImageStreamReassembler({required this.store})
    : super(onFailed: ((failure) => unawaited(store.handleFailure(failure))));

  @override
  int? get selfPrefix => _selfPrefix;

  set selfPrefix(int? value) => _selfPrefix = value;

  @override
  ImageChunkOutcome addChunk(
    Uint8List blob, {
    int channelIndex = 0,
    DateTime? now,
  }) {
    final outcome = super.addChunk(blob, channelIndex: channelIndex, now: now);
    unawaited(store.handleOutcome(outcome, channelIndex: channelIndex));
    return outcome;
  }
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
  static final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final MeshCoreConnector connector;
  final MessageRetryService retryService;
  final PathHistoryService pathHistoryService;
  final StorageService storage;
  final AppSettingsService appSettingsService;
  final BleDebugLogService bleDebugLogService;
  final AppDebugLogService appDebugLogService;
  final BackgroundService backgroundService;
  final MapTileCacheService mapTileCacheService;
  final ChatTextScaleService chatTextScaleService;
  final TranslationService translationService;
  final UiViewStateService uiViewStateService;
  final SettingsSectionsService settingsSectionsService;
  final TimeoutPredictionService timeoutPredictionService;
  final WardriveService wardriveService;
  final ImageCodecService imageCodecService;
  final ReceivedImageStore receivedImageStore;
  final ImageStreamReassembler imageReassembler;

  const MeshCoreApp({
    super.key,
    required this.connector,
    required this.retryService,
    required this.pathHistoryService,
    required this.storage,
    required this.appSettingsService,
    required this.bleDebugLogService,
    required this.appDebugLogService,
    required this.backgroundService,
    required this.mapTileCacheService,
    required this.chatTextScaleService,
    required this.translationService,
    required this.uiViewStateService,
    required this.settingsSectionsService,
    required this.timeoutPredictionService,
    required this.wardriveService,
    required this.imageCodecService,
    required this.receivedImageStore,
    required this.imageReassembler,
  });

  @override
  State<MeshCoreApp> createState() => _MeshCoreAppState();
}

/// How often abandoned image streams are swept.
///
/// `ImageReassembler.evictExpired` otherwise only runs from `addChunk`, so a
/// sender that stops mid-image would leave its bubble stuck on "2 of 3
/// packets" until some unrelated image arrived.
const Duration _kImageSweepInterval = Duration(seconds: 5);

class _MeshCoreAppState extends State<MeshCoreApp> with WidgetsBindingObserver {
  Timer? _imageSweepTimer;
  bool _hadReadyConnection = false;
  bool _recoveringConnection = false;
  bool _scannerNavigationScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settingsSectionsService.setUiContextProvider(
      () => MeshCoreApp._navigatorKey.currentContext,
    );
    widget.connector.addListener(_handleConnectionStateChanged);
    _hadReadyConnection = widget.connector.isSessionReady;
    if (_hadReadyConnection) {
      unawaited(widget.connector.resumePendingOutgoingMessages());
    } else {
      widget.connector.pausePendingOutgoingMessages();
    }
    _imageSweepTimer = Timer.periodic(
      _kImageSweepInterval,
      (_) => widget.imageReassembler.evictExpired(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        widget.backgroundService.ensureBatteryOptimizationExemption(
          reason: 'startup',
        ),
      );
    });
  }

  @override
  void dispose() {
    widget.connector.removeListener(_handleConnectionStateChanged);
    _imageSweepTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleConnectionStateChanged() {
    final connector = widget.connector;
    if (connector.isOfflineMode) {
      _scannerNavigationScheduled = false;
      return;
    }
    if (connector.wasManuallyDisconnected) {
      _hadReadyConnection = false;
      _recoveringConnection = false;
      _scheduleScannerNavigation();
      return;
    }
    if (connector.isConnected) {
      _scannerNavigationScheduled = false;
    }

    if (_hadReadyConnection &&
        !connector.isConnected &&
        !connector.isRecoveringConnection) {
      _hadReadyConnection = false;
      _recoveringConnection = false;
      MeshCoreApp._scaffoldMessengerKey.currentState?.clearSnackBars();
      _scheduleScannerNavigation();
      return;
    }

    if (_hadReadyConnection &&
        !connector.isConnected &&
        connector.isRecoveringConnection &&
        !_recoveringConnection) {
      _recoveringConnection = true;
      connector.pausePendingOutgoingMessages();
      _showConnectionSnackBar(
        isError: true,
        text: (l10n) => l10n.app_connectionLostReconnect,
      );
      return;
    }

    if (connector.hasCompletedSelfInfoHandshake && _recoveringConnection) {
      _recoveringConnection = false;
      _showConnectionSnackBar(
        isError: false,
        text: (l10n) => l10n.app_connectionLostReconnected,
      );
    }

    if (connector.isSessionReady) {
      _hadReadyConnection = true;
      unawaited(connector.resumePendingOutgoingMessages());
    }
  }

  void _scheduleScannerNavigation() {
    if (_scannerNavigationScheduled) return;
    _scannerNavigationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      MeshCoreApp._navigatorKey.currentState?.popUntil(
        (route) => route.isFirst,
      );
    });
  }

  void _showConnectionSnackBar({
    required bool isError,
    required String Function(AppLocalizations l10n) text,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = MeshCoreApp._navigatorKey.currentContext;
      final messenger = MeshCoreApp._scaffoldMessengerKey.currentState;
      if (context == null || messenger == null) return;
      final l10n = AppLocalizations.of(context);
      final content = Text(text(l10n));
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: isError
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: messenger.hideCurrentSnackBar,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: content,
                    ),
                  )
                : content,
            backgroundColor: isError ? Colors.red : Colors.green,
            padding: isError ? EdgeInsets.zero : null,
            duration: isError
                ? const Duration(days: 1)
                : const Duration(seconds: 4),
          ),
        );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(widget.backgroundService.logRuntimeState(state.name));
    }
    if (state == AppLifecycleState.resumed) {
      _refreshNotificationPermissionState();
    }
    widget.receivedImageStore.setForeground(state == AppLifecycleState.resumed);
    // The neural codec has a very high memory peak, so release its native
    // sessions whenever the app leaves the foreground.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(widget.imageCodecService.handleMemoryPressure());
      unawaited(widget.receivedImageStore.handleMemoryPressure());
    }
  }

  void _refreshNotificationPermissionState() {
    if (!PlatformInfo.isAndroid) {
      return;
    }
    final settings = widget.appSettingsService.settings;
    if (!settings.notificationsEnabled ||
        (!settings.notifyOnNewMessage && !settings.notifyOnNewChannelMessage)) {
      return;
    }
    unawaited(NotificationService().areNotificationsEnabled());
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    unawaited(widget.imageCodecService.handleMemoryPressure());
    unawaited(widget.receivedImageStore.handleMemoryPressure());
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
        ChangeNotifierProvider.value(value: widget.settingsSectionsService),
        Provider.value(value: widget.storage),
        ChangeNotifierProvider.value(value: widget.mapTileCacheService),
        ChangeNotifierProvider.value(value: widget.timeoutPredictionService),
        ChangeNotifierProvider.value(value: widget.wardriveService),
        ChangeNotifierProvider.value(value: widget.imageCodecService),
        ChangeNotifierProvider.value(value: widget.receivedImageStore),
      ],
      child: Consumer<AppSettingsService>(
        builder: (context, settingsService, child) {
          return MaterialApp(
            title: 'MeshCore Open (Advanced mod)',
            navigatorKey: MeshCoreApp._navigatorKey,
            scaffoldMessengerKey: MeshCoreApp._scaffoldMessengerKey,
            navigatorObservers: [appRouteObserver],
            debugShowCheckedModeBanner: false,
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...widget.settingsSectionsService.localizationsDelegates,
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

              final settings = settingsService.settings;
              Widget content = child ?? const SizedBox.shrink();

              // Global UI scale: multiply the user's factor on top of the
              // system text scale so accessibility settings are still honored.
              // Icons follow when enabled via IconThemeData.applyTextScaling.
              if (settings.uiScale != 1.0 || settings.uiScaleApplyToIcons) {
                final mediaQuery = MediaQuery.of(context);
                final systemScale = mediaQuery.textScaler.scale(1.0);
                final theme = Theme.of(context);
                content = MediaQuery(
                  data: mediaQuery.copyWith(
                    textScaler: TextScaler.linear(
                      systemScale * settings.uiScale,
                    ),
                  ),
                  child: Theme(
                    data: theme.copyWith(
                      iconTheme: theme.iconTheme.copyWith(
                        applyTextScaling: settings.uiScaleApplyToIcons,
                      ),
                      primaryIconTheme: theme.primaryIconTheme.copyWith(
                        applyTextScaling: settings.uiScaleApplyToIcons,
                      ),
                    ),
                    child: content,
                  ),
                );
              }

              content = EdgeSwipePop(
                navigatorKey: MeshCoreApp._navigatorKey,
                enabled: PlatformInfo.isMobile,
                child: content,
              );

              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: _systemUiOverlayStyle(context),
                child: content,
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
    if (navigator == null || MeshCoreApp._navigatorKey.currentContext == null) {
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
