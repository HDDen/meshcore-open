import 'dart:async';
import 'dart:io' show Directory, File, FileSystemException, Platform;
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../widgets/mco_image_message.dart';
import '../helpers/background_work_tracker.dart';
import '../helpers/gif_helper.dart';
import '../helpers/marker_message.dart';
import '../helpers/notification_background_work.dart';
import '../helpers/notification_conversation_work.dart';
import '../helpers/mcoimg_codec.dart';
import '../helpers/mcoimg_palette.dart';
import '../helpers/message_url_image_helper.dart';
import '../helpers/legacy_notification_registry.dart';
import '../helpers/reaction_helper.dart';
import '../helpers/windows_notification_identity.dart';
import '../l10n/app_localizations.dart';
import '../models/app_settings.dart';
import '../storage/data_root.dart';
import '../utils/app_logger.dart';
import '../storage/prefs_manager.dart';
import '../utils/platform_info.dart';
import 'notification_reply.dart';
import 'received_image_store.dart' show ReceivedImageRef;

typedef NotificationTapHandler = FutureOr<void> Function(String payload);

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  String _publicIpfsGateway = AppSettings.defaultPublicIpfsGateway;

  void setPublicIpfsGateway(String gateway) {
    _publicIpfsGateway = gateway.trim();
  }

  final _backgroundWork = NotificationBackgroundWork();
  // Serialize only battery show/cancel calls. A recovery/disconnect cancel
  // must run after an earlier native show, even when that show completes late.
  Future<void> _lowBatteryQueue = Future<void>.value();

  void attachBackgroundWorkTracker(BackgroundWorkTracker tracker) =>
      _backgroundWork.attach(tracker);

  void detachBackgroundWorkTracker(BackgroundWorkTracker tracker) =>
      _backgroundWork.detach(tracker);

  static const MethodChannel _settingsChannel = MethodChannel(
    'mco_advanced/notification_settings',
  );

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  NotificationTapHandler? _tapHandler;
  String? _pendingTapPayload;

  // Locale for localized notification strings
  Locale _locale = const Locale('en');

  /// Set the locale for notification strings (call when app locale changes)
  void setLocale(Locale locale) {
    _locale = locale;
    // The background action isolate reads this to localize its notices.
    try {
      PrefsManager.instance.setString(
        notificationLanguagePrefsKey,
        locale.languageCode,
      );
    } catch (_) {}
  }

  void setTapHandler(NotificationTapHandler handler) {
    _tapHandler = handler;
    final pendingPayload = _pendingTapPayload;
    if (pendingPayload == null) return;
    _pendingTapPayload = null;
    unawaited(Future<void>.sync(() => handler(pendingPayload)));
  }

  AppLocalizations get _l10n => lookupAppLocalizations(_locale);

  String? _selfName;

  /// Name of the connected radio, shown as the sender of your own replies.
  void setSelfName(String? name) {
    _selfName = name;
  }

  // Recent messages per conversation notification id, so each notification
  // shows the conversation (Android MessagingStyle, used by Android Auto).
  static const _maxConversationMessages = 6;
  final Map<int, _Conversation> _conversations = {};
  final _conversationWork = NotificationConversationWork();
  final _conversationPosts = <int, DateTime>{};
  final _conversationBatches = <int, _ConversationBatch>{};
  final _conversationRevisions = <int, int>{};
  int _conversationEpoch = 0;
  String? _radioKey;

  // Single-subscription so actions that arrive before the connector listens
  // (e.g. during startup) are buffered instead of dropped.
  final StreamController<NotificationReply> _replies =
      StreamController<NotificationReply>();
  ReceivePort? _replyPort;

  /// Reply, mark-as-read and mute actions taken on message notifications.
  /// Has a single listener (the connector).
  Stream<NotificationReply> get replies => _replies.stream;

  /// Stops receiving notification actions. The background handler then tells
  /// the user the app isn't running instead of forwarding to nobody.
  void releaseReplyPort() {
    if (_replyPort == null) return;
    IsolateNameServer.removePortNameMapping(notificationReplyPortName);
    _replyPort!.close();
    _replyPort = null;
  }

  String _logSafe(String value) {
    final sanitized = value.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ');
    return Uri.encodeComponent(sanitized);
  }

  // Rate limiting to prevent notification storms
  // (Added after getting notification-flooded while evaluating RF flood management. The irony.)
  static const _minNotificationInterval = Duration(seconds: 3);
  static const _batchWindow = Duration(seconds: 5);
  static const _conversationWindow = Duration(milliseconds: 800);

  DateTime? _lastNotificationTime;
  DateTime Function() _rateLimitNow = DateTime.now;
  final List<_PendingNotification> _pendingNotifications = [];
  bool _isBatchingActive = false;
  bool _suppressNotifications = false;

  /// Temporarily suppress all notifications (e.g., during sync)
  void suppressNotifications(bool suppress) {
    _suppressNotifications = suppress;
    if (suppress) {
      _pendingNotifications.clear();
      _dropPendingConversationUpdates();
    }
  }

  /// Часы только для проверки rate limit; по умолчанию используется DateTime.now.
  @visibleForTesting
  void setRateLimitClockForTest(DateTime Function() now) {
    _rateLimitNow = now;
  }

  /// Forgets the plugin, the permission answer, the tap handler and the
  /// rate limiter, so a test starts from a service nothing has used yet.
  @visibleForTesting
  void resetForTest() {
    _backgroundWork.detachAll();
    _isInitialized = false;
    _canNotify = null;
    _tapHandler = null;
    _pendingTapPayload = null;
    _lastNotificationTime = null;
    _rateLimitNow = DateTime.now;
    // A completed Future retains its zone. Start a fresh queue in this
    // test zone, rather than scheduling work in a previous FakeAsync zone.
    _lowBatteryQueue = Future<void>.value();
    _pendingNotifications.clear();
    _isBatchingActive = false;
    _suppressNotifications = false;
    _radioKey = null;
    _invalidateConversations();
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const macSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    // One identity per data folder, or a click on a toast may reach another
    // running copy of the app; see WindowsNotificationIdentity.
    final windowsIdentity = WindowsNotificationIdentity.forDataFolder(
      DataRoot.mode == DataRootMode.portable ? DataRoot.path : null,
      appName: 'MeshCore Open',
    );
    final windowsSettings = WindowsInitializationSettings(
      appName: windowsIdentity.displayName,
      appUserModelId: windowsIdentity.appUserModelId,
      guid: windowsIdentity.guid,
    );
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open notification',
    );

    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: macSettings,
      windows: windowsSettings,
      linux: linuxSettings,
    );

    // On Linux, the notifications plugin opens a D-Bus session bus
    // connection whose async subscription can throw an unhandled
    // SocketException when the bus socket is missing (e.g. running as
    // root or inside a container without a session bus).
    if (PlatformInfo.isLinux && !_isDbusSessionAvailable()) {
      debugPrint('Skipping notification init: D-Bus session bus unavailable');
      return;
    }

    try {
      await _notifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
        onDidReceiveBackgroundNotificationResponse:
            notificationActionBackgroundHandler,
      );
      _registerReplyPort();
      _isInitialized = true;
      await _handleLaunchNotificationTap();
    } catch (e) {
      debugPrint('Error initializing notifications: $e');
      return;
    }
    if (PlatformInfo.isWindows &&
        windowsIdentity.guid != WindowsNotificationIdentity.legacyGuid) {
      unawaited(_removeLegacyNotificationIdentity());
    }
  }

  /// The registry entries of the identity earlier builds used go once no
  /// such build is running; nothing waits for the answer.
  Future<void> _removeLegacyNotificationIdentity() async {
    try {
      final outcome = await LegacyNotificationRegistry.removeWhenUnused();
      if (outcome != LegacyNotificationCleanup.absent) {
        appLogger.info(
          'Legacy notification identity ${outcome.name}',
          tag: 'Notifications',
        );
      }
    } catch (error) {
      appLogger.warn(
        'Legacy notification identity not removed: $error',
        tag: 'Notifications',
      );
    }
  }

  Future<void> _handleLaunchNotificationTap() async {
    try {
      final launchDetails = await _notifications
          .getNotificationAppLaunchDetails();
      final response = launchDetails?.notificationResponse;
      final payload = response?.payload;
      if (launchDetails?.didNotificationLaunchApp == true &&
          payload != null &&
          payload.isNotEmpty) {
        _dispatchNotificationTapPayload(payload);
      }
    } catch (e) {
      debugPrint('Failed to read launch notification payload: $e');
    }
  }

  void _registerReplyPort() {
    if (kIsWeb || _replyPort != null) return;
    final port = ReceivePort();
    IsolateNameServer.removePortNameMapping(notificationReplyPortName);
    IsolateNameServer.registerPortWithName(
      port.sendPort,
      notificationReplyPortName,
    );
    port.listen((dynamic message) {
      if (message is! Map) return;
      _dispatchAction(
        actionId: message['actionId'] as String?,
        payload: message['payload'] as String?,
        input: message['input'] as String?,
      );
    });
    _replyPort = port;
  }

  void _dispatchAction({
    required String? actionId,
    required String? payload,
    String? input,
  }) {
    final reply = NotificationReply.parse(
      actionId: actionId,
      payload: payload,
      input: input,
    );
    if (reply != null) _replies.add(reply);
  }

  static bool _isDbusSessionAvailable() {
    final addr = Platform.environment['DBUS_SESSION_BUS_ADDRESS'];
    if (addr != null && addr.isNotEmpty) return true;
    // Fallback: check the default socket for the current user.
    final uid = Platform.environment['UID'] ?? Platform.environment['EUID'];
    final path = '/run/user/${uid ?? '1000'}/bus';
    return File(path).existsSync();
  }

  Future<bool> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
    return _isInitialized;
  }

  // Cached "are we allowed to post notifications" result. Null = not yet
  // determined. A positive Android grant can be cached, but a denied state is
  // rechecked because the user can enable notifications in system settings
  // while the app is running.
  bool? _canNotify;
  static const _permissionRequestedKey = 'notification_permission_requested';

  Future<bool> _ensureCanNotify() async {
    if (!await _ensureInitialized()) {
      return false;
    }
    final cached = _canNotify;
    if (cached == true) {
      return true;
    }
    if (cached == false && !PlatformInfo.isAndroid) {
      return false;
    }

    // flutter_local_notifications has no web backend, so show() always throws.
    // Skip silently instead of logging an error per incoming message.
    if (kIsWeb) return _canNotify = false;

    // On Android 13+ notifications require an explicit grant; reflect the real
    // OS state so we don't spam failed show() calls when denied.
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      final enabled = await androidPlugin.areNotificationsEnabled() ?? false;
      if (enabled) _canNotify = true;
      return enabled;
    }

    // iOS/macOS request permission during initialize(); desktop has no gate.
    return _canNotify = true;
  }

  Future<bool> areNotificationsEnabled() async {
    if (!await _ensureInitialized()) return false;
    if (kIsWeb) return false;

    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      final enabled = await androidPlugin.areNotificationsEnabled();
      _canNotify = enabled ?? false;
      return _canNotify!;
    }

    return true;
  }

  Future<void> openAppNotificationSettings() async {
    if (!PlatformInfo.isAndroid) return;
    await _settingsChannel.invokeMethod<void>('openNotificationSettings');
  }

  Future<bool> requestPermissions() async {
    if (!_isInitialized) {
      await initialize();
    }

    // Request Android 13+ notification permission
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      if (granted == true) _canNotify = true;
      return granted ?? false;
    }

    // iOS permissions are requested during initialization
    final iosPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (iosPlugin != null) {
      final granted = await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      if (granted == true) _canNotify = true;
      return granted ?? false;
    }

    return true;
  }

  /// Asks for the Android 13+ notification permission the first time it is
  /// needed. Never re-prompts after the user has answered once; iOS/macOS
  /// already prompt during [initialize].
  Future<void> requestPermissionsOnce() async {
    if (!PlatformInfo.isAndroid || !await _ensureInitialized()) return;
    final prefs = PrefsManager.instance;
    if (prefs.getBool(_permissionRequestedKey) ?? false) return;
    if (await _ensureCanNotify()) return;
    await prefs.setBool(_permissionRequestedKey, true);
    await requestPermissions();
  }

  /// Summarize structured messages using the same parsers as the chat.
  /// This does not load image bytes, resolve URLs or initialize a decoder.
  static String formatNotificationText(String text, AppLocalizations l10n) {
    final trimmed = text.trim();
    final reaction = ReactionHelper.parseReaction(trimmed);
    if (reaction != null) {
      return l10n.notification_reacted(reaction.emoji);
    }
    if (ReceivedImageRef.parse(trimmed) != null) {
      return l10n.notification_sentImage;
    }
    if (GifHelper.parseGif(trimmed) != null) {
      return l10n.notification_sentGif;
    }
    if (isMcoImageNotificationText(trimmed)) {
      return 'MCOimg';
    }
    final marker = parseMarkerText(trimmed);
    if (marker != null) {
      return marker.label.isEmpty
          ? l10n.notification_sharedLocation
          : l10n.notification_sharedLocationNamed(marker.label);
    }
    return text;
  }

  static bool isMcoImageNotificationText(String text) {
    return _mcoImagePayloadTextForNotification(text) != null;
  }

  static String? _mcoImagePayloadTextForNotification(String text) {
    final trimmed = text.trim();
    if (MCOImageMessage.decodeMetadata(trimmed).image != null) {
      return trimmed;
    }
    final separatorIndex = trimmed.indexOf(': ');
    if (separatorIndex <= 0 || separatorIndex + 2 >= trimmed.length) {
      return null;
    }
    final messageText = trimmed.substring(separatorIndex + 2).trimLeft();
    if (MCOImageMessage.decodeMetadata(messageText).image != null) {
      return messageText;
    }
    return null;
  }

  Future<_MCOImageNotificationAttachment?> _tryBuildMcoImageAttachment(
    String text,
  ) async {
    try {
      final imageText = _mcoImagePayloadTextForNotification(text);
      if (imageText == null) return null;
      final image = MCOImageMessage.decodeMetadata(imageText).image;
      if (image == null) return null;
      final bytes = await MCOImageMessage.renderPngBytes(image, cellSize: 1);
      final rawIcon = _linuxRawIconDataFor(image);
      String? filePath;
      // Apple's attachment and the Windows toast take the picture as a file;
      // Android and Linux take the bytes.
      if (!kIsWeb &&
          (PlatformInfo.isIOS ||
              PlatformInfo.isMacOS ||
              PlatformInfo.isWindows)) {
        final directory = await getTemporaryDirectory();
        final timestamp = DateTime.now().microsecondsSinceEpoch;
        final file = File(
          '${directory.path}/$_notificationImagePrefix$timestamp.png',
        );
        await file.writeAsBytes(bytes, flush: true);
        filePath = file.path;
        unawaited(_deleteStaleNotificationImages(directory));
      }
      return _MCOImageNotificationAttachment(
        bytes: bytes,
        filePath: filePath,
        linuxRawIcon: rawIcon,
      );
    } catch (error) {
      debugPrint('Failed to build MCOimg notification attachment: $error');
      return null;
    }
  }

  /// The system moves an Apple attachment into its own store, but Windows
  /// reads the file when the toast is shown and can show the toast again
  /// from the action centre, so a picture stays for a day and the next
  /// MCOimg notification deletes what is older.
  static const String _notificationImagePrefix = 'mcoimg_notification_';
  static const Duration _notificationImageLifetime = Duration(hours: 24);

  Future<void> _deleteStaleNotificationImages(Directory directory) async {
    try {
      final cutoff = DateTime.now().subtract(_notificationImageLifetime);
      await for (final entry in directory.list()) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        if (!name.startsWith(_notificationImagePrefix) ||
            !name.endsWith('.png')) {
          continue;
        }
        try {
          if ((await entry.lastModified()).isAfter(cutoff)) continue;
          await entry.delete();
        } on FileSystemException {
          // Gone already, or still open by a toast: the next sweep sees it.
        }
      }
    } catch (error) {
      debugPrint(
        'Failed to delete stale MCOimg notification pictures: $error',
      );
    }
  }

  List<DarwinNotificationAttachment>? _darwinAttachmentsFor(
    _MCOImageNotificationAttachment? attachment, {
    String? imagePath,
  }) {
    final filePath = attachment?.filePath ?? imagePath;
    if (filePath == null) {
      return null;
    }
    return [DarwinNotificationAttachment(filePath)];
  }

  LinuxNotificationDetails? _linuxDetailsFor(
    _MCOImageNotificationAttachment? attachment,
  ) {
    final rawIcon = attachment?.linuxRawIcon;
    if (rawIcon == null) {
      return null;
    }
    return LinuxNotificationDetails(icon: ByteDataLinuxIcon(rawIcon));
  }

  WindowsNotificationDetails? _windowsDetailsFor(
    _MCOImageNotificationAttachment? attachment,
  ) {
    final filePath = attachment?.filePath;
    if (filePath == null) {
      return null;
    }
    return WindowsNotificationDetails(
      images: [
        WindowsImage(
          Uri.file(filePath, windows: true),
          altText: 'MCOimg',
          placement: WindowsImagePlacement.appLogoOverride,
        ),
      ],
    );
  }

  LinuxRawIconData _linuxRawIconDataFor(MCOImage image) {
    final palette = image.paletteProfile.isDynamic
        ? MCOImageDynamicPalette.global512
        : MCOImagePalette.colorsFor(image.paletteProfile);
    final data = Uint8List(image.width * image.height * 4);
    for (var i = 0; i < image.pixels.length; i++) {
      final pixel = image.pixels[i];
      final color = _colorForMcoPixel(image, pixel, palette);
      final offset = i * 4;
      data[offset] = _colorChannelToByte(color.r);
      data[offset + 1] = _colorChannelToByte(color.g);
      data[offset + 2] = _colorChannelToByte(color.b);
      data[offset +
          3] = image.transparentColor != null && pixel == image.transparentColor
          ? 0
          : _colorChannelToByte(color.a);
    }
    return LinuxRawIconData(
      data: data,
      width: image.width,
      height: image.height,
      channels: 4,
      hasAlpha: true,
    );
  }

  Color _colorForMcoPixel(MCOImage image, int pixel, List<Color> palette) {
    if (image.paletteProfile.isDynamic) {
      if (pixel < 0 ||
          pixel >= MCOImageDynamicPalette.global512.length ||
          MCOImageDynamicPalette.profileColorIdForGlobalIndex(
                image.paletteProfile,
                pixel,
              ) ==
              null) {
        final whiteIndex = MCOImagePalette.whiteIndexFor(image.paletteProfile);
        return MCOImageDynamicPalette.global512[whiteIndex];
      }
      return MCOImageDynamicPalette.global512[pixel];
    }
    if (pixel < 0 || pixel >= palette.length) {
      return const Color(0x00000000);
    }
    return palette[pixel];
  }

  int _colorChannelToByte(double value) {
    return (value * 255.0).round().clamp(0, 255).toInt();
  }

  // The notification is shown off the receive path, so this bounds only how
  // long a notification waits for its picture before it goes out without one.
  static const Duration _notificationImageTimeout = Duration(seconds: 5);

  Future<String?> _resolveNotificationImagePath(
    String text, {
    required bool urlImagesEnabled,
  }) async {
    if (!urlImagesEnabled || !MessageUrlImageHelper.loadLinkImages.value) return null;

    final imageUrl = await MessageUrlImageHelper.parseVerified(text, publicGateway: _publicIpfsGateway);
    if (imageUrl == null || !MessageUrlImageHelper.loadLinkImages.value) return null;

    try {
      // Cache the image so notification platforms can read it from disk.
      final imageFile = await DefaultCacheManager().getSingleFile(imageUrl);
      if (!MessageUrlImageHelper.loadLinkImages.value || !imageFile.existsSync()) return null;
      return imageFile.path;
    } catch (e) {
      debugPrint('Failed to resolve notification image: $e');
      return null;
    }
  }

  List<AndroidNotificationAction> _conversationActions(bool isChannel) => [
    AndroidNotificationAction(
      notificationReplyActionId,
      _l10n.notification_actionReply,
      inputs: [
        AndroidNotificationActionInput(label: _l10n.notification_replyHint),
      ],
      semanticAction: SemanticAction.reply,
      allowGeneratedReplies: true,
      cancelNotification: false,
    ),
    AndroidNotificationAction(
      notificationMarkReadActionId,
      _l10n.notification_actionMarkRead,
      semanticAction: SemanticAction.markAsRead,
      invisible: true,
    ),
    if (isChannel)
      AndroidNotificationAction(
        notificationMuteActionId,
        _l10n.notification_actionMuteChannel,
        semanticAction: SemanticAction.mute,
      ),
  ];

  // Always MessagingStyle: Android Auto only handles messaging notifications
  // in that style, so an image preview is shown as the large icon instead.
  AndroidNotificationDetails _androidConversationDetails(
    _Conversation conversation, {
    int? badgeCount,
    bool silent = false,
  }) {
    final imagePath = conversation.imagePath;
    final mcoAttachment = conversation.mcoAttachment;
    return AndroidNotificationDetails(
      conversation.isChannel ? 'channel_messages' : 'messages',
      conversation.isChannel ? 'Channel Messages' : 'Messages',
      channelDescription: conversation.isChannel
          ? 'New channel message notifications'
          : 'New message notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      number: badgeCount,
      silent: silent,
      category: AndroidNotificationCategory.message,
      // MessagingStyle leaves no room for a big picture, so an MCOimg or a
      // URL image rides as the large icon.
      largeIcon: mcoAttachment != null
          ? ByteArrayAndroidBitmap(mcoAttachment.bytes)
          : imagePath != null
          ? FilePathAndroidBitmap(imagePath)
          : null,
      styleInformation: MessagingStyleInformation(
        Person(key: 'self', name: _selfName ?? _l10n.notification_you),
        conversationTitle: conversation.isChannel ? conversation.title : null,
        groupConversation: conversation.isChannel,
        messages: List<Message>.of(conversation.messages),
      ),
      actions: _conversationActions(conversation.isChannel),
    );
  }

  DarwinNotificationDetails _darwinDetails(
    String? imagePath,
    int? badge, [
    _MCOImageNotificationAttachment? attachment,
    bool silent = false,
  ]) => DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: !silent,
    badgeNumber: badge,
    attachments: _darwinAttachmentsFor(attachment, imagePath: imagePath),
  );

  Future<void> _showConversationNotificationImpl({
    required int id,
    required String payload,
    required List<_PendingNotification> updates,
    required bool Function() isCurrent,
    required bool silent,
  }) async {
    if (!isCurrent() || !await _ensureCanNotify() || !isCurrent()) return;
    final latest = updates.last;
    final title = latest.title;
    final isChannel = latest.type == _NotificationType.channelMessage;
    final message = latest.body;
    final mcoAttachment = await _tryBuildMcoImageAttachment(message);
    if (!isCurrent()) return;
    final imagePath = mcoAttachment == null
        ? await _resolveNotificationImagePath(
            message,
            urlImagesEnabled: latest.urlImagesEnabled,
          ).timeout(_notificationImageTimeout, onTimeout: () => null)
        : null;
    if (!isCurrent()) return;
    final badgeCount = latest.currentUnreadTotal?.call() ?? latest.badgeCount;

    final conversation =
        _conversations.putIfAbsent(
            id,
            () => _Conversation(
              title: title,
              payload: payload,
              isChannel: isChannel,
            ),
          )
          ..title = title
          ..badgeCount = badgeCount
          ..imagePath = imagePath
          ..mcoAttachment = mcoAttachment;
    for (final update in updates) {
      final preview = identical(update, latest) && mcoAttachment != null
          ? 'MCOimg'
          : formatNotificationText(update.body.trim(), _l10n);
      final sender = isChannel ? (update.senderName ?? update.title) : update.title;
      conversation.add(
        Message(
          preview.isEmpty ? _l10n.notification_receivedNewMessage : preview,
          update.receivedAt,
          Person(key: isChannel ? 'sender:$sender' : payload, name: sender),
        ),
        _maxConversationMessages,
      );
    }

    final notificationDetails = NotificationDetails(
      android: _androidConversationDetails(
        conversation,
        badgeCount: badgeCount,
        silent: silent,
      ),
      iOS: _darwinDetails(imagePath, badgeCount, mcoAttachment, silent),
      macOS: _darwinDetails(imagePath, badgeCount, mcoAttachment, silent),
      linux: _linuxDetailsFor(mcoAttachment),
      windows: _windowsDetailsFor(mcoAttachment),
    );

    try {
      await _notifications.show(
        id: id,
        title: title,
        body: _collapsedBody(conversation),
        notificationDetails: notificationDetails,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Failed to show message notification: $e');
    }
  }

  /// Text shown when the notification is collapsed. Channel messages keep
  /// the sender prefix, including after your own reply.
  String _collapsedBody(_Conversation conversation) {
    final last = conversation.messages.last;
    if (!conversation.isChannel) return last.text;
    final sender = last.person?.name ?? _selfName ?? _l10n.notification_you;
    return '$sender: ${last.text}';
  }

  int _conversationId(NotificationReply reply) => reply.isChannel
      ? reply.channelIndex!.hashCode
      : reply.contactKeyHex!.hashCode;

  Future<void> _runConversationAction(
    NotificationReply reply,
    Future<void> Function(int id) action,
  ) {
    final id = _conversationId(reply);
    _flushConversation(id, beforeAction: true);
    final revision = _conversationRevision(id);
    return _conversationWork.run(id, () async {
      if (revision != _conversationRevision(id)) return;
      await _backgroundWork.run(() => action(id));
    });
  }

  /// Adds the user's reply to the conversation notification. Android keeps
  /// showing a progress spinner on a replied notification until it is updated.
  /// Pass the current [badgeCount]: an update replaces the whole notification,
  /// and the Android launcher badge comes from the notification number.
  Future<void> showOwnReply(
    NotificationReply reply,
    String text, {
    int? badgeCount,
  }) => _runConversationAction(reply, (id) async {
    if (!await _ensureInitialized()) return;
    final conversation = _conversations[id];
    if (conversation == null) {
      await _notifications.cancel(id: id);
      return;
    }
    conversation.badgeCount = badgeCount ?? conversation.badgeCount;
    conversation.add(
      Message(text, DateTime.now(), null),
      _maxConversationMessages,
    );
    await _repostConversation(id, conversation);
  });

  /// Tells the user a notification reply could not be sent.
  Future<void> showReplyFailed(
    NotificationReply reply,
    NotificationReplyFailure failure, {
    int? badgeCount,
  }) => _runConversationAction(reply, (id) async {
    if (!await _ensureInitialized()) return;
    final reason = switch (failure) {
      NotificationReplyFailure.notConnected =>
        _l10n.notification_replyNotConnected,
      NotificationReplyFailure.unavailable =>
        _l10n.notification_replyUnavailable,
      NotificationReplyFailure.tooLong => _l10n.notification_replyTooLong,
      NotificationReplyFailure.sendFailed => _l10n.notification_replySendFailed,
    };
    final conversation = _conversations[id];
    if (conversation != null) {
      conversation.badgeCount = badgeCount ?? conversation.badgeCount;
      await _repostConversation(id, conversation);
    } else {
      await _notifications.cancel(id: id);
    }
    try {
      await _notifications.show(
        id: 'reply_failed:$id'.hashCode,
        title: _l10n.notification_replyFailedTitle,
        body: reason,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'messages',
            'Messages',
            channelDescription: 'New message notifications',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
        payload: conversation?.payload,
      );
    } catch (e) {
      debugPrint('Failed to show reply failure notification: $e');
    }
  });

  Future<void> _repostConversation(int id, _Conversation conversation) async {
    try {
      await _notifications.show(
        id: id,
        title: conversation.title,
        body: _collapsedBody(conversation),
        notificationDetails: NotificationDetails(
          android: _androidConversationDetails(
            conversation,
            badgeCount: conversation.badgeCount,
            silent: true,
          ),
        ),
        payload: conversation.payload,
      );
    } catch (e) {
      debugPrint('Failed to update message notification: $e');
    }
  }

  Future<void> _showAdvertNotificationImpl({
    required String contactName,
    required String contactType,
    String? contactId,
  }) async {
    if (!await _ensureCanNotify()) return;

    const androidDetails = AndroidNotificationDetails(
      'adverts',
      'Advertisements',
      channelDescription: 'New node advertisement notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const macDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: macDetails,
    );

    try {
      await _notifications.show(
        id: contactId != null
            ? 'advert:$contactId'.hashCode
            : DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF,
        title: _l10n.notification_newTypeDiscovered(contactType),
        body: contactName,
        notificationDetails: notificationDetails,
        payload: 'advert:$contactId',
      );
    } catch (e) {
      debugPrint('Failed to show advert notification: $e');
    }
  }

  /// Posts a low-battery alert for the connected device.
  ///
  /// Uses a per-device, per-threshold notification id so each alert level
  /// updates its own notification instead of stacking, and alerts for
  /// different radios don't overwrite each other. Bypasses the rate-limit
  /// queue, which only handles message and advert notifications.
  Future<void> showLowBatteryNotification({
    required String deviceKey,
    required String deviceName,
    required int batteryPercent,
    required int threshold,
    bool Function()? isStillAllowed,
  }) => _backgroundWork.run(() {
    final operation = _lowBatteryQueue.then<void>((_) async {
      try {
        if (!await _ensureCanNotify()) {
          return;
        }
        if (!(isStillAllowed?.call() ?? true)) return;
        const notificationDetails = NotificationDetails(
          android: AndroidNotificationDetails(
            'low_battery',
            'Low Battery',
            channelDescription: 'Low battery alerts for the connected device',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          ),
          macOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          ),
        );
        await _notifications.show(
          id: _lowBatteryNotificationId(deviceKey, threshold),
          title: _l10n.notification_lowBatteryTitle,
          body: _l10n.notification_lowBatteryBody(deviceName, batteryPercent),
          notificationDetails: notificationDetails,
          payload: 'low_battery',
        );
      } catch (error) {
        debugPrint('Failed to show low battery notification: $error');
      }
    });
    _lowBatteryQueue = operation;
    return operation;
  });

  /// Returns a privacy-safe identifier for debug logging.
  /// - advert: shows device name (body contains contactName)
  /// - message: shows "from: sender" (avoids logging message content)
  /// - channelMessage: shows "in: channel" (avoids logging message content)
  String _getNotificationIdentifier(_PendingNotification n) {
    switch (n.type) {
      case _NotificationType.advert:
        return _logSafe(n.body);
      case _NotificationType.message:
        return 'from: ${_logSafe(n.title)}';
      case _NotificationType.channelMessage:
        return 'in: ${_logSafe(n.title)}';
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) {
      debugPrint('Notification tapped: $payload');
      _dispatchNotificationTapPayload(payload);
    }
  }

  void _dispatchNotificationTapPayload(String payload) {
    final handler = _tapHandler;
    if (handler == null) {
      _pendingTapPayload = payload;
      return;
    }
    unawaited(Future<void>.sync(() => handler(payload)));
  }

  void _dropPendingConversationUpdates() {
    for (final batch in _conversationBatches.values) {
      batch.timer.cancel();
    }
    _conversationBatches.clear();
    _conversationPosts.clear();
  }

  void _invalidateConversations() {
    _conversationEpoch++;
    _conversationRevisions.clear();
    _dropPendingConversationUpdates();
    _conversations.clear();
  }

  Future<void> cancelAll() {
    _invalidateConversations();
    return _conversationWork.run(null, () => _backgroundWork.run(() async {
      await _notifications.cancelAll();
      await _updateBadge(0);
    }));
  }

  static const _radioKeyPrefsKey = 'notifications_radio_key';
  static const _licenseExpiryNotificationId = 0x4d434f4c;

  /// Discard the previous node's conversation notifications. The key lives
  /// in the current application profile, including portable profiles.
  Future<void> bindRadio(
    String radioKey, {
    int Function()? currentUnreadTotal,
  }) async {
    if (radioKey.isEmpty || _radioKey == radioKey) return;
    String? previous = _radioKey;
    try {
      previous ??= PrefsManager.instance.getString(_radioKeyPrefsKey);
    } catch (_) {}
    _radioKey = radioKey;
    if (previous != null && previous != radioKey) {
      final ids = {..._conversations.keys, ..._conversationPosts.keys};
      _pendingTapPayload = null;
      _lastNotificationTime = null;
      _invalidateConversations();
      await _conversationWork.run(null, () => _backgroundWork.run(() async {
        if (!await _ensureInitialized()) return;
        try {
          final active = await _notifications.getActiveNotifications();
          for (final notification in active) {
            final id = notification.id;
            final payload = notification.payload ?? '';
            // The Windows plugin only returns IDs from its own toast history.
            final windowsToast = PlatformInfo.isWindows &&
                notification.title == null && notification.channelId == null;
            if (id != null &&
                id != _licenseExpiryNotificationId &&
                (notification.channelId == 'messages' ||
                    notification.channelId == 'channel_messages' ||
                    payload.startsWith('message:') ||
                    payload.startsWith('channel:') ||
                    windowsToast)) {
              ids.add(id);
            }
          }
        } catch (e) {
          debugPrint('Could not list notifications for the previous radio: $e');
        }
        for (final id in ids) {
          try {
            await _notifications.cancel(id: id);
          } catch (e) {
            debugPrint('Could not clear conversation notification: $e');
          }
        }
        await _updateBadge(currentUnreadTotal?.call() ?? 0);
      }));
    }
    if (_radioKey != radioKey) return;
    try {
      await PrefsManager.instance.setString(_radioKeyPrefsKey, radioKey);
    } catch (_) {}
  }

  Future<void> cancel(int id) => _backgroundWork.run(() async {
    await _notifications.cancel(id: id);
  });

  Future<bool> showLicenseExpiryNotification({
    required String title,
    required String body,
  }) async {
    if (!await _ensureCanNotify()) return false;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'license_expiry',
        'License expiry',
        channelDescription: 'License expiration reminders',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(presentAlert: true),
      macOS: DarwinNotificationDetails(presentAlert: true),
    );
    try {
      await _notifications.show(
        id: _licenseExpiryNotificationId,
        title: title,
        body: body,
        notificationDetails: details,
      );
      return true;
    } catch (error) {
      debugPrint('Failed to show license expiry notification: $error');
      return false;
    }
  }

  /// Cancel the notification for a specific contact and update the app badge.
  Future<void> clearContactNotification(
    String contactId,
    int totalUnreadCount,
  ) => _clearConversation(contactId.hashCode, totalUnreadCount);

  /// Cancel the notification for a specific channel and update the app badge.
  Future<void> clearChannelNotification(
    int channelIndex,
    int totalUnreadCount,
  ) => _clearConversation(channelIndex.hashCode, totalUnreadCount);

  Future<void> _clearConversation(int id, int totalUnreadCount) {
    _conversationRevisions.update(id, (value) => value + 1, ifAbsent: () => 1);
    _conversationBatches.remove(id)?.timer.cancel();
    _conversationPosts.remove(id);
    _conversations.remove(id);
    return _conversationWork.run(id, () => _backgroundWork.run(() async {
      if (!await _ensureInitialized()) return;
      await _notifications.cancel(id: id);
      await _updateBadge(totalUnreadCount);
    }));
  }

  static int _lowBatteryNotificationId(String deviceKey, int threshold) =>
      'low_battery:$deviceKey:$threshold'.hashCode;

  /// Cancel a device's low-battery notifications for the given thresholds.
  Future<void> clearLowBatteryNotifications(
    String deviceKey,
    Iterable<int> thresholds,
  ) {
    final toClear = thresholds.toList(growable: false);
    return _backgroundWork.run(() {
      final operation = _lowBatteryQueue.then<void>((_) async {
        try {
          if (!await _ensureInitialized()) {
            return;
          }
          for (final threshold in toClear) {
            try {
              await _notifications.cancel(
                id: _lowBatteryNotificationId(deviceKey, threshold),
              );
            } catch (error) {
              debugPrint('Failed to clear low battery notification: $error');
            }
          }
        } catch (error) {
          debugPrint('Failed to prepare low battery cleanup: $error');
        }
      });
      _lowBatteryQueue = operation;
      return operation;
    });
  }

  /// Cancel advert notifications for the given contact public key hexes.
  Future<void> clearAdvertNotifications(List<String> contactIds) => _backgroundWork.run(() async {
    if (!await _ensureInitialized()) return;
    for (final id in contactIds) {
      await _notifications.cancel(id: 'advert:$id'.hashCode);
    }
  });

  static const MethodChannel _badgeChannel = MethodChannel(
    'meshcore_open/app_badge',
  );

  /// Sets the app icon badge to the current unread total.
  Future<void> setAppBadge(int count) => _updateBadge(count);

  Future<void> _updateBadge(int count) async {
    if (PlatformInfo.isIOS || PlatformInfo.isMacOS) {
      // Set natively: a silent notification cancelled right after show() is
      // removed before iOS delivers it, so its badge number never applied.
      try {
        await _badgeChannel.invokeMethod<void>('setBadgeCount', count);
      } catch (e) {
        debugPrint('Failed to update app badge: $e');
      }
    }
    // On Android, badge count is derived from active notifications,
    // so cancelling the specific notification above is sufficient.
  }

  // ─────────────────────────────────────────────────────────────────
  // Public notification methods (rate limiting is enforced automatically)
  // ─────────────────────────────────────────────────────────────────

  Future<void> showMessageNotification({
    required String contactName,
    required String message,
    required bool urlImagesEnabled,
    String? contactId,
    int? badgeCount,
    int Function()? currentUnreadTotal,
    NotificationQueueAlert? queueAlert,
  }) async {
    if (_suppressNotifications) return;

    await _queueNotification(
      _PendingNotification(
        type: _NotificationType.message,
        title: contactName,
        body: message,
        urlImagesEnabled: urlImagesEnabled,
        id: contactId,
        badgeCount: badgeCount,
        currentUnreadTotal: currentUnreadTotal,
        queueAlert: queueAlert,
      ),
    );
  }

  Future<void> showAdvertNotification({
    required String contactName,
    required String contactType,
    String? contactId,
  }) async {
    if (_suppressNotifications) return;

    await _queueNotification(
      _PendingNotification(
        type: _NotificationType.advert,
        title: contactType,
        body: contactName,
        id: contactId,
      ),
    );
  }

  Future<void> showChannelMessageNotification({
    required String channelName,
    required String senderName,
    required String message,
    required bool urlImagesEnabled,
    int? channelIndex,
    int? badgeCount,
    int Function()? currentUnreadTotal,
    NotificationQueueAlert? queueAlert,
  }) async {
    if (_suppressNotifications) return;

    await _queueNotification(
      _PendingNotification(
        type: _NotificationType.channelMessage,
        title: channelName,
        body: message,
        senderName: senderName,
        urlImagesEnabled: urlImagesEnabled,
        id: channelIndex?.toString(),
        badgeCount: badgeCount,
        currentUnreadTotal: currentUnreadTotal,
        queueAlert: queueAlert,
      ),
    );
  }

  Future<void> _queueNotification(_PendingNotification notification) async {
    final now = _rateLimitNow();
    if (notification.type != _NotificationType.advert) {
      _queueConversation(notification, now);
      return;
    }
    final throttled =
        _lastNotificationTime != null &&
        now.difference(_lastNotificationTime!) < _minNotificationInterval;

    // If we recently showed a notification, start batching
    if (throttled) {
      _pendingNotifications.add(notification);
      debugPrint(
        '[Notification] queued: ${notification.type.name} (${_getNotificationIdentifier(notification)})',
      );

      // Start batch timer if not already running
      if (!_isBatchingActive) {
        _isBatchingActive = true;
        Future.delayed(_batchWindow, _processBatch);
      }
      return;
    }

    // Show immediately if enough time has passed
    debugPrint(
      '[Notification] sent immediately: ${notification.type.name} (${_getNotificationIdentifier(notification)})',
    );
    _lastNotificationTime = now;
    await _showAdvertInBackground(notification);
  }

  void _queueConversation(_PendingNotification update, DateTime now) {
    final id = update.conversationId;
    if (id == null) {
      _postConversation(update.type == _NotificationType.message
          ? 0
          : now.millisecondsSinceEpoch & 0x7FFFFFFF, [update]);
      return;
    }
    final batch = _conversationBatches[id];
    if (batch != null) {
      batch.add(update, _maxConversationMessages);
      return;
    }
    final lastPost = _conversationPosts[id];
    final remaining = lastPost?.add(_conversationWindow).difference(now) ??
        Duration.zero;
    if (remaining <= Duration.zero && _conversationWork.pendingFor(id) == null) {
      _conversationPosts[id] = now;
      _postConversation(id, [update]);
      return;
    }
    _conversationBatches[id] = _ConversationBatch(
      Timer(remaining.isNegative ? Duration.zero : remaining,
          () => _flushConversation(id)),
      [update],
    );
  }

  void _flushConversation(int id, {bool beforeAction = false}) {
    final batch = _conversationBatches[id];
    if (batch == null) return;
    batch.timer.cancel();
    final pending = _conversationWork.pendingFor(id);
    if (!beforeAction && pending != null) {
      // Keep replacing the same bounded batch while a slow show finishes.
      unawaited(pending.then((_) {
        if (identical(_conversationBatches[id], batch)) _flushConversation(id);
      }));
      return;
    }
    _conversationBatches.remove(id);
    _conversationPosts[id] = _rateLimitNow();
    _postConversation(id, batch.updates);
  }

  (int, int) _conversationRevision(int id) =>
      (_conversationEpoch, _conversationRevisions[id] ?? 0);

  void _postConversation(int id, List<_PendingNotification> updates) {
    final now = _rateLimitNow();
    final latest = updates.last;
    final queueAlert = latest.queueAlert;
    final silent = (queueAlert?.alerted ?? false) ||
        (_lastNotificationTime != null &&
            now.difference(_lastNotificationTime!) < _minNotificationInterval);
    if (!silent) {
      _lastNotificationTime = now;
      queueAlert?.alerted = true;
    }
    final revision = _conversationRevision(id);
    final isChannel = latest.type == _NotificationType.channelMessage;
    final payload = isChannel ? 'channel:${latest.channelIndex}' : 'message:${latest.id}';
    unawaited(_conversationWork.run(id, () async {
      bool isCurrent() => revision == _conversationRevision(id);
      if (!isCurrent()) return;
      await _backgroundWork.run(() async {
        try {
          await _showConversationNotificationImpl(
            id: id,
            payload: payload,
            updates: updates,
            isCurrent: isCurrent,
            silent: silent,
          );
        } catch (e) {
          debugPrint('Failed to show conversation notification: $e');
        }
      });
    }));
  }

  Future<void> _processBatch() async {
    _isBatchingActive = false;

    if (_pendingNotifications.isEmpty) return;

    final batch = List<_PendingNotification>.from(_pendingNotifications);
    _pendingNotifications.clear();

    if (batch.length == 1) {
      // Single notification, show normally
      await _showAdvertInBackground(batch.first);
    } else {
      // Multiple notifications, show summary
      await _showBatchSummary(batch);
    }

    _lastNotificationTime = _rateLimitNow();
  }

  Future<void> _showAdvertInBackground(_PendingNotification notification) =>
      _backgroundWork.run(() async {
    try {
      await _showAdvertNotificationImpl(
        contactName: notification.body,
        contactType: notification.title,
        contactId: notification.id,
      );
    } catch (e) {
      debugPrint('Failed to show immediate notification: $e');
    }
  });

  Future<void> _showBatchSummary(List<_PendingNotification> batch) async {
    // Group by type
    final messages = batch
        .where((n) => n.type == _NotificationType.message)
        .toList();
    final adverts = batch
        .where((n) => n.type == _NotificationType.advert)
        .toList();
    final channelMsgs = batch
        .where((n) => n.type == _NotificationType.channelMessage)
        .toList();

    await _showActivitySummary(
      messagesCount: messages.length,
      channelMessagesCount: channelMsgs.length,
      advertsCount: adverts.length,
      advertNames: adverts.map((n) => n.body),
    );
  }

  Future<void> showSyncSummaryNotification({
    required int messagesCount,
    required int channelMessagesCount,
  }) async {
    if (_suppressNotifications) return;

    await _showActivitySummary(
      messagesCount: messagesCount,
      channelMessagesCount: channelMessagesCount,
      advertsCount: 0,
      advertNames: const [],
    );
  }

  Future<void> _showActivitySummary({
    required int messagesCount,
    required int channelMessagesCount,
    required int advertsCount,
    required Iterable<String> advertNames,
  }) => _backgroundWork.run(() async {
    if (!await _ensureCanNotify()) return;

    // Build summary text using localized plurals
    final parts = <String>[];
    if (messagesCount > 0) {
      parts.add(_l10n.notification_messagesCount(messagesCount));
    }
    if (channelMessagesCount > 0) {
      parts.add(
        _l10n.notification_channelMessagesCount(channelMessagesCount),
      );
    }
    if (advertsCount > 0) {
      parts.add(_l10n.notification_newNodesCount(advertsCount));
    }

    if (parts.isEmpty) return;

    // Show first few device names in batch summary for debugging (only if adverts exist)
    final advertNamesList = advertNames.toList();
    final deviceInfo = advertNamesList.isNotEmpty
        ? ' ('
              '${advertNamesList.take(5).map(_logSafe).join(', ')}'
              '${advertNamesList.length > 5 ? ', ...' : ''}'
              ')'
        : '';
    debugPrint('[Notification] batch summary: ${parts.join(", ")}$deviceInfo');

    const androidDetails = AndroidNotificationDetails(
      'batch_summary',
      'Activity Summary',
      channelDescription: 'Batched notification summaries',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    try {
      await _notifications.show(
        id: 'batch_summary'.hashCode,
        title: _l10n.notification_activityTitle,
        body: parts.join(', '),
        notificationDetails: notificationDetails,
        payload: 'batch',
      );
    } catch (e) {
      debugPrint('Failed to show batch summary notification: $e');
    }
  });
}

class _MCOImageNotificationAttachment {
  final Uint8List bytes;
  final String? filePath;
  final LinuxRawIconData? linuxRawIcon;

  const _MCOImageNotificationAttachment({
    required this.bytes,
    required this.filePath,
    required this.linuxRawIcon,
  });
}

// Helper class for pending notifications
enum _NotificationType { message, advert, channelMessage }

class _PendingNotification {
  final _NotificationType type;
  final String title;
  final String body;
  final String? senderName;
  final bool urlImagesEnabled;
  final String? id;
  final int? badgeCount;
  final int Function()? currentUnreadTotal;
  final NotificationQueueAlert? queueAlert;
  final DateTime receivedAt = DateTime.now();

  int? get channelIndex => int.tryParse(id ?? '');
  int? get conversationId => type == _NotificationType.channelMessage
      ? channelIndex?.hashCode
      : id?.hashCode;

  _PendingNotification({
    required this.type,
    required this.title,
    required this.body,
    this.senderName,
    this.urlImagesEnabled = false,
    this.id,
    this.badgeCount,
    this.currentUnreadTotal,
    this.queueAlert,
  });
}

class _ConversationBatch {
  _ConversationBatch(this.timer, this.updates);

  final Timer timer;
  final List<_PendingNotification> updates;

  void add(_PendingNotification update, int max) {
    updates.add(update);
    if (updates.length > max) updates.removeAt(0);
  }
}

class _Conversation {
  String title;
  int? badgeCount;
  String? imagePath;
  _MCOImageNotificationAttachment? mcoAttachment;
  final String payload;
  final bool isChannel;
  final List<Message> messages = [];

  _Conversation({
    required this.title,
    required this.payload,
    required this.isChannel,
  });

  void add(Message message, int max) {
    messages.add(message);
    if (messages.length > max) messages.removeRange(0, messages.length - max);
  }
}
