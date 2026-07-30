import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:mco_service/mco_service.dart';
import 'package:meshcore_open/storage/region_store.dart';
import 'package:pointycastle/export.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';

import '../models/channel.dart';
import '../models/channel_message.dart';
import '../models/companion_radio_stats.dart';
import '../models/contact.dart';
import '../models/message.dart';
import '../models/message_compression.dart';
import '../models/app_settings.dart';
import '../models/path_selection.dart';
import '../models/translation_support.dart';
import '../helpers/reaction_helper.dart';
import '../helpers/channel_binary_data_helper.dart';
import '../helpers/contact_share_helper.dart';
import '../helpers/contact_merge_helper.dart';
import '../helpers/cyr2lat.dart';
import '../helpers/mesh_compressor.dart';
import '../helpers/message_text_codec.dart';
import '../helpers/mcoimg_codec.dart';
import '../helpers/mcoimg_v3_codec.dart';
import '../helpers/mcmp_app_codec.dart';
import '../helpers/mcmp_signature_verifier.dart';
import '../helpers/south_frame_fragment_reassembler.dart';
import '../helpers/south_queued_fragment_ack_tracker.dart';
import '../helpers/smaz.dart';
import '../services/app_debug_log_service.dart';
import '../services/ble_debug_log_service.dart';
import '../services/linux_ble_error_classifier.dart';
import '../services/linux_ble_pairing_service_stub.dart'
    if (dart.library.io) '../services/linux_ble_pairing_service.dart';
import '../services/message_retry_service.dart';
import '../services/path_history_service.dart';
import '../services/app_settings_service.dart';
import '../services/background_service.dart';
import '../services/timeout_prediction_service.dart';
import '../services/translation_service.dart';
import '../services/notification_service.dart';
import 'meshcore_connector_usb.dart';
import 'meshcore_connector_tcp.dart';
import '../storage/channel_message_store.dart';
import '../storage/channel_order_store.dart';
import '../storage/channel_settings_store.dart';
import '../storage/channel_region_store.dart';
import '../storage/channel_store.dart';
import '../storage/connection_transport_preference_store.dart';
import '../storage/contact_discovery_store.dart';
import '../storage/contact_settings_store.dart';
import '../storage/contact_store.dart';
import '../storage/message_store.dart';
import '../storage/node_identity_store.dart';
import '../storage/shared_message_history_helper.dart';
import '../storage/unread_store.dart';
import '../utils/app_logger.dart';
import '../utils/battery_utils.dart';
import '../utils/platform_info.dart';
import 'meshcore_uuids.dart';
import 'meshcore_protocol.dart';

class OfflineHistorySource {
  final String scope;
  final String name;

  const OfflineHistorySource({required this.scope, required this.name});
}

class DirectRepeater {
  static const int maxAgeMinutes = 30; // Max age for direct repeater info
  List<int> pubkeyPrefix;
  int pathHashWidth;
  String? contactKeyHex;
  double snr;
  DateTime lastUpdated;

  DirectRepeater({
    required List<int> pubkeyPrefix,
    required this.pathHashWidth,
    this.contactKeyHex,
    required this.snr,
    DateTime? lastUpdated,
  }) : pubkeyPrefix = List.unmodifiable(pubkeyPrefix),
       lastUpdated = lastUpdated ?? DateTime.now();

  String get pubkeyPrefixHex => pubkeyPrefix
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join();

  bool matchesPrefix(List<int> prefix) {
    return pubkeyPrefix.length == prefix.length &&
        listEquals(pubkeyPrefix, prefix);
  }

  bool matchesPathStart(List<int> pathBytes, int pathHashByteWidth) {
    final width = pathHashByteWidth.clamp(1, 4).toInt();
    if (pathBytes.length < width || pubkeyPrefix.length != width) {
      return false;
    }
    return listEquals(pubkeyPrefix, pathBytes.sublist(0, width));
  }

  void update(
    double newSNR, {
    List<int>? pubkeyPrefix,
    int? pathHashWidth,
    String? contactKeyHex,
  }) {
    snr = newSNR;
    if (pubkeyPrefix != null &&
        pubkeyPrefix.length >= this.pubkeyPrefix.length) {
      this.pubkeyPrefix = List.unmodifiable(pubkeyPrefix);
    }
    if (pathHashWidth != null && pathHashWidth >= this.pathHashWidth) {
      this.pathHashWidth = pathHashWidth;
    }
    this.contactKeyHex ??= contactKeyHex;
    lastUpdated = DateTime.now();
  }

  int get ranking {
    if (isStale()) {
      return -1; // Stale repeaters get lowest rank
    }
    // Higher SNR gets higher rank and recency within maxAgeMinutes breaks ties.
    final ageMs =
        DateTime.now().millisecondsSinceEpoch -
        lastUpdated.millisecondsSinceEpoch;
    final maxAgeMs = maxAgeMinutes * 60 * 1000;
    final recencyScore = (maxAgeMs - ageMs).clamp(0, maxAgeMs);
    return ((snr - 31.75) * 1000).round() + recencyScore;
  }

  bool isStale() {
    return DateTime.now().difference(lastUpdated) >
        const Duration(minutes: maxAgeMinutes);
  }
}

enum MeshCoreConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  disconnecting,
}

enum MeshCoreTransportType { bluetooth, usb, tcp }

class RepeaterBatterySnapshot {
  final int millivolts;
  final DateTime updatedAt;
  final String source;

  const RepeaterBatterySnapshot({
    required this.millivolts,
    required this.updatedAt,
    required this.source,
  });
}

class MeshCoreRadioStateSnapshot {
  final int freqHz;
  final int bwHz;
  final int sf;
  final int cr;
  final int txPowerDbm;

  const MeshCoreRadioStateSnapshot({
    required this.freqHz,
    required this.bwHz,
    required this.sf,
    required this.cr,
    required this.txPowerDbm,
  });
}

class MeshCoreConnector extends ChangeNotifier {
  // Message windowing to limit memory usage
  static const int _messageWindowSize = 500;

  // Cap on discovered (non-contact) nodes retained in memory. Adverts arrive
  // continuously from the whole mesh, so without a bound this list grows for
  // as long as the app stays connected. When full, the stalest node (oldest
  // lastSeen) is evicted to make room for a newly heard one.
  static const int _maxDiscoveredContacts = 500;

  MeshCoreConnectionState _state = MeshCoreConnectionState.disconnected;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _rxCharacteristic;
  BluetoothCharacteristic? _txCharacteristic;
  String? _deviceDisplayName;
  String? _deviceId;
  BluetoothDevice? _lastDevice;
  String? _lastDeviceId;
  String? _lastDeviceDisplayName;
  bool _manualDisconnect = false;
  bool _isRecoveringConnection = false;
  MeshCoreTransportType? _lastManualDisconnectTransport;
  final MeshCoreUsbManager _usbManager = MeshCoreUsbManager();
  final LinuxBlePairingService _linuxBlePairingService =
      LinuxBlePairingService();
  StreamSubscription<Uint8List>? _usbFrameSubscription;
  final MeshCoreTcpConnector _tcpConnector = MeshCoreTcpConnector();
  MeshCoreTransportType _activeTransport = MeshCoreTransportType.bluetooth;

  final List<ScanResult> _scanResults = [];
  final List<ScanResult> _linuxSystemScanResults = [];
  final List<Contact> _contacts = [];
  final List<Contact> _discoveredContacts = [];
  Future<void>? _contactCacheLoadFuture;
  int _contactCacheLoadGeneration = 0;
  final List<Channel> _channels = [];
  final Map<String, List<Message>> _conversations = {};
  final Map<int, List<ChannelMessage>> _channelMessages = {};
  final List<String> _pendingChannelSentQueue = [];
  final List<_PendingCommandAck> _pendingGenericAckQueue = [];
  static const String _reactionSendQueuePrefix = '__reaction_send__';
  int _reactionSendQueueSequence = 0;
  final Set<String> _loadedConversationKeys = {};
  final Map<String, Future<void>> _conversationLoadFutures = {};
  int _conversationLoadGeneration = 0;
  final Map<int, Set<String>> _processedChannelReactions =
      {}; // channelIndex -> Set of "targetHash_emoji"
  final Map<String, Set<String>> _processedContactReactions =
      {}; // contactPubKeyHex -> Set of "targetHash_emoji"

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _isScanningSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  Timer? _notifyListenersTimer;
  Timer? _selfInfoRetryTimer;
  Timer? _reconnectTimer;
  Timer? _batteryPollTimer;
  Timer? _rxWatchdogTimer;
  DateTime _rxSilenceAnchor = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastRxWatchdogTickAt;
  int _rxWatchdogReconnects = 0;
  Timer? _gpsLocationPollTimer;
  static const _gpsLocationPollInterval = Duration(minutes: 1);
  final List<Completer<void>> _selfInfoRefreshWaiters = [];
  Timer? _radioStatsPollTimer;
  int _radioStatsPollRefCount = 0;
  final ValueNotifier<CompanionRadioStats?> radioStatsNotifier =
      ValueNotifier<CompanionRadioStats?>(null);
  int _reconnectAttempts = 0;
  bool _notifyListenersDirty = false;
  static const Duration _notifyListenersDebounce = Duration(milliseconds: 50);

  final StreamController<Uint8List> _receivedFramesController =
      StreamController<Uint8List>.broadcast();
  final SouthFrameFragmentReassembler _southFrameFragmentReassembler =
      SouthFrameFragmentReassembler();
  final SouthQueuedFragmentAckTracker _southQueuedFragmentAckTracker =
      SouthQueuedFragmentAckTracker();

  /// Emits when a signed MCMP v3 channel/room message could not be signed by
  /// the node (message signing was requested but the signature came back
  /// null). The UI surfaces this as an error and the message is still sent
  /// unsigned. Direct messages never emit here: they are authenticated by the
  /// transport and are not signed.
  final StreamController<void> _mcmpSigningFailedController =
      StreamController<void>.broadcast();

  Uint8List? _selfPublicKey;
  String? _selfName;
  int? _currentTxPower;
  int? _maxTxPower;
  int? _currentFreqHz;
  int? _currentBwHz;
  int? _currentSf;
  int? _currentCr;
  bool? _clientRepeat;
  MeshCoreRadioStateSnapshot? _rememberedNonRepeatRadioState;
  int? _firmwareVerCode;
  String? _firmwareVersion;
  String? _firmwareBuildDate;
  String? _boardName;
  int _pathHashByteWidth = 1;
  CompanionRadioStats? _latestRadioStats;
  Stopwatch? _airtimeBumpStopwatch;
  int _prevTotalAirSecs = 0;
  int? _batteryMillivolts;
  double? _selfLatitude;
  double? _selfLongitude;
  final List<DirectRepeater> _directRepeaters = List.empty(growable: true);
  // Signal activity of repeaters seen as the last hop of any received packet
  // (not just adverts). Used by the "all repeater activity" SNR indicator.
  final List<DirectRepeater> _activeRepeaters = List.empty(growable: true);
  static const int _maxActiveRepeaters = 10;
  bool _isLoadingContacts = false;
  bool _hasLoadedContacts = false;
  Map<String, int>? _contactSyncIndexes;
  Map<String, int>? _discoveredContactSyncIndexes;
  bool _isLoadingChannels = false;
  bool _hasLoadedChannels = false;
  TimeoutPredictionService? _timeoutPredictionService;
  TranslationService? _translationService;
  // Intentionally global (not per-contact): tracks overall network activity.
  // Frequent RX from any source indicates a busy network with more collisions.
  DateTime _lastRxTime = DateTime.now();
  // Snapshot of _lastRxTime taken before the ACK frame updates it, so that
  // onDeliveryObserved records the pre-ACK elapsed time (matching prediction).
  DateTime _lastRxBeforeFrame = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastRadioRxTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastContactMsgRxTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastChannelMsgRxTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastZeroHopAdvertAt = DateTime.fromMillisecondsSinceEpoch(0);
  double? _lastZeroHopAdvertLatitude;
  double? _lastZeroHopAdvertLongitude;
  static const int _radioQuietMs = 3000;
  static const int _radioQuietMaxWaitMs = 3000;

  /// When companion radio stats are unavailable, keep the legacy fixed backoff.
  static const int _contactMsgBackoffFallbackMs = 5000;
  static const int _contactMsgBackoffMinMs = 500;
  static const int _contactMsgBackoffMaxMs = 15000;
  int _pollingInterval = 30;
  bool _batteryRequested = false;
  bool _awaitingSelfInfo = false;
  bool _hasCompletedSelfInfoHandshake = false;
  bool _hasReceivedDeviceInfo = false;
  bool _hasLoadedCachedChannelStorage = false;
  // Initial sync is serialized for predictable progress. Firmware exposes one
  // FIFO queued-message stream, so direct/room frames are buffered until after
  // contacts are known.
  bool _pendingInitialChannelSync = false;
  bool _pendingInitialContactsSync = false;
  bool _pendingInitialQueuedMessageSync = false;
  bool _bleInitialSyncStarted = false;
  bool _webInitialHandshakeRequestSent = false;
  bool _preserveContactsOnRefresh = false;
  final Map<String, DateTime> _contactMessageSummarySnapshot = {};
  bool _autoAddUsers = false;
  bool _autoAddRepeaters = false;
  bool _autoAddRoomServers = false;
  bool _autoAddSensors = false;
  bool _overwriteOldest = false;
  bool _manualAddContacts = false;
  int _telemetryModeBase = 0;
  int _telemetryModeLoc = 0;
  int _telemetryModeEnv = 0;
  int _advertLocPolicy = 0;
  int _multiAcks = 0;

  static const int _defaultMaxContacts = 350;
  static const int _defaultMaxChannels = 40;
  static const String _backgroundTcpReason = 'tcp-connection';
  int _maxContacts = _defaultMaxContacts;
  int _maxChannels = _defaultMaxChannels;
  int? _contactSyncTotal;
  int _contactSyncReceived = 0;
  bool _contactSyncUsesSinceFilter = false;
  Timer? _contactSyncTimeout;
  static const Duration _contactSyncIdleTimeout = Duration(seconds: 10);
  bool _isSyncingQueuedMessages = false;

  /// True only while draining the backlog the node accumulated before this
  /// connection (the initial post-connect queued sync). During this window
  /// queued channel messages are ordered by their original send time, since
  /// the node replays the whole backlog "now" and the local receivedAt is
  /// meaningless for them. Incremental live deliveries afterwards keep real
  /// receivedAt ordering (robust to per-message radio flight time).
  bool _isInitialBacklogDrain = false;
  bool _deferQueuedContactMessagesUntilContacts = false;
  bool _isProcessingDeferredQueuedContactMessages = false;
  bool _queuedMessageSyncInFlight = false;
  final List<Uint8List> _deferredQueuedContactMessageFrames = [];
  bool _pendingQueueSync = false;
  Timer? _queueSyncTimeout;
  int _queueSyncRetries = 0;
  static const int _maxQueueSyncRetries = 3;
  static const int _queueSyncTimeoutMs = 5000; // 5 second timeout
  // Serializes path operations (setContactPath/clearContactPath) to prevent
  // interleaved async calls from leaving in-memory state inconsistent with device.
  Future<void> _pathOpLock = Future.value();
  // Flood scope is a global firmware setting, so scoped channel sends must not
  // overlap or a message may inherit another channel's region.
  Future<void> _channelScopedSendLock = Future.value();
  static const Duration _commandAckTimeout = Duration(seconds: 5);
  Map<String, String>? _currentCustomVars;

  /// Maps repeater pubkey-prefix hex (12 hex chars = first 6 bytes) → the
  /// repeater's RTC clock at the moment of the most recent successful login.
  /// Reported by firmware in the login-success push frame at byte offset 8.
  final Map<String, DateTime> _repeaterLoginClocks = {};

  // Channel syncing state (sequential pattern)
  bool _isSyncingChannels = false;
  bool _channelSyncInFlight = false;
  bool _pendingChannelSyncRestart = false;
  int? _pendingChannelSyncRestartMaxChannels;
  Timer? _channelSyncTimeout;
  int _channelSyncRetries = 0;
  int _nextChannelIndexToRequest = 0;
  int _totalChannelsToRequest = 0;
  List<Channel> _previousChannelsCache = [];
  static const int _maxChannelSyncRetries = 3;
  static const int _channelSyncTimeoutMs = 2000; // 2 second timeout per channel
  static const Duration _batteryPollInterval = Duration(seconds: 120);
  static const Duration _rxWatchdogCheckInterval = Duration(seconds: 60);
  // Battery polling is expected to produce request-response traffic every
  // poll interval, which makes prolonged RX silence anomalous on a quiet mesh.
  // Threshold = two missed battery cycles plus one check window, and must
  // keep tracking the polling cadence if it ever changes.
  static final Duration _rxWatchdogSilence =
      _batteryPollInterval * 2 + _rxWatchdogCheckInterval;
  static const int _rxWatchdogMaxConsecutive = 3;

  // Services
  MessageRetryService? _retryService;
  PathHistoryService? _pathHistoryService;
  AppSettingsService? _appSettingsService;
  SettingsSectionsService? _settingsSectionsService;
  bool _lastSouthNodeEnableFragmentedFrames = false;
  BackgroundService? _backgroundService;
  final NotificationService _notificationService = NotificationService();
  BleDebugLogService? _bleDebugLogService;
  AppDebugLogService? _appDebugLogService;
  final ChannelMessageStore _channelMessageStore = ChannelMessageStore();
  final SharedMessageHistoryHelper _sharedMessageHistoryHelper =
      SharedMessageHistoryHelper();
  final MessageStore _messageStore = MessageStore();
  final ChannelOrderStore _channelOrderStore = ChannelOrderStore();
  final ChannelSettingsStore _channelSettingsStore = ChannelSettingsStore();
  final ChannelRegionStore _channelRegionStore = ChannelRegionStore();
  final ContactSettingsStore _contactSettingsStore = ContactSettingsStore();
  final ContactStore _contactStore = ContactStore();
  final ContactDiscoveryStore _discoveryContactStore = ContactDiscoveryStore();
  final ChannelStore _channelStore = ChannelStore();
  final ConnectionTransportPreferenceStore _transportPreferenceStore =
      ConnectionTransportPreferenceStore();
  final NodeIdentityStore _nodeIdentityStore = NodeIdentityStore();
  final UnreadStore _unreadStore = UnreadStore();
  List<Channel> _cachedChannels = [];
  final Map<int, bool> _channelMcmpEnabled = {};
  final Map<int, int> _channelMcmpVersion = {};
  final Map<int, bool> _channelMcmpUseSign = {};
  final Map<int, bool> _channelSmazEnabled = {};
  final Map<int, bool> _channelCyr2LatEnabled = {};
  final Map<int, String?> _channelCyr2LatProfileId = {};
  final Map<int, int?> _channelWidgetColor = {};
  final Map<int, int?> _channelWidgetTextColor = {};
  final Map<int, Region> _channelRegions = {};
  String? _defaultRegionScope;
  bool _hasLoadedDefaultRegionScope = false;
  Future<void>? _defaultRegionScopeRefreshFuture;
  bool _lastSentWasCliCommand =
      false; // Track if last sent message was a CLI command
  final Map<String, bool> _contactMcmpEnabled = {};
  final Map<String, int> _contactMcmpVersion = {};
  final Map<String, bool> _contactMcmpUseSign = {};
  final Map<String, bool> _contactSmazEnabled = {};
  final Map<String, bool> _contactCyr2LatEnabled = {};
  final Map<String, String?> _contactCyr2LatProfileId = {};
  final Map<String, bool> _contactSendingDelayEnabled = {};
  final Map<String, List<String>> _contactQuickAnswerIds = {};
  final Map<int, List<ChannelMessage>> _sharedChannelSecondaryMessages = {};
  final Map<int, String> _sharedChannelSecondaryIdentityKeys = {};
  final Map<String, List<Message>> _sharedContactSecondaryMessages = {};
  final Map<String, ({String text, DateTime timestamp})>
  _contactMessagePreviews = {};
  final Set<int> _loadingSharedChannelIndexes = {};
  final Set<String> _loadingSharedContactKeys = {};
  final Map<int, String> _hiddenSharedChannelIdentityKeys = {};
  final Set<String> _hiddenSharedContactKeys = {};
  SharedMessageHistoryMode _lastSharedMessageHistoryMode =
      SharedMessageHistoryMode.disabled;
  int _lastNoRetransmissionWarningSeconds = 0;
  final Map<String, _PendingContactSend> _pendingContactSends = {};
  final Map<String, _PendingChannelSend> _pendingChannelSends = {};
  bool _isOfflineMode = false;
  bool _isOfflineSharedMode = false;
  String? _offlineHistoryScope;
  String? _offlinePublicKeyHex;
  List<String> _offlineSharedScopes = const [];
  bool _isFlushingPendingOutgoingMessages = false;
  final Map<String, Timer> _channelNoRetransmissionTimers = {};
  final List<_DeferredChannelMessageSend> _deferredChannelMessageSends = [];
  final Map<String, _DeferredChannelMessageSend> _retriableChannelMessageSends =
      {};
  bool _isFlushingDeferredChannelMessageSends = false;
  bool _isFlushingRetriableChannelMessageSends = false;
  bool _shouldReplayRetriableChannelMessageSends = false;
  final Map<int, bool> _channelSendingDelayEnabled = {};
  final Map<int, List<String>> _channelQuickAnswerIds = {};
  final Set<String> _knownContactKeys = {};
  final Map<String, int> _contactUnreadCount = {};
  final Map<String, RepeaterBatterySnapshot> _repeaterBatterySnapshots = {};
  bool _unreadStateLoaded = false;
  int _cachedContactsUnreadTotal = 0;
  int _cachedChannelsUnreadTotal = 0;
  final Map<String, _RepeaterAckContext> _pendingRepeaterAcks = {};
  String? _activeContactKey;
  int? _activeChannelIndex;
  List<int> _channelOrder = [];

  int _storageUsedKb = -1;
  int _storageTotalKb = -1;

  // Getters
  MeshCoreConnectionState get state => _state;
  BluetoothDevice? get device => _device;
  String? get deviceId => _deviceId;
  String get deviceIdLabel => _deviceId ?? 'Unknown';

  /// Stable per-radio key for transport-agnostic per-device settings such as
  /// battery chemistry. On BLE this is the existing remoteId (so previously
  /// saved settings are preserved); on USB/TCP — where there is no BLE
  /// remoteId — it falls back to the node's public key, which identifies the
  /// same physical radio across transports. Null until a device identity is
  /// known.
  String? get batteryDeviceKey {
    if (_deviceId != null) return _deviceId;
    if (_selfPublicKey != null && _selfPublicKey!.isNotEmpty) {
      return selfPublicKeyHex;
    }
    return null;
  }

  MeshCoreTransportType get activeTransport => _activeTransport;
  String? get activeUsbPort => _usbManager.activePortKey;
  String? get activeUsbPortDisplayLabel => _usbManager.activePortDisplayLabel;
  bool get isUsbTransportConnected =>
      _state == MeshCoreConnectionState.connected &&
      _activeTransport == MeshCoreTransportType.usb;
  bool get isAutoReconnectScheduled =>
      _shouldAutoReconnect && (_reconnectTimer?.isActive ?? false);
  String? get activeTcpEndpoint => _tcpConnector.activeEndpoint;
  bool get isTcpTransportConnected =>
      _state == MeshCoreConnectionState.connected &&
      _activeTransport == MeshCoreTransportType.tcp;
  bool shouldSuppressAutoconnect(MeshCoreTransportType transport) =>
      _manualDisconnect && _lastManualDisconnectTransport == transport;

  String get deviceDisplayName {
    if (_selfName != null && _selfName!.isNotEmpty) {
      return _selfName!;
    }
    final platformName = _device?.platformName;
    if (platformName != null && platformName.isNotEmpty) {
      return platformName;
    }
    if (_deviceDisplayName != null && _deviceDisplayName!.isNotEmpty) {
      return _deviceDisplayName!;
    }
    return 'Unknown Device';
  }

  List<ScanResult> get scanResults => List.unmodifiable(_scanResults);
  List<Contact> get contacts {
    final selfKey = _selfPublicKey;
    if (selfKey == null) {
      return List.unmodifiable(_contacts);
    }
    return List.unmodifiable(
      _contacts.where((contact) => !listEquals(contact.publicKey, selfKey)),
    );
  }

  List<Contact> get allContacts => List.unmodifiable([
    ..._contacts,
    ..._discoveredContacts.where(
      (c) => !c.isActive && c.publicKeyHex != selfPublicKeyHex,
    ),
  ]);

  List<Contact> get allContactsUnfiltered =>
      List.unmodifiable([..._contacts, ..._discoveredContacts]);

  List<Contact> get discoveredContacts {
    return List.unmodifiable(_discoveredContacts);
  }

  List<Channel> get channels => List.unmodifiable(_channels);
  bool get isConnected => _state == MeshCoreConnectionState.connected;
  bool get isOfflineMode => _isOfflineMode;
  bool get isOfflineSharedMode => _isOfflineMode && _isOfflineSharedMode;
  String? get offlineHistoryScope => _offlineHistoryScope;
  bool get hasReadableSession => isConnected || isOfflineMode;
  bool get wasManuallyDisconnected => _manualDisconnect;
  bool get isRecoveringConnection => _isRecoveringConnection;
  bool get isLoadingContacts => _isLoadingContacts;
  bool get hasLoadedContacts => _hasLoadedContacts;
  bool get isLoadingChannels => _isLoadingChannels;
  bool get hasLoadedChannels => _hasLoadedChannels;
  bool get hasCompletedSelfInfoHandshake =>
      isConnected && _hasCompletedSelfInfoHandshake;
  bool get isSessionReady =>
      isConnected &&
      _hasLoadedContacts &&
      _hasLoadedChannels &&
      !_isInitialBacklogDrain &&
      !_deferQueuedContactMessagesUntilContacts &&
      !_isProcessingDeferredQueuedContactMessages &&
      !_pendingInitialChannelSync &&
      !_pendingInitialContactsSync &&
      !_pendingInitialQueuedMessageSync;
  Stream<Uint8List> get receivedFrames => _receivedFramesController.stream;

  /// Broadcast of MCMP v3 channel/room signing failures; see
  /// [_mcmpSigningFailedController].
  Stream<void> get mcmpSigningFailures => _mcmpSigningFailedController.stream;
  Uint8List? get selfPublicKey => _selfPublicKey;
  String get selfPublicKeyHex =>
      _offlinePublicKeyHex ?? pubKeyToHex(_selfPublicKey ?? Uint8List(0));
  String? get selfName => _selfName;
  double? get selfLatitude => _selfLatitude;
  double? get selfLongitude => _selfLongitude;
  List<DirectRepeater> get directRepeaters => _directRepeaters;
  List<DirectRepeater> get activeRepeaters => _activeRepeaters;
  int? get currentTxPower => _currentTxPower;
  int? get maxTxPower => _maxTxPower;

  int get pathHashByteWidth => _pathHashByteWidth;

  CompanionRadioStats? get latestRadioStats => _latestRadioStats;

  bool get supportsCompanionRadioStats => (_firmwareVerCode ?? 0) >= 8;

  bool get radioStatsAirActivityPulse {
    final sw = _airtimeBumpStopwatch;
    if (sw == null || !sw.isRunning) return false;
    return sw.elapsed < const Duration(seconds: 2);
  }

  int? get currentFreqHz => _currentFreqHz;
  int? get currentBwHz => _currentBwHz;
  int? get currentSf => _currentSf;
  int? get currentCr => _currentCr;
  MeshCoreRadioStateSnapshot? get rememberedNonRepeatRadioState =>
      _rememberedNonRepeatRadioState;
  bool? get autoAddUsers => _autoAddUsers;
  bool? get autoAddRepeaters => _autoAddRepeaters;
  bool? get autoAddRoomServers => _autoAddRoomServers;
  bool? get autoAddSensors => _autoAddSensors;
  bool? get autoAddOverwriteOldest => _overwriteOldest;
  int get telemetryModeBase => _telemetryModeBase;
  int get telemetryModeLoc => _telemetryModeLoc;
  int get telemetryModeEnv => _telemetryModeEnv;
  int get advertLocationPolicy => _advertLocPolicy;
  int get multiAcks => _multiAcks;
  bool? get clientRepeat => _clientRepeat;

  /// Returns the repeater's RTC clock at the time of the most recent
  /// successful login, looked up by the contact's full public key.
  /// Returns null if no login response has been observed for this repeater
  /// since connection.
  DateTime? repeaterClockAtLogin(Uint8List publicKey) {
    if (publicKey.length < 6) return null;
    final prefix = pubKeyToHex(publicKey.sublist(0, 6));
    return _repeaterLoginClocks[prefix];
  }

  void rememberNonRepeatRadioState(MeshCoreRadioStateSnapshot snapshot) {
    _rememberedNonRepeatRadioState = snapshot;
  }

  int? get firmwareVerCode => _firmwareVerCode;

  List<OfflineHistorySource> get offlineHistorySources {
    final scopes = SharedMessageHistoryHelper.knownScopes().toList()..sort();
    return scopes
        .map(
          (scope) => OfflineHistorySource(
            scope: scope,
            name:
                (NodeIdentityStore()..setPublicKeyHex = scope).loadName() ??
                scope.substring(0, 6).toUpperCase(),
          ),
        )
        .toList();
  }

  Future<bool> enterOfflineHistory({String? scope, bool shared = false}) async {
    if (isConnected || _state == MeshCoreConnectionState.connecting) {
      return false;
    }
    final knownScopes = SharedMessageHistoryHelper.knownScopes().toList()
      ..sort();
    if (knownScopes.isEmpty) return false;
    // Shared mode still needs one deterministic scope for the synthetic
    // session's store bindings. It is only a presentation scope: all history
    // reads below remain explicitly read-only and aggregate every known scope.
    final selectedScope = shared
        ? knownScopes.first
        : scope?.trim().toLowerCase();
    if (selectedScope == null || !knownScopes.contains(selectedScope)) {
      return false;
    }

    _cancelReconnectTimer();
    await stopScan();
    _clearOfflineHistoryData();
    _isOfflineMode = true;
    _isOfflineSharedMode = shared;
    _offlineHistoryScope = shared ? null : selectedScope;
    _offlineSharedScopes = shared ? knownScopes : [selectedScope];
    _offlinePublicKeyHex = selectedScope.padRight(pubKeySize * 2, '0');
    _selfName = shared
        ? null
        : (NodeIdentityStore()..setPublicKeyHex = selectedScope).loadName();
    _bindStoresToPublicKey(selfPublicKeyHex);

    try {
      if (shared) {
        await _loadSharedOfflineHistory(knownScopes);
      } else {
        await _loadNodeOfflineHistory();
      }
    } catch (error, stackTrace) {
      appLogger.error(
        'Failed to load offline history: $error\n$stackTrace',
        tag: 'OfflineHistory',
      );
      _clearOfflineHistoryData();
      _isOfflineMode = false;
      _isOfflineSharedMode = false;
      _offlineHistoryScope = null;
      _offlinePublicKeyHex = null;
      _offlineSharedScopes = const [];
      _selfName = null;
      _bindStoresToPublicKey('');
      notifyListeners();
      return false;
    }
    _hasLoadedContacts = true;
    _hasLoadedChannels = true;
    _hasLoadedCachedChannelStorage = true;
    notifyListeners();
    return true;
  }

  Future<void> exitOfflineHistory() async {
    if (!_isOfflineMode) return;
    _clearOfflineHistoryData();
    _isOfflineMode = false;
    _isOfflineSharedMode = false;
    _offlineHistoryScope = null;
    _offlinePublicKeyHex = null;
    _offlineSharedScopes = const [];
    _selfName = null;
    _bindStoresToPublicKey('');
    notifyListeners();
  }

  void _bindStoresToPublicKey(String publicKeyHex) {
    _channelMessageStore.setPublicKeyHex = publicKeyHex;
    _messageStore.setPublicKeyHex = publicKeyHex;
    _channelOrderStore.setPublicKeyHex = publicKeyHex;
    _channelSettingsStore.setPublicKeyHex = publicKeyHex;
    _channelRegionStore.setPublicKeyHex = publicKeyHex;
    _contactSettingsStore.setPublicKeyHex = publicKeyHex;
    _contactStore.setPublicKeyHex = publicKeyHex;
    _channelStore.setPublicKeyHex = publicKeyHex;
    _nodeIdentityStore.setPublicKeyHex = publicKeyHex;
    _unreadStore.setPublicKeyHex = publicKeyHex;
    _settingsSectionsService?.setActiveDeviceKey(
      publicKeyHex.isEmpty ? null : publicKeyHex,
    );
  }

  void _clearOfflineHistoryData() {
    _contacts.clear();
    _discoveredContacts.clear();
    _channels.clear();
    _cachedChannels.clear();
    _conversations.clear();
    _channelMessages.clear();
    _loadedConversationKeys.clear();
    _conversationLoadGeneration++;
    _conversationLoadFutures.clear();
    _knownContactKeys.clear();
    _channelOrder.clear();
    _clearSharedMessageHistoryState();
    _contactMessagePreviews.clear();
    _contactUnreadCount.clear();
    _unreadStateLoaded = false;
    _cachedContactsUnreadTotal = 0;
    _cachedChannelsUnreadTotal = 0;
    _activeContactKey = null;
    _activeChannelIndex = null;
    _resetSyncProgressState();
  }

  Future<void> _loadNodeOfflineHistory() async {
    final publicKeyHex = selfPublicKeyHex;
    final channelStore = ChannelStore()..setPublicKeyHex = publicKeyHex;
    final channels = await channelStore.loadChannels(
      allowLegacyMigration: false,
    );
    _channels.addAll(channels);
    _cachedChannels.addAll(channels);
    _replaceChannelStorageBindings(channels);
    await loadChannelSettings(
      publicKeyHex: publicKeyHex,
      channelBindings: channels,
      allowLegacyMigration: false,
    );
    await loadAllChannelMessages(
      publicKeyHex: publicKeyHex,
      channelBindings: channels,
      allowLegacyMigration: false,
    );
    await _loadChannelOrder(
      publicKeyHex: publicKeyHex,
      allowLegacyMigration: false,
    );

    final contacts = await (ContactStore()..setPublicKeyHex = publicKeyHex)
        .loadContacts(allowLegacyMigration: false);
    final normalized = deduplicateContactsByPublicKey(contacts);
    _contacts.addAll(normalized);
    _knownContactKeys.addAll(normalized.map((contact) => contact.publicKeyHex));
    await _refreshContactMessageSummaries(persistChanges: false);
    await loadUnreadState();
  }

  Future<void> _loadSharedOfflineHistory(List<String> scopes) async {
    final allContacts = <Contact>[];
    final channelByIdentity = <String, Channel>{};
    final messagesByIdentity = <String, List<ChannelMessage>>{};

    for (final scope in scopes) {
      final publicKeyHex = scope.padRight(pubKeySize * 2, '0');
      final sourceName =
          (NodeIdentityStore()..setPublicKeyHex = scope).loadName() ??
          scope.substring(0, 6).toUpperCase();
      allContacts.addAll(
        await (ContactStore()..setPublicKeyHex = publicKeyHex).loadContacts(
          allowLegacyMigration: false,
        ),
      );

      final channels = await (ChannelStore()..setPublicKeyHex = publicKeyHex)
          .loadChannels(allowLegacyMigration: false);
      final messageStore = ChannelMessageStore()
        ..setPublicKeyHex = publicKeyHex
        ..replaceChannels(channels);
      for (final channel in channels.where((channel) => !channel.isEmpty)) {
        final identity = _sharedChannelIdentityKey(channel);
        channelByIdentity.putIfAbsent(identity, () => channel);
        final storedMessages = await messageStore.loadChannelMessages(
          channel.index,
          allowLegacyMigration: false,
        );
        final historicalMessages = storedMessages
            .map(
              (message) => message.copyWith(
                status:
                    message.isOutgoing &&
                        message.status == ChannelMessageStatus.pending
                    ? ChannelMessageStatus.sent
                    : message.status,
                sharedHistorySourceName: sourceName,
              ),
            )
            .toList();
        messagesByIdentity[identity] = _mergeChannelMessages(
          messagesByIdentity[identity] ?? const [],
          historicalMessages,
        );
      }
    }

    final normalizedContacts = deduplicateContactsByPublicKey(allContacts);
    _contacts.addAll(normalizedContacts);
    _knownContactKeys.addAll(
      normalizedContacts.map((contact) => contact.publicKeyHex),
    );
    await _refreshOfflineSharedContactMessageSummaries(scopes);

    var syntheticIndex = 0;
    for (final entry in channelByIdentity.entries) {
      final source = entry.value;
      final channel = Channel(
        index: syntheticIndex,
        name: source.name,
        psk: Uint8List.fromList(source.psk),
        unreadCount: 0,
      );
      _channels.add(channel);
      _channelMessages[syntheticIndex] = _orderedChannelMessages(
        (messagesByIdentity[entry.key] ?? const [])
            .map((message) => message.copyWith(channelIndex: syntheticIndex))
            .toList(),
      );
      syntheticIndex++;
    }
    _cachedChannels.addAll(_channels);
    _replaceChannelStorageBindings(_channels);
    _unreadStateLoaded = true;
    _cachedContactsUnreadTotal = 0;
    _cachedChannelsUnreadTotal = 0;
  }

  Future<void> _refreshOfflineSharedContactMessageSummaries(
    List<String> scopes,
  ) async {
    final contactKeys = _contacts
        .where(_supportsContactMessageSummary)
        .map((contact) => contact.publicKeyHex)
        .toSet()
        .toList();

    for (var i = 0; i < contactKeys.length; i++) {
      if (i > 0 && i % 8 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final contactKeyHex = contactKeys[i];
      MessageStoreSummary? latestSummary;
      for (final scope in scopes) {
        final summary = await (MessageStore()..setPublicKeyHex = scope)
            .loadMessageSummary(contactKeyHex, includeLegacyUnscoped: false);
        if (summary != null &&
            (latestSummary == null ||
                summary.latestMessageAt.isAfter(
                  latestSummary.latestMessageAt,
                ))) {
          latestSummary = summary;
        }
      }

      _cacheContactMessagePreview(contactKeyHex, latestSummary, replace: true);
      if (latestSummary == null) {
        _clearContactMessageSummary(contactKeyHex);
      } else {
        _applyContactMessageSummary(
          contactKeyHex,
          latestSummary.latestMessageAt,
        );
      }
    }
  }

  /// Human-readable firmware version string reported in RESP_CODE_DEVICE_INFO
  /// (FIRMWARE_VERSION), e.g. "v1.7.4"; null until the device info arrives.
  String? get firmwareVersion => _firmwareVersion;

  /// Firmware build date reported in RESP_CODE_DEVICE_INFO
  /// (FIRMWARE_BUILD_DATE); null until the device info arrives.
  String? get firmwareBuildDate => _firmwareBuildDate;

  /// Board name reported in RESP_CODE_DEVICE_INFO (Board::getManufacturerName),
  /// e.g. "Heltec V3"; null until the device info arrives. Custom builds may
  /// report a generic name such as "Generic ESP32".
  String? get boardName => _boardName;

  Map<String, String>? get currentCustomVars => _currentCustomVars;
  int? get batteryMillivolts => _batteryMillivolts;
  int? get storageUsedKb => _storageUsedKb;
  int? get storageTotalKb => _storageTotalKb;
  int get maxContacts => _maxContacts;
  int get maxChannels => _maxChannels;
  Set<String> get knownContactKeys => Set.unmodifiable(_knownContactKeys);
  double? get contactSyncProgress {
    final total = _contactSyncTotal;
    if (!_isLoadingContacts || total == null || total <= 0) return null;
    return (_contactSyncReceived / total).clamp(0.0, 1.0).toDouble();
  }

  bool get isSyncingQueuedMessages =>
      _isSyncingQueuedMessages || _isProcessingDeferredQueuedContactMessages;
  bool get isShowingQueuedMessageSyncProgress =>
      _deferQueuedContactMessagesUntilContacts && isSyncingQueuedMessages;
  bool get isSyncingChannels => _isSyncingChannels;
  int get channelSyncProgress =>
      _isSyncingChannels && _totalChannelsToRequest > 0
      ? ((_nextChannelIndexToRequest / _totalChannelsToRequest) * 100).round()
      : 0;
  int? get batteryPercent => _batteryMillivolts == null
      ? null
      : estimateBatteryPercentFromMillivolts(
          _batteryMillivolts!,
          _batteryChemistryForDevice(),
          customRange: _batteryVoltageRangeForDevice(),
        );
  RepeaterBatterySnapshot? getRepeaterBatterySnapshot(String contactKeyHex) =>
      _repeaterBatterySnapshots[contactKeyHex];
  int? getRepeaterBatteryMillivolts(String contactKeyHex) =>
      _repeaterBatterySnapshots[contactKeyHex]?.millivolts;

  void updateRepeaterBatterySnapshot(
    String contactKeyHex,
    int millivolts, {
    String source = 'unknown',
  }) {
    if (contactKeyHex.isEmpty || millivolts <= 0) return;
    final previous = _repeaterBatterySnapshots[contactKeyHex];
    final snapshot = RepeaterBatterySnapshot(
      millivolts: millivolts,
      updatedAt: DateTime.now(),
      source: source,
    );
    _repeaterBatterySnapshots[contactKeyHex] = snapshot;
    if (previous?.millivolts != millivolts) {
      notifyListeners();
    }
  }

  String _batteryChemistryForDevice() {
    final deviceId = batteryDeviceKey;
    if (deviceId == null || _appSettingsService == null) return 'nmc';
    return _appSettingsService!.batteryChemistryForDevice(deviceId);
  }

  BatteryVoltageRange? _batteryVoltageRangeForDevice() {
    final deviceId = batteryDeviceKey;
    if (deviceId == null || _appSettingsService == null) return null;
    return _appSettingsService!.batteryVoltageRangeForDevice(deviceId);
  }

  List<Message> getMessages(Contact contact) {
    final primary = _conversations[contact.publicKeyHex] ?? [];
    if (isOfflineMode) return primary;
    if (!_sharedContactsEnabled || contact.type == advTypeRoom) {
      return primary;
    }
    _ensureSharedContactHistory(contact);
    return _mergeContactMessages(
      primary,
      _sharedContactSecondaryMessages[contact.publicKeyHex] ?? const [],
    );
  }

  List<Message> getLoadedMessages(Contact contact) {
    // Side-effect-free read for aggregate screens; getMessages() may trigger
    // shared-history loading and should only be used for a focused chat.
    return _conversations[contact.publicKeyHex] ?? const [];
  }

  ({String text, DateTime timestamp})? getContactMessagePreview(
    Contact contact,
  ) {
    return _contactMessagePreviews[contact.publicKeyHex];
  }

  List<ChannelMessage> getLoadedChannelMessages(Channel channel) {
    // Side-effect-free read for aggregate screens; getChannelMessages() may
    // trigger shared-history loading and should only be used for a focused chat.
    return _channelMessages[channel.index] ?? const [];
  }

  Future<void> deleteMessage(Message message) async {
    final pending = _pendingContactSends.remove(message.messageId);
    if (pending != null) {
      pending.timer?.cancel();
      notifyListeners();
      return;
    }
    final contactKeyHex = message.senderKeyHex;
    final messages = _conversations[contactKeyHex];
    if (messages == null) return;
    final removed = messages.remove(message);
    if (!removed) return;
    _retryService?.untrack(message.messageId);
    await _messageStore.saveMessages(contactKeyHex, messages);
    notifyListeners();
  }

  Future<void> resendMessage(Contact contact, Message message) async {
    await deleteMessage(message);
    await sendMessage(
      contact,
      message.text,
      originalText: message.originalText,
      translatedLanguageCode: message.translatedLanguageCode,
      translationModelId: message.translationModelId,
    );
  }

  Future<void> _loadMessagesForContact(String contactKeyHex) async {
    if (_loadedConversationKeys.contains(contactKeyHex)) return;
    final pending = _conversationLoadFutures[contactKeyHex];
    if (pending != null) return pending;

    final generation = _conversationLoadGeneration;
    final load = _loadMessagesForContactInternal(contactKeyHex, generation);
    _conversationLoadFutures[contactKeyHex] = load;
    try {
      await load;
      if (generation == _conversationLoadGeneration) {
        _loadedConversationKeys.add(contactKeyHex);
      }
    } finally {
      if (identical(_conversationLoadFutures[contactKeyHex], load)) {
        _conversationLoadFutures.remove(contactKeyHex);
      }
    }
  }

  Future<void> _loadMessagesForContactInternal(
    String contactKeyHex,
    int generation,
  ) async {
    if (isOfflineSharedMode) {
      final merged = <Message>[];
      for (final scope in _offlineSharedScopes) {
        final publicKeyHex = scope.padRight(pubKeySize * 2, '0');
        final sourceName =
            (NodeIdentityStore()..setPublicKeyHex = scope).loadName() ??
            scope.substring(0, 6).toUpperCase();
        final messages = await (MessageStore()..setPublicKeyHex = publicKeyHex)
            .loadScopedMessages(contactKeyHex);
        if (generation != _conversationLoadGeneration) return;
        merged.addAll(
          messages.map(
            (message) => message.copyWith(
              status:
                  message.isOutgoing && message.status == MessageStatus.pending
                  ? MessageStatus.sent
                  : message.status,
              sharedHistorySourceName: sourceName,
            ),
          ),
        );
      }
      merged.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      _conversations[contactKeyHex] = merged;
      _applyContactMessageSummaryFromMessages(contactKeyHex, merged);
      notifyListeners();
      return;
    }
    final allMessages = isOfflineMode
        ? await _messageStore.loadScopedMessages(contactKeyHex)
        : await _messageStore.loadMessages(contactKeyHex);
    if (generation != _conversationLoadGeneration) return;
    _applyContactMessageSummaryFromMessages(contactKeyHex, allMessages);
    if (allMessages.isNotEmpty) {
      // Keep only the most recent N messages in memory to bound memory usage
      final windowedMessages = allMessages.length > _messageWindowSize
          ? allMessages.sublist(allMessages.length - _messageWindowSize)
          : allMessages;

      final currentMessages =
          _conversations[contactKeyHex] ?? const <Message>[];
      final mergedMessages = <Message>[...windowedMessages];
      final persistedKeyCounts = <String, int>{};
      for (final message in windowedMessages) {
        final key = _messageMergeKey(message);
        persistedKeyCounts[key] = (persistedKeyCounts[key] ?? 0) + 1;
      }
      final currentKeyCounts = <String, int>{};

      for (final message in currentMessages) {
        final key = _messageMergeKey(message);
        final currentCount = (currentKeyCounts[key] ?? 0) + 1;
        currentKeyCounts[key] = currentCount;
        final persistedCount = persistedKeyCounts[key] ?? 0;

        // Preserve distinct duplicates without IDs (for example same text
        // received multiple times in the same second) by only skipping the
        // overlapping occurrences that already exist in persisted storage.
        if (currentCount > persistedCount) {
          mergedMessages.add(message);
        }
      }

      // Re-sort after merging persisted and in-memory messages so the
      // conversation window remains stable after optimistic inserts.
      mergedMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final windowedMergedMessages = mergedMessages.length > _messageWindowSize
          ? mergedMessages.sublist(mergedMessages.length - _messageWindowSize)
          : mergedMessages;

      _conversations[contactKeyHex] = windowedMergedMessages;
      notifyListeners();
    }
  }

  String _messageMergeKey(Message message) {
    final messageId = message.messageId;
    if (messageId.isNotEmpty) {
      return 'id:$messageId';
    }
    return 'fallback:${message.senderKeyHex}:${message.isOutgoing}:${message.isCli}:${message.timestamp.millisecondsSinceEpoch}:${message.text}';
  }

  Future<void> _refreshContactMessageSummaries({
    bool persistChanges = true,
  }) async {
    if (_contacts.isEmpty && _discoveredContacts.isEmpty) {
      if (_contactMessagePreviews.isNotEmpty) {
        _contactMessagePreviews.clear();
        notifyListeners();
      }
      return;
    }
    final contactKeys = <String, bool>{};
    for (final contact in _contacts) {
      if (!_supportsContactMessageSummary(contact)) continue;
      contactKeys[contact.publicKeyHex] =
          (contactKeys[contact.publicKeyHex] ?? false) ||
          _canUseSharedContactHistorySummary(contact);
    }
    for (final contact in _discoveredContacts) {
      if (!_supportsContactMessageSummary(contact)) continue;
      contactKeys[contact.publicKeyHex] =
          (contactKeys[contact.publicKeyHex] ?? false) ||
          _canUseSharedContactHistorySummary(contact);
    }
    final stalePreviewKeys = _contactMessagePreviews.keys
        .where((key) => !contactKeys.containsKey(key))
        .toList();
    for (final key in stalePreviewKeys) {
      _contactMessagePreviews.remove(key);
    }
    final contactEntries = contactKeys.entries.toList();
    var changed = false;
    var previewChanged = stalePreviewKeys.isNotEmpty;
    for (var i = 0; i < contactEntries.length; i++) {
      if (i > 0 && i % 8 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final entry = contactEntries[i];
      final contactKeyHex = entry.key;
      var latestSummary = _loadedContactMessageSummary(contactKeyHex);
      latestSummary ??= await _messageStore.loadMessageSummary(
        contactKeyHex,
        includeLegacyUnscoped: !isOfflineMode,
      );
      if (entry.value && selfPublicKeyHex.isNotEmpty) {
        final sharedSummary = await _sharedMessageHistoryHelper
            .loadSecondaryContactMessageSummary(
              currentPublicKeyHex: selfPublicKeyHex,
              contactKeyHex: contactKeyHex,
            );
        if (sharedSummary != null &&
            (latestSummary == null ||
                sharedSummary.latestMessageAt.isAfter(
                  latestSummary.latestMessageAt,
                ))) {
          latestSummary = sharedSummary;
        }
      }
      previewChanged =
          _cacheContactMessagePreview(
            contactKeyHex,
            latestSummary,
            replace: true,
          ) ||
          previewChanged;
      if (latestSummary == null) {
        changed = _clearContactMessageSummary(contactKeyHex) || changed;
      } else {
        changed =
            _applyContactMessageSummary(
              contactKeyHex,
              latestSummary.latestMessageAt,
            ) ||
            changed;
      }
    }
    if (changed && persistChanges) {
      unawaited(_persistContacts());
      unawaited(_persistDiscoveredContacts());
    }
    if (changed || previewChanged) notifyListeners();
  }

  bool _canUseSharedContactHistorySummary(Contact contact) {
    return !(_isOfflineMode && !_isOfflineSharedMode) &&
        _sharedContactsEnabled &&
        contact.type != advTypeRoom;
  }

  void _applyContactMessageSummaryFromMessages(
    String contactKeyHex,
    List<Message> messages,
  ) {
    final summary = _messageSummaryFromMessages(messages);
    if (summary == null) return;
    final previewChanged = _cacheContactMessagePreview(contactKeyHex, summary);
    final summaryChanged = _applyContactMessageSummary(
      contactKeyHex,
      summary.latestMessageAt,
    );
    if (summaryChanged) {
      unawaited(_persistContacts());
      unawaited(_persistDiscoveredContacts());
    }
    if (summaryChanged || previewChanged) {
      notifyListeners();
    }
  }

  DateTime? _loadedContactMessageSummaryAt(String contactKeyHex) {
    return _loadedContactMessageSummary(contactKeyHex)?.latestMessageAt;
  }

  MessageStoreSummary? _loadedContactMessageSummary(String contactKeyHex) {
    return _messageSummaryFromMessages(
      _conversations[contactKeyHex] ?? const <Message>[],
    );
  }

  MessageStoreSummary? _messageSummaryFromMessages(Iterable<Message> messages) {
    Message? latestMessage;
    var messageCount = 0;
    for (final message in messages) {
      if (message.isCli) continue;
      messageCount++;
      if (latestMessage == null ||
          message.timestamp.isAfter(latestMessage.timestamp)) {
        latestMessage = message;
      }
    }
    if (latestMessage == null) return null;
    return MessageStoreSummary(
      messageCount: messageCount,
      latestMessageAt: latestMessage.timestamp,
      latestMessageText: latestMessage.text,
    );
  }

  bool _cacheContactMessagePreview(
    String contactKeyHex,
    MessageStoreSummary? summary, {
    bool replace = false,
  }) {
    if (summary == null) {
      return _contactMessagePreviews.remove(contactKeyHex) != null;
    }
    final current = _contactMessagePreviews[contactKeyHex];
    if (!replace &&
        current != null &&
        current.timestamp.isAfter(summary.latestMessageAt)) {
      return false;
    }
    if (current?.timestamp == summary.latestMessageAt &&
        current?.text == summary.latestMessageText) {
      return false;
    }
    _contactMessagePreviews[contactKeyHex] = (
      text: summary.latestMessageText,
      timestamp: summary.latestMessageAt,
    );
    return true;
  }

  bool _applyContactMessageSummary(
    String contactKeyHex,
    DateTime latestMessageAt,
  ) {
    var changed = false;
    for (var i = 0; i < _contacts.length; i++) {
      final contact = _contacts[i];
      if (contact.publicKeyHex != contactKeyHex ||
          !_supportsContactMessageSummary(contact)) {
        continue;
      }
      if (!contact.hasMessages ||
          latestMessageAt.isAfter(contact.lastMessageAt)) {
        _contacts[i] = contact.copyWith(
          hasMessages: true,
          lastMessageAt: latestMessageAt.isAfter(contact.lastMessageAt)
              ? latestMessageAt
              : contact.lastMessageAt,
        );
        changed = true;
      }
    }
    for (var i = 0; i < _discoveredContacts.length; i++) {
      final contact = _discoveredContacts[i];
      if (contact.publicKeyHex != contactKeyHex ||
          !_supportsContactMessageSummary(contact)) {
        continue;
      }
      if (!contact.hasMessages ||
          latestMessageAt.isAfter(contact.lastMessageAt)) {
        _discoveredContacts[i] = contact.copyWith(
          hasMessages: true,
          lastMessageAt: latestMessageAt.isAfter(contact.lastMessageAt)
              ? latestMessageAt
              : contact.lastMessageAt,
        );
        changed = true;
      }
    }
    return changed;
  }

  bool _clearContactMessageSummary(String contactKeyHex) {
    var changed = false;
    for (var i = 0; i < _contacts.length; i++) {
      final contact = _contacts[i];
      if (contact.publicKeyHex != contactKeyHex ||
          !_supportsContactMessageSummary(contact) ||
          !contact.hasMessages) {
        continue;
      }
      _contacts[i] = contact.copyWith(hasMessages: false);
      changed = true;
    }
    for (var i = 0; i < _discoveredContacts.length; i++) {
      final contact = _discoveredContacts[i];
      if (contact.publicKeyHex != contactKeyHex ||
          !_supportsContactMessageSummary(contact) ||
          !contact.hasMessages) {
        continue;
      }
      _discoveredContacts[i] = contact.copyWith(hasMessages: false);
      changed = true;
    }
    return changed;
  }

  ({bool hasMessages, DateTime lastMessageAt}) _mergedContactMessageSummary(
    Contact existing,
    Contact contact,
  ) {
    final loadedLatest = _loadedContactMessageSummaryAt(existing.publicKeyHex);
    if (loadedLatest != null) {
      return (
        hasMessages: true,
        lastMessageAt: loadedLatest.isAfter(existing.lastMessageAt)
            ? loadedLatest
            : existing.lastMessageAt,
      );
    }
    if (contact.hasMessages) {
      return (
        hasMessages: true,
        lastMessageAt: contact.lastMessageAt.isAfter(existing.lastMessageAt)
            ? contact.lastMessageAt
            : existing.lastMessageAt,
      );
    }
    return (hasMessages: false, lastMessageAt: existing.lastMessageAt);
  }

  void _captureContactMessageSummarySnapshot() {
    _contactMessageSummarySnapshot
      ..clear()
      ..addEntries([
        for (final contact in _contacts)
          if (_supportsContactMessageSummary(contact) && contact.hasMessages)
            MapEntry(contact.publicKeyHex, contact.lastMessageAt),
        for (final contact in _discoveredContacts)
          if (_supportsContactMessageSummary(contact) && contact.hasMessages)
            MapEntry(contact.publicKeyHex, contact.lastMessageAt),
      ]);
  }

  Contact _withContactMessageSummarySnapshot(Contact contact) {
    if (!_supportsContactMessageSummary(contact)) return contact;
    final latestMessageAt =
        _contactMessageSummarySnapshot[contact.publicKeyHex];
    if (latestMessageAt == null) return contact;
    if (contact.hasMessages &&
        !latestMessageAt.isAfter(contact.lastMessageAt)) {
      return contact;
    }
    return contact.copyWith(
      hasMessages: true,
      lastMessageAt: latestMessageAt.isAfter(contact.lastMessageAt)
          ? latestMessageAt
          : contact.lastMessageAt,
    );
  }

  bool _supportsContactMessageSummary(Contact contact) {
    return contact.type == advTypeChat || contact.type == advTypeRoom;
  }

  /// Load older messages for a contact (pagination)
  Future<List<Message>> loadOlderMessages(
    String contactKeyHex, {
    int count = 50,
  }) async {
    if (isOfflineSharedMode) return const [];
    final allMessages = isOfflineMode
        ? await _messageStore.loadScopedMessages(contactKeyHex)
        : await _messageStore.loadMessages(contactKeyHex);
    final currentMessages = _conversations[contactKeyHex] ?? [];

    if (allMessages.length <= currentMessages.length) {
      return []; // No more messages to load
    }

    final currentOffset = allMessages.length - currentMessages.length;
    final fetchCount = count.clamp(0, currentOffset);
    final startIndex = currentOffset - fetchCount;

    final olderMessages = allMessages.sublist(startIndex, currentOffset);

    // Prepend to current conversation
    _conversations[contactKeyHex] = [...olderMessages, ...currentMessages];
    notifyListeners();

    return olderMessages;
  }

  List<ChannelMessage> getChannelMessages(Channel channel) {
    final primary = _channelMessages[channel.index] ?? [];
    if (isOfflineMode) return primary;
    if (!_sharedChannelsEnabled) return primary;
    _ensureSharedChannelHistory(channel);
    return _mergeChannelMessages(
      primary,
      _sharedChannelSecondaryMessages[channel.index] ?? const [],
    );
  }

  bool get _sharedChannelsEnabled =>
      _appSettingsService?.settings.sharedMessageHistoryMode.includesChannels ??
      false;

  bool get _sharedContactsEnabled =>
      _appSettingsService?.settings.sharedMessageHistoryMode.includesContacts ??
      false;

  void _ensureSharedChannelHistory(Channel channel) {
    if (!_sharedChannelsEnabled) return;
    final identityKey = _sharedChannelIdentityKey(channel);
    if (_hiddenSharedChannelIdentityKeys[channel.index] == identityKey) return;
    if (_hiddenSharedChannelIdentityKeys.containsKey(channel.index)) {
      _hiddenSharedChannelIdentityKeys.remove(channel.index);
    }
    if (_loadingSharedChannelIndexes.contains(channel.index)) return;
    if (_sharedChannelSecondaryMessages.containsKey(channel.index) &&
        _sharedChannelSecondaryIdentityKeys[channel.index] == identityKey) {
      return;
    }
    _sharedChannelSecondaryMessages.remove(channel.index);
    _sharedChannelSecondaryIdentityKeys.remove(channel.index);
    if (selfPublicKeyHex.isEmpty || channel.isEmpty) return;

    final expectedPublicKeyHex = selfPublicKeyHex;
    _loadingSharedChannelIndexes.add(channel.index);
    unawaited(() async {
      try {
        final secondary = await _sharedMessageHistoryHelper
            .loadSecondaryChannelMessages(
              currentPublicKeyHex: expectedPublicKeyHex,
              channel: channel,
            );
        if (expectedPublicKeyHex != selfPublicKeyHex) return;
        _sharedChannelSecondaryMessages[channel.index] = secondary;
        _sharedChannelSecondaryIdentityKeys[channel.index] = identityKey;
        notifyListeners();
      } finally {
        _loadingSharedChannelIndexes.remove(channel.index);
      }
    }());
  }

  void _ensureSharedContactHistory(Contact contact) {
    if (!_sharedContactsEnabled || contact.type == advTypeRoom) return;
    final contactKeyHex = contact.publicKeyHex;
    if (_hiddenSharedContactKeys.contains(contactKeyHex)) return;
    if (_loadingSharedContactKeys.contains(contactKeyHex)) return;
    if (_sharedContactSecondaryMessages.containsKey(contactKeyHex)) return;
    if (selfPublicKeyHex.isEmpty || contactKeyHex.isEmpty) return;

    final expectedPublicKeyHex = selfPublicKeyHex;
    _loadingSharedContactKeys.add(contactKeyHex);
    unawaited(() async {
      try {
        final secondary = await _sharedMessageHistoryHelper
            .loadSecondaryContactMessages(
              currentPublicKeyHex: expectedPublicKeyHex,
              contactKeyHex: contactKeyHex,
            );
        if (expectedPublicKeyHex != selfPublicKeyHex) return;
        _sharedContactSecondaryMessages[contactKeyHex] = secondary;
        notifyListeners();
      } finally {
        _loadingSharedContactKeys.remove(contactKeyHex);
      }
    }());
  }

  List<ChannelMessage> _mergeChannelMessages(
    List<ChannelMessage> primary,
    List<ChannelMessage> secondary,
  ) {
    return mergeChannelMessagesPreservingPrimaryOrder(primary, secondary);
  }

  @visibleForTesting
  static List<ChannelMessage> mergeChannelMessagesPreservingPrimaryOrder(
    List<ChannelMessage> primary,
    List<ChannelMessage> secondary,
  ) {
    if (secondary.isEmpty) return primary;
    if (primary.isEmpty) return secondary;
    final merged = <ChannelMessage>[...primary];
    final knownKeys = primary.map(_sharedChannelMessageKey).toSet();
    for (final message in secondary) {
      final key = _sharedChannelMessageKey(message);
      if (knownKeys.contains(key)) continue;
      final insertAt = merged.indexWhere(
        (current) => current.receivedAt.isAfter(message.receivedAt),
      );
      if (insertAt < 0) {
        merged.add(message);
      } else {
        merged.insert(insertAt, message);
      }
      knownKeys.add(key);
    }
    return merged;
  }

  List<Message> _mergeContactMessages(
    List<Message> primary,
    List<Message> secondary,
  ) {
    if (secondary.isEmpty) return primary;
    final merged = <Message>[...primary, ...secondary];
    merged.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return merged;
  }

  List<ChannelMessage> _orderedChannelMessages(List<ChannelMessage> messages) {
    if (messages.length < 2) return messages;
    final ordered = List<ChannelMessage>.of(messages);
    ordered.sort(_compareChannelMessages);
    return ordered;
  }

  int _compareChannelMessages(ChannelMessage a, ChannelMessage b) {
    final receivedCompare = a.receivedAt.compareTo(b.receivedAt);
    if (receivedCompare != 0) return receivedCompare;
    return a.messageId.compareTo(b.messageId);
  }

  static String _sharedChannelMessageKey(ChannelMessage message) {
    final timestamp = message.timestamp;
    final hourKey =
        '${timestamp.year.toString().padLeft(4, '0')}-'
        '${timestamp.month.toString().padLeft(2, '0')}-'
        '${timestamp.day.toString().padLeft(2, '0')}-'
        '${timestamp.hour.toString().padLeft(2, '0')}';
    return [
      message.senderName.trim().toLowerCase(),
      message.text,
      hourKey,
    ].join('\u001f');
  }

  String _sharedChannelIdentityKey(Channel channel) {
    return '${channel.name.trim().toLowerCase()}|${channel.pskHex.toLowerCase()}';
  }

  Future<void> deleteChannelMessage(ChannelMessage message) async {
    _retriableChannelMessageSends.remove(message.messageId);
    final pending = _pendingChannelSends.remove(message.messageId);
    if (pending != null) {
      pending.timer?.cancel();
      notifyListeners();
      return;
    }
    final channelIndex = message.channelIndex;
    if (channelIndex == null) return;
    final messages = _channelMessages[channelIndex];
    if (messages == null) return;
    final removed = messages.remove(message);
    if (!removed) return;
    _cancelChannelNoRetransmissionWarning(message.messageId);
    await _channelMessageStore.saveChannelMessages(channelIndex, messages);
    notifyListeners();
  }

  int getUnreadCountForContact(Contact contact) {
    if (contact.type == advTypeRepeater) return 0;
    return getUnreadCountForContactKey(contact.publicKeyHex);
  }

  int getUnreadCountForContactKey(String contactKeyHex) {
    if (!_unreadStateLoaded) return 0;
    if (!_shouldTrackUnreadForContactKey(contactKeyHex)) return 0;
    return _contactUnreadCount[contactKeyHex] ?? 0;
  }

  int getUnreadCountForChannel(Channel channel) {
    return getUnreadCountForChannelIndex(channel.index);
  }

  int getUnreadCountForChannelIndex(int channelIndex) {
    if (!_unreadStateLoaded) return 0;
    return _findChannelByIndex(channelIndex)?.unreadCount ?? 0;
  }

  int getTotalUnreadCount() {
    if (!_unreadStateLoaded) return 0;
    return getTotalContactsUnreadCount() + getTotalChannelsUnreadCount();
  }

  int getTotalContactsUnreadCount() {
    if (!_unreadStateLoaded) return 0;
    return _cachedContactsUnreadTotal;
  }

  int getTotalChannelsUnreadCount() {
    if (!_unreadStateLoaded) return 0;
    return _cachedChannelsUnreadTotal;
  }

  /// Recalculates both cached unread totals from scratch.
  /// Called when unread state is first loaded.
  void _recalculateCachedUnreadTotals() {
    _recalculateCachedContactsUnreadTotal();
    _recalculateCachedChannelsUnreadTotal();
  }

  void _recalculateCachedContactsUnreadTotal() {
    int total = 0;
    _contactUnreadCount.forEach((contactKeyHex, count) {
      if (_shouldTrackUnreadForContactKey(contactKeyHex)) {
        total += count;
      }
    });
    _cachedContactsUnreadTotal = total;
  }

  void _recalculateCachedChannelsUnreadTotal() {
    final allChannels = _channels.isNotEmpty ? _channels : _cachedChannels;
    _cachedChannelsUnreadTotal = allChannels.fold(
      0,
      (total, ch) => total + ch.unreadCount,
    );
  }

  bool isChannelMcmpEnabled(int channelIndex) {
    return _channelMcmpEnabled[channelIndex] ?? false;
  }

  int channelMcmpVersion(int channelIndex) {
    return _channelMcmpVersion[channelIndex] ?? 2;
  }

  bool channelMcmpUseSign(int channelIndex) {
    return _channelMcmpUseSign[channelIndex] ?? true;
  }

  bool isChannelSmazEnabled(int channelIndex) {
    return _channelSmazEnabled[channelIndex] ?? false;
  }

  bool isContactMcmpEnabled(String contactKeyHex) {
    return _contactMcmpEnabled[contactKeyHex] ?? false;
  }

  int contactMcmpVersion(String contactKeyHex) {
    return _contactMcmpVersion[contactKeyHex] ?? 2;
  }

  bool contactMcmpUseSign(String contactKeyHex) {
    return _contactMcmpUseSign[contactKeyHex] ?? true;
  }

  bool isContactSmazEnabled(String contactKeyHex) {
    return _contactSmazEnabled[contactKeyHex] ?? false;
  }

  void ensureContactMcmpSettingLoaded(String contactKeyHex) {
    _ensureContactMcmpSettingLoaded(contactKeyHex);
    _ensureContactMcmpVersionLoaded(contactKeyHex);
    _ensureContactMcmpUseSignLoaded(contactKeyHex);
  }

  bool hasChannelRegion(int channelIndex) {
    return (_channelRegions[channelIndex] ?? '').isNotEmpty;
  }

  Region getChannelRegion(int channelIndex) {
    return _channelRegions[channelIndex] ?? '';
  }

  Region _outgoingChannelRegion(int channelIndex) {
    final channelRegion = getChannelRegion(channelIndex).trim();
    if (channelRegion.isNotEmpty) return channelRegion;
    return _defaultRegionScope?.trim() ?? '';
  }

  void _setDefaultRegionScopeCache(String? region) {
    final normalized = region?.trim();
    _defaultRegionScope = normalized == null || normalized.isEmpty
        ? null
        : normalized;
  }

  Future<void> _refreshDefaultRegionScope() async {
    final existing = _defaultRegionScopeRefreshFuture;
    if (existing != null) {
      await existing;
      return;
    }

    late final Future<void> refresh;
    refresh = () async {
      try {
        await getDefaultRegionScope();
      } catch (error) {
        _appDebugLogService?.warn(
          'Failed to refresh default region scope: $error',
          tag: 'Regions',
        );
      } finally {
        if (isConnected) {
          _hasLoadedDefaultRegionScope = true;
        }
        if (identical(_defaultRegionScopeRefreshFuture, refresh)) {
          _defaultRegionScopeRefreshFuture = null;
        }
      }
    }();
    _defaultRegionScopeRefreshFuture = refresh;
    await refresh;
  }

  Future<Region> _outgoingChannelRegionForMessage(int channelIndex) async {
    final channelRegion = getChannelRegion(channelIndex).trim();
    if (channelRegion.isNotEmpty) return channelRegion;
    if (!_hasLoadedDefaultRegionScope && isConnected) {
      await _refreshDefaultRegionScope();
    }
    return _outgoingChannelRegion(channelIndex);
  }

  void ensureContactSmazSettingLoaded(String contactKeyHex) {
    _ensureContactSmazSettingLoaded(contactKeyHex);
  }

  bool isChannelCyr2LatEnabled(int channelIndex) {
    _ensureChannelCyr2LatSettingLoaded(channelIndex);
    return _channelCyr2LatEnabled[channelIndex] ?? false;
  }

  bool isContactCyr2LatEnabled(String contactKeyHex) {
    _ensureContactCyr2LatSettingLoaded(contactKeyHex);
    return _contactCyr2LatEnabled[contactKeyHex] ?? false;
  }

  void ensureContactCyr2LatSettingLoaded(String contactKeyHex) {
    _ensureContactCyr2LatSettingLoaded(contactKeyHex);
  }

  void ensureContactSendingDelaySettingLoaded(String contactKeyHex) {
    _ensureContactSendingDelaySettingLoaded(contactKeyHex);
  }

  void ensureContactQuickAnswerIdsLoaded(String contactKeyHex) {
    _ensureContactQuickAnswerIdsLoaded(contactKeyHex);
  }

  bool isChannelSendingDelayEnabled(int channelIndex) {
    _ensureChannelSendingDelaySettingLoaded(channelIndex);
    return _channelSendingDelayEnabled[channelIndex] ?? false;
  }

  bool isContactSendingDelayEnabled(String contactKeyHex) {
    _ensureContactSendingDelaySettingLoaded(contactKeyHex);
    return _contactSendingDelayEnabled[contactKeyHex] ?? false;
  }

  List<String> getChannelQuickAnswerIds(int channelIndex) {
    _ensureChannelQuickAnswerIdsLoaded(channelIndex);
    return List.unmodifiable(_channelQuickAnswerIds[channelIndex] ?? const []);
  }

  List<String> getContactQuickAnswerIds(String contactKeyHex) {
    _ensureContactQuickAnswerIdsLoaded(contactKeyHex);
    return List.unmodifiable(_contactQuickAnswerIds[contactKeyHex] ?? const []);
  }

  Future<List<String>> loadChannelQuickAnswerIds(int channelIndex) async {
    final answerIds = await _channelSettingsStore.loadQuickAnswerIds(
      channelIndex,
    );
    _channelQuickAnswerIds[channelIndex] = answerIds;
    notifyListeners();
    return List.unmodifiable(answerIds);
  }

  Future<List<String>> loadContactQuickAnswerIds(String contactKeyHex) async {
    final answerIds = await _contactSettingsStore.loadQuickAnswerIds(
      contactKeyHex,
    );
    _contactQuickAnswerIds[contactKeyHex] = answerIds;
    notifyListeners();
    return List.unmodifiable(answerIds);
  }

  Future<bool> loadContactSendingDelayEnabled(String contactKeyHex) async {
    final cached = _contactSendingDelayEnabled[contactKeyHex];
    if (cached != null) return cached;
    final enabled = await _contactSettingsStore.loadSendingDelayEnabled(
      contactKeyHex,
    );
    _contactSendingDelayEnabled[contactKeyHex] = enabled;
    notifyListeners();
    return enabled;
  }

  Future<void> loadUnreadState() async {
    _contactUnreadCount
      ..clear()
      ..addAll(await _unreadStore.loadContactUnreadCount());
    _unreadStateLoaded = true;
    _recalculateCachedUnreadTotals();
    notifyListeners();
  }

  Future<void> loadCachedChannels({String? publicKeyHex}) async {
    final expectedPublicKeyHex = publicKeyHex ?? selfPublicKeyHex;
    final store = publicKeyHex == null
        ? _channelStore
        : (ChannelStore()..setPublicKeyHex = publicKeyHex);
    final cached = await store.loadChannels();
    if (expectedPublicKeyHex != selfPublicKeyHex) return;
    _cachedChannels = cached;
    _replaceChannelStorageBindings(cached);
    _recalculateCachedChannelsUnreadTotal();
    try {
      await loadChannelSettings(
        publicKeyHex: expectedPublicKeyHex,
        channelBindings: cached,
      );
      await loadAllChannelMessages(
        publicKeyHex: expectedPublicKeyHex,
        channelBindings: cached,
      );
    } finally {
      if (expectedPublicKeyHex == selfPublicKeyHex) {
        _channelMessageStore.finishLegacyIndexMigration();
        _channelSettingsStore.finishLegacyIndexMigration();
        _channelRegionStore.finishLegacyIndexMigration();
      }
    }
  }

  Future<void> _prepareCachedChannelStorage(String publicKeyHex) async {
    try {
      await loadCachedChannels(publicKeyHex: publicKeyHex);
    } catch (error, stackTrace) {
      _appDebugLogService?.error(
        'Failed to load name-keyed channel storage: $error',
        tag: 'Channel storage',
      );
      appLogger.error(
        'Failed to load name-keyed channel storage: $error\n$stackTrace',
        tag: 'Channel storage',
      );
    } finally {
      if (publicKeyHex == selfPublicKeyHex) {
        _hasLoadedCachedChannelStorage = true;
        _maybeStartInitialChannelSync();
      }
    }
  }

  void _replaceChannelStorageBindings(Iterable<Channel> channels) {
    _channelMessageStore.replaceChannels(channels);
    _channelSettingsStore.replaceChannels(channels);
    _channelRegionStore.replaceChannels(channels);
  }

  void _registerChannelStorageBinding(Channel channel) {
    _channelMessageStore.registerChannel(channel);
    _channelSettingsStore.registerChannel(channel);
    _channelRegionStore.registerChannel(channel);
  }

  void setActiveContact(String? contactKeyHex) {
    if (contactKeyHex != null &&
        !_shouldTrackUnreadForContactKey(contactKeyHex)) {
      _activeContactKey = null;
      return;
    }
    _activeContactKey = contactKeyHex;
    if (contactKeyHex != null) {
      unawaited(_loadMessagesForContact(contactKeyHex));
      final contact = _contacts.cast<Contact?>().firstWhere(
        (entry) => entry?.publicKeyHex == contactKeyHex,
        orElse: () => null,
      );
      if (!isOfflineMode && contact != null) {
        _ensureSharedContactHistory(contact);
      }
      markContactRead(contactKeyHex);
    }
  }

  void setActiveChannel(int? channelIndex) {
    _activeChannelIndex = channelIndex;
    if (channelIndex != null) {
      final channel = _findChannelByIndex(channelIndex);
      if (!isOfflineMode && channel != null) {
        _ensureSharedChannelHistory(channel);
      }
      markChannelRead(channelIndex);
    }
  }

  void markContactRead(String contactKeyHex) {
    if (isOfflineMode) return;
    if (!_shouldTrackUnreadForContactKey(contactKeyHex)) return;
    final previousCount = _contactUnreadCount[contactKeyHex] ?? 0;
    if (previousCount > 0) {
      _contactUnreadCount[contactKeyHex] = 0;
      _cachedContactsUnreadTotal = (_cachedContactsUnreadTotal - previousCount)
          .clamp(0, _cachedContactsUnreadTotal);
      _appDebugLogService?.info(
        'Contact $contactKeyHex marked as read (was $previousCount unread)',
        tag: 'Unread',
      );
      _unreadStore.saveContactUnreadCount(
        Map<String, int>.from(_contactUnreadCount),
      );
      _notificationService.clearContactNotification(
        contactKeyHex,
        getTotalUnreadCount(),
      );
      notifyListeners();
    }
  }

  void setContactUnreadCount(String contactKeyHex, int count) {
    _contactUnreadCount[contactKeyHex] = count;
    _unreadStore.saveContactUnreadCount(
      Map<String, int>.from(_contactUnreadCount),
    );
    notifyListeners();
  }

  void setChannelUnreadCount(int channelIndex, int count) {
    final channel = _findChannelByIndex(channelIndex);
    if (channel != null) {
      channel.unreadCount = count;
      unawaited(
        _channelStore.saveChannels(
          _channels.isNotEmpty ? _channels : _cachedChannels,
        ),
      );
      notifyListeners();
    }
  }

  void markChannelRead(int channelIndex) {
    if (isOfflineMode) return;
    final channel = _findChannelByIndex(channelIndex);
    if (channel != null && channel.unreadCount > 0) {
      final previousCount = channel.unreadCount;
      channel.unreadCount = 0;
      _cachedChannelsUnreadTotal = (_cachedChannelsUnreadTotal - previousCount)
          .clamp(0, _cachedChannelsUnreadTotal);
      _appDebugLogService?.info(
        'Channel ${channel.name.isNotEmpty ? channel.name : channelIndex} marked as read (was $previousCount unread)',
        tag: 'Unread',
      );
      unawaited(
        _channelStore.saveChannels(
          _channels.isNotEmpty ? _channels : _cachedChannels,
        ),
      );
      _notificationService.clearChannelNotification(
        channelIndex,
        getTotalUnreadCount(),
      );
      notifyListeners();
    }
  }

  Future<void> setChannelMcmpEnabled(int channelIndex, bool enabled) async {
    _channelMcmpEnabled[channelIndex] = enabled;
    if (enabled) {
      _channelSmazEnabled[channelIndex] = false;
      _channelCyr2LatEnabled[channelIndex] = false;
      await _channelSettingsStore.saveSmazEnabled(channelIndex, false);
      await _channelSettingsStore.saveCyr2LatEnabled(channelIndex, false);
    }
    await _channelSettingsStore.saveMcmpEnabled(channelIndex, enabled);
    notifyListeners();
  }

  Future<void> setChannelMcmpVersion(int channelIndex, int version) async {
    final normalized = version == 3 ? 3 : 2;
    if (_channelMcmpVersion[channelIndex] == normalized) return;
    _channelMcmpVersion[channelIndex] = normalized;
    await _channelSettingsStore.saveMcmpVersion(channelIndex, normalized);
    notifyListeners();
  }

  Future<void> setChannelMcmpUseSign(int channelIndex, bool useSign) async {
    if (_channelMcmpUseSign[channelIndex] == useSign) return;
    _channelMcmpUseSign[channelIndex] = useSign;
    await _channelSettingsStore.saveMcmpUseSign(channelIndex, useSign);
    notifyListeners();
  }

  Future<void> setChannelSmazEnabled(int channelIndex, bool enabled) async {
    _channelSmazEnabled[channelIndex] = enabled;
    if (enabled) {
      _channelMcmpEnabled[channelIndex] = false;
      _channelCyr2LatEnabled[channelIndex] = false;
      await _channelSettingsStore.saveMcmpEnabled(channelIndex, false);
      await _channelSettingsStore.saveCyr2LatEnabled(channelIndex, false);
    }
    await _channelSettingsStore.saveSmazEnabled(channelIndex, enabled);
    notifyListeners();
  }

  Future<void> setContactMcmpEnabled(String contactKeyHex, bool enabled) async {
    _contactMcmpEnabled[contactKeyHex] = enabled;
    if (enabled) {
      _contactSmazEnabled[contactKeyHex] = false;
      _contactCyr2LatEnabled[contactKeyHex] = false;
      await _contactSettingsStore.saveSmazEnabled(contactKeyHex, false);
      await _contactSettingsStore.saveCyr2LatEnabled(contactKeyHex, false);
    }
    await _contactSettingsStore.saveMcmpEnabled(contactKeyHex, enabled);
    notifyListeners();
  }

  Future<void> setContactMcmpVersion(String contactKeyHex, int version) async {
    final normalized = version == 3 ? 3 : 2;
    if (_contactMcmpVersion[contactKeyHex] == normalized) return;
    _contactMcmpVersion[contactKeyHex] = normalized;
    await _contactSettingsStore.saveMcmpVersion(contactKeyHex, normalized);
    notifyListeners();
  }

  Future<void> setContactMcmpUseSign(String contactKeyHex, bool useSign) async {
    if (_contactMcmpUseSign[contactKeyHex] == useSign) return;
    _contactMcmpUseSign[contactKeyHex] = useSign;
    await _contactSettingsStore.saveMcmpUseSign(contactKeyHex, useSign);
    notifyListeners();
  }

  Future<void> setContactSmazEnabled(String contactKeyHex, bool enabled) async {
    _contactSmazEnabled[contactKeyHex] = enabled;
    if (enabled) {
      _contactMcmpEnabled[contactKeyHex] = false;
      _contactCyr2LatEnabled[contactKeyHex] = false;
      await _contactSettingsStore.saveMcmpEnabled(contactKeyHex, false);
      await _contactSettingsStore.saveCyr2LatEnabled(contactKeyHex, false);
    }
    await _contactSettingsStore.saveSmazEnabled(contactKeyHex, enabled);
    notifyListeners();
  }

  Future<void> setChannelCyr2LatEnabled(int channelIndex, bool enabled) async {
    if (_channelCyr2LatEnabled[channelIndex] == enabled) return;
    _channelCyr2LatEnabled[channelIndex] = enabled;
    if (enabled) {
      _channelMcmpEnabled[channelIndex] = false;
      _channelSmazEnabled[channelIndex] = false;
      await _channelSettingsStore.saveMcmpEnabled(channelIndex, false);
      await _channelSettingsStore.saveSmazEnabled(channelIndex, false);
    }
    await _channelSettingsStore.saveCyr2LatEnabled(channelIndex, enabled);
    notifyListeners();
  }

  Future<void> setContactCyr2LatEnabled(
    String contactKeyHex,
    bool enabled,
  ) async {
    if (_contactCyr2LatEnabled[contactKeyHex] == enabled) return;
    _contactCyr2LatEnabled[contactKeyHex] = enabled;
    if (enabled) {
      _contactMcmpEnabled[contactKeyHex] = false;
      _contactSmazEnabled[contactKeyHex] = false;
      await _contactSettingsStore.saveMcmpEnabled(contactKeyHex, false);
      await _contactSettingsStore.saveSmazEnabled(contactKeyHex, false);
    }
    await _contactSettingsStore.saveCyr2LatEnabled(contactKeyHex, enabled);
    notifyListeners();
  }

  Future<void> setChannelSendingDelayEnabled(
    int channelIndex,
    bool enabled,
  ) async {
    if (_channelSendingDelayEnabled[channelIndex] == enabled) return;
    _channelSendingDelayEnabled[channelIndex] = enabled;
    await _channelSettingsStore.saveSendingDelayEnabled(channelIndex, enabled);
    notifyListeners();
  }

  Future<void> setContactSendingDelayEnabled(
    String contactKeyHex,
    bool enabled,
  ) async {
    if (_contactSendingDelayEnabled[contactKeyHex] == enabled) return;
    _contactSendingDelayEnabled[contactKeyHex] = enabled;
    await _contactSettingsStore.saveSendingDelayEnabled(contactKeyHex, enabled);
    notifyListeners();
  }

  Future<void> setChannelQuickAnswerIds(
    int channelIndex,
    List<String> answerIds,
  ) async {
    final normalized = AppSettings.normalizeQuickAnswerIds(answerIds);
    if (listEquals(_channelQuickAnswerIds[channelIndex], normalized)) return;
    _channelQuickAnswerIds[channelIndex] = normalized;
    await _channelSettingsStore.saveQuickAnswerIds(channelIndex, normalized);
    notifyListeners();
  }

  Future<void> setContactQuickAnswerIds(
    String contactKeyHex,
    List<String> answerIds,
  ) async {
    final normalized = AppSettings.normalizeQuickAnswerIds(answerIds);
    if (listEquals(_contactQuickAnswerIds[contactKeyHex], normalized)) return;
    _contactQuickAnswerIds[contactKeyHex] = normalized;
    await _contactSettingsStore.saveQuickAnswerIds(contactKeyHex, normalized);
    notifyListeners();
  }

  Future<void> setChannelRegion(int channelIndex, String region) async {
    final normalized = await _channelRegionStore.saveRegion(
      channelIndex,
      region,
    );
    if (normalized.isEmpty) {
      _channelRegions.remove(channelIndex);
    } else {
      _channelRegions[channelIndex] = normalized;
    }
    notifyListeners();
  }

  Future<String?> getDefaultRegionScope() async {
    if (!isConnected) return null;

    final completer = Completer<String?>();
    late final StreamSubscription<Uint8List> subscription;
    late final Timer timeout;

    void complete(String? region) {
      if (!completer.isCompleted) completer.complete(region);
    }

    void completeError(Object error) {
      if (!completer.isCompleted) completer.completeError(error);
    }

    subscription = receivedFrames.listen((frame) {
      if (frame.isEmpty) return;
      if (frame[0] == respCodeDefaultFloodScope) {
        complete(parseDefaultFloodScopeFrame(frame));
      }
    });

    timeout = Timer(_commandAckTimeout, () {
      completeError(TimeoutException('Default region scope request timed out'));
    });

    try {
      await sendFrame(buildGetDefaultFloodScopeFrame());
      final region = await completer.future;
      _setDefaultRegionScopeCache(region);
      _hasLoadedDefaultRegionScope = true;
      return region;
    } finally {
      timeout.cancel();
      await subscription.cancel();
    }
  }

  Future<void> setDefaultRegionScope(String? region) async {
    await sendFrame(
      buildSetDefaultFloodScopeFrame(region),
      waitForGenericAck: true,
    );
    _setDefaultRegionScopeCache(region);
    _hasLoadedDefaultRegionScope = true;
  }

  Future<void> _loadChannelOrder({
    String? publicKeyHex,
    bool allowLegacyMigration = true,
  }) async {
    final expectedPublicKeyHex = publicKeyHex ?? selfPublicKeyHex;
    final store = publicKeyHex == null
        ? _channelOrderStore
        : (ChannelOrderStore()..setPublicKeyHex = publicKeyHex);
    final channelOrder = await store.loadChannelOrder(
      allowLegacyMigration: allowLegacyMigration,
    );
    if (expectedPublicKeyHex != selfPublicKeyHex) return;
    _channelOrder = channelOrder;
    _applyChannelOrder();
    notifyListeners();
  }

  /// Load persisted channel messages for a specific channel
  Future<bool> _loadChannelMessages(
    int channelIndex, {
    bool notify = true,
    ChannelMessageStore? store,
    String? expectedPublicKeyHex,
    bool allowLegacyMigration = true,
  }) async {
    final allMessages = await (store ?? _channelMessageStore)
        .loadChannelMessages(
          channelIndex,
          allowLegacyMigration: allowLegacyMigration,
        );
    if (expectedPublicKeyHex != null &&
        expectedPublicKeyHex != selfPublicKeyHex) {
      return false;
    }
    if (allMessages.isNotEmpty) {
      // Keep only the most recent N messages in memory to bound memory usage
      final orderedMessages = _orderedChannelMessages(allMessages);
      final windowedMessages = orderedMessages.length > _messageWindowSize
          ? orderedMessages.sublist(orderedMessages.length - _messageWindowSize)
          : orderedMessages;

      _channelMessages[channelIndex] = windowedMessages;
      if (notify) notifyListeners();
      return true;
    } else {
      final removed = _channelMessages.remove(channelIndex) != null;
      if (removed && notify) notifyListeners();
      return removed;
    }
  }

  /// Load older channel messages (pagination)
  Future<List<ChannelMessage>> loadOlderChannelMessages(
    int channelIndex, {
    int count = 50,
  }) async {
    if (isOfflineSharedMode) return const [];
    final allMessages = _orderedChannelMessages(
      await _channelMessageStore.loadChannelMessages(
        channelIndex,
        allowLegacyMigration: !isOfflineMode,
      ),
    );
    final currentMessages = _channelMessages[channelIndex] ?? [];

    if (allMessages.length <= currentMessages.length) {
      return []; // No more messages to load
    }

    final currentOffset = allMessages.length - currentMessages.length;
    final fetchCount = count.clamp(0, currentOffset);
    final startIndex = currentOffset - fetchCount;

    final olderMessages = allMessages.sublist(startIndex, currentOffset);

    // Prepend to current conversation
    _channelMessages[channelIndex] = _orderedChannelMessages([
      ...olderMessages,
      ...currentMessages,
    ]);
    notifyListeners();

    return olderMessages;
  }

  /// Load all persisted channel messages on startup
  Future<void> loadAllChannelMessages({
    int? maxChannels,
    String? publicKeyHex,
    Iterable<Channel>? channelBindings,
    bool allowLegacyMigration = true,
  }) async {
    final expectedPublicKeyHex = publicKeyHex ?? selfPublicKeyHex;
    final store = publicKeyHex == null
        ? _channelMessageStore
        : (ChannelMessageStore()..setPublicKeyHex = publicKeyHex);
    store.replaceChannels(
      channelBindings ?? (_channels.isNotEmpty ? _channels : _cachedChannels),
    );
    final channelCount = maxChannels ?? _maxChannels;
    var changed = false;
    // Load messages for all known channels (0-7 by default)
    for (int i = 0; i < channelCount; i++) {
      changed =
          await _loadChannelMessages(
            i,
            notify: false,
            store: store,
            expectedPublicKeyHex: expectedPublicKeyHex,
            allowLegacyMigration: allowLegacyMigration,
          ) ||
          changed;
      if (expectedPublicKeyHex != selfPublicKeyHex) return;
    }
    if (changed) notifyListeners();
  }

  void initialize({
    required MessageRetryService retryService,
    required PathHistoryService pathHistoryService,
    AppSettingsService? appSettingsService,
    SettingsSectionsService? settingsSectionsService,
    TranslationService? translationService,
    BleDebugLogService? bleDebugLogService,
    AppDebugLogService? appDebugLogService,
    BackgroundService? backgroundService,
    TimeoutPredictionService? timeoutPredictionService,
  }) {
    _retryService = retryService;
    _pathHistoryService = pathHistoryService;
    _appSettingsService?.removeListener(_handleAppSettingsChanged);
    _appSettingsService = appSettingsService;
    _lastSharedMessageHistoryMode =
        appSettingsService?.settings.sharedMessageHistoryMode ??
        SharedMessageHistoryMode.disabled;
    _lastNoRetransmissionWarningSeconds =
        appSettingsService?.settings.noRetransmissionWarningSeconds ?? 0;
    _appSettingsService?.addListener(_handleAppSettingsChanged);
    _settingsSectionsService?.removeListener(_handleSettingsSectionsChanged);
    _settingsSectionsService = settingsSectionsService;
    settingsSectionsService?.setDeviceVarsRequester(() async {
      if (!isConnected) return;
      await sendFrame(buildGetCustomVarsFrame());
    });
    _lastSouthNodeEnableFragmentedFrames =
        settingsSectionsService?.southFrameFragmentsEnabled ?? false;
    _settingsSectionsService?.addListener(_handleSettingsSectionsChanged);
    _translationService = translationService;
    _bleDebugLogService = bleDebugLogService;
    _appDebugLogService = appDebugLogService;
    _southFrameFragmentReassembler.onWarning = (message) {
      _appDebugLogService?.warn(message, tag: 'Protocol');
    };
    _backgroundService = backgroundService;
    _timeoutPredictionService = timeoutPredictionService;
    _usbManager.setDebugLogService(_appDebugLogService);
    _tcpConnector.setDebugLogService(_appDebugLogService);

    // Initialize notification service
    _notificationService.initialize();
    _loadChannelOrder();

    // Initialize retry service callbacks
    _retryService?.initialize(
      RetryServiceConfig(
        sendMessage: _sendMessageDirect,
        addMessage: _addMessage,
        updateMessage: _updateMessage,
        clearContactPath: clearContactPath,
        setContactPath: setContactPath,
        calculateTimeout:
            (
              pathLength,
              messageBytes, {
              String? contactKey,
              int? deviceTimeoutMs,
            }) => calculateTimeout(
              pathLength: pathLength,
              messageBytes: messageBytes,
              contactKey: contactKey,
              deviceTimeoutMs: deviceTimeoutMs,
            ),
        getSelfPublicKey: () => _selfPublicKey,
        // The retry service computes wire-facing values (ACK hashes); it must
        // never see the size-estimation signature placeholder.
        prepareContactOutboundText: (contact, text) =>
            prepareContactOutboundText(
              contact,
              text,
              estimateSignatureOverhead: false,
            ),
        appSettingsService: appSettingsService,
        debugLogService: _appDebugLogService,
        recordPathResult: _recordPathResult,
        selectRetryPath:
            (contactKey, attemptIndex, maxRetries, recentSelections) =>
                _selectAutoPathForAttempt(
                  contactKey,
                  attemptIndex: attemptIndex,
                  maxRetries: maxRetries,
                  recentSelections: recentSelections,
                ),
        onDeliveryObserved: (contactKey, pathLength, messageBytes, tripTimeMs) {
          final secSinceRx = DateTime.now()
              .difference(_lastRxBeforeFrame)
              .inSeconds;
          _timeoutPredictionService?.recordObservation(
            contactKey: contactKey,
            pathLength: pathLength,
            messageBytes: messageBytes,
            tripTimeMs: tripTimeMs,
            secondsSinceLastRx: secSinceRx,
          );
        },
      ),
    );
    final maxRetries = _appSettingsService?.settings.maxMessageRetries ?? 5;
    _retryService?.setMaxRetries(maxRetries);
  }

  void _handleSettingsSectionsChanged() {
    final fragmentedFramesEnabled = _southFrameFragmentsEnabled;
    if (fragmentedFramesEnabled != _lastSouthNodeEnableFragmentedFrames) {
      _lastSouthNodeEnableFragmentedFrames = fragmentedFramesEnabled;
      _southFrameFragmentReassembler.clear();
      _southQueuedFragmentAckTracker.clear();
      if (isConnected) unawaited(_renegotiateSouthFrameFragments());
    }
  }

  void _handleAppSettingsChanged() {
    final settings = _appSettingsService?.settings;
    _syncBackgroundTcpService();
    final noRetransmissionWarningSeconds =
        settings?.noRetransmissionWarningSeconds ?? 0;
    if (noRetransmissionWarningSeconds != _lastNoRetransmissionWarningSeconds) {
      _lastNoRetransmissionWarningSeconds = noRetransmissionWarningSeconds;
      if (noRetransmissionWarningSeconds <= 0) {
        _cancelAllChannelNoRetransmissionTimers();
      }
    }
    final mode =
        settings?.sharedMessageHistoryMode ?? SharedMessageHistoryMode.disabled;
    if (mode == _lastSharedMessageHistoryMode) return;
    _lastSharedMessageHistoryMode = mode;
    _clearSharedMessageHistoryCache();
    _refreshActiveSharedMessageHistory();
    unawaited(_refreshContactMessageSummaries());
    notifyListeners();
  }

  bool get _southFrameFragmentsEnabled =>
      _settingsSectionsService?.southFrameFragmentsEnabled ?? false;

  Uint8List _buildAppStartFrame() {
    // Firmware treats every APP_START as a fresh fragmentation session.
    _southFrameFragmentReassembler.clear();
    _southQueuedFragmentAckTracker.clear();
    return buildAppStartFrame(
      appName: buildMeshCoreOpenAppName(
        enableSouthFrameFragments: _southFrameFragmentsEnabled,
      ),
    );
  }

  Future<void> _renegotiateSouthFrameFragments() async {
    try {
      await sendFrame(_buildAppStartFrame());
    } catch (error) {
      _appDebugLogService?.warn(
        'Could not renegotiate FR01 support: $error',
        tag: 'Protocol',
      );
    }
  }

  bool get _shouldKeepTcpInBackground {
    return PlatformInfo.isAndroid &&
        _activeTransport == MeshCoreTransportType.tcp &&
        _state == MeshCoreConnectionState.connected &&
        (_appSettingsService?.settings.backgroundTcpEnabled ?? false);
  }

  void _syncBackgroundTcpService() {
    if (_shouldKeepTcpInBackground) {
      unawaited(_backgroundService?.start(reason: _backgroundTcpReason));
    } else {
      unawaited(_backgroundService?.stop(reason: _backgroundTcpReason));
    }
  }

  void _clearSharedMessageHistoryCache() {
    _sharedChannelSecondaryMessages.clear();
    _sharedChannelSecondaryIdentityKeys.clear();
    _sharedContactSecondaryMessages.clear();
    _contactMessagePreviews.clear();
    _loadingSharedChannelIndexes.clear();
    _loadingSharedContactKeys.clear();
  }

  void _clearSharedMessageHistoryState() {
    _clearSharedMessageHistoryCache();
    _hiddenSharedChannelIdentityKeys.clear();
    _hiddenSharedContactKeys.clear();
  }

  void _refreshActiveSharedMessageHistory() {
    final activeChannelIndex = _activeChannelIndex;
    if (activeChannelIndex != null) {
      final channel = _findChannelByIndex(activeChannelIndex);
      if (channel != null) {
        _ensureSharedChannelHistory(channel);
      }
    }

    final activeContactKey = _activeContactKey;
    if (activeContactKey != null) {
      final contact = _contacts.cast<Contact?>().firstWhere(
        (entry) => entry?.publicKeyHex == activeContactKey,
        orElse: () => null,
      );
      if (contact != null) {
        _ensureSharedContactHistory(contact);
      }
    }
  }

  Future<void> loadContactCache({
    String? publicKeyHex,
    int? loadGeneration,
  }) async {
    final expectedPublicKeyHex = publicKeyHex ?? selfPublicKeyHex;
    final store = publicKeyHex == null
        ? _contactStore
        : (ContactStore()..setPublicKeyHex = publicKeyHex);
    final storedContacts = await store.loadContacts();
    final cached = deduplicateContactsByPublicKey(storedContacts);
    if (expectedPublicKeyHex != selfPublicKeyHex ||
        (loadGeneration != null &&
            loadGeneration != _contactCacheLoadGeneration)) {
      return;
    }
    _knownContactKeys
      ..clear()
      ..addAll(cached.map((c) => c.publicKeyHex));
    _contacts
      ..clear()
      ..addAll(cached);
    if (cached.length != storedContacts.length) {
      await store.saveContacts(cached);
    }
    await _refreshContactMessageSummaries();
  }

  Future<void> _loadContactCacheForNode(
    String publicKeyHex,
    int loadGeneration,
  ) async {
    try {
      await loadContactCache(
        publicKeyHex: publicKeyHex,
        loadGeneration: loadGeneration,
      );
    } catch (error, stackTrace) {
      _appDebugLogService?.error(
        'Failed to load contact cache: $error',
        tag: 'Contact storage',
      );
      appLogger.error(
        'Failed to load contact cache: $error\n$stackTrace',
        tag: 'Contact storage',
      );
    }
  }

  Future<void> _loadDiscoveredContactCache() async {
    final cached = await _discoveryContactStore.loadContacts();
    // Trim a previously-saved oversized list down to the freshest entries so a
    // device that grew unbounded before the cap existed recovers on load.
    if (cached.length > _maxDiscoveredContacts) {
      cached.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
      cached.removeRange(_maxDiscoveredContacts, cached.length);
      unawaited(_discoveryContactStore.saveContacts(cached));
    }
    _discoveredContacts
      ..clear()
      ..addAll(cached);
    await _refreshContactMessageSummaries();
  }

  Future<void> loadChannelSettings({
    int? maxChannels,
    String? publicKeyHex,
    Iterable<Channel>? channelBindings,
    bool allowLegacyMigration = true,
  }) async {
    final expectedPublicKeyHex = publicKeyHex ?? selfPublicKeyHex;
    final settingsStore = publicKeyHex == null
        ? _channelSettingsStore
        : (ChannelSettingsStore()..setPublicKeyHex = publicKeyHex);
    final regionStore = publicKeyHex == null
        ? _channelRegionStore
        : (ChannelRegionStore()..setPublicKeyHex = publicKeyHex);
    final knownChannels =
        channelBindings ?? (_channels.isNotEmpty ? _channels : _cachedChannels);
    settingsStore.replaceChannels(knownChannels);
    regionStore.replaceChannels(knownChannels);
    if (!allowLegacyMigration) {
      settingsStore.finishLegacyIndexMigration();
      regionStore.finishLegacyIndexMigration();
    }
    _channelMcmpEnabled.clear();
    _channelMcmpVersion.clear();
    _channelMcmpUseSign.clear();
    _channelSmazEnabled.clear();
    _channelCyr2LatEnabled.clear();
    _channelCyr2LatProfileId.clear();
    _channelSendingDelayEnabled.clear();
    _channelQuickAnswerIds.clear();
    _channelWidgetColor.clear();
    _channelWidgetTextColor.clear();
    _channelRegions.clear();
    final channelCount = maxChannels ?? _maxChannels;
    for (int i = 0; i < channelCount; i++) {
      await _loadChannelSettingsForIndex(
        i,
        settingsStore: settingsStore,
        regionStore: regionStore,
        expectedPublicKeyHex: expectedPublicKeyHex,
      );
      if (expectedPublicKeyHex != selfPublicKeyHex) return;
    }
  }

  Future<void> _loadChannelSettingsForIndex(
    int channelIndex, {
    ChannelSettingsStore? settingsStore,
    ChannelRegionStore? regionStore,
    String? expectedPublicKeyHex,
  }) async {
    final channelSettingsStore = settingsStore ?? _channelSettingsStore;
    final channelRegionStore = regionStore ?? _channelRegionStore;
    _channelCyr2LatProfileId.remove(channelIndex);
    final mcmpEnabled = await channelSettingsStore.loadMcmpEnabled(
      channelIndex,
    );
    final mcmpVersion = await channelSettingsStore.loadMcmpVersion(
      channelIndex,
    );
    final mcmpUseSign = await channelSettingsStore.loadMcmpUseSign(
      channelIndex,
    );
    final smazEnabled = await channelSettingsStore.loadSmazEnabled(
      channelIndex,
    );
    final cyr2LatEnabled = await channelSettingsStore.loadCyr2LatEnabled(
      channelIndex,
    );
    final sendingDelayEnabled = await channelSettingsStore
        .loadSendingDelayEnabled(channelIndex);
    final quickAnswerIds = await channelSettingsStore.loadQuickAnswerIds(
      channelIndex,
    );
    final widgetColor = await channelSettingsStore.loadWidgetColor(
      channelIndex,
    );
    final widgetTextColor = await channelSettingsStore.loadWidgetTextColor(
      channelIndex,
    );
    final region = await channelRegionStore.loadRegion(channelIndex);
    if (expectedPublicKeyHex != null &&
        expectedPublicKeyHex != selfPublicKeyHex) {
      return;
    }
    _channelMcmpEnabled[channelIndex] = mcmpEnabled;
    _channelMcmpVersion[channelIndex] = mcmpVersion == 3 ? 3 : 2;
    _channelMcmpUseSign[channelIndex] = mcmpUseSign;
    _channelSmazEnabled[channelIndex] = smazEnabled;
    _channelCyr2LatEnabled[channelIndex] = cyr2LatEnabled;
    _channelSendingDelayEnabled[channelIndex] = sendingDelayEnabled;
    _channelQuickAnswerIds[channelIndex] = quickAnswerIds;
    _channelWidgetColor[channelIndex] = widgetColor;
    _channelWidgetTextColor[channelIndex] = widgetTextColor;
    if (region.isEmpty) {
      _channelRegions.remove(channelIndex);
    } else {
      _channelRegions[channelIndex] = region;
    }
  }

  /// After an incoming DM or channel message, wait before TX so we do not
  /// collide with mesh propagation. With companion stats, scale wait by RF
  /// conditions (up to [_contactMsgBackoffMaxMs]); otherwise use
  /// [_contactMsgBackoffFallbackMs].
  int _contactMessageBackoffTargetMs() {
    if (!supportsCompanionRadioStats || _latestRadioStats == null) {
      return _contactMsgBackoffFallbackMs;
    }
    final stats = _latestRadioStats!;
    final nf = stats.noiseFloorDbm.toDouble();
    // Quieter (more negative) → lower score; noisier → higher.
    const noiseQuietDbm = -118.0;
    const noiseNoisyDbm = -88.0;
    final noiseT = ((nf - noiseQuietDbm) / (noiseNoisyDbm - noiseQuietDbm))
        .clamp(0.0, 1.0);

    final snr = stats.lastSnrDb;
    const snrGood = 12.0;
    const snrBad = -2.0;
    final snrT = (1.0 - ((snr - snrBad) / (snrGood - snrBad))).clamp(0.0, 1.0);

    final airBusy = _recentAirtimeBusyFraction();
    final severity = (math.max(noiseT, snrT) * 0.82 + airBusy * 0.18).clamp(
      0.0,
      1.0,
    );

    return (_contactMsgBackoffMinMs +
            severity * (_contactMsgBackoffMaxMs - _contactMsgBackoffMinMs))
        .round();
  }

  /// 1.0 shortly after TX/RX airtime counters increase, decaying to 0 over ~8s.
  double _recentAirtimeBusyFraction() {
    final sw = _airtimeBumpStopwatch;
    if (sw == null || !sw.isRunning) return 0;
    final ms = sw.elapsedMilliseconds;
    const windowMs = 8000;
    if (ms >= windowMs) return 0;
    return 1.0 - (ms / windowMs);
  }

  /// Start of the post-inbound cool-down: the later of BLE message RX time and
  /// companion airtime bump ([_airtimeBumpStopwatch], same as the activity dot).
  DateTime _postTxBackoffAnchor(DateTime lastInboundRxTime) {
    if (!supportsCompanionRadioStats) return lastInboundRxTime;
    final sw = _airtimeBumpStopwatch;
    if (sw == null || !sw.isRunning) return lastInboundRxTime;
    final bumpAt = DateTime.now().subtract(sw.elapsed);
    return bumpAt.isAfter(lastInboundRxTime) ? bumpAt : lastInboundRxTime;
  }

  Future<void> _waitForRadioQuiet({required DateTime lastInboundRxTime}) async {
    // Wait for backoff after inbound traffic / RF airtime (avoid collision with
    // mesh propagation). Elapsed time uses the dot's airtime bump when newer.
    final backoffTargetMs = _contactMessageBackoffTargetMs();
    final anchor = _postTxBackoffAnchor(lastInboundRxTime);
    final msSinceAnchor = DateTime.now().difference(anchor).inMilliseconds;
    if (msSinceAnchor < backoffTargetMs) {
      final waitMs = backoffTargetMs - msSinceAnchor;
      debugPrint(
        'Post-inbound backoff: waiting ${waitMs}ms '
        '(target=${backoffTargetMs}ms, anchorAge=${msSinceAnchor}ms)',
      );
      await Future<void>.delayed(Duration(milliseconds: waitMs));
    }

    // Then wait for radio silence (no RF activity for 3s)
    final msSinceRx = DateTime.now()
        .difference(_lastRadioRxTime)
        .inMilliseconds;
    if (msSinceRx >= _radioQuietMs) return;

    final deadline = DateTime.now().add(
      const Duration(milliseconds: _radioQuietMaxWaitMs),
    );
    while (DateTime.now().isBefore(deadline)) {
      final quiet = DateTime.now().difference(_lastRadioRxTime).inMilliseconds;
      if (quiet >= _radioQuietMs) {
        debugPrint('Radio quiet for ${quiet}ms, proceeding with send');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    debugPrint(
      'Radio quiet wait exceeded ${_radioQuietMaxWaitMs}ms, sending anyway',
    );
  }

  Future<DateTime?> _sendMessageDirect(
    Contact contact,
    String text,
    int attempt,
    int timestampSeconds,
  ) async {
    if (!isConnected || text.isEmpty) return null;
    try {
      await _waitForRadioQuiet(lastInboundRxTime: _lastContactMsgRxTime);
      final outboundText = prepareContactOutboundText(
        contact,
        text,
        estimateSignatureOverhead: false,
      );
      final sentByRadioAt = DateTime.now();
      await sendFrame(
        buildSendTextMsgFrame(
          contact.publicKey,
          outboundText,
          attempt: attempt,
          timestampSeconds: timestampSeconds,
        ),
      );
      return sentByRadioAt;
    } catch (e) {
      appLogger.error('Failed to send message: $e', tag: 'Connector');
      return null;
    }
  }

  void _updateMessage(Message message) {
    final contactKey = pubKeyToHex(message.senderKey);
    final messages = _conversations[contactKey];
    if (messages != null) {
      final index = messages.indexWhere(
        (m) => m.messageId == message.messageId,
      );
      if (index != -1) {
        messages[index] = message;
        _messageStore.saveMessages(contactKey, messages);
        notifyListeners();
      }
    }

    // If this is a reaction message, update the target message's reaction status
    final reactionInfo = ReactionHelper.parseReaction(message.text);
    if (reactionInfo != null &&
        (message.status == MessageStatus.delivered ||
            message.status == MessageStatus.failed)) {
      final contactKey2 = pubKeyToHex(message.senderKey);
      _setReactionStatus(contactKey2, reactionInfo, message.status);
      _messageStore.saveMessages(
        contactKey2,
        _conversations[contactKey2] ?? [],
      );
      notifyListeners();
    }
  }

  Future<TranslationResult?> translateContactMessage(
    String contactKeyHex,
    Message message, {
    bool manualTranslation = false,
  }) async {
    try {
      if (message.translatedText?.trim().isNotEmpty == true ||
          (!manualTranslation &&
              message.translationStatus != MessageTranslationStatus.none)) {
        return null;
      }
      final service = _translationService;
      if (service == null ||
          !(manualTranslation
              ? service.canTranslateIncoming(
                  text: message.text,
                  isCli: message.isCli,
                  isOutgoing: message.isOutgoing,
                )
              : service.shouldAutoTranslateIncoming(
                  text: message.text,
                  isCli: message.isCli,
                  isOutgoing: message.isOutgoing,
                ))) {
        return null;
      }
      final targetLanguageCode = service.resolvedIncomingLanguageCode(
        _appSettingsService?.settings.languageOverride,
      );
      final result = await service.translateIncomingText(
        text: message.text,
        targetLanguageCode: targetLanguageCode,
      );
      if (result == null) {
        return null;
      }
      final translated = result.status == MessageTranslationStatus.completed
          ? result.translatedText
          : null;
      _updateStoredContactMessage(
        contactKeyHex,
        message.messageId,
        (current) => current.copyWith(
          translatedText: translated,
          translatedLanguageCode: result.detectedLanguageCode,
          translationStatus: result.status,
          translationModelId: result.modelId,
        ),
      );
      return result;
    } catch (error) {
      appLogger.warn('Translation failed for contact message: $error');
      return null;
    }
  }

  Future<TranslationResult?> translateChannelMessage(
    int channelIndex,
    ChannelMessage message, {
    bool manualTranslation = false,
  }) async {
    try {
      if (message.translatedText?.trim().isNotEmpty == true ||
          (!manualTranslation &&
              message.translationStatus != MessageTranslationStatus.none)) {
        return null;
      }
      final service = _translationService;
      if (service == null ||
          !(manualTranslation
              ? service.canTranslateIncoming(
                  text: message.text,
                  isCli: false,
                  isOutgoing: message.isOutgoing,
                )
              : service.shouldAutoTranslateIncoming(
                  text: message.text,
                  isCli: false,
                  isOutgoing: message.isOutgoing,
                ))) {
        return null;
      }
      final targetLanguageCode = service.resolvedIncomingLanguageCode(
        _appSettingsService?.settings.languageOverride,
      );
      final result = await service.translateIncomingText(
        text: message.text,
        targetLanguageCode: targetLanguageCode,
      );
      if (result == null) {
        return null;
      }
      var translated = result.status == MessageTranslationStatus.completed
          ? result.translatedText
          : null;
      // Strip replyInfo prefix from translated text to match stored message.text
      if (translated != null) {
        final regex = RegExp(r'^@\[[^\]]+\]\s+', dotAll: true);
        translated = translated.replaceFirst(regex, '');
      }
      _updateStoredChannelMessage(
        channelIndex,
        message.messageId,
        (current) => current.copyWith(
          translatedText: translated,
          translatedLanguageCode: result.detectedLanguageCode,
          translationStatus: result.status,
          translationModelId: result.modelId,
        ),
      );
      return result;
    } catch (error) {
      appLogger.warn('Translation failed for channel message: $error');
      return null;
    }
  }

  void _updateStoredContactMessage(
    String contactKeyHex,
    String messageId,
    Message Function(Message current) update,
  ) {
    final messages = _conversations[contactKeyHex];
    if (messages == null) {
      return;
    }
    final index = messages.indexWhere((entry) => entry.messageId == messageId);
    if (index < 0) {
      return;
    }
    messages[index] = update(messages[index]);
    _messageStore.saveMessages(contactKeyHex, messages);
    notifyListeners();
  }

  void _updateStoredChannelMessage(
    int channelIndex,
    String messageId,
    ChannelMessage Function(ChannelMessage current) update,
  ) {
    final messages = _channelMessages[channelIndex];
    if (messages == null) {
      return;
    }
    final index = messages.indexWhere((entry) => entry.messageId == messageId);
    if (index < 0) {
      return;
    }
    messages[index] = update(messages[index]);
    _channelMessageStore.saveChannelMessages(channelIndex, messages);
    notifyListeners();
  }

  void _recordPathResult(
    String contactPubKeyHex,
    PathSelection selection,
    bool success,
    int? tripTimeMs,
  ) {
    if (_pathHistoryService == null) return;
    final settings = _appSettingsService?.settings;
    _pathHistoryService!.recordPathResult(
      contactPubKeyHex,
      selection,
      success: success,
      tripTimeMs: tripTimeMs,
      successIncrement: settings?.routeWeightSuccessIncrement ?? 0.2,
      failureDecrement: settings?.routeWeightFailureDecrement ?? 0.2,
      maxWeight: settings?.maxRouteWeight ?? 5.0,
    );

    // Flood path attribution: when a flood delivery succeeds, credit the
    // contact's current device path so the route the ACK traveled back
    // through gets a weight boost in the path history.
    if (selection.useFlood && success) {
      final contact = _contacts.cast<Contact?>().firstWhere(
        (c) => c?.publicKeyHex == contactPubKeyHex,
        orElse: () => null,
      );
      if (contact != null &&
          contact.pathLength >= 0 &&
          contact.path.isNotEmpty) {
        _pathHistoryService!.recordFloodPathAttribution(
          contactPubKeyHex: contactPubKeyHex,
          pathBytes: contact.path,
          hopCount: contact.pathLength,
          tripTimeMs: tripTimeMs,
          successIncrement: settings?.routeWeightSuccessIncrement ?? 0.2,
          maxWeight: settings?.maxRouteWeight ?? 5.0,
        );
      }

      // Request a fresh contact from the device so the next flood
      // attribution uses the most up-to-date path.
      if (contact != null) {
        unawaited(getContactByKey(contact.publicKey));
      }
    }
  }

  PathSelection? _selectAutoPathForAttempt(
    String contactPubKeyHex, {
    required int attemptIndex,
    required int maxRetries,
    List<PathSelection> recentSelections = const [],
  }) {
    final hasKnownPaths =
        _pathHistoryService?.getRecentPaths(contactPubKeyHex).isNotEmpty ??
        false;
    if (!hasKnownPaths) {
      return null;
    }

    final selection = _pathHistoryService?.selectPathForAttempt(
      contactPubKeyHex,
      attemptIndex: attemptIndex,
      maxRetries: maxRetries,
      recentSelections: recentSelections,
    );
    if (selection != null) {
      _pathHistoryService?.recordPathAttempt(contactPubKeyHex, selection);
    }
    return selection;
  }

  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_state == MeshCoreConnectionState.scanning) return;

    // A BLE scan must never disturb an active (or in-progress) non-BLE
    // connection. The connection state enum is shared across transports, so
    // entering the `scanning` state while connected over TCP/USB would clobber
    // the live `connected` state and later reset it to `disconnected`.
    if (_state != MeshCoreConnectionState.disconnected ||
        _tcpConnector.isConnected ||
        _usbManager.isConnected) {
      _appDebugLogService?.warn(
        'startScan ignored: not idle (state=$_state, '
        'tcp=${_tcpConnector.isConnected}, usb=${_usbManager.isConnected})',
        tag: 'BLE Scan',
      );
      return;
    }

    _scanResults.clear();
    _linuxSystemScanResults.clear();
    _setState(MeshCoreConnectionState.scanning);

    // Ensure any previous scan is fully stopped. Guard with isScanningNow to
    // avoid triggering stale native callbacks when no scan is active.
    if (FlutterBluePlus.isScanningNow) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (e) {
        _appDebugLogService?.warn(
          'stopScan error in startScan (ignored): $e',
          tag: 'BLE Scan',
        );
      }
    }
    await _scanSubscription?.cancel();

    // On iOS/macOS, wait for Bluetooth to be powered on before scanning
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      // Wait for adapter state to be powered on
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        // Wait for the adapter to turn on, with timeout
        await FlutterBluePlus.adapterState
            .firstWhere((state) => state == BluetoothAdapterState.on)
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                _setState(MeshCoreConnectionState.disconnected);
                throw Exception('Bluetooth adapter not available');
              },
            );
      }

      // Add a small delay to allow BLE stack to fully initialize
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (PlatformInfo.isLinux) {
      await _loadLinuxSystemDevicesForScan();
    }

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      _scanResults
        ..clear()
        ..addAll(results);
      _mergeLinuxSystemScanResults();
      notifyListeners();
    });

    try {
      // Filter by the Nordic UART Service UUID rather than by advertised
      // name. All MeshCore-compatible firmware (ESP32 + nRF52) advertises this
      // service UUID, so this matches every device regardless of the name it
      // chooses to advertise (e.g. community forks like the M5 Cardputer that
      // do not use a "MeshCore-" name prefix). This mirrors how the official
      // app discovers devices. Note: on Android `withKeywords` cannot be
      // combined with any other filter, which is why name keywords are not
      // used here.
      await FlutterBluePlus.startScan(
        withServices: [Guid(MeshCoreUuids.service)],
        webOptionalServices: [Guid(MeshCoreUuids.service)],
        timeout: timeout,
        androidScanMode: AndroidScanMode.lowLatency,
      );
    } catch (error) {
      _appDebugLogService?.warn('Scan/picker failure: $error', tag: 'BLE Scan');
      await stopScan();
      rethrow;
    }

    // Reset our shared state when the native scan ends — whether it was stopped
    // by the user (stopScan), by the platform timeout, or by Bluetooth turning
    // off. This replaces a blocking `Future.delayed(timeout)` tail that kept
    // startScan() pending for the whole timeout and made Stop appear ineffective.
    // `isScanning` is a re-emit stream that replays its latest value on listen,
    // so skip(1) to ignore that and only react to a genuine transition to false.
    await _isScanningSubscription?.cancel();
    _isScanningSubscription = FlutterBluePlus.isScanning.skip(1).listen((
      scanning,
    ) {
      if (!scanning && _state == MeshCoreConnectionState.scanning) {
        unawaited(stopScan());
      }
    });
  }

  Future<void> _loadLinuxSystemDevicesForScan() async {
    try {
      final systemDevices = await FlutterBluePlus.systemDevices([
        Guid(MeshCoreUuids.service),
      ]);
      // systemDevices is already filtered by the NUS service UUID above, so no
      // additional name-prefix filtering is applied here. This keeps Linux
      // discovery name-agnostic and consistent with the main scan path.
      _linuxSystemScanResults
        ..clear()
        ..addAll(
          systemDevices.map(
            (device) => ScanResult(
              device: device,
              advertisementData: AdvertisementData(
                advName: device.platformName,
                txPowerLevel: null,
                appearance: null,
                connectable: true,
                manufacturerData: const <int, List<int>>{},
                serviceData: const <Guid, List<int>>{},
                serviceUuids: <Guid>[Guid(MeshCoreUuids.service)],
              ),
              rssi: 0,
              timeStamp: DateTime.now(),
            ),
          ),
        );
      _mergeLinuxSystemScanResults();
      notifyListeners();
    } catch (error) {
      _appDebugLogService?.warn(
        'Failed loading Linux paired/system BLE devices: $error',
        tag: 'BLE Scan',
      );
    }
  }

  void _mergeLinuxSystemScanResults() {
    if (!PlatformInfo.isLinux || _linuxSystemScanResults.isEmpty) {
      return;
    }
    final existingIds = _scanResults
        .map((result) => result.device.remoteId.str)
        .toSet();
    for (final result in _linuxSystemScanResults) {
      if (existingIds.contains(result.device.remoteId.str)) {
        continue;
      }
      _scanResults.add(result);
    }
  }

  Future<void> stopScan() async {
    // Only call FlutterBluePlus.stopScan() when a scan is actually running.
    // Calling it when idle triggers a native BLE completion callback even
    // though no scan was started. After a hot restart Dart has already freed
    // those callback handles, so the callback crashes with
    // "Callback invoked after it has been deleted".
    if (FlutterBluePlus.isScanningNow) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (e) {
        _appDebugLogService?.warn(
          'stopScan error (ignored): $e',
          tag: 'BLE Scan',
        );
      }
    }
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _isScanningSubscription?.cancel();
    _isScanningSubscription = null;

    if (_state == MeshCoreConnectionState.scanning) {
      // Restore to `connected` if a non-BLE transport is still live, so a stray
      // scan can never tear down the reported connection state. Normally there
      // is no live transport here and we fall through to `disconnected`.
      final restored = (_tcpConnector.isConnected || _usbManager.isConnected)
          ? MeshCoreConnectionState.connected
          : MeshCoreConnectionState.disconnected;
      _setState(restored);
    }
  }

  Future<List<String>> listUsbPorts() => _usbManager.listPorts();

  void setUsbRequestPortLabel(String label) {
    _usbManager.setRequestPortLabel(label);
  }

  void setUsbFallbackDeviceName(String label) {
    _usbManager.setFallbackDeviceName(label);
  }

  Future<void> connectUsb({
    required String portName,
    int baudRate = 115200,
  }) async {
    if (_isOfflineMode) {
      _appDebugLogService?.warn(
        'connectUsb ignored while offline history is open',
        tag: 'USB',
      );
      return;
    }
    if (_state == MeshCoreConnectionState.connecting ||
        _state == MeshCoreConnectionState.connected) {
      _appDebugLogService?.warn(
        'connectUsb ignored: already $_state',
        tag: 'USB',
      );
      return;
    }

    _appDebugLogService?.info(
      'connectUsb: port=$portName baud=$baudRate',
      tag: 'USB',
    );

    await stopScan();
    _cancelReconnectTimer();
    _manualDisconnect = false;
    _resetConnectionHandshakeState();
    _activeTransport = MeshCoreTransportType.usb;
    _setState(MeshCoreConnectionState.connecting);

    try {
      await _usbFrameSubscription?.cancel();
      _usbFrameSubscription = null;
      _appDebugLogService?.info('connectUsb: opening serial port…', tag: 'USB');
      await _usbManager.connect(portName: portName, baudRate: baudRate);
      _appDebugLogService?.info(
        'connectUsb: serial port opened, label=${_usbManager.activePortDisplayLabel}',
        tag: 'USB',
      );
      notifyListeners();
      if (PlatformInfo.isWeb) {
        await stopScan();
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // The read pump can fail the instant the port opens (e.g. a device that
      // re-enumerates on open). That error is emitted on a broadcast stream
      // before the listener below attaches, so it would otherwise be lost and
      // the connect would stall until the SELF_INFO timeout. Check transport
      // liveness directly and abort fast with the real cause.
      if (!_usbManager.isConnected) {
        final cause = _usbManager.lastError;
        throw StateError(
          'USB device disconnected during connect'
          '${cause == null ? '' : ': $cause'}',
        );
      }

      _usbFrameSubscription = _usbManager.frameStream.listen(
        _handleFrame,
        onError: (error, stackTrace) {
          _appDebugLogService?.error('USB transport error: $error', tag: 'USB');
          unawaited(disconnect(manual: false));
        },
        onDone: () {
          _appDebugLogService?.warn('USB frame stream ended', tag: 'USB');
          unawaited(disconnect(manual: false));
        },
      );

      _setState(MeshCoreConnectionState.connected);
      _syncBackgroundTcpService();
      _pendingInitialChannelSync = true;
      _pendingInitialQueuedMessageSync = true;
      _pendingInitialContactsSync = true;
      _appDebugLogService?.info(
        'connectUsb: requesting device info…',
        tag: 'USB',
      );
      await _requestDeviceInfo();
      _startBatteryPolling();
      if (_radioStatsPollRefCount > 0) _startRadioStatsPolling();
      var gotSelfInfo = await _waitForSelfInfo(
        timeout: const Duration(seconds: 3),
      );
      if (!gotSelfInfo) {
        _appDebugLogService?.warn(
          'connectUsb: SELF_INFO timeout, retrying…',
          tag: 'USB',
        );
        await refreshDeviceInfo();
        gotSelfInfo = await _waitForSelfInfo(
          timeout: const Duration(seconds: 3),
        );
      }
      if (!gotSelfInfo) {
        throw StateError('Timed out waiting for SELF_INFO during connect');
      }

      _appDebugLogService?.info('connectUsb: syncing time…', tag: 'USB');
      await syncTime();
      unawaited(_refreshDefaultRegionScope());
      _appDebugLogService?.info('connectUsb: complete', tag: 'USB');
    } catch (error) {
      _appDebugLogService?.error('USB connection error: $error', tag: 'USB');
      await disconnect(manual: false);
      rethrow;
    }
  }

  Future<void> connectTcp({required String host, required int port}) async {
    if (_isOfflineMode) {
      _appDebugLogService?.warn(
        'connectTcp ignored while offline history is open',
        tag: 'TCP',
      );
      return;
    }
    if (_state == MeshCoreConnectionState.connecting ||
        _state == MeshCoreConnectionState.connected) {
      _appDebugLogService?.warn(
        'connectTcp ignored: already $_state',
        tag: 'TCP',
      );
      return;
    }

    _appDebugLogService?.info('connectTcp: endpoint=$host:$port', tag: 'TCP');

    await stopScan();
    _cancelReconnectTimer();
    _manualDisconnect = false;
    _lastManualDisconnectTransport = null;
    _resetConnectionHandshakeState();
    _activeTransport = MeshCoreTransportType.tcp;
    _setState(MeshCoreConnectionState.connecting);

    try {
      Future<void> handleTcpConnectAbort({required String message}) async {
        _appDebugLogService?.warn(message, tag: 'TCP');
        final shouldResetState = shouldResetStateAfterTcpConnectAbort(
          state: _state,
          activeTransport: _activeTransport,
        );
        if (shouldResetState) {
          await disconnect(manual: false);
          return;
        }
        if (_tcpConnector.isConnected) {
          await _tcpConnector.disconnect();
        }
      }

      await _tcpConnector.cancelFrameSubscription();
      await _tcpConnector.connect(host: host, port: port);
      final isTcpConnectCancelled =
          _activeTransport != MeshCoreTransportType.tcp ||
          _state != MeshCoreConnectionState.connecting ||
          !_tcpConnector.isConnected;
      if (isTcpConnectCancelled) {
        await handleTcpConnectAbort(
          message:
              'connectTcp aborted before handshake: state=$_state transport=$_activeTransport connected=${_tcpConnector.isConnected}',
        );
        return;
      }
      notifyListeners();

      await Future<void>.delayed(const Duration(milliseconds: 200));
      final isTcpConnectCancelledAfterDelay =
          _activeTransport != MeshCoreTransportType.tcp ||
          _state != MeshCoreConnectionState.connecting ||
          !_tcpConnector.isConnected;
      if (isTcpConnectCancelledAfterDelay) {
        await handleTcpConnectAbort(
          message:
              'connectTcp aborted after connect delay: state=$_state transport=$_activeTransport connected=${_tcpConnector.isConnected}',
        );
        return;
      }
      _tcpConnector.listenFrames(
        onFrame: _handleFrame,
        onError: (error, stackTrace) {
          _appDebugLogService?.error('TCP transport error: $error', tag: 'TCP');
          unawaited(disconnect(manual: false));
        },
        onDone: () {
          _appDebugLogService?.warn('TCP frame stream ended', tag: 'TCP');
          unawaited(disconnect(manual: false));
        },
      );

      _setState(MeshCoreConnectionState.connected);
      _pendingInitialChannelSync = true;
      _pendingInitialQueuedMessageSync = true;
      _pendingInitialContactsSync = true;
      await _requestDeviceInfo();
      _startBatteryPolling();
      if (_radioStatsPollRefCount > 0) _startRadioStatsPolling();

      var gotSelfInfo = await _waitForSelfInfo(
        timeout: const Duration(seconds: 3),
      );
      if (!gotSelfInfo) {
        await refreshDeviceInfo();
        gotSelfInfo = await _waitForSelfInfo(
          timeout: const Duration(seconds: 3),
        );
      }
      if (!gotSelfInfo) {
        throw StateError('Timed out waiting for SELF_INFO during TCP connect');
      }

      await syncTime();
      unawaited(_refreshDefaultRegionScope());
    } catch (error) {
      _appDebugLogService?.error('TCP connection error: $error', tag: 'TCP');
      final tcpConnectCancelledBeforeHandshake =
          shouldIgnoreLateTcpConnectError(
            manualDisconnect: _manualDisconnect,
            state: _state,
            activeTransport: _activeTransport,
            tcpManagerConnected: _tcpConnector.isConnected,
          );
      if (tcpConnectCancelledBeforeHandshake) {
        _appDebugLogService?.info(
          'Ignoring late TCP connect error after cancellation/switch: state=$_state transport=$_activeTransport',
          tag: 'TCP',
        );
        return;
      }
      await disconnect(manual: false);
      rethrow;
    }
  }

  @visibleForTesting
  static bool shouldIgnoreLateTcpConnectError({
    required bool manualDisconnect,
    required MeshCoreConnectionState state,
    required MeshCoreTransportType activeTransport,
    required bool tcpManagerConnected,
  }) {
    return manualDisconnect &&
        (state == MeshCoreConnectionState.disconnected ||
            state == MeshCoreConnectionState.disconnecting) &&
        (activeTransport != MeshCoreTransportType.tcp || !tcpManagerConnected);
  }

  @visibleForTesting
  static bool shouldResetStateAfterTcpConnectAbort({
    required MeshCoreConnectionState state,
    required MeshCoreTransportType activeTransport,
  }) {
    return state == MeshCoreConnectionState.connecting &&
        activeTransport == MeshCoreTransportType.tcp;
  }

  /// Fast (non-timeout) connect failures are usually a stale link left over
  /// from a previous session and recover on an immediate retry. Timeouts mean
  /// the device is likely off or out of range, so retrying would only delay
  /// genuine failure feedback.
  @visibleForTesting
  static bool shouldRetryBleConnectAfterError(String errorText) {
    final lowerErrorText = errorText.toLowerCase();
    return !lowerErrorText.contains('timed out') &&
        !lowerErrorText.contains('timeout');
  }

  Future<void> connect(
    BluetoothDevice device, {
    String? displayName,
    Future<String?> Function()? linuxPairingPinProvider,
  }) async {
    if (_isOfflineMode) {
      _appDebugLogService?.warn(
        'BLE connect ignored while offline history is open',
        tag: 'BLE Connect',
      );
      return;
    }
    if (_state == MeshCoreConnectionState.connecting ||
        _state == MeshCoreConnectionState.connected) {
      return;
    }

    _activeTransport = MeshCoreTransportType.bluetooth;

    await stopScan();
    _setState(MeshCoreConnectionState.connecting);
    _device = device;
    _deviceId = device.remoteId.toString();
    if (displayName != null && displayName.trim().isNotEmpty) {
      _deviceDisplayName = displayName.trim();
    } else if (device.platformName.isNotEmpty) {
      _deviceDisplayName = device.platformName;
    }
    _lastDevice = device;
    _lastDeviceId = _deviceId;
    _lastDeviceDisplayName = _deviceDisplayName;
    _manualDisconnect = false;
    _cancelReconnectTimer();
    _bleInitialSyncStarted = false;
    _hasCompletedSelfInfoHandshake = false;
    if (PlatformInfo.isWeb) {
      _resetConnectionHandshakeState();
    }
    unawaited(_backgroundService?.start());
    notifyListeners();

    try {
      final connectLabel = _deviceDisplayName ?? _deviceId;
      _appDebugLogService?.info(
        'Starting connect to $connectLabel',
        tag: 'BLE Connect',
      );
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;
      await _notifySubscription?.cancel();
      _notifySubscription = null;
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && isConnected) {
          _handleDisconnection();
        }
      });

      if (PlatformInfo.isLinux) {
        final remoteId = device.remoteId.str;
        _appDebugLogService?.info(
          'Linux pre-connect BlueZ disconnect for $remoteId',
          tag: 'BLE Connect',
        );
        await _linuxBlePairingService.disconnectDevice(
          remoteId,
          onLog: (message) {
            _appDebugLogService?.info(message, tag: 'BLE Pair');
          },
        );
      }

      final connectTimeout = PlatformInfo.isLinux
          ? const Duration(seconds: 6)
          : const Duration(seconds: 15);
      _appDebugLogService?.info(
        'device.connect timeout set to ${connectTimeout.inSeconds}s',
        tag: 'BLE Connect',
      );
      if (PlatformInfo.isLinux) {
        Future<void> attemptConnect() {
          return device
              .connect(
                timeout: connectTimeout,
                mtu: null,
                license: License.nonprofit,
              )
              .timeout(
                connectTimeout + const Duration(seconds: 2),
                onTimeout: () {
                  throw TimeoutException(
                    'Linux connect hard-timeout after ${connectTimeout.inSeconds + 2}s',
                  );
                },
              );
        }

        try {
          await attemptConnect();
        } catch (error) {
          _appDebugLogService?.error(
            'device.connect() failure: $error',
            tag: 'BLE Connect',
          );
          final remoteId = device.remoteId.str;
          _appDebugLogService?.warn(
            'Linux immediate retry: forcing BlueZ disconnect before second connect attempt',
            tag: 'BLE Connect',
          );
          await _linuxBlePairingService.disconnectDevice(
            remoteId,
            onLog: (message) {
              _appDebugLogService?.info(message, tag: 'BLE Pair');
            },
          );
          await Future<void>.delayed(const Duration(milliseconds: 700));
          try {
            await attemptConnect();
            _appDebugLogService?.info(
              'Linux immediate retry connect succeeded',
              tag: 'BLE Connect',
            );
          } catch (retryError, retryStackTrace) {
            Object finalConnectError = retryError;
            StackTrace finalConnectStackTrace = retryStackTrace;
            final retryErrorText = retryError.toString().toLowerCase();
            final isAbortByLocal = retryErrorText.contains(
              'le-connection-abort-by-local',
            );
            var recoveredOnThirdAttempt = false;
            if (isAbortByLocal) {
              _appDebugLogService?.warn(
                'Linux immediate retry aborted by local stack; waiting and retrying once more',
                tag: 'BLE Connect',
              );
              await Future<void>.delayed(const Duration(milliseconds: 1200));
              try {
                await attemptConnect();
                _appDebugLogService?.info(
                  'Linux third-attempt connect succeeded after local abort',
                  tag: 'BLE Connect',
                );
                recoveredOnThirdAttempt = true;
              } catch (thirdError, thirdStackTrace) {
                finalConnectError = thirdError;
                finalConnectStackTrace = thirdStackTrace;
                _appDebugLogService?.error(
                  'device.connect() third-attempt failure: $thirdError',
                  tag: 'BLE Connect',
                );
              }
            }
            if (!recoveredOnThirdAttempt) {
              final recoveredByPairing = await _recoverLinuxConnectFailure(
                device,
                attemptConnect: attemptConnect,
                onRequestPin: linuxPairingPinProvider,
              );
              if (recoveredByPairing) {
                _appDebugLogService?.info(
                  'Linux connect succeeded after pairing/trust recovery',
                  tag: 'BLE Connect',
                );
              } else {
                _appDebugLogService?.error(
                  'device.connect() retry failure: $finalConnectError',
                  tag: 'BLE Connect',
                );
                Error.throwWithStackTrace(
                  _wrapLinuxConnectStageError(finalConnectError),
                  finalConnectStackTrace,
                );
              }
            }
          }
        }
      } else {
        Future<void> attemptConnect() {
          return device.connect(
            timeout: connectTimeout,
            mtu: null,
            license: License.nonprofit,
          );
        }

        // A previous app session (e.g. killed from the iOS app switcher) can
        // leave the OS holding a stale link to the peripheral. Clear it before
        // connecting so the fresh attempt doesn't race the stale handle.
        if (!PlatformInfo.isWeb && device.isConnected) {
          _appDebugLogService?.warn(
            'Device reports an existing connection before connect; clearing stale link',
            tag: 'BLE Connect',
          );
          try {
            await device.disconnect(queue: false);
          } catch (cleanupError) {
            _appDebugLogService?.warn(
              'Stale-link cleanup disconnect failed (continuing): $cleanupError',
              tag: 'BLE Connect',
            );
          }
        }

        try {
          await attemptConnect();
        } catch (error) {
          _appDebugLogService?.error(
            'device.connect() failure: $error',
            tag: 'BLE Connect',
          );
          if (PlatformInfo.isWeb ||
              !shouldRetryBleConnectAfterError(error.toString())) {
            rethrow;
          }
          // Fast (non-timeout) failures are usually a stale connection left by
          // a previous session; clean up and retry once before surfacing.
          _appDebugLogService?.warn(
            'Retrying connect once after clearing possible stale connection',
            tag: 'BLE Connect',
          );
          try {
            await device.disconnect(queue: false);
          } catch (cleanupError) {
            _appDebugLogService?.warn(
              'Pre-retry cleanup disconnect failed (continuing): $cleanupError',
              tag: 'BLE Connect',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 500));
          try {
            await attemptConnect();
            _appDebugLogService?.info(
              'Retry connect succeeded after stale-connection cleanup',
              tag: 'BLE Connect',
            );
          } catch (retryError) {
            _appDebugLogService?.error(
              'device.connect() retry failure: $retryError',
              tag: 'BLE Connect',
            );
            rethrow;
          }
        }
      }

      if (PlatformInfo.isLinux) {
        await _ensureLinuxBleBond(
          device,
          onRequestPin: linuxPairingPinProvider,
        );
      } else if (PlatformInfo.isWindows) {
        await _ensureWindowsBleBond(device);
      }

      // flutter_blue_plus only supports explicit MTU requests on Android.
      if (PlatformInfo.isAndroid) {
        try {
          final mtu = await device.requestMtu(185);
          _appDebugLogService?.info('MTU set to: $mtu', tag: 'BLE Connect');
        } catch (e) {
          _appDebugLogService?.warn(
            'MTU request failed: $e, using default',
            tag: 'BLE Connect',
          );
        }
      } else if (PlatformInfo.isLinux) {
        _appDebugLogService?.info(
          'Skipping MTU request on Linux; flutter_blue_plus only supports requestMtu on Android',
          tag: 'BLE Connect',
        );
      }

      late final List<BluetoothService> services;
      try {
        services = await device.discoverServices();
      } catch (error) {
        _appDebugLogService?.error(
          'service discovery failure: $error',
          tag: 'BLE Connect',
        );
        if (PlatformInfo.isWeb &&
            error.toString().contains('GATT Server is disconnected')) {
          // Chrome Web Bluetooth intermittently disconnects between connect()
          // and service discovery; retry once to recover that transient state.
          _appDebugLogService?.warn(
            'retrying service discovery after transient web disconnect',
            tag: 'BLE Connect',
          );
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await device.connect(
            timeout: const Duration(seconds: 15),
            mtu: null,
            license: License.nonprofit,
          );
          services = await device.discoverServices();
        } else {
          rethrow;
        }
      }

      BluetoothService? uartService;
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == MeshCoreUuids.service) {
          uartService = service;
          break;
        }
      }

      if (uartService == null) {
        throw Exception("MeshCore UART service not found");
      }

      for (var characteristic in uartService.characteristics) {
        String uuid = characteristic.uuid.toString().toLowerCase();
        if (uuid == MeshCoreUuids.rxCharacteristic) {
          _rxCharacteristic = characteristic;
        } else if (uuid == MeshCoreUuids.txCharacteristic) {
          _txCharacteristic = characteristic;
        }
      }

      if (_rxCharacteristic == null || _txCharacteristic == null) {
        throw Exception("MeshCore characteristics not found");
      }

      final txProperties = _txCharacteristic!.properties;
      _appDebugLogService?.info(
        'NUS TX properties: notify=${txProperties.notify} '
        'indicate=${txProperties.indicate} '
        'descriptors=${_txCharacteristic!.descriptors.length}',
        tag: 'BLE Connect',
      );

      if (PlatformInfo.isWeb) {
        _appDebugLogService?.info(
          'Starting setNotifyValue(true)',
          tag: 'BLE Connect',
        );
        _appDebugLogService?.info(
          'Web: Calling setNotifyValue(true) without awaiting',
          tag: 'BLE Connect',
        );
        unawaited(() async {
          try {
            await _txCharacteristic!.setNotifyValue(true);
          } catch (error) {
            _appDebugLogService?.warn(
              'notify failure (web, ignored): $error',
              tag: 'BLE Connect',
            );
            _appDebugLogService?.warn(
              'Web setNotifyValue error (ignoring): $error',
              tag: 'BLE Connect',
            );
          }
        }());
        _appDebugLogService?.info(
          'setNotifyValue(true) configuration completed',
          tag: 'BLE Connect',
        );
      } else {
        // WinRT may report the link as connected before descriptor writes are
        // ready. Let service discovery settle before the first CCCD write;
        // retrying only after an immediate failed write is less reliable.
        if (PlatformInfo.isWindows) {
          await Future<void>.delayed(const Duration(milliseconds: 750));
        }
        bool notifySet = false;
        for (int attempt = 0; attempt < 3 && !notifySet; attempt++) {
          try {
            if (attempt > 0) {
              final retryDelay = PlatformInfo.isWindows
                  ? Duration(milliseconds: 1000 * attempt)
                  : Duration(milliseconds: 500 * attempt);
              await Future<void>.delayed(retryDelay);
            }
            await _txCharacteristic!.setNotifyValue(true);
            notifySet = true;
            _appDebugLogService?.info(
              'NUS TX notifications enabled on attempt ${attempt + 1}/3',
              tag: 'BLE Connect',
            );
          } catch (e) {
            _appDebugLogService?.warn('notify failure: $e', tag: 'BLE Connect');
            _appDebugLogService?.warn(
              'setNotifyValue attempt ${attempt + 1}/3 failed: $e',
              tag: 'BLE Connect',
            );
            if (attempt == 2) rethrow;
          }
        }
      }
      _notifySubscription = _txCharacteristic!.onValueReceived.listen(
        _handleFrame,
      );

      _setState(MeshCoreConnectionState.connected);
      _rxSilenceAnchor = DateTime.now();
      _startRxWatchdog();
      if (_shouldGateInitialChannelSync) {
        _hasReceivedDeviceInfo = false;
        _pendingInitialChannelSync = true;
      }
      await _startBleInitialSync();
    } catch (e) {
      _appDebugLogService?.error('Connection error: $e', tag: 'BLE Connect');
      final errorText = e.toString();
      final lowerErrorText = errorText.toLowerCase();
      final isLinuxPairingFailure =
          PlatformInfo.isLinux && isLinuxBlePairingFailureText(errorText);
      final isLikelyPairingTimeout = isLikelyLinuxBlePairingTimeoutText(
        errorText,
      );
      final isConnectFailure = isLinuxBleConnectFailureText(errorText);
      final isConnectTimeoutFailure =
          isConnectFailure && lowerErrorText.contains('timed out');
      final isLinuxConnectFailure = PlatformInfo.isLinux && isConnectFailure;
      final isWindowsPairingFailure =
          PlatformInfo.isWindows &&
          lowerErrorText.contains('windows ble pairing failed');
      // Linux pairing failures should not enter auto-reconnect loops; user
      // needs to retry manually so they can re-enter PIN / resolve pairing.
      if (isLinuxPairingFailure || isWindowsPairingFailure) {
        _appDebugLogService?.warn(
          isWindowsPairingFailure
              ? 'Windows pairing failure: stopping reconnect until user retries manually'
              : isLikelyPairingTimeout
              ? 'Linux pairing timed out: stopping reconnect until user retries manually'
              : 'Linux pairing failure: stopping reconnect until user retries manually',
          tag: 'BLE Connect',
        );
        await disconnect(manual: true);
      } else if (isLinuxConnectFailure) {
        _appDebugLogService?.warn(
          isConnectTimeoutFailure
              ? 'Linux connect timeout: issuing BlueZ disconnect before reconnect'
              : 'Linux connect failure: issuing BlueZ disconnect before reconnect',
          tag: 'BLE Connect',
        );
        final remoteId = _device?.remoteId.str;
        if (remoteId != null) {
          await _linuxBlePairingService.disconnectDevice(
            remoteId,
            onLog: (message) {
              _appDebugLogService?.info(message, tag: 'BLE Pair');
            },
          );
        }
        await disconnect(manual: false, skipBleDeviceDisconnect: true);
      } else {
        await disconnect(manual: false);
      }
      rethrow;
    }
  }

  Future<bool> _recoverLinuxConnectFailure(
    BluetoothDevice device, {
    required Future<void> Function() attemptConnect,
    Future<String?> Function()? onRequestPin,
  }) async {
    if (!PlatformInfo.isLinux ||
        !await _linuxBlePairingService.isBluetoothctlAvailable()) {
      return false;
    }
    final remoteId = device.remoteId.str;
    final pluginBondState = await _getLinuxPluginBondState(device);
    final trustedByBluez = await _linuxBlePairingService.isPairedAndTrusted(
      remoteId,
    );
    final needsBondRecovery =
        (pluginBondState != null &&
            pluginBondState != BmBondStateEnum.bonded) ||
        !trustedByBluez;
    if (!needsBondRecovery) {
      return false;
    }
    _appDebugLogService?.warn(
      pluginBondState == BmBondStateEnum.bonded
          ? 'Linux connect failed with an untrusted bond; attempting trust/pair recovery'
          : 'Linux connect failed before bond completed; attempting pairing fallback',
      tag: 'BLE Connect',
    );
    await _ensureLinuxBleBond(device, onRequestPin: onRequestPin);
    _appDebugLogService?.info(
      'Resetting BlueZ connection after Linux pairing/trust recovery',
      tag: 'BLE Connect',
    );
    await _linuxBlePairingService.disconnectDevice(
      remoteId,
      onLog: (message) {
        _appDebugLogService?.info(message, tag: 'BLE Pair');
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 700));
    try {
      await attemptConnect();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(_wrapLinuxConnectStageError(error), stackTrace);
    }
    return true;
  }

  Object _wrapLinuxConnectStageError(Object error) {
    final errorText = error.toString();
    if (errorText.toLowerCase().contains(linuxConnectStageFailureMarker)) {
      return error;
    }
    return StateError('Linux connect stage failure: $error');
  }

  Future<void> _ensureWindowsBleBond(BluetoothDevice device) async {
    final remoteId = device.remoteId;
    BmBondStateEnum? bondState;
    try {
      final response = await FlutterBluePlusPlatform.instance.getBondState(
        BmBondStateRequest(remoteId: remoteId),
      );
      bondState = response.bondState;
      _appDebugLogService?.info(
        'Windows BLE bond state before NUS setup: $bondState',
        tag: 'BLE Pair',
      );
    } catch (error) {
      _appDebugLogService?.warn(
        'Windows getBondState failed; attempting pairing: $error',
        tag: 'BLE Pair',
      );
    }

    if (bondState == BmBondStateEnum.bonded) {
      return;
    }

    _appDebugLogService?.info(
      'Windows BLE device is not bonded; requesting system pairing',
      tag: 'BLE Pair',
    );
    try {
      final paired = await FlutterBluePlusPlatform.instance.createBond(
        BmCreateBondRequest(remoteId: remoteId, pin: null),
      );
      if (!paired) {
        throw StateError('Windows pairing request was rejected or cancelled');
      }
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        StateError('Windows BLE pairing failed: $error'),
        stackTrace,
      );
    }

    _appDebugLogService?.info('Windows BLE pairing completed', tag: 'BLE Pair');
  }

  Future<BmBondStateEnum?> _getLinuxPluginBondState(
    BluetoothDevice device,
  ) async {
    try {
      final response = await FlutterBluePlusPlatform.instance.getBondState(
        BmBondStateRequest(remoteId: device.remoteId),
      );
      return response.bondState;
    } catch (error) {
      _appDebugLogService?.warn(
        'Linux getBondState unavailable for ${device.remoteId.str}: $error',
        tag: 'BLE Connect',
      );
      return null;
    }
  }

  Future<void> _ensureLinuxBleBond(
    BluetoothDevice device, {
    Future<String?> Function()? onRequestPin,
  }) async {
    final remoteId = device.remoteId.str;
    final bluetoothctlAvailable = await _linuxBlePairingService
        .isBluetoothctlAvailable();
    final beforeBondState = await _getLinuxPluginBondState(device);
    if (!bluetoothctlAvailable) {
      if (beforeBondState == BmBondStateEnum.bonded) {
        _appDebugLogService?.warn(
          'bluetoothctl unavailable; continuing with plugin bonded state',
          tag: 'BLE Connect',
        );
      } else if (beforeBondState == null) {
        _appDebugLogService?.warn(
          'bluetoothctl unavailable and plugin bond state is unknown; skipping Linux pairing fallback',
          tag: 'BLE Connect',
        );
      } else {
        _appDebugLogService?.warn(
          'bluetoothctl unavailable and device is not bonded; skipping Linux pairing fallback',
          tag: 'BLE Connect',
        );
      }
      return;
    }

    final trustedByBluez = await _linuxBlePairingService.isPairedAndTrusted(
      remoteId,
    );
    if (trustedByBluez) {
      _appDebugLogService?.info(
        'Linux BLE device already paired/trusted, skipping pairing flow',
        tag: 'BLE Connect',
      );
      return;
    }

    if (beforeBondState == BmBondStateEnum.bonded && !trustedByBluez) {
      _appDebugLogService?.warn(
        'Linux BLE device is bonded but not trusted in BlueZ; repairing trust',
        tag: 'BLE Connect',
      );
      final trustRepaired = await _linuxBlePairingService.trustDevice(
        remoteId,
        onLog: (message) {
          _appDebugLogService?.info(message, tag: 'BLE Pair');
        },
      );
      if (trustRepaired) {
        _appDebugLogService?.info(
          'Linux BLE trust repair succeeded without re-pairing',
          tag: 'BLE Connect',
        );
        return;
      }
      _appDebugLogService?.warn(
        'Linux BLE trust repair did not stick; retrying pairing flow',
        tag: 'BLE Connect',
      );
    }

    _appDebugLogService?.info(
      beforeBondState == BmBondStateEnum.bonded
          ? 'Linux BLE device still untrusted after repair; requesting pair'
          : beforeBondState == null
          ? 'Linux BLE device bond state unknown; requesting pair'
          : 'Linux BLE device not bonded, requesting pair',
      tag: 'BLE Connect',
    );
    final paired = await _linuxBlePairingService.pairAndTrust(
      remoteId: remoteId,
      onLog: (message) {
        _appDebugLogService?.info(message, tag: 'BLE Pair');
      },
      onRequestPin: onRequestPin,
    );
    if (!paired) {
      throw StateError('Linux pairing fallback failed');
    }

    final afterBondState = await _getLinuxPluginBondState(device);
    if (afterBondState != null && afterBondState != BmBondStateEnum.bonded) {
      throw StateError('Linux BLE pairing did not complete');
    } else if (afterBondState == null) {
      _appDebugLogService?.warn(
        'Linux plugin bond state unavailable after pairing; relying on BlueZ trust verification',
        tag: 'BLE Connect',
      );
    }
    final trustedAfter = await _linuxBlePairingService.isPairedAndTrusted(
      remoteId,
    );
    if (!trustedAfter) {
      throw StateError('Linux BLE trust repair did not complete');
    }
  }

  Future<bool> _waitForSelfInfo({required Duration timeout}) async {
    if (_selfPublicKey != null) return true;
    if (!isConnected) return false;

    final completer = Completer<bool>();
    late final VoidCallback listener;
    listener = () {
      if (_selfPublicKey != null) {
        if (!completer.isCompleted) {
          completer.complete(true);
        }
      } else if (!isConnected) {
        if (!completer.isCompleted) {
          completer.complete(false);
        }
      }
    };
    addListener(listener);

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });

    final result = await completer.future;
    timer.cancel();
    removeListener(listener);
    return result;
  }

  Future<void> _startBleInitialSync() async {
    if (_bleInitialSyncStarted ||
        !isConnected ||
        _activeTransport != MeshCoreTransportType.bluetooth) {
      return;
    }
    _bleInitialSyncStarted = true;
    _pendingInitialChannelSync = true;
    _pendingInitialContactsSync = true;
    _pendingInitialQueuedMessageSync = true;

    await _requestDeviceInfo();
    _startBatteryPolling();
    if (_radioStatsPollRefCount > 0) _startRadioStatsPolling();

    final gotSelfInfo = await _waitForSelfInfo(
      timeout: const Duration(seconds: 3),
    );
    if (!gotSelfInfo) {
      await refreshDeviceInfo();
      await _waitForSelfInfo(timeout: const Duration(seconds: 3));
    }

    await syncTime();
    unawaited(_refreshDefaultRegionScope());
    _maybeStartInitialChannelSync();
  }

  void _resetConnectionHandshakeState() {
    _contactCacheLoadGeneration++;
    _contactCacheLoadFuture = null;
    _southFrameFragmentReassembler.clear();
    _southQueuedFragmentAckTracker.clear();
    _selfPublicKey = null;
    _selfName = null;
    _selfLatitude = null;
    _selfLongitude = null;
    _setDefaultRegionScopeCache(null);
    _hasLoadedDefaultRegionScope = false;
    _defaultRegionScopeRefreshFuture = null;
    _lastZeroHopAdvertLatitude = null;
    _lastZeroHopAdvertLongitude = null;
    _awaitingSelfInfo = false;
    _hasCompletedSelfInfoHandshake = false;
    _webInitialHandshakeRequestSent = false;
    _selfInfoRetryTimer?.cancel();
    _selfInfoRetryTimer = null;
    _hasReceivedDeviceInfo = false;
    _hasLoadedCachedChannelStorage = false;
    _resetSyncProgressState();
    _clearSharedMessageHistoryState();
    _bleInitialSyncStarted = false;
    _pathHashByteWidth = 1;
  }

  void _resetSyncProgressState() {
    _hasLoadedCachedChannelStorage = false;
    _pendingInitialChannelSync = false;
    _pendingInitialContactsSync = false;
    _pendingInitialQueuedMessageSync = false;
    _contactSyncTotal = null;
    _contactSyncReceived = 0;
    _contactSyncUsesSinceFilter = false;
    _contactSyncTimeout?.cancel();
    _contactSyncTimeout = null;
    _isLoadingContacts = false;
    _hasLoadedContacts = false;
    _contactSyncIndexes = null;
    _discoveredContactSyncIndexes = null;
    _contactMessageSummarySnapshot.clear();
    _isLoadingChannels = false;
    _hasLoadedChannels = false;
    _isSyncingQueuedMessages = false;
    _isInitialBacklogDrain = false;
    _deferQueuedContactMessagesUntilContacts = false;
    _isProcessingDeferredQueuedContactMessages = false;
    _queuedMessageSyncInFlight = false;
    _deferredQueuedContactMessageFrames.clear();
    _pendingQueueSync = false;
    _queueSyncTimeout?.cancel();
    _queueSyncTimeout = null;
    _queueSyncRetries = 0;
    _isSyncingChannels = false;
    _channelSyncInFlight = false;
    _channelSyncTimeout?.cancel();
    _channelSyncTimeout = null;
    _channelSyncRetries = 0;
    _nextChannelIndexToRequest = 0;
    _totalChannelsToRequest = 0;
    _previousChannelsCache.clear();
  }

  bool get _shouldAutoReconnect =>
      !_isOfflineMode &&
      !_manualDisconnect &&
      _lastDeviceId != null &&
      _activeTransport == MeshCoreTransportType.bluetooth;

  bool get _shouldGateInitialChannelSync =>
      _activeTransport == MeshCoreTransportType.usb ||
      _activeTransport == MeshCoreTransportType.tcp ||
      (_activeTransport == MeshCoreTransportType.bluetooth &&
          PlatformInfo.isWeb);

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
  }

  int _nextReconnectDelayMs() {
    final attempt = _reconnectAttempts < 6 ? _reconnectAttempts : 6;
    _reconnectAttempts += 1;
    final delayMs = 1000 * (1 << attempt);
    return delayMs > 30000 ? 30000 : delayMs;
  }

  void _scheduleReconnect() {
    if (!_shouldAutoReconnect) return;
    if (_reconnectTimer?.isActive == true) return;

    final delayMs = _nextReconnectDelayMs();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () async {
      if (!_shouldAutoReconnect) return;
      if (_state == MeshCoreConnectionState.connecting ||
          _state == MeshCoreConnectionState.connected) {
        return;
      }

      final device =
          _lastDevice ??
          (_lastDeviceId == null
              ? null
              : BluetoothDevice.fromId(_lastDeviceId!));
      if (device == null) return;

      try {
        await connect(device, displayName: _lastDeviceDisplayName);
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  Future<void> disconnect({
    bool manual = true,
    bool skipBleDeviceDisconnect = false,
  }) async {
    if (_isOfflineMode) {
      await exitOfflineHistory();
      return;
    }
    if (_state == MeshCoreConnectionState.disconnecting) return;
    final transportAtDisconnect = _activeTransport;
    final transportLabel = switch (transportAtDisconnect) {
      MeshCoreTransportType.bluetooth => 'BLE',
      MeshCoreTransportType.usb => 'USB',
      MeshCoreTransportType.tcp => 'TCP',
    };

    _appDebugLogService?.info(
      'Starting disconnect transport=$transportLabel manual=$manual',
      tag: 'Connection',
    );

    unawaited(_backgroundService?.stop(reason: _backgroundTcpReason));
    if (manual) {
      // A deliberate reconnect starts a fresh watchdog recovery budget.
      // Automatic watchdog reconnects use manual=false and retain the count.
      _rxWatchdogReconnects = 0;
      _manualDisconnect = true;
      _isRecoveringConnection = false;
      _lastManualDisconnectTransport = transportAtDisconnect;
      _cancelReconnectTimer();
      unawaited(_backgroundService?.stop());
    } else {
      _manualDisconnect = false;
      _lastManualDisconnectTransport = null;
      _isRecoveringConnection =
          transportAtDisconnect == MeshCoreTransportType.bluetooth &&
          _lastDeviceId != null;
      if (_isRecoveringConnection) {
        unawaited(_backgroundService?.setConnectionLost(true));
      }
    }
    _setState(MeshCoreConnectionState.disconnecting);
    pausePendingOutgoingMessages();
    _stopBatteryPolling();
    _stopRadioStatsPolling();
    _stopRxWatchdog();
    _southFrameFragmentReassembler.clear();
    _southQueuedFragmentAckTracker.clear();

    await _usbFrameSubscription?.cancel();
    _usbFrameSubscription = null;
    await _usbManager.disconnect();
    await _tcpConnector.disconnect();

    await _notifySubscription?.cancel();
    _notifySubscription = null;

    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _selfInfoRetryTimer?.cancel();
    _selfInfoRetryTimer = null;
    _queueSyncTimeout?.cancel();
    _queueSyncTimeout = null;
    _queueSyncRetries = 0;
    _channelSyncTimeout?.cancel();
    _channelSyncTimeout = null;
    _channelSyncRetries = 0;
    await _translationService?.releaseModel();

    if (!skipBleDeviceDisconnect) {
      try {
        // Skip queued BLE operations so disconnect doesn't get stuck behind them.
        await _device?.disconnect(queue: false);
      } catch (e) {
        _appDebugLogService?.warn('Disconnect error: $e', tag: 'BLE Connect');
      }
    } else {
      _appDebugLogService?.info(
        'Skipping plugin BLE disconnect and continuing cleanup',
        tag: 'BLE Connect',
      );
    }

    _device = null;
    _rxCharacteristic = null;
    _txCharacteristic = null;
    _deviceDisplayName = null;
    _deviceId = null;
    // Device capability flags must not leak into the next connection.
    _currentCustomVars = null;
    _settingsSectionsService?.setDeviceRawVars(null);
    _settingsSectionsService?.setActiveDeviceKey(null);
    _contacts.clear();
    _discoveredContacts.clear();
    _conversations.clear();
    _loadedConversationKeys.clear();
    _conversationLoadGeneration++;
    _conversationLoadFutures.clear();
    _selfPublicKey = null;
    _selfName = null;
    _selfLatitude = null;
    _selfLongitude = null;
    _setDefaultRegionScopeCache(null);
    _hasLoadedDefaultRegionScope = false;
    _defaultRegionScopeRefreshFuture = null;
    _lastZeroHopAdvertLatitude = null;
    _lastZeroHopAdvertLongitude = null;
    _clientRepeat = null;
    _rememberedNonRepeatRadioState = null;
    _firmwareVerCode = null;
    _firmwareVersion = null;
    _firmwareBuildDate = null;
    _boardName = null;
    _batteryMillivolts = null;
    _repeaterBatterySnapshots.clear();
    _batteryRequested = false;
    _awaitingSelfInfo = false;
    _hasCompletedSelfInfoHandshake = false;
    _lastSentWasCliCommand = false;
    _hasReceivedDeviceInfo = false;
    _maxContacts = _defaultMaxContacts;
    _maxChannels = _defaultMaxChannels;
    _resetSyncProgressState();
    _clearSharedMessageHistoryState();
    _cancelAllChannelNoRetransmissionTimers();
    _pendingChannelSentQueue.clear();
    _pendingGenericAckQueue.clear();
    final preserveChannelSendsForReconnect =
        !manual && transportAtDisconnect == MeshCoreTransportType.bluetooth;
    _shouldReplayRetriableChannelMessageSends =
        preserveChannelSendsForReconnect &&
        _retriableChannelMessageSends.isNotEmpty;
    if (!preserveChannelSendsForReconnect) {
      _clearDeferredChannelMessageSends(markFailed: true);
      _clearRetriableChannelMessageSends(markFailed: true);
    }
    _reactionSendQueueSequence = 0;

    _activeTransport = MeshCoreTransportType.bluetooth;

    _setState(MeshCoreConnectionState.disconnected);
    _appDebugLogService?.info(
      'Disconnect complete transport=$transportLabel manual=$manual',
      tag: 'Connection',
    );
    if (!manual && transportAtDisconnect == MeshCoreTransportType.bluetooth) {
      _scheduleReconnect();
    }
  }

  Future<void> sendFrame(
    Uint8List data, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {
    if (!isConnected) {
      throw Exception("Not connected to a MeshCore device");
    }
    _bleDebugLogService?.logFrame(data, outgoing: true);

    // Register the expected OK before writing. Some transports can deliver the
    // response quickly enough that waiting until after write races with _handleOk().
    final pendingAck = _trackPendingGenericAck(
      data,
      channelSendQueueId: channelSendQueueId,
      expectsGenericAck: expectsGenericAck || waitForGenericAck,
      waitForAck: waitForGenericAck,
    );

    try {
      if (_activeTransport == MeshCoreTransportType.usb) {
        await _usbManager.write(data);
        // Brief pause so the device firmware can process each frame before the
        // next arrives. Without this, rapid-fire frames over USB can cause the
        // device to miss responses (especially on reconnect).
        await Future<void>.delayed(const Duration(milliseconds: 10));
      } else if (_activeTransport == MeshCoreTransportType.tcp) {
        await _tcpConnector.write(data);
      } else {
        if (_rxCharacteristic == null) {
          throw Exception("MeshCore RX characteristic not available");
        }
        // Prefer write without response when supported; fall back to write with response.
        final properties = _rxCharacteristic!.properties;
        final canWriteWithoutResponse = properties.writeWithoutResponse;
        final canWriteWithResponse = properties.write;
        if (!canWriteWithoutResponse && !canWriteWithResponse) {
          throw Exception("MeshCore RX characteristic does not support write");
        }
        await _rxCharacteristic!.write(
          data.toList(),
          withoutResponse: canWriteWithoutResponse,
        );
      }
    } catch (_) {
      if (pendingAck != null) {
        _pendingGenericAckQueue.remove(pendingAck);
      }
      rethrow;
    }

    if (pendingAck?.completer != null) {
      try {
        await pendingAck!.completer!.future.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        _pendingGenericAckQueue.remove(pendingAck);
        throw TimeoutException(
          'Timed out waiting for firmware acknowledgement',
        );
      }
    }
  }

  Future<void> requestBatteryStatus({bool force = false}) async {
    if (!isConnected) return;
    if (_batteryRequested && !force) return;
    _batteryRequested = true;
    await sendFrame(buildGetBattAndStorageFrame());
  }

  void _startBatteryPolling() {
    _batteryPollTimer?.cancel();
    _batteryPollTimer = Timer.periodic(_batteryPollInterval, (timer) {
      if (!isConnected) {
        timer.cancel();
        return;
      }
      unawaited(requestBatteryStatus(force: true));
    });
  }

  void _stopBatteryPolling() {
    _batteryPollTimer?.cancel();
    _batteryPollTimer = null;
  }

  // BLE-only: detects a dead notify stream (connected link, writes succeed,
  // but no inbound frames despite expected battery-poll traffic) and
  // recovers through the normal disconnect → auto-reconnect path.
  void _startRxWatchdog() {
    // Web BLE reconnects need a user gesture, so a forced reconnect is moot.
    if (PlatformInfo.isWeb) return;
    _rxWatchdogTimer?.cancel();
    // Seed the first tick so a background/doze gap immediately after connect
    // is detected just like a gap between subsequent ticks.
    _lastRxWatchdogTickAt = DateTime.now();
    _rxWatchdogTimer = Timer.periodic(_rxWatchdogCheckInterval, (_) {
      _handleRxWatchdogTick();
    });
  }

  void _stopRxWatchdog() {
    _rxWatchdogTimer?.cancel();
    _rxWatchdogTimer = null;
  }

  void _handleRxWatchdogTick() {
    final now = DateTime.now();
    final previousTick = _lastRxWatchdogTickAt;
    _lastRxWatchdogTickAt = now;
    if (!isConnected || _activeTransport != MeshCoreTransportType.bluetooth) {
      return;
    }
    // A large gap between ticks means timers were suspended (background /
    // doze) or the event loop stalled; polling needs a fresh window before
    // silence is meaningful again.
    if (previousTick != null &&
        now.difference(previousTick) >= _rxWatchdogCheckInterval * 2) {
      _rxSilenceAnchor = now;
      return;
    }
    final anchor = _lastRxTime.isAfter(_rxSilenceAnchor)
        ? _lastRxTime
        : _rxSilenceAnchor;
    final silence = now.difference(anchor);
    if (silence < _rxWatchdogSilence) return;
    if (_rxWatchdogReconnects >= _rxWatchdogMaxConsecutive) {
      _appDebugLogService?.warn(
        'RX watchdog: reconnect limit reached after '
        '$_rxWatchdogMaxConsecutive automatic recovery attempts; '
        'current session is still mute, stopping until a manual reconnect',
        tag: 'Watchdog',
      );
      _stopRxWatchdog();
      return;
    }
    _rxWatchdogReconnects++;
    _appDebugLogService?.warn(
      'RX watchdog: connected but no inbound frames for '
      '${silence.inSeconds}s, forcing reconnect '
      '($_rxWatchdogReconnects/$_rxWatchdogMaxConsecutive)',
      tag: 'Watchdog',
    );
    unawaited(disconnect(manual: false));
  }

  /// Start polling the radio's GPS-backed self-info every minute.
  /// No-op if already running. Triggered when the radio reports `gps=1`.
  void _startGpsLocationPolling() {
    if (_gpsLocationPollTimer != null) return;
    _gpsLocationPollTimer = Timer.periodic(_gpsLocationPollInterval, (timer) {
      if (!isConnected) {
        timer.cancel();
        _gpsLocationPollTimer = null;
        return;
      }
      unawaited(sendFrame(_buildAppStartFrame()));
    });
  }

  void _stopGpsLocationPolling() {
    _gpsLocationPollTimer?.cancel();
    _gpsLocationPollTimer = null;
  }

  void setPollingInterval(int i) {
    _pollingInterval = i.clamp(1, 60);
    if (isConnected) {
      _startRadioStatsPolling();
    }
  }

  void _startRadioStatsPolling() {
    _radioStatsPollTimer?.cancel();
    _radioStatsPollTimer = Timer.periodic(Duration(seconds: _pollingInterval), (
      _,
    ) {
      if (!isConnected) {
        _stopRadioStatsPolling();
        return;
      }
      unawaited(requestRadioStats());
    });
  }

  void _stopRadioStatsPolling() {
    _radioStatsPollTimer?.cancel();
    _radioStatsPollTimer = null;
  }

  void acquireRadioStatsPolling() {
    _radioStatsPollRefCount++;
    if (_radioStatsPollRefCount == 1 && isConnected) {
      _startRadioStatsPolling();
    }
  }

  void releaseRadioStatsPolling() {
    _radioStatsPollRefCount = (_radioStatsPollRefCount - 1).clamp(0, 999);
    if (_radioStatsPollRefCount == 0) {
      _stopRadioStatsPolling();
    }
  }

  Future<void> requestRadioStats() async {
    if (!isConnected) return;
    if (!supportsCompanionRadioStats) return;
    try {
      await sendFrame(buildGetStatsFrame(statsTypeRadio));
    } catch (_) {}
  }

  Future<void> setPathHashMode(int mode) async {
    if (!isConnected) return;
    final clampedMode = mode.clamp(0, 3).toInt();
    await sendFrame(buildSetPathHashModeFrame(clampedMode));
    final nextWidth = clampedMode + 1;
    if (_pathHashByteWidth != nextWidth) {
      _pathHashByteWidth = nextWidth;
      _directRepeaters.clear();
      _activeRepeaters.clear();
      notifyListeners();
    }
  }

  bool _isPathLenValidForCurrentMode(int pathLen, List<int> pathBytes) {
    return _isPathLenValidForMode(pathLen, pathBytes, _pathHashByteWidth);
  }

  int? _encodePathLenForCurrentMode(int pathLen, List<int> pathBytes) {
    if (pathLen < 0 || pathLen == 0xFF) return pathLen;
    if (!_isPathLenValidForCurrentMode(pathLen, pathBytes)) {
      appLogger.warn(
        'Invalid path_len for mode: pathLen=$pathLen, '
        'bytesLen=${pathBytes.length}, width=$_pathHashByteWidth',
        tag: 'Connector',
      );
      return null;
    }
    final mode = (_pathHashByteWidth - 1) & 0x03;
    return (pathLen & 0x3F) | (mode << 6);
  }

  Future<void> refreshDeviceInfo() async {
    if (!isConnected) return;
    if (PlatformInfo.isWeb &&
        _activeTransport == MeshCoreTransportType.bluetooth &&
        _webInitialHandshakeRequestSent &&
        _selfPublicKey == null) {
      return;
    }
    _awaitingSelfInfo = true;
    if (PlatformInfo.isWeb &&
        _activeTransport == MeshCoreTransportType.bluetooth &&
        _selfPublicKey == null) {
      _webInitialHandshakeRequestSent = true;
    }
    await sendFrame(buildDeviceQueryFrame());
    await sendFrame(_buildAppStartFrame());
    await requestBatteryStatus(force: true);
    await sendFrame(buildGetCustomVarsFrame());
    await sendFrame(buildGetAutoAddFlagsFrame());

    _scheduleSelfInfoRetry();
  }

  Future<({double latitude, double longitude})?> refreshSelfLocation({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (!isConnected) return _validSelfLocationOrNull();

    final waiter = Completer<void>();
    _selfInfoRefreshWaiters.add(waiter);
    try {
      await sendFrame(_buildAppStartFrame());
      await waiter.future.timeout(timeout, onTimeout: () {});
    } catch (_) {
      // Return the latest cached location below; menu actions should not throw.
    } finally {
      _selfInfoRefreshWaiters.remove(waiter);
    }

    return _validSelfLocationOrNull();
  }

  ({double latitude, double longitude})? _validSelfLocationOrNull() {
    final latitude = _selfLatitude;
    final longitude = _selfLongitude;
    if (!hasValidLocation(latitude, longitude)) return null;
    return (latitude: latitude!, longitude: longitude!);
  }

  Future<void> _requestDeviceInfo() async {
    if (!isConnected || _awaitingSelfInfo) return;
    if (PlatformInfo.isWeb &&
        _activeTransport == MeshCoreTransportType.bluetooth &&
        _webInitialHandshakeRequestSent &&
        _selfPublicKey == null) {
      return;
    }
    _awaitingSelfInfo = true;
    if (PlatformInfo.isWeb &&
        _activeTransport == MeshCoreTransportType.bluetooth &&
        _selfPublicKey == null) {
      _webInitialHandshakeRequestSent = true;
    }
    await sendFrame(buildDeviceQueryFrame());
    await sendFrame(_buildAppStartFrame());
    await sendFrame(buildGetCustomVarsFrame());
    await requestBatteryStatus();
    await sendFrame(buildGetAutoAddFlagsFrame());
    _scheduleSelfInfoRetry();
  }

  void _scheduleSelfInfoRetry() {
    _selfInfoRetryTimer?.cancel();
    if (PlatformInfo.isWeb &&
        _activeTransport == MeshCoreTransportType.bluetooth) {
      var attempts = 0;
      const maxAttempts = 3;
      _selfInfoRetryTimer = Timer.periodic(const Duration(seconds: 10), (
        timer,
      ) {
        if (!isConnected || !_awaitingSelfInfo) {
          timer.cancel();
          return;
        }
        if (_isLoadingContacts || _isSyncingChannels || _channelSyncInFlight) {
          return;
        }
        attempts += 1;
        unawaited(sendFrame(_buildAppStartFrame()));
        if (attempts >= maxAttempts) {
          timer.cancel();
        }
      });
      return;
    }
    _selfInfoRetryTimer = Timer.periodic(const Duration(milliseconds: 3500), (
      timer,
    ) {
      if (!isConnected) {
        timer.cancel();
        return;
      }
      if (!_awaitingSelfInfo) {
        timer.cancel();
        return;
      }
      unawaited(sendFrame(_buildAppStartFrame()));
    });
  }

  Contact getFromDiscovered(Contact contact) {
    final indexedPosition =
        _discoveredContactSyncIndexes?[contact.publicKeyHex];
    final tmp =
        indexedPosition != null &&
            indexedPosition >= 0 &&
            indexedPosition < _discoveredContacts.length
        ? _discoveredContacts[indexedPosition]
        : _discoveredContacts.firstWhere(
            (c) => c.publicKeyHex == contact.publicKeyHex,
            orElse: () => contact,
          );
    return contact.copyWith(
      rawPacket: tmp.rawPacket,
      latitude: tmp.latitude,
      longitude: tmp.longitude,
    );
  }

  Future<void> getContacts({int? since, bool preserveExisting = false}) async {
    if (!isConnected) return;

    final contactCacheLoad = _contactCacheLoadFuture;
    if (contactCacheLoad != null) {
      await contactCacheLoad;
      if (!isConnected) return;
    }

    _isLoadingContacts = true;
    _preserveContactsOnRefresh = preserveExisting;
    _contactSyncTotal = null;
    _contactSyncReceived = 0;
    _contactSyncUsesSinceFilter = since != null;
    _armContactSyncTimeout();
    if (!preserveExisting) {
      await _refreshContactMessageSummaries();
      _captureContactMessageSummarySnapshot();
      _hasLoadedContacts = false;
      _contacts.clear();
    }
    notifyListeners();

    await sendFrame(buildGetContactsFrame(since: since));
  }

  void _armContactSyncTimeout() {
    _contactSyncTimeout?.cancel();
    // Contact sync has no request/response timeout and normally ends only with
    // END_OF_CONTACTS. If BLE drops that final frame, the progress indicator
    // otherwise remains active forever, so treat prolonged RX silence as end.
    _contactSyncTimeout = Timer(_contactSyncIdleTimeout, () {
      if (!_isLoadingContacts) return;
      appLogger.warn(
        'Contact sync timed out after receiving $_contactSyncReceived contacts',
        tag: 'Connector',
      );
      _contactSyncTimeout = null;
      _isLoadingContacts = false;
      _hasLoadedContacts = true;
      _preserveContactsOnRefresh = false;
      _contactSyncUsesSinceFilter = false;
      _contactSyncIndexes = null;
      _discoveredContactSyncIndexes = null;
      _contactMessageSummarySnapshot.clear();
      _unreadStore.saveContactUnreadCount(
        Map<String, int>.from(_contactUnreadCount),
      );
      unawaited(updateKnownDiscovered());
      notifyListeners();
      unawaited(_refreshContactMessageSummaries());
      unawaited(_persistContacts());
      unawaited(_flushDeferredChannelMessageSends());
      if (PlatformInfo.isWeb &&
          _activeTransport == MeshCoreTransportType.bluetooth &&
          _isSyncingChannels &&
          !_channelSyncInFlight) {
        unawaited(_requestNextChannel());
      }
      if (_deferQueuedContactMessagesUntilContacts) {
        unawaited(_processDeferredQueuedContactMessages());
      } else if (_pendingQueueSync) {
        _pendingQueueSync = false;
        unawaited(syncQueuedMessages(force: true));
      }
    });
  }

  Future<void> refreshContacts() async {
    await getContacts(preserveExisting: true);
  }

  Future<void> refreshContactsSinceLastmod() async {
    await getContacts(since: _latestContactLastmod(), preserveExisting: true);
  }

  Future<void> getContactByKey(Uint8List pubKey) async {
    if (!isConnected) return;
    await sendFrame(buildGetContactByKeyFrame(pubKey));
  }

  Future<void> sendMessage(
    Contact contact,
    String text, {
    String? uncompressedText,
    String? originalText,
    String? translatedLanguageCode,
    String? translationModelId,
    String? pendingMessageId,
    DateTime? pendingTimestamp,
  }) async {
    if (text.isEmpty || isOfflineMode) return;
    if (!isSessionReady) {
      if (pendingMessageId == null) {
        scheduleContactMessage(
          contact,
          text,
          inputText: originalText ?? text,
          uncompressedText: uncompressedText,
          delaySeconds: 0,
          originalText: originalText,
          translatedLanguageCode: translatedLanguageCode,
          translationModelId: translationModelId,
        );
      }
      return;
    }
    await _loadMessagesForContact(contact.publicKeyHex);

    // Room-server messages sign via the node (a few seconds). Show a pending
    // placeholder while signing so the message does not visually disappear;
    // it is removed just before the retry service adds the finalized message.
    final willSignRoomMcmp =
        contact.type == advTypeRoom &&
        isContactMcmpEnabled(contact.publicKeyHex) &&
        contactMcmpVersion(contact.publicKeyHex) == 3 &&
        contactMcmpUseSign(contact.publicKeyHex) &&
        _isMcmpSignableText(text) &&
        ReactionHelper.parseReaction(text) == null;
    Message? signingPlaceholder;
    if (willSignRoomMcmp && pendingMessageId == null) {
      signingPlaceholder = Message.outgoing(
        contact.publicKey,
        text,
        originalText: originalText,
        translatedLanguageCode: translatedLanguageCode,
        translationModelId: translationModelId,
      );
      _addMessage(contact.publicKeyHex, signingPlaceholder);
      notifyListeners();
    }

    final outboundText = await prepareContactOutboundTextAsync(contact, text);
    if (signingPlaceholder != null) {
      _conversations[contact.publicKeyHex]?.removeWhere(
        (m) => m.messageId == signingPlaceholder!.messageId,
      );
    }
    if (!isConnected) {
      if (signingPlaceholder != null) notifyListeners();
      return;
    }
    final compression = _contactCompressionMetadata(
      contact,
      uncompressedText ?? text,
      outboundText,
    );
    final outboundBytes = utf8.encode(outboundText);
    // Room servers store posts in a 151-byte buffer (MAX_POST_TEXT_LEN =
    // 160-9) and silently truncate anything longer, which would destroy the
    // MCMP container and its signature.
    final maxOutboundBytes = contact.type == advTypeRoom
        ? maxRoomServerTextBytes
        : maxTextPayloadBytes;
    if (outboundBytes.length > maxOutboundBytes) {
      debugPrint(
        'sendMessage: dropping overlong message '
        '(${outboundBytes.length} > $maxOutboundBytes bytes)',
      );
      return;
    }

    // Meta exactly as transmitted in the MCMP body (if any): reply anchors
    // and manual signature re-checks rely on the verbatim values.
    final mcmpMeta = McmpAppCodec.tryDecodeTextPayloadMessage(outboundText);
    final mcmpStatus = mcmpMeta == null
        ? McmpSignatureStatus.none
        : (mcmpMeta.isSigned
              ? McmpSignatureStatus.valid
              : McmpSignatureStatus.unsigned);

    if (pendingMessageId != null) {
      _pendingContactSends.remove(pendingMessageId)?.timer?.cancel();
    }

    // Check if this is a reaction - apply locally with pending status and route through retry service
    final reactionInfo = ReactionHelper.parseReaction(text);
    if (reactionInfo != null) {
      _conversations.putIfAbsent(contact.publicKeyHex, () => []);
      final messages = _conversations[contact.publicKeyHex]!;

      // Apply reaction locally with pending status
      _processOutgoingContactReaction(messages, reactionInfo, contact);
      _setReactionStatus(
        contact.publicKeyHex,
        reactionInfo,
        MessageStatus.pending,
      );
      _messageStore.saveMessages(contact.publicKeyHex, messages);
      notifyListeners();

      // Route through retry service (same as normal messages)
      // Don't use auto-rotation for reactions — just send directly
      if (_retryService != null) {
        _retryService!.sendMessageWithRetry(
          contact: contact,
          text: text,
          messageId: pendingMessageId,
          timestamp: pendingTimestamp,
        );
      } else {
        final outboundText = prepareContactOutboundText(contact, text);
        await sendFrame(buildSendTextMsgFrame(contact.publicKey, outboundText));
      }
      return;
    }

    if (_retryService != null) {
      await _retryService!.sendMessageWithRetry(
        contact: contact,
        text: text,
        messageId: pendingMessageId,
        timestamp: pendingTimestamp,
        preparedOutboundText: outboundText,
        compressionType: compression?.type,
        compressionSavingsPercent: compression?.savingsPercent,
        compressionOriginalBytes: compression?.originalBytes,
        compressionPayloadBytes: compression?.payloadBytes,
        mcmpSignatureStatus: mcmpStatus,
        mcmpTimestamp: mcmpMeta?.timestamp,
        mcmpSenderName: mcmpMeta?.senderName,
        mcmpIsSigned: mcmpMeta?.isSigned ?? false,
        mcmpSignature: mcmpMeta?.signature,
        originalText: originalText,
        translatedLanguageCode: translatedLanguageCode,
        translationModelId: translationModelId,
      );
    } else {
      // Fallback to old behavior if retry service not initialized
      final resolved = resolvePathSelection(contact);
      final message = Message.outgoing(
        contact.publicKey,
        text,
        messageId: pendingMessageId,
        timestamp: pendingTimestamp,
        wasMcmpCompressed: _isMcmpEncodedText(outboundText),
        compressionType: compression?.type,
        compressionSavingsPercent: compression?.savingsPercent,
        compressionOriginalBytes: compression?.originalBytes,
        compressionPayloadBytes: compression?.payloadBytes,
        mcmpSignatureStatus: mcmpStatus,
        mcmpTimestamp: mcmpMeta?.timestamp,
        mcmpSenderName: mcmpMeta?.senderName,
        mcmpIsSigned: mcmpMeta?.isSigned ?? false,
        mcmpSignature: mcmpMeta?.signature,
        pathLength: resolved.useFlood ? -1 : resolved.hopCount,
        pathBytes: Uint8List.fromList(resolved.pathBytes),
        originalText: originalText,
        translatedLanguageCode: translatedLanguageCode,
        translationModelId: translationModelId,
      );
      _addMessage(contact.publicKeyHex, message);
      notifyListeners();
      final sentByRadioAt = DateTime.now();
      final waitSeconds = sentByRadioAt.difference(message.timestamp).inSeconds;
      _updateMessage(
        message.copyWith(
          sentByRadioAt: sentByRadioAt,
          sentByRadioWaitSeconds: [waitSeconds < 0 ? 0 : waitSeconds],
        ),
      );
      await sendFrame(buildSendTextMsgFrame(contact.publicKey, outboundText));
    }
  }

  Future<void> setContactPath(
    Contact contact,
    Uint8List customPath,
    int pathLen,
  ) async {
    // Serialize path operations to prevent interleaved async calls from
    // leaving in-memory state inconsistent with the device.
    final prev = _pathOpLock;
    final completer = Completer<void>();
    _pathOpLock = completer.future;
    await prev;
    try {
      if (!isConnected) return;

      final encodedPathLen = _encodePathLenForCurrentMode(pathLen, customPath);
      if (encodedPathLen == null) {
        return;
      }
      await sendFrame(
        buildUpdateContactPathFrame(
          contact.publicKey,
          customPath,
          encodedPathLen,
          type: contact.type,
          flags: contact.flags,
          name: contact.name,
        ),
      );
      // USB writes return instantly (no BLE flow control), so give the firmware
      // time to persist the path change before subsequent commands.
      if (_activeTransport == MeshCoreTransportType.usb) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final idx = _contacts.indexWhere(
        (c) => c.publicKeyHex == contact.publicKeyHex,
      );
      if (idx != -1) {
        _contacts[idx] = _contacts[idx].copyWith(
          pathLength: pathLen,
          path: customPath,
        );
        notifyListeners();
      }
    } finally {
      completer.complete();
    }
  }

  Future<void> setContactFlags(
    Contact contact, {
    bool? isFavorite,
    bool? teleBase,
    bool? teleLoc,
    bool? teleEnv,
  }) async {
    if (!isConnected) return;
    final latestContact =
        await _fetchContactSnapshotFromDevice(contact.publicKey) ?? contact;
    int updatedFlags = isFavorite != null
        ? (isFavorite
              ? (latestContact.flags | contactFlagFavorite)
              : (latestContact.flags & ~contactFlagFavorite))
        : latestContact.flags;
    updatedFlags = teleBase != null
        ? (teleBase
              ? (updatedFlags | contactFlagTeleBase)
              : (updatedFlags & ~contactFlagTeleBase))
        : updatedFlags;
    updatedFlags = teleLoc != null
        ? (teleLoc
              ? (updatedFlags | contactFlagTeleLoc)
              : (updatedFlags & ~contactFlagTeleLoc))
        : updatedFlags;
    updatedFlags = teleEnv != null
        ? (teleEnv
              ? (updatedFlags | contactFlagTeleEnv)
              : (updatedFlags & ~contactFlagTeleEnv))
        : updatedFlags;

    final encodedPathLen = _encodePathLenForCurrentMode(
      latestContact.pathLength,
      latestContact.path,
    );
    if (encodedPathLen == null) return;
    await sendFrame(
      buildUpdateContactPathFrame(
        latestContact.publicKey,
        latestContact.path,
        encodedPathLen,
        type: latestContact.type,
        flags: updatedFlags,
        name: latestContact.name,
      ),
    );

    final index = _contacts.indexWhere(
      (c) => c.publicKeyHex == contact.publicKeyHex,
    );
    if (index >= 0) {
      _contacts[index] = _contacts[index].copyWith(
        type: latestContact.type,
        name: latestContact.name,
        pathLength: latestContact.pathLength,
        path: latestContact.path,
        flags: updatedFlags,
      );
      notifyListeners();
      unawaited(_persistContacts());
    }
  }

  Future<Contact?> _fetchContactSnapshotFromDevice(
    Uint8List pubKey, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (!isConnected) return null;
    final expectedKeyHex = pubKeyToHex(pubKey);
    final completer = Completer<Contact?>();

    void finish(Contact? result) {
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    }

    final subscription = receivedFrames.listen((frame) {
      if (frame.isEmpty || frame[0] != respCodeContact) return;
      final parsed = Contact.fromFrame(frame);
      if (parsed == null || parsed.publicKeyHex != expectedKeyHex) return;
      finish(parsed);
    });

    final timer = Timer(timeout, () => finish(null));
    try {
      await getContactByKey(pubKey);
      return await completer.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  }

  /// Set path override for a contact (persists across contact refreshes)
  /// pathLen: -1 = force flood, null = auto (use device path), >= 0 = specific path
  Future<void> setPathOverride(
    Contact contact, {
    int? pathLen,
    Uint8List? pathBytes,
  }) async {
    appLogger.info(
      'setPathOverride called for ${contact.name}: pathLen=$pathLen, bytesLen=${pathBytes?.length ?? 0}',
      tag: 'Connector',
    );

    // Find contact in list
    final index = _contacts.indexWhere(
      (c) => c.publicKeyHex == contact.publicKeyHex,
    );
    if (index == -1) {
      appLogger.warn(
        'setPathOverride: Contact not found in list: ${contact.name}',
        tag: 'Connector',
      );
      return;
    }

    appLogger.info(
      'Found contact at index $index. Current override: ${_contacts[index].pathOverride}',
      tag: 'Connector',
    );

    if (pathLen != null &&
        pathLen >= 0 &&
        !_isPathLenValidForCurrentMode(pathLen, pathBytes ?? Uint8List(0))) {
      appLogger.warn(
        'setPathOverride: invalid path for ${contact.name}: '
        'pathLen=$pathLen, bytesLen=${pathBytes?.length ?? 0}, '
        'width=$_pathHashByteWidth',
        tag: 'Connector',
      );
      return;
    }

    // Update contact with new path override
    _contacts[index] = _contacts[index].copyWith(
      pathOverride: pathLen,
      pathOverrideBytes: pathBytes,
      clearPathOverride: pathLen == null, // Clear if pathLen is null
    );

    appLogger.info(
      'Updated contact. New override: ${_contacts[index].pathOverride}, bytesLen: ${_contacts[index].pathOverrideBytes?.length}',
      tag: 'Connector',
    );

    // Save to storage
    await _persistContacts();
    appLogger.info('Saved contacts to storage', tag: 'Connector');

    // Update any in-flight retries so they use the new path override
    final updatedContact = _contacts.cast<Contact?>().firstWhere(
      (entry) => entry?.publicKeyHex == contact.publicKeyHex,
      orElse: () => null,
    );
    if (updatedContact != null) {
      _retryService?.updatePendingContact(updatedContact);
    }

    // If setting a specific path (not flood, not auto), also sync with device
    if (pathLen != null && pathLen >= 0 && pathBytes != null) {
      appLogger.info('Sending path to device...', tag: 'Connector');
      await setContactPath(contact, pathBytes, pathLen);
      appLogger.info('Path sent to device', tag: 'Connector');
    }

    debugPrint(
      'Set path override for ${contact.name}: pathLen=$pathLen, bytes=${pathBytes?.length ?? 0}',
    );
    notifyListeners();
  }

  Future<PathSelection> preparePathForContactSend(Contact contact) async {
    PathSelection? autoSelection;
    final autoRotationEnabled =
        _appSettingsService?.settings.autoRouteRotationEnabled == true;
    if (autoRotationEnabled && contact.pathOverride == null) {
      final maxRetries = _appSettingsService?.settings.maxMessageRetries ?? 5;
      autoSelection = _selectAutoPathForAttempt(
        contact.publicKeyHex,
        attemptIndex: 0,
        maxRetries: maxRetries,
      );
    }

    final resolved = resolvePathSelection(contact, selection: autoSelection);

    if (resolved.useFlood) {
      await clearContactPath(contact);
    } else {
      await setContactPath(
        contact,
        Uint8List.fromList(resolved.pathBytes),
        resolved.hopCount,
      );
    }

    return resolved;
  }

  void trackRepeaterAck({
    required Contact contact,
    required PathSelection selection,
    required String text,
    required int timestampSeconds,
    int attempt = 0,
  }) {
    final selfKey = _selfPublicKey;
    if (selfKey == null) return;
    // Use transformed text to match device's ACK hash computation
    final outboundText = prepareContactOutboundText(
      contact,
      text,
      estimateSignatureOverhead: false,
    );
    final ackHash = MessageRetryService.computeExpectedAckHash(
      timestampSeconds,
      attempt,
      outboundText,
      selfKey,
    );
    final ackHashHex = ackHashToHex(ackHash);
    final messageBytes = utf8.encode(outboundText).length;
    _pendingRepeaterAcks[ackHashHex]?.timeout?.cancel();
    _pendingRepeaterAcks[ackHashHex] = _RepeaterAckContext(
      contactKeyHex: contact.publicKeyHex,
      selection: selection,
      pathLength: selection.useFlood ? -1 : selection.hopCount,
      messageBytes: messageBytes,
    );
  }

  void recordRepeaterPathResult(
    Contact contact,
    PathSelection selection,
    bool success,
    int? tripTimeMs,
  ) {
    _recordPathResult(contact.publicKeyHex, selection, success, tripTimeMs);
  }

  Future<bool> verifyContactPathOnDevice(
    Contact contact,
    Uint8List expectedPath, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (!isConnected) return false;

    final expectedLength = expectedPath.length;
    final completer = Completer<bool>();

    void finish(bool result) {
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    }

    final subscription = receivedFrames.listen((frame) {
      if (frame.isEmpty || frame[0] != respCodeContact) return;
      final updated = Contact.fromFrame(frame);
      if (updated == null) return;
      if (updated.publicKeyHex != contact.publicKeyHex) return;
      final matchesLength = updated.pathLength == expectedLength;
      final matchesBytes = _pathsEqual(updated.path, expectedPath);
      if (matchesLength && matchesBytes) {
        finish(true);
      }
    });

    final timer = Timer(timeout, () => finish(false));
    try {
      await getContactByKey(contact.publicKey);
      return await completer.future;
    } finally {
      await subscription.cancel();
      timer.cancel();
    }
  }

  Future<void> sendChannelMessage(
    Channel channel,
    String text, {
    EncodedMCOImageV3? mcoImageV3,
    String? uncompressedText,
    String? originalText,
    String? translatedLanguageCode,
    String? translationModelId,
    String? replyToMessageId,
    String? replyToSenderName,
    String? replyToText,
    int? replyToTimestamp,
    ChannelBinaryDataOutbound? preparedMcoImageV3Outbound,
    String? pendingMessageId,
    DateTime? pendingTimestamp,
    DateTime? pendingReceivedAt,
  }) async {
    if (text.isEmpty || isOfflineMode) return;
    if (!isSessionReady) {
      if (pendingMessageId == null) {
        scheduleChannelMessage(
          channel,
          text,
          inputText: originalText ?? text,
          mcoImageV3: mcoImageV3,
          uncompressedText: uncompressedText,
          delaySeconds: 0,
          originalText: originalText,
          translatedLanguageCode: translatedLanguageCode,
          translationModelId: translationModelId,
          replyToMessageId: replyToMessageId,
          replyToSenderName: replyToSenderName,
          replyToText: replyToText,
          replyToTimestamp: replyToTimestamp,
        );
      }
      return;
    }
    final shouldBypassAckAndRetry = _isChannelAckAndRetryBypassed(channel.name);
    final shouldDeferForSync =
        !shouldBypassAckAndRetry && _shouldDeferChannelSendForSync;
    final hasExplicitMcoImageV3 =
        preparedMcoImageV3Outbound?.kind == ChannelBinaryDataKind.mcoImageV3 ||
        (mcoImageV3 != null && ChannelBinaryDataHelper.canSend);

    // Check if this is a reaction - if so, process it immediately instead of adding as a message.
    // An explicit MCOimg v3 object can never be a reaction payload.
    final reactionInfo = hasExplicitMcoImageV3
        ? null
        : ReactionHelper.parseReaction(text);
    if (reactionInfo != null) {
      // Check if we've already processed this reaction
      _processedChannelReactions.putIfAbsent(channel.index, () => {});
      final reactionIdentifier =
          '${reactionInfo.targetHash}_${reactionInfo.emoji}';

      if (_processedChannelReactions[channel.index]!.contains(
        reactionIdentifier,
      )) {
        // Already processed, don't process again
        return;
      }

      // Get the in-memory messages list (same as _addChannelMessage uses)
      _channelMessages.putIfAbsent(channel.index, () => []);
      final messages = _channelMessages[channel.index]!;

      // Process reaction locally to update the UI immediately
      _processReaction(messages, reactionInfo);
      await _channelMessageStore.saveChannelMessages(channel.index, messages);

      // Mark this reaction as processed
      _processedChannelReactions[channel.index]!.add(reactionIdentifier);

      notifyListeners();

      // Send the reaction to the device (don't add as a visible message)
      final reactionQueueId = _nextReactionSendQueueId();
      _pendingChannelSentQueue.add(reactionQueueId);
      await _runScopedChannelSend(() async {
        await _waitForRadioQuiet(lastInboundRxTime: _lastChannelMsgRxTime);
        await _sendFrameAndWaitForCommandAck(
          buildSendChannelTextMsgFrame(channel.index, text),
          channelSendQueueId: reactionQueueId,
          expectsGenericAck: true,
          successCode: respCodeSent,
        );
      }, region: getChannelRegion(channel.index));
      return;
    }

    final outgoingRegion = shouldDeferForSync
        ? _outgoingChannelRegion(channel.index)
        : await _outgoingChannelRegionForMessage(channel.index);
    if (!isConnected) return;

    // MCMP v3: the reply pair travels only when both parts are known, and the
    // signature covers the exact same flags/reply data as the encoded body.
    final hasReplyPair = replyToSenderName != null && replyToTimestamp != null;
    final mcmpReplyAuthorName = hasReplyPair ? replyToSenderName : null;
    final mcmpReplyTimestamp = hasReplyPair ? replyToTimestamp : null;
    final mcmpV3Applies =
        !hasExplicitMcoImageV3 &&
        isChannelMcmpEnabled(channel.index) &&
        channelMcmpVersion(channel.index) == 3 &&
        _isMcmpSignableText(text);
    final mcmpTimestamp = mcmpV3Applies
        ? DateTime.now().millisecondsSinceEpoch ~/ 1000
        : null;
    Uint8List? mcmpSignature;
    if (mcmpV3Applies && channelMcmpUseSign(channel.index)) {
      // Signing round-trips to the node (up to a few seconds). Show the
      // message right away in the pending state so it does not visually
      // disappear while we wait; it is finalized (badges/state) below once
      // the signature result is known, and only then actually transmitted.
      ChannelMessage? signingPlaceholder;
      if (pendingMessageId == null) {
        signingPlaceholder = ChannelMessage.outgoing(
          text,
          _selfName ?? 'Me',
          channel.index,
          originalText: originalText,
          translatedLanguageCode: translatedLanguageCode,
          translationModelId: translationModelId,
          replyToMessageId: replyToMessageId,
          replyToSenderName: replyToSenderName,
          replyToText: replyToText,
          packetRegion: _displayPacketRegion(outgoingRegion),
          packetRegionInfoAvailable: true,
        );
        _addChannelMessage(channel.index, signingPlaceholder);
        notifyListeners();
      }

      mcmpSignature = await _signMcmpCanonical(
        context: McmpSigningContext.channel,
        binding: McmpAppCodec.channelSigningBinding(channel.psk),
        senderName: _selfName ?? 'Me',
        timestamp: mcmpTimestamp!,
        hasSenderNameInBody: false,
        text: text,
        replyAuthorName: mcmpReplyAuthorName,
        replyTimestamp: mcmpReplyTimestamp,
      );

      // Drop the placeholder; the finalized message is (re-)added below in the
      // same synchronous pass, so the bubble never leaves the list.
      if (signingPlaceholder != null) {
        _channelMessages[channel.index]?.removeWhere(
          (m) => m.messageId == signingPlaceholder!.messageId,
        );
      }
      if (!isConnected) {
        notifyListeners();
        return;
      }
      if (mcmpSignature == null) _notifyMcmpSigningFailed();
    }

    final binaryOutbound =
        preparedMcoImageV3Outbound ??
        (hasExplicitMcoImageV3
            ? ChannelBinaryDataHelper.tryEncodeMcoImageV3Outbound(
                image: mcoImageV3!,
                senderName: _selfName ?? 'Me',
              )
            : ChannelBinaryDataHelper.tryEncodeOutbound(
                text: text,
                senderName: _selfName ?? 'Me',
                mcmpEnabled: isChannelMcmpEnabled(channel.index),
                mcmpVersion: channelMcmpVersion(channel.index),
                mcmpUseSign: channelMcmpUseSign(channel.index),
                timestamp:
                    mcmpTimestamp ??
                    DateTime.now().millisecondsSinceEpoch ~/ 1000,
                signature: mcmpSignature,
                replyAuthorName: replyToSenderName,
                replyTimestamp: replyToTimestamp,
              ));
    if (hasExplicitMcoImageV3 && binaryOutbound == null) return;

    final isMcoImageV3Binary =
        binaryOutbound?.kind == ChannelBinaryDataKind.mcoImageV3;
    final messageText = binaryOutbound?.canonicalText ?? text;
    final String outboundText;
    if (isMcoImageV3Binary) {
      outboundText = messageText;
    } else if (mcmpV3Applies && binaryOutbound == null) {
      // Text transport carries the signed body in the mcmp3: Base91 wrapper;
      // the sender name stays in the outer "Name: text" layer (no bit2).
      outboundText = McmpAppCodec.encodeTextTransport(
        text: text,
        timestamp: mcmpTimestamp!,
        signature: mcmpSignature,
        replyAuthorName: mcmpReplyAuthorName,
        replyTimestamp: mcmpReplyTimestamp,
      );
    } else {
      outboundText = prepareChannelOutboundText(channel.index, text);
    }
    final binaryFrame = binaryOutbound == null
        ? null
        : buildSendChannelDataFrame(
            channel.index,
            binaryOutbound.dataType,
            binaryOutbound.payload,
          );
    final isBinaryTransport = binaryFrame != null;
    final isBinaryMcmpTransport =
        binaryOutbound?.kind == ChannelBinaryDataKind.mcmp;
    final compression = isMcoImageV3Binary
        ? null
        : _channelCompressionMetadata(
            channel.index,
            uncompressedText ?? text,
            outboundText,
            binaryPayloadBytes: isBinaryMcmpTransport
                ? binaryOutbound?.payload.length
                : null,
            senderName: _selfName ?? 'Me',
          );
    final packetHash = binaryOutbound == null
        ? null
        : _computeChannelDataHash(
            channel.index,
            binaryOutbound.dataType,
            binaryOutbound.payload,
          );
    final packetRegion = _displayPacketRegion(outgoingRegion);
    if (pendingMessageId != null) {
      _pendingChannelSends.remove(pendingMessageId)?.timer?.cancel();
    }
    final baseMessage = ChannelMessage.outgoing(
      messageText,
      _selfName ?? 'Me',
      channel.index,
      messageId: pendingMessageId,
      timestamp: pendingTimestamp,
      receivedAt: pendingReceivedAt,
      wasMcmpCompressed:
          (!isMcoImageV3Binary && _isMcmpEncodedText(outboundText)) ||
          isBinaryMcmpTransport,
      compressionType: compression?.type,
      compressionSavingsPercent: compression?.savingsPercent,
      compressionOriginalBytes: compression?.originalBytes,
      compressionPayloadBytes: compression?.payloadBytes,
      mcmpSignatureStatus: mcmpV3Applies
          ? (mcmpSignature != null
                ? McmpSignatureStatus.valid
                : McmpSignatureStatus.unsigned)
          : (isBinaryMcmpTransport
                ? binaryOutbound!.mcmpSignatureStatus
                : McmpAppCodec.signatureStatusFromTextPayload(outboundText)),
      mcmpTimestamp: mcmpTimestamp,
      mcmpIsSigned: mcmpSignature != null,
      mcmpSignature: mcmpSignature,
      mcmpReplyAuthorName: mcmpV3Applies ? mcmpReplyAuthorName : null,
      mcmpReplyTimestamp: mcmpV3Applies ? mcmpReplyTimestamp : null,
      originalText: originalText,
      translatedLanguageCode: translatedLanguageCode,
      translationModelId: translationModelId,
      wasBinaryTransport: isBinaryTransport,
      binaryPacketBytes: binaryOutbound?.payload.length,
      packetRegion: packetRegion,
      packetRegionInfoAvailable: true,
      replyToMessageId: replyToMessageId,
      replyToSenderName: replyToSenderName,
      replyToText: replyToText,
    );
    final message = packetHash == null
        ? baseMessage
        : baseMessage.copyWith(packetHash: packetHash);
    _addChannelMessage(channel.index, message);
    if (!isBinaryTransport &&
        utf8.encode(outboundText).length > maxChannelMessageBytes(_selfName)) {
      // Belt-and-suspenders: the composer counter should prevent this, but a
      // signed container may exceed the frame/payload budget for long texts.
      appLogger.warn(
        'Channel message too long after MCMP encoding '
        '(${utf8.encode(outboundText).length} bytes), not sending',
      );
      _markPendingChannelMessageFailedById(message.messageId);
      return;
    }
    if (shouldDeferForSync) {
      _deferChannelMessageSend(
        channel,
        message.messageId,
        messageText,
        binaryOutbound: binaryOutbound,
        preparedOutboundText: isMcoImageV3Binary ? null : outboundText,
        uncompressedText: uncompressedText,
        originalText: originalText,
        translatedLanguageCode: translatedLanguageCode,
        translationModelId: translationModelId,
        replyToMessageId: replyToMessageId,
        replyToSenderName: replyToSenderName,
        replyToText: replyToText,
        replyToTimestamp: replyToTimestamp,
      );
      notifyListeners();
      return;
    }
    if (shouldBypassAckAndRetry) {
      notifyListeners();
      await _runScopedChannelSend(
        () async {
          await _waitForRadioQuiet(lastInboundRxTime: _lastChannelMsgRxTime);
          final sentByRadioAt = DateTime.now();
          final sentTimestampSeconds =
              sentByRadioAt.millisecondsSinceEpoch ~/ 1000;
          _updateChannelMessagePacketTimestamp(
            channel.index,
            message.messageId,
            sentTimestampSeconds,
            packetHash: binaryFrame == null
                ? _computeContentHash(
                    channel.index,
                    sentTimestampSeconds,
                    '${_selfName ?? 'Me'}: $messageText',
                  )
                : null,
          );
          _markPendingChannelMessageSentById(message.messageId);
          await sendFrame(
            binaryFrame ??
                buildSendChannelTextMsgFrame(
                  channel.index,
                  outboundText,
                  timestampSeconds: sentTimestampSeconds,
                ),
          );
        },
        region: getChannelRegion(channel.index),
        waitForScopeReset: false,
      );
      return;
    }
    _retriableChannelMessageSends[message.messageId] =
        _DeferredChannelMessageSend(
          channel: channel,
          messageId: message.messageId,
          text: messageText,
          binaryOutbound: binaryOutbound,
          preparedOutboundText: isMcoImageV3Binary ? null : outboundText,
          uncompressedText: uncompressedText,
          originalText: originalText,
          translatedLanguageCode: translatedLanguageCode,
          translationModelId: translationModelId,
          replyToMessageId: replyToMessageId,
          replyToSenderName: replyToSenderName,
          replyToText: replyToText,
          replyToTimestamp: replyToTimestamp,
        );
    _pendingChannelSentQueue.add(message.messageId);
    notifyListeners();

    await _runScopedChannelSend(() async {
      await _waitForRadioQuiet(lastInboundRxTime: _lastChannelMsgRxTime);
      final sentByRadioAt = DateTime.now();
      _markChannelMessageSentByRadio(message.messageId, sentByRadioAt);
      final sentTimestampSeconds = sentByRadioAt.millisecondsSinceEpoch ~/ 1000;
      _updateChannelMessagePacketTimestamp(
        channel.index,
        message.messageId,
        sentTimestampSeconds,
        packetHash: binaryFrame == null
            ? _computeContentHash(
                channel.index,
                sentTimestampSeconds,
                '${_selfName ?? 'Me'}: $messageText',
              )
            : null,
      );
      if (binaryFrame != null) {
        await _sendFrameAndWaitForCommandAck(
          binaryFrame,
          channelSendQueueId: message.messageId,
          expectsGenericAck: true,
        );
        return;
      }
      // Stamp the outgoing packet with the actual send time and align the
      // stored message.timestamp to the exact value that went on the air, so
      // replies to our own message resolve by exact-timestamp matching.
      await _sendFrameAndWaitForCommandAck(
        buildSendChannelTextMsgFrame(
          channel.index,
          outboundText,
          timestampSeconds: sentTimestampSeconds,
        ),
        channelSendQueueId: message.messageId,
        expectsGenericAck: true,
        successCode: respCodeSent,
      );
    }, region: getChannelRegion(channel.index));
  }

  bool get _shouldDeferChannelSendForSync =>
      _isLoadingContacts || _isSyncingChannels || _channelSyncInFlight;

  void _deferChannelMessageSend(
    Channel channel,
    String messageId,
    String text, {
    ChannelBinaryDataOutbound? binaryOutbound,
    String? preparedOutboundText,
    String? uncompressedText,
    String? originalText,
    String? translatedLanguageCode,
    String? translationModelId,
    String? replyToMessageId,
    String? replyToSenderName,
    String? replyToText,
    int? replyToTimestamp,
  }) {
    _deferredChannelMessageSends.add(
      _DeferredChannelMessageSend(
        channel: channel,
        messageId: messageId,
        text: text,
        binaryOutbound: binaryOutbound,
        preparedOutboundText: preparedOutboundText,
        uncompressedText: uncompressedText,
        originalText: originalText,
        translatedLanguageCode: translatedLanguageCode,
        translationModelId: translationModelId,
        replyToMessageId: replyToMessageId,
        replyToSenderName: replyToSenderName,
        replyToText: replyToText,
        replyToTimestamp: replyToTimestamp,
      ),
    );
  }

  void _clearDeferredChannelMessageSends({required bool markFailed}) {
    if (markFailed) {
      for (final pending in _deferredChannelMessageSends) {
        _markPendingChannelMessageFailedById(pending.messageId);
      }
    }
    _deferredChannelMessageSends.clear();
  }

  void _clearRetriableChannelMessageSends({required bool markFailed}) {
    final messageIds = List<String>.from(_retriableChannelMessageSends.keys);
    _retriableChannelMessageSends.clear();
    if (!markFailed) return;
    for (final messageId in messageIds) {
      _markPendingChannelMessageFailedById(messageId);
    }
  }

  Future<void> _flushDeferredChannelMessageSends() async {
    if (_isFlushingDeferredChannelMessageSends ||
        _deferredChannelMessageSends.isEmpty ||
        !isConnected ||
        _shouldDeferChannelSendForSync) {
      return;
    }

    _isFlushingDeferredChannelMessageSends = true;
    try {
      while (_deferredChannelMessageSends.isNotEmpty &&
          isConnected &&
          !_shouldDeferChannelSendForSync) {
        final pending = _deferredChannelMessageSends.removeAt(0);
        await _sendDeferredChannelMessage(pending);
      }
    } finally {
      _isFlushingDeferredChannelMessageSends = false;
    }
  }

  Future<void> _sendDeferredChannelMessage(
    _DeferredChannelMessageSend pending,
  ) async {
    final outgoingRegion = await _outgoingChannelRegionForMessage(
      pending.channel.index,
    );
    if (!isConnected) return;
    _updatePendingChannelMessageRegion(
      pending.messageId,
      _displayPacketRegion(outgoingRegion),
    );

    // Reuse the exact binary payload that was used to create the local
    // outgoing message. In particular, do not refresh the MCOimg v3 nonce a
    // second time while a send is deferred for channel/contact sync.
    final binaryOutbound = pending.binaryOutbound;
    final isMcoImageV3Binary =
        binaryOutbound?.kind == ChannelBinaryDataKind.mcoImageV3;
    final outboundText = isMcoImageV3Binary
        ? pending.text
        : pending.preparedOutboundText ??
              prepareChannelOutboundText(
                pending.channel.index,
                pending.text,
                estimateSignatureOverhead: false,
              );
    final binaryFrame = binaryOutbound == null
        ? null
        : buildSendChannelDataFrame(
            pending.channel.index,
            binaryOutbound.dataType,
            binaryOutbound.payload,
          );

    final shouldBypassAckAndRetry = _isChannelAckAndRetryBypassed(
      pending.channel.name,
    );
    if (!shouldBypassAckAndRetry) {
      _retriableChannelMessageSends[pending.messageId] = pending;
      _pendingChannelSentQueue.remove(pending.messageId);
      _pendingChannelSentQueue.add(pending.messageId);
    }
    notifyListeners();

    await _runScopedChannelSend(
      () async {
        await _waitForRadioQuiet(lastInboundRxTime: _lastChannelMsgRxTime);
        final sentByRadioAt = DateTime.now();
        final sentTimestampSeconds =
            sentByRadioAt.millisecondsSinceEpoch ~/ 1000;
        _updateChannelMessagePacketTimestamp(
          pending.channel.index,
          pending.messageId,
          sentTimestampSeconds,
          packetHash: binaryFrame == null
              ? _computeContentHash(
                  pending.channel.index,
                  sentTimestampSeconds,
                  '${_selfName ?? 'Me'}: ${pending.text}',
                )
              : null,
        );
        if (shouldBypassAckAndRetry) {
          _markPendingChannelMessageSentById(pending.messageId);
          await sendFrame(
            binaryFrame ??
                buildSendChannelTextMsgFrame(
                  pending.channel.index,
                  outboundText,
                  timestampSeconds: sentTimestampSeconds,
                ),
          );
          return;
        }
        _markChannelMessageSentByRadio(pending.messageId, sentByRadioAt);
        if (binaryFrame != null) {
          await _sendFrameAndWaitForCommandAck(
            binaryFrame,
            channelSendQueueId: pending.messageId,
            expectsGenericAck: true,
          );
          return;
        }
        await _sendFrameAndWaitForCommandAck(
          buildSendChannelTextMsgFrame(
            pending.channel.index,
            outboundText,
            timestampSeconds: sentTimestampSeconds,
          ),
          channelSendQueueId: pending.messageId,
          expectsGenericAck: true,
        );
      },
      region: getChannelRegion(pending.channel.index),
      waitForScopeReset: !shouldBypassAckAndRetry,
    );
  }

  void _updatePendingChannelMessageRegion(String messageId, String? region) {
    for (final entry in _channelMessages.entries) {
      final channelMessages = entry.value;
      final index = channelMessages.indexWhere(
        (message) => message.messageId == messageId,
      );
      if (index < 0) continue;

      final message = channelMessages[index];
      if (!message.isOutgoing || message.packetRegion == region) return;

      channelMessages[index] = message.copyWith(
        packetRegion: region,
        packetRegionInfoAvailable: true,
      );
      unawaited(
        _channelMessageStore.saveChannelMessages(entry.key, channelMessages),
      );
      notifyListeners();
      return;
    }
  }

  Future<void> _runScopedChannelSend(
    Future<void> Function() action, {
    required String region,
    bool waitForScopeReset = true,
  }) async {
    final prev = _channelScopedSendLock;
    final completer = Completer<void>();
    _channelScopedSendLock = completer.future;
    await prev;

    try {
      // An empty channel region deliberately clears any previous app override,
      // handing scope selection back to the node's default-region setting.
      // This must happen for unscoped channels too: otherwise a stale scope
      // left by another client can leak into the outgoing packet.
      await _sendFrameAndWaitForCommandAck(buildSetFloodScopeFrame(region));
      try {
        await action();
      } finally {
        if (isConnected) {
          final clearScopeFrame = buildSetFloodScopeFrame('');
          if (waitForScopeReset) {
            await _sendFrameAndWaitForCommandAck(clearScopeFrame);
          } else {
            unawaited(
              sendFrame(clearScopeFrame).catchError((error) {
                appLogger.warn(
                  'Best-effort flood scope reset failed: $error',
                  tag: 'Channel Send',
                );
              }),
            );
          }
        }
      }
    } finally {
      completer.complete();
    }
  }

  // Sends [data] and resolves once the device replies. [successCode] is the
  // response code that signals success for this frame: SET_FLOOD_SCOPE replies
  // with RESP_CODE_OK, whereas a channel text send replies with RESP_CODE_SENT.
  // Waiting for the text send's RESP_CODE_SENT before the scope is reset
  // guarantees the firmware has already built the packet with the active scope.
  Future<void> _sendFrameAndWaitForCommandAck(
    Uint8List data, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    int successCode = respCodeOk,
  }) async {
    final completer = Completer<void>();
    late final StreamSubscription<Uint8List> subscription;
    late final Timer timeout;

    void complete() {
      if (!completer.isCompleted) completer.complete();
    }

    void completeError(Object error) {
      if (!completer.isCompleted) completer.completeError(error);
    }

    subscription = receivedFrames.listen((frame) {
      if (frame.isEmpty) return;
      if (frame[0] == successCode) {
        complete();
      } else if (frame[0] == respCodeErr) {
        final errCode = frame.length > 1 ? frame[1] : -1;
        completeError(Exception('Command failed with error code $errCode'));
      }
    });

    timeout = Timer(_commandAckTimeout, () {
      completeError(TimeoutException('Command ACK timed out'));
    });

    try {
      await sendFrame(
        data,
        channelSendQueueId: channelSendQueueId,
        expectsGenericAck: expectsGenericAck,
      );
      await completer.future;
    } finally {
      timeout.cancel();
      await subscription.cancel();
    }
  }

  static const Duration _signAttemptTimeout = Duration(seconds: 3);
  static const int _signAttempts = 5;
  Future<void> _signSessionTail = Future.value();

  /// Signs [data] with the connected node's identity key via
  /// CMD_SIGN_START/DATA/FINISH. Returns the 64-byte Ed25519 signature, or
  /// null when signing is unavailable (old firmware, timeouts, disconnect) —
  /// callers should then proceed unsigned.
  ///
  /// Sessions are serialized: the firmware keeps a single global sign buffer
  /// and a new CMD_SIGN_START silently resets the previous session. Each
  /// attempt gets [_signAttemptTimeout] counted from the moment its first
  /// frame is handed to the transport; time spent waiting in the queue does
  /// not count.
  Future<Uint8List?> signWithNode(Uint8List data) async {
    if (data.isEmpty || data.length > maxSignDataTotalBytes) {
      appLogger.warn(
        'MCMP sign request of ${data.length} bytes is out of range',
      );
      return null;
    }
    final previous = _signSessionTail;
    final sessionDone = Completer<void>();
    _signSessionTail = sessionDone.future;
    await previous;
    try {
      for (var attempt = 1; attempt <= _signAttempts; attempt++) {
        if (!isConnected) return null;
        try {
          return await _runSignAttempt(data);
        } catch (e) {
          appLogger.warn(
            'MCMP sign attempt $attempt/$_signAttempts failed: $e',
          );
        }
      }
      return null;
    } finally {
      sessionDone.complete();
    }
  }

  Future<Uint8List> _runSignAttempt(Uint8List data) async {
    // Signing shares the broadcast frame stream with all other command
    // traffic (battery/stats polling, flood-scope, channel-data sends, the
    // channel sync loop) and RESP_CODE_OK is emitted by many of those. So we
    // correlate the session boundaries on the sign-unique codes
    // (RESP_CODE_SIGN_START / RESP_CODE_SIGNATURE). Each data chunk must still
    // receive its OK before FINISH is sent: otherwise a rejected DATA followed
    // by FINISH produces two ERR frames, and the second one can poison the next
    // retry. RESP_CODE_OK is shared with other commands, so signing sessions
    // should remain serialized and short.
    final buffered = <Uint8List>[];
    Completer<Uint8List>? waiter;
    Set<int>? waitCodes;
    late final StreamSubscription<Uint8List> subscription;

    bool matches(int code, Set<int> codes) => codes.contains(code);

    subscription = receivedFrames.listen((frame) {
      if (frame.isEmpty) return;
      final code = frame[0];
      final pending = waiter;
      final codes = waitCodes;
      if (pending != null && codes != null && matches(code, codes)) {
        waiter = null;
        waitCodes = null;
        pending.complete(Uint8List.fromList(frame));
      } else {
        buffered.add(Uint8List.fromList(frame));
      }
    });

    final deadline = DateTime.now().add(_signAttemptTimeout);

    // Waits for the next frame whose code is in [codes], discarding any other
    // (foreign) frames. Throws on timeout.
    Future<Uint8List> waitForCodes(Set<int> codes) async {
      while (buffered.isNotEmpty) {
        final frame = buffered.removeAt(0);
        if (matches(frame[0], codes)) return frame;
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw TimeoutException('Sign attempt timed out');
      }
      final pending = Completer<Uint8List>();
      waiter = pending;
      waitCodes = codes;
      try {
        return await pending.future.timeout(remaining);
      } finally {
        if (identical(waiter, pending)) {
          waiter = null;
          waitCodes = null;
        }
      }
    }

    try {
      await sendFrame(buildSignStartFrame());
      final startResp = await waitForCodes({respCodeSignStart, respCodeErr});
      if (startResp[0] == respCodeErr) {
        final errCode = startResp.length > 1 ? startResp[1] : -1;
        throw Exception('Sign start rejected with error code $errCode');
      }
      if (startResp.length >= 6) {
        final reader = BufferReader(startResp);
        reader.skipBytes(2); // code + reserved
        final maxLen = reader.readUInt32LE();
        if (data.length > maxLen) {
          throw Exception(
            'Sign data of ${data.length} bytes exceeds node limit $maxLen',
          );
        }
      }

      // Confirm every chunk before advancing. In particular, do not send
      // FINISH after a rejected DATA: the firmware would emit another ERR for
      // the same failed session and that stale response could be mistaken for
      // the result of the next retry.
      for (
        var offset = 0;
        offset < data.length;
        offset += maxSignDataChunkBytes
      ) {
        final end = (offset + maxSignDataChunkBytes) > data.length
            ? data.length
            : offset + maxSignDataChunkBytes;
        await sendFrame(
          buildSignDataFrame(Uint8List.sublistView(data, offset, end)),
        );
        final dataResp = await waitForCodes({respCodeOk, respCodeErr});
        if (dataResp[0] == respCodeErr) {
          final errCode = dataResp.length > 1 ? dataResp[1] : -1;
          throw Exception('Sign data rejected with error code $errCode');
        }
      }

      await sendFrame(buildSignFinishFrame());
      final finishResp = await waitForCodes({respCodeSignature, respCodeErr});
      if (finishResp[0] == respCodeErr) {
        final errCode = finishResp.length > 1 ? finishResp[1] : -1;
        throw Exception('Sign finish rejected with error code $errCode');
      }
      if (finishResp.length < 1 + signatureSize) {
        throw Exception('Malformed signature response');
      }
      return Uint8List.fromList(finishResp.sublist(1, 1 + signatureSize));
    } finally {
      await subscription.cancel();
    }
  }

  List<Message> getPendingContactMessages(String contactKeyHex) {
    return _pendingContactSends.values
        .where((pending) => pending.contact.publicKeyHex == contactKeyHex)
        .map((pending) => pending.message)
        .toList();
  }

  List<ChannelMessage> getPendingChannelMessages(int channelIndex) {
    return _pendingChannelSends.values
        .where((pending) => pending.channel.index == channelIndex)
        .map((pending) => pending.message)
        .toList();
  }

  DateTime? pendingContactSendAt(String messageId) {
    final pending = _pendingContactSends[messageId];
    return pending == null || pending.delaySeconds <= 0 ? null : pending.sendAt;
  }

  int? pendingContactSendDelaySeconds(String messageId) {
    final delay = _pendingContactSends[messageId]?.delaySeconds;
    return delay == null || delay <= 0 ? null : delay;
  }

  DateTime? pendingChannelSendAt(String messageId) {
    final pending = _pendingChannelSends[messageId];
    return pending == null || pending.delaySeconds <= 0 ? null : pending.sendAt;
  }

  int? pendingChannelSendDelaySeconds(String messageId) {
    final delay = _pendingChannelSends[messageId]?.delaySeconds;
    return delay == null || delay <= 0 ? null : delay;
  }

  void pausePendingOutgoingMessages() {
    _retryService?.setSendingPaused(true);
  }

  Future<void> resumePendingOutgoingMessages() async {
    if (!isSessionReady || _isFlushingPendingOutgoingMessages) return;
    _isFlushingPendingOutgoingMessages = true;
    try {
      final now = DateTime.now();
      final contactIds = List<String>.from(_pendingContactSends.keys);
      for (final messageId in contactIds) {
        final pending = _pendingContactSends[messageId];
        if (pending == null) continue;
        if (pending.delaySeconds > 0 && pending.sendAt.isAfter(now)) {
          pending.timer?.cancel();
          pending.timer = Timer(
            pending.sendAt.difference(now),
            () => _commitPendingContactSend(messageId),
          );
          continue;
        }
        await _commitPendingContactSend(messageId);
        if (!isSessionReady) return;
      }

      final channelIds = List<String>.from(_pendingChannelSends.keys);
      for (final messageId in channelIds) {
        final pending = _pendingChannelSends[messageId];
        if (pending == null) continue;
        if (pending.delaySeconds > 0 && pending.sendAt.isAfter(now)) {
          pending.timer?.cancel();
          pending.timer = Timer(
            pending.sendAt.difference(now),
            () => _commitPendingChannelSend(messageId),
          );
          continue;
        }
        await _commitPendingChannelSend(messageId);
        if (!isSessionReady) return;
      }

      if (_shouldReplayRetriableChannelMessageSends) {
        _shouldReplayRetriableChannelMessageSends = false;
        await _flushRetriableChannelMessageSends();
      }
    } finally {
      _isFlushingPendingOutgoingMessages = false;
      if (isSessionReady) {
        _retryService?.setSendingPaused(false);
      }
    }
  }

  Future<void> _flushRetriableChannelMessageSends() async {
    if (_isFlushingRetriableChannelMessageSends || !isSessionReady) return;
    _isFlushingRetriableChannelMessageSends = true;
    try {
      final pendingSends = List<_DeferredChannelMessageSend>.from(
        _retriableChannelMessageSends.values,
      );
      for (final pending in pendingSends) {
        if (!isSessionReady) return;
        final messages = _channelMessages[pending.channel.index];
        ChannelMessage? message;
        if (messages != null) {
          for (final candidate in messages) {
            if (candidate.messageId == pending.messageId) {
              message = candidate;
              break;
            }
          }
        }
        if (message == null ||
            !message.isOutgoing ||
            message.status != ChannelMessageStatus.pending) {
          _retriableChannelMessageSends.remove(pending.messageId);
          continue;
        }
        try {
          await _sendDeferredChannelMessage(pending);
        } catch (error) {
          _appDebugLogService?.warn(
            'Retryable channel send failed: $error',
            tag: 'Channel Send',
          );
          if (!isSessionReady) return;
        }
      }
    } finally {
      _isFlushingRetriableChannelMessageSends = false;
    }
  }

  void scheduleContactMessage(
    Contact contact,
    String text, {
    required String inputText,
    String? uncompressedText,
    required int delaySeconds,
    String? originalText,
    String? translatedLanguageCode,
    String? translationModelId,
  }) {
    if (text.isEmpty || delaySeconds < 0 || isOfflineMode) return;
    final resolved = resolvePathSelection(contact);
    // Preview only: the real send re-prepares (and re-signs) at commit time.
    final outboundText = prepareContactOutboundText(contact, text);
    final compression = _contactCompressionMetadata(
      contact,
      uncompressedText ?? text,
      outboundText,
    );
    final message = Message.outgoing(
      contact.publicKey,
      text,
      wasMcmpCompressed: _isMcmpEncodedText(outboundText),
      compressionType: compression?.type,
      compressionSavingsPercent: compression?.savingsPercent,
      compressionOriginalBytes: compression?.originalBytes,
      compressionPayloadBytes: compression?.payloadBytes,
      // Pending previews never show a signature badge; the real send at
      // commit time re-prepares, signs and stamps the actual meta.
      mcmpSignatureStatus: McmpSignatureStatus.none,
      pathLength: resolved.useFlood ? -1 : resolved.hopCount,
      pathBytes: Uint8List.fromList(resolved.pathBytes),
      originalText: originalText,
      translatedLanguageCode: translatedLanguageCode,
      translationModelId: translationModelId,
    );
    final pending = _PendingContactSend(
      contact: contact,
      message: message,
      text: text,
      inputText: inputText,
      uncompressedText: uncompressedText ?? text,
      originalText: originalText,
      translatedLanguageCode: translatedLanguageCode,
      translationModelId: translationModelId,
      delaySeconds: delaySeconds,
      sendAt: DateTime.now().add(Duration(seconds: delaySeconds)),
    );
    if (delaySeconds > 0) {
      pending.timer = Timer(
        Duration(seconds: delaySeconds),
        () => _commitPendingContactSend(message.messageId),
      );
    }
    _pendingContactSends[message.messageId] = pending;
    notifyListeners();
  }

  void scheduleChannelMessage(
    Channel channel,
    String text, {
    required String inputText,
    EncodedMCOImageV3? mcoImageV3,
    String? uncompressedText,
    required int delaySeconds,
    String? originalText,
    String? translatedLanguageCode,
    String? translationModelId,
    String? replyToMessageId,
    String? replyToSenderName,
    String? replyToText,
    int? replyToTimestamp,
  }) {
    if (text.isEmpty || delaySeconds < 0 || isOfflineMode) return;
    final outboundText = prepareChannelOutboundText(channel.index, text);
    final binaryOutbound = mcoImageV3 != null
        ? ChannelBinaryDataHelper.tryEncodeMcoImageV3Outbound(
            image: mcoImageV3,
            senderName: _selfName ?? 'Me',
          )
        : ChannelBinaryDataHelper.tryEncodeOutbound(
            text: text,
            senderName: _selfName ?? 'Me',
            mcmpEnabled: isChannelMcmpEnabled(channel.index),
            mcmpVersion: channelMcmpVersion(channel.index),
            mcmpUseSign: channelMcmpUseSign(channel.index),
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            replyAuthorName: replyToSenderName,
            replyTimestamp: replyToTimestamp,
          );
    final binaryFrame = binaryOutbound == null
        ? null
        : buildSendChannelDataFrame(
            channel.index,
            binaryOutbound.dataType,
            binaryOutbound.payload,
          );
    final usesBinaryTransport = binaryFrame != null;
    final usesBinaryMcmp = binaryOutbound?.kind == ChannelBinaryDataKind.mcmp;
    final messageText = binaryOutbound?.canonicalText ?? text;
    final compression = _channelCompressionMetadata(
      channel.index,
      uncompressedText ?? text,
      outboundText,
      binaryPayloadBytes: usesBinaryMcmp
          ? binaryOutbound?.payload.length
          : null,
      senderName: _selfName ?? 'Me',
    );
    final packetHash = binaryOutbound == null
        ? null
        : _computeChannelDataHash(
            channel.index,
            binaryOutbound.dataType,
            binaryOutbound.payload,
          );
    final packetRegion = _displayPacketRegion(
      _outgoingChannelRegion(channel.index),
    );
    final baseMessage = ChannelMessage.outgoing(
      messageText,
      _selfName ?? 'Me',
      channel.index,
      wasMcmpCompressed: _isMcmpEncodedText(outboundText) || usesBinaryMcmp,
      compressionType: compression?.type,
      compressionSavingsPercent: compression?.savingsPercent,
      compressionOriginalBytes: compression?.originalBytes,
      compressionPayloadBytes: compression?.payloadBytes,
      // Pending previews never show a signature badge; the real send at
      // commit time re-encodes, signs and stamps the actual meta.
      mcmpSignatureStatus: McmpSignatureStatus.none,
      wasBinaryTransport: usesBinaryTransport,
      binaryPacketBytes: binaryOutbound?.payload.length,
      packetRegion: packetRegion,
      packetRegionInfoAvailable: true,
      originalText: originalText,
      translatedLanguageCode: translatedLanguageCode,
      translationModelId: translationModelId,
      replyToMessageId: replyToMessageId,
      replyToSenderName: replyToSenderName,
      replyToText: replyToText,
    );
    final message = packetHash == null
        ? baseMessage
        : baseMessage.copyWith(packetHash: packetHash);
    final pending = _PendingChannelSend(
      channel: channel,
      message: message,
      text: messageText,
      mcoImageV3: mcoImageV3,
      mcoImageV3Outbound:
          binaryOutbound?.kind == ChannelBinaryDataKind.mcoImageV3
          ? binaryOutbound
          : null,
      inputText: inputText,
      uncompressedText: uncompressedText ?? text,
      originalText: originalText,
      translatedLanguageCode: translatedLanguageCode,
      translationModelId: translationModelId,
      replyToMessageId: replyToMessageId,
      replyToSenderName: replyToSenderName,
      replyToText: replyToText,
      replyToTimestamp: replyToTimestamp,
      delaySeconds: delaySeconds,
      sendAt: DateTime.now().add(Duration(seconds: delaySeconds)),
    );
    if (delaySeconds > 0) {
      pending.timer = Timer(
        Duration(seconds: delaySeconds),
        () => _commitPendingChannelSend(message.messageId),
      );
    }
    _pendingChannelSends[message.messageId] = pending;
    notifyListeners();
  }

  String? cancelPendingContactSend(String messageId) {
    final pending = _pendingContactSends.remove(messageId);
    if (pending == null) return null;
    pending.timer?.cancel();
    notifyListeners();
    return pending.inputText;
  }

  String? cancelPendingChannelSend(String messageId) {
    _retriableChannelMessageSends.remove(messageId);
    final pending = _pendingChannelSends.remove(messageId);
    if (pending == null) return null;
    pending.timer?.cancel();
    notifyListeners();
    return pending.inputText;
  }

  Future<void> _commitPendingContactSend(String messageId) async {
    final pending = _pendingContactSends[messageId];
    if (pending == null) return;
    if (!isSessionReady) return;
    pending.timer?.cancel();
    final liveContactIndex = _contacts.indexWhere(
      (contact) => contact.publicKeyHex == pending.contact.publicKeyHex,
    );
    final contact = liveContactIndex < 0
        ? pending.contact
        : _contacts[liveContactIndex];
    try {
      await sendMessage(
        contact,
        pending.text,
        uncompressedText: pending.uncompressedText,
        originalText: pending.originalText,
        translatedLanguageCode: pending.translatedLanguageCode,
        translationModelId: pending.translationModelId,
        pendingMessageId: pending.message.messageId,
        pendingTimestamp: pending.message.timestamp,
      );
    } catch (error) {
      appLogger.warn(
        'Deferred contact send failed before retry tracking: $error',
        tag: 'Connector',
      );
    }
  }

  Future<void> _commitPendingChannelSend(String messageId) async {
    final pending = _pendingChannelSends[messageId];
    if (pending == null) return;
    if (!isSessionReady) return;
    pending.timer?.cancel();
    final liveChannelIndex = _channels.indexWhere(
      (channel) => channel.index == pending.channel.index,
    );
    if (liveChannelIndex < 0) {
      _pendingChannelSends.remove(messageId);
      _addChannelMessage(
        pending.channel.index,
        pending.message.copyWith(status: ChannelMessageStatus.failed),
      );
      return;
    }
    final channel = _channels[liveChannelIndex];
    try {
      await sendChannelMessage(
        channel,
        pending.text,
        mcoImageV3: pending.mcoImageV3,
        uncompressedText: pending.uncompressedText,
        originalText: pending.originalText,
        translatedLanguageCode: pending.translatedLanguageCode,
        translationModelId: pending.translationModelId,
        replyToMessageId: pending.replyToMessageId,
        replyToSenderName: pending.replyToSenderName,
        replyToText: pending.replyToText,
        replyToTimestamp: pending.replyToTimestamp,
        preparedMcoImageV3Outbound: pending.mcoImageV3Outbound,
        pendingMessageId: pending.message.messageId,
        pendingTimestamp: pending.message.timestamp,
        pendingReceivedAt: pending.message.receivedAt,
      );
    } catch (error) {
      appLogger.warn('Deferred channel send failed: $error', tag: 'Connector');
      if (!_pendingChannelSends.containsKey(messageId)) {
        _markPendingChannelMessageFailedById(messageId);
      }
    }
  }

  void _markChannelMessageSentByRadio(
    String messageId,
    DateTime sentByRadioAt,
  ) {
    for (final entry in _channelMessages.entries) {
      final channelMessages = entry.value;
      final index = channelMessages.indexWhere(
        (message) => message.messageId == messageId,
      );
      if (index < 0) continue;

      final message = channelMessages[index];
      if (!message.isOutgoing) return;

      // Keep the visible message timestamp unchanged; sentByRadioAt is only
      // for matching late log-rx repeats after radio backoff/quiet waits.
      channelMessages[index] = message.copyWith(sentByRadioAt: sentByRadioAt);
      _scheduleChannelNoRetransmissionWarning(messageId);
      unawaited(
        _channelMessageStore.saveChannelMessages(entry.key, channelMessages),
      );
      notifyListeners();
      return;
    }
  }

  /// Aligns an outgoing message's packet timestamp to the value that was
  /// actually written into the transmitted frame, so replies to our own
  /// message resolve by exact-timestamp matching. The visible bubble time uses
  /// receivedAt and is unaffected.
  void _updateChannelMessagePacketTimestamp(
    int channelIndex,
    String messageId,
    int timestampSeconds, {
    String? packetHash,
  }) {
    final channelMessages = _channelMessages[channelIndex];
    if (channelMessages == null) return;
    final index = channelMessages.indexWhere(
      (message) => message.messageId == messageId,
    );
    if (index < 0) return;
    final message = channelMessages[index];
    if (!message.isOutgoing) return;
    channelMessages[index] = message.copyWith(
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampSeconds * 1000),
      packetHash: packetHash,
    );
    unawaited(
      _channelMessageStore.saveChannelMessages(channelIndex, channelMessages),
    );
    notifyListeners();
  }

  void _scheduleChannelNoRetransmissionWarning(String messageId) {
    _cancelChannelNoRetransmissionWarning(messageId);
    final seconds =
        _appSettingsService?.settings.noRetransmissionWarningSeconds ?? 0;
    if (seconds <= 0) return;

    _channelNoRetransmissionTimers[messageId] = Timer(
      Duration(seconds: seconds),
      () {
        _channelNoRetransmissionTimers.remove(messageId);
        _markChannelMessageNoRetransmission(messageId, seconds);
      },
    );
  }

  void _cancelChannelNoRetransmissionWarning(String messageId) {
    _channelNoRetransmissionTimers.remove(messageId)?.cancel();
  }

  void _cancelAllChannelNoRetransmissionTimers() {
    for (final timer in _channelNoRetransmissionTimers.values) {
      timer.cancel();
    }
    _channelNoRetransmissionTimers.clear();
  }

  void _markChannelMessageNoRetransmission(String messageId, int seconds) {
    if ((_appSettingsService?.settings.noRetransmissionWarningSeconds ?? 0) <=
        0) {
      return;
    }

    for (final entry in _channelMessages.entries) {
      final channelMessages = entry.value;
      final index = channelMessages.indexWhere(
        (message) => message.messageId == messageId,
      );
      if (index < 0) continue;

      final message = channelMessages[index];
      if (!message.isOutgoing ||
          message.sentByRadioAt == null ||
          message.repeatCount > 0 ||
          message.status == ChannelMessageStatus.failed) {
        return;
      }

      channelMessages[index] = message.copyWith(
        noRetransmissionWarningSeconds: seconds,
      );
      unawaited(
        _channelMessageStore.saveChannelMessages(entry.key, channelMessages),
      );
      notifyListeners();
      return;
    }
  }

  Future<void> removeContact(Contact contact, {bool waitForAck = false}) async {
    if (!isConnected) {
      if (waitForAck) {
        throw Exception('Not connected to a MeshCore device');
      }
      return;
    }

    await sendFrame(
      buildRemoveContactFrame(contact.publicKey),
      waitForGenericAck: waitForAck,
    );

    _handleDiscovery(
      contact,
      contact.rawPacket ?? Uint8List(0),
      noNotify: true,
    );
    _contacts.removeWhere((c) => c.publicKeyHex == contact.publicKeyHex);
    _contactMessagePreviews.remove(contact.publicKeyHex);
    _knownContactKeys.remove(contact.publicKeyHex);
    unawaited(updateKnownDiscovered());
    unawaited(_persistContacts());
    _conversations.remove(contact.publicKeyHex);
    _loadedConversationKeys.remove(contact.publicKeyHex);
    _conversationLoadFutures.remove(contact.publicKeyHex);
    final removedCount = _contactUnreadCount[contact.publicKeyHex] ?? 0;
    _cachedContactsUnreadTotal = (_cachedContactsUnreadTotal - removedCount)
        .clamp(0, _cachedContactsUnreadTotal);
    _contactUnreadCount.remove(contact.publicKeyHex);
    _unreadStore.saveContactUnreadCount(
      Map<String, int>.from(_contactUnreadCount),
    );
    _messageStore.clearMessages(contact.publicKeyHex);
    notifyListeners();
  }

  Future<void> updateKnownDiscovered() async {
    if (!isConnected) return;
    for (int i = 0; i < _discoveredContacts.length; i++) {
      _discoveredContacts[i] = _discoveredContacts[i].copyWith(
        isActive: _knownContactKeys.contains(
          _discoveredContacts[i].publicKeyHex,
        ),
      );
    }
    unawaited(_persistDiscoveredContacts());
    notifyListeners();
  }

  Future<void> removeDiscoveredContact(Contact contact) async {
    if (!isConnected) return;
    _discoveredContacts.removeWhere(
      (c) => c.publicKeyHex == contact.publicKeyHex,
    );
    unawaited(_persistDiscoveredContacts());
    notifyListeners();
  }

  Future<bool> importDiscoveredContact(Contact contact) async {
    if (!isConnected) return false;

    // Manual saves must bypass the firmware's auto-add discovery policy.
    // CMD_IMPORT_CONTACT replays an advert and may remain discovery-only.
    final encodedPathLen = _encodePathLenForCurrentMode(
      contact.pathLength,
      contact.path,
    );
    if (encodedPathLen == null) return false;
    await sendFrame(
      buildUpdateContactPathFrame(
        contact.publicKey,
        contact.path,
        encodedPathLen,
        type: contact.type,
        flags: contact.flags,
        name: contact.name,
        lat: contact.latitude,
        lon: contact.longitude,
        lastModified: contact.lastSeen,
      ),
      waitForGenericAck: true,
    );

    // Update the discovered contact to mark it as active (imported)
    final discoveredIndex = _discoveredContacts.indexWhere(
      (c) => c.publicKeyHex == contact.publicKeyHex,
    );
    if (discoveredIndex >= 0) {
      _discoveredContacts[discoveredIndex] =
          _discoveredContacts[discoveredIndex].copyWith(isActive: true);
    }

    _handleContactAdvert(
      Contact(
        publicKey: contact.publicKey,
        name: contact.name,
        type: contact.type,
        pathLength: contact.pathLength,
        path: contact.path,
        latitude: contact.latitude,
        longitude: contact.longitude,
        lastSeen: DateTime.now(),
        flags: contact.flags,
      ),
    );
    notifyListeners();
    unawaited(_persistDiscoveredContacts());
    return true;
  }

  Future<void> addOrUpdateSharedContact({
    required Uint8List publicKey,
    required int type,
    required String name,
  }) async {
    if (!isConnected) {
      throw Exception("Not connected to a MeshCore device");
    }

    final existingIndex = _contacts.indexWhere(
      (contact) => listEquals(contact.publicKey, publicKey),
    );
    final existing = existingIndex >= 0 ? _contacts[existingIndex] : null;
    final pathLength = existing == null
        ? 0xFF
        : (existing.pathLength < 0
              ? 0xFF
              : (_encodePathLenForCurrentMode(
                      existing.pathLength,
                      existing.path,
                    ) ??
                    0xFF));
    final path = existing?.path ?? Uint8List(0);
    final flags = existing?.flags ?? 0;

    await sendFrame(
      buildUpdateContactPathFrame(
        publicKey,
        path,
        pathLength,
        type: type,
        flags: flags,
        name: name,
        lat: existing?.latitude,
        lon: existing?.longitude,
        lastModified: existing?.lastModified ?? existing?.lastSeen,
      ),
      waitForGenericAck: true,
    );

    _handleContactAdvert(
      Contact(
        publicKey: publicKey,
        name: name,
        type: type,
        pathLength: existing?.pathLength ?? -1,
        path: path,
        latitude: existing?.latitude,
        longitude: existing?.longitude,
        lastSeen: DateTime.now(),
        lastModified: existing?.lastModified,
        flags: flags,
      ),
    );
    notifyListeners();
  }

  Future<void> clearContactPath(Contact contact) async {
    // Serialize path operations to prevent interleaved async calls.
    final prev = _pathOpLock;
    final completer = Completer<void>();
    _pathOpLock = completer.future;
    await prev;
    try {
      if (!isConnected) return;

      await sendFrame(buildResetPathFrame(contact.publicKey));
      if (_activeTransport == MeshCoreTransportType.usb) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final existingIndex = _contacts.indexWhere(
        (c) => c.publicKeyHex == contact.publicKeyHex,
      );
      if (existingIndex >= 0) {
        final existing = _contacts[existingIndex];
        // Preserve pathOverride and pathOverrideBytes — only reset device path
        _contacts[existingIndex] = existing.copyWith(
          pathLength: -1,
          path: Uint8List(0),
        );
        notifyListeners();
        unawaited(_persistContacts());
      }
    } finally {
      completer.complete();
    }
  }

  void updateContactInMemory(
    String publicKeyHex, {
    Uint8List? pathBytes,
    int? pathLength,
  }) {
    final existingIndex = _contacts.indexWhere(
      (c) => c.publicKeyHex == publicKeyHex,
    );
    if (existingIndex >= 0) {
      final existing = _contacts[existingIndex];
      _contacts[existingIndex] = existing.copyWith(
        pathLength: pathLength,
        path: pathBytes,
      );
      notifyListeners();
      unawaited(_persistContacts());
    }
  }

  Future<void> syncTime() async {
    if (!isConnected) return;

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await sendFrame(buildSetDeviceTimeFrame(now));
  }

  Future<void> syncQueuedMessages({bool force = false}) async {
    if (!isConnected) return;
    if (!force && _isSyncingQueuedMessages) return;
    if (_isProcessingDeferredQueuedContactMessages) {
      _pendingQueueSync = true;
      return;
    }
    if (_awaitingSelfInfo || _isLoadingContacts) {
      _pendingQueueSync = true;
      return;
    }
    if (_isSyncingChannels || _channelSyncInFlight) {
      _pendingQueueSync = true;
      return;
    }
    _isSyncingQueuedMessages = true;
    notifyListeners();
    await _requestNextQueuedMessage();
  }

  Future<void> _requestNextQueuedMessage() async {
    if (!isConnected) {
      _isSyncingQueuedMessages = false;
      _isInitialBacklogDrain = false;
      _queuedMessageSyncInFlight = false;
      _queueSyncRetries = 0;
      return;
    }
    if (_queuedMessageSyncInFlight) return;
    _queuedMessageSyncInFlight = true;

    // Cancel any existing timeout
    _queueSyncTimeout?.cancel();

    // Set up timeout for this request
    _queueSyncTimeout = Timer(Duration(milliseconds: _queueSyncTimeoutMs), () {
      _handleQueueSyncTimeout();
    });

    debugPrint(
      '[QueueSync] Requesting next message (retry: $_queueSyncRetries/$_maxQueueSyncRetries)',
    );

    try {
      final frame = _southQueuedFragmentAckTracker.buildSyncNextMessageFrameFor(
        enabled: _southFrameFragmentsEnabled,
      );
      if (_southFrameFragmentsEnabled) {
        _southQueuedFragmentAckTracker.markSyncRequestSent();
      }
      await sendFrame(frame);
    } catch (e) {
      _southQueuedFragmentAckTracker.clearAwaitingSyncResponse();
      debugPrint('[QueueSync] Error sending sync request: $e');
      _queuedMessageSyncInFlight = false;
      _isSyncingQueuedMessages = false;
      _isInitialBacklogDrain = false;
      _queueSyncTimeout?.cancel();
      _queueSyncRetries = 0;
      notifyListeners();
      _continueAfterQueuedMessageSync();
    }
  }

  void _handleQueueSyncTimeout() {
    debugPrint(
      '[QueueSync] Timeout waiting for message (retry: $_queueSyncRetries/$_maxQueueSyncRetries)',
    );

    if (_queueSyncRetries < _maxQueueSyncRetries) {
      // Retry
      _queueSyncRetries++;
      _queuedMessageSyncInFlight = false;
      _southQueuedFragmentAckTracker.clearAwaitingSyncResponse();
      _requestNextQueuedMessage();
    } else {
      // Max retries reached, give up
      debugPrint('[QueueSync] Max retries reached, stopping sync');
      _queuedMessageSyncInFlight = false;
      _isSyncingQueuedMessages = false;
      _isInitialBacklogDrain = false;
      _southQueuedFragmentAckTracker.clearAwaitingSyncResponse();
      _queueSyncRetries = 0;
      notifyListeners();
      _continueAfterQueuedMessageSync();
    }
  }

  Future<void> sendCliCommand(String command) async {
    if (!isConnected) return;
    final selfKey = _selfPublicKey;
    if (selfKey == null) return;
    _lastSentWasCliCommand = true;
    await sendFrame(buildSendCliCommandFrame(selfKey, command));
  }

  Future<void> setNodeName(String name) async {
    if (!isConnected) return;
    await sendFrame(buildSetAdvertNameFrame(name));
  }

  Future<void> setNodeLocation({
    required double lat,
    required double lon,
  }) async {
    if (!isConnected) return;
    await sendFrame(buildSetAdvertLatLonFrame(lat, lon));
  }

  Future<void> setCustomVar(String value) async {
    if (!isConnected) return;
    await sendFrame(buildSetCustomVarFrame(value));
    final sep = value.indexOf(':');
    if (sep > 0) {
      final key = value.substring(0, sep);
      final val = value.substring(sep + 1);
      (_currentCustomVars ??= <String, String>{})[key] = val;
      notifyListeners();
    }
    if (value == 'gps:1') {
      _startGpsLocationPolling();
    } else if (value == 'gps:0') {
      _stopGpsLocationPolling();
    }
  }

  Future<void> sendSelfAdvert({bool flood = true}) async {
    if (!isConnected) return;
    await sendFrame(buildSendSelfAdvertFrame(flood: flood));
    if (!flood) {
      _lastZeroHopAdvertAt = DateTime.now();
      _lastZeroHopAdvertLatitude = _selfLatitude;
      _lastZeroHopAdvertLongitude = _selfLongitude;
    }
  }

  Future<void> rebootDevice() async {
    if (!isConnected) return;
    await sendFrame(buildRebootFrame());
  }

  Future<void> setPrivacyMode(bool enabled) async {
    await sendCliCommand('set privacy ${enabled ? 'on' : 'off'}');
  }

  Future<void> setTelemetryModeBase(
    int base,
    int location,
    int env,
    int advert,
    int multiAcks,
  ) async {
    if (!isConnected) return;
    _telemetryModeBase = base.clamp(teleModeDeny, teleModeAllowAll).toInt();
    _telemetryModeLoc = location.clamp(teleModeDeny, teleModeAllowAll).toInt();
    _telemetryModeEnv = env.clamp(teleModeDeny, teleModeAllowAll).toInt();
    _advertLocPolicy = advert.clamp(0, 1).toInt();
    _multiAcks = multiAcks.clamp(0, 2).toInt();
    await sendFrame(
      buildSetOtherParamsFrame(
        (_telemetryModeEnv << 4) |
            (_telemetryModeLoc << 2) |
            _telemetryModeBase,
        _advertLocPolicy,
        _multiAcks,
      ),
    );
    notifyListeners();
  }

  Future<void> getChannels({int? maxChannels, bool force = false}) async {
    if (!isConnected) return;
    if (_isSyncingChannels) {
      if (force) {
        debugPrint(
          '[ChannelSync] Sync already active, scheduling forced restart',
        );
        _pendingChannelSyncRestart = true;
        _pendingChannelSyncRestartMaxChannels =
            maxChannels ?? _pendingChannelSyncRestartMaxChannels;
        if (!_channelSyncInFlight) {
          unawaited(_restartPendingChannelSync());
        }
      } else {
        debugPrint('[ChannelSync] Already syncing channels, ignoring request');
      }
      return;
    }

    // Skip fetching if already loaded and not forced
    if (_hasLoadedChannels && !force) {
      debugPrint(
        '[ChannelSync] Channels already loaded, skipping fetch (use force=true to reload)',
      );
      return;
    }

    _isLoadingChannels = true;
    _isSyncingChannels = true;
    _hasLoadedChannels = false;
    _previousChannelsCache = List<Channel>.from(_channels);
    _channels.clear();
    _nextChannelIndexToRequest = 0;
    _totalChannelsToRequest = maxChannels ?? _maxChannels;
    _channelSyncRetries = 0;
    notifyListeners();

    debugPrint(
      '[ChannelSync] Starting sync for $_totalChannelsToRequest channels',
    );

    // Start sequential sync
    await _requestNextChannel();
  }

  Future<void> _requestNextChannel() async {
    if (!isConnected) {
      _cleanupChannelSync(completed: false);
      return;
    }

    if (_channelSyncInFlight) return;

    if (_pendingChannelSyncRestart) {
      await _restartPendingChannelSync();
      return;
    }

    // Check if we've requested all channels
    if (_nextChannelIndexToRequest >= _totalChannelsToRequest) {
      await _completeChannelSync();
      return;
    }

    _channelSyncInFlight = true;
    final channelIndex = _nextChannelIndexToRequest;

    // Cancel any existing timeout
    _channelSyncTimeout?.cancel();

    // Set up timeout for this channel request
    _channelSyncTimeout = Timer(
      Duration(milliseconds: _channelSyncTimeoutMs),
      () => _handleChannelSyncTimeout(channelIndex),
    );

    debugPrint(
      '[ChannelSync] Requesting channel $channelIndex/$_totalChannelsToRequest (retry: $_channelSyncRetries/$_maxChannelSyncRetries)',
    );

    try {
      await sendFrame(buildGetChannelFrame(channelIndex));
    } catch (e) {
      debugPrint('[ChannelSync] Error sending channel request: $e');
      _channelSyncInFlight = false;
      _cleanupChannelSync(completed: false);
    }
  }

  void _handleChannelSyncTimeout(int channelIndex) {
    debugPrint(
      '[ChannelSync] Timeout waiting for channel $channelIndex (retry: $_channelSyncRetries/$_maxChannelSyncRetries)',
    );

    if (_channelSyncRetries < _maxChannelSyncRetries) {
      // Retry the same channel
      _channelSyncRetries++;
      _channelSyncInFlight = false;
      unawaited(_requestNextChannel());
    } else {
      // Max retries reached for this channel, restore from cache and move to next
      debugPrint(
        '[ChannelSync] Max retries reached for channel $channelIndex, attempting cache restore',
      );

      // Try to restore this channel from cache
      try {
        final cachedChannel = _previousChannelsCache.firstWhere(
          (c) => c.index == channelIndex,
        );
        if (!cachedChannel.isEmpty) {
          _channels.add(cachedChannel);
          debugPrint(
            '[ChannelSync] Restored channel $channelIndex (${cachedChannel.name}) from cache',
          );
        }
      } catch (e) {
        // No cached channel found, that's okay
      }

      // Move to next channel
      _nextChannelIndexToRequest++;
      _channelSyncRetries = 0;
      _channelSyncInFlight = false;
      notifyListeners();
      unawaited(_requestNextChannel());
    }
  }

  Future<void> _completeChannelSync() async {
    _channelSyncTimeout?.cancel();

    if (_pendingChannelSyncRestart) {
      await _restartPendingChannelSync();
      return;
    }

    debugPrint(
      '[ChannelSync] Sync complete: received ${_channels.length}/$_totalChannelsToRequest channels',
    );

    // Cache channels for offline use
    _cachedChannels = List<Channel>.from(_channels);
    await _channelStore.saveChannels(_channels);
    _recalculateCachedChannelsUnreadTotal();

    _cleanupChannelSync(completed: true);

    // Apply ordering and notify UI
    _applyChannelOrder();
    notifyListeners();
  }

  void _cleanupChannelSync({required bool completed}) {
    _isSyncingChannels = false;
    _channelSyncInFlight = false;
    _isLoadingChannels = false;
    _channelSyncTimeout?.cancel();
    _channelSyncRetries = 0;
    _nextChannelIndexToRequest = 0;
    _totalChannelsToRequest = 0;

    if (completed) {
      _hasLoadedChannels = true;
      _previousChannelsCache.clear();
    }

    if (!completed && _channels.isEmpty && _previousChannelsCache.isNotEmpty) {
      // A failed initial sync should not leave the UI empty/spinning forever.
      // Restore the pre-sync list so cached channels remain usable.
      _channels.addAll(_previousChannelsCache);
      _applyChannelOrder();
      _recalculateCachedChannelsUnreadTotal();
    }

    if (isConnected) {
      _startPostChannelInitialQueuedMessageSync();
    }
    unawaited(_flushDeferredChannelMessageSends());

    // Keep cache on failure/disconnection for future attempts
    if (!completed) {
      notifyListeners();
    }
  }

  Future<void> _restartPendingChannelSync() async {
    if (!_pendingChannelSyncRestart || _channelSyncInFlight) return;
    final maxChannels = _pendingChannelSyncRestartMaxChannels;
    _pendingChannelSyncRestart = false;
    _pendingChannelSyncRestartMaxChannels = null;

    debugPrint('[ChannelSync] Restarting forced channel sync');

    _channelSyncTimeout?.cancel();
    _isSyncingChannels = false;
    _channelSyncInFlight = false;
    _isLoadingChannels = false;
    _channelSyncRetries = 0;
    _nextChannelIndexToRequest = 0;
    _totalChannelsToRequest = 0;
    if (_previousChannelsCache.isNotEmpty) {
      _channels
        ..clear()
        ..addAll(_previousChannelsCache);
      _applyChannelOrder();
      _recalculateCachedChannelsUnreadTotal();
    }

    await getChannels(maxChannels: maxChannels, force: true);
  }

  void _startPostChannelInitialQueuedMessageSync() {
    if (_pendingInitialQueuedMessageSync || _pendingQueueSync) {
      _deferQueuedContactMessagesUntilContacts = _pendingInitialContactsSync;
      // This drain replays the backlog accumulated before we connected;
      // order queued channel messages by their send time until it finishes.
      _isInitialBacklogDrain = _pendingInitialQueuedMessageSync;
      _pendingInitialQueuedMessageSync = false;
      _pendingQueueSync = false;
      unawaited(syncQueuedMessages(force: true));
    }
  }

  Future<void> setChannel(int index, String name, Uint8List psk) async {
    if (!isConnected) return;

    await sendFrame(buildSetChannelFrame(index, name, psk));
    // Refresh channels after setting
    await getChannels(force: true);
  }

  Future<void> deleteChannel(int index) async {
    if (!isConnected) return;

    // Delete by setting empty name and zero PSK
    await sendFrame(buildSetChannelFrame(index, '', Uint8List(16)));
    // Explicit deletion clears all persisted data for this channel name.
    await _channelMessageStore.clearChannelMessages(index);
    await _channelSettingsStore.clearChannelSettings(index);
    await _channelRegionStore.clearRegion(index);
    // Clear in-memory messages for this channel
    _channelMessages.remove(index);
    // Refresh channels after deleting
    await getChannels(force: true);
  }

  void _handleFrame(List<int> data) {
    if (data.isEmpty) return;
    _lastRxBeforeFrame = _lastRxTime;
    _lastRxTime = DateTime.now();
    // Any inbound frame proves the notify stream is alive.
    if (_rxWatchdogReconnects != 0) {
      _rxWatchdogReconnects = 0;
    }

    final incomingFrame = Uint8List.fromList(data);
    if (!_southFrameFragmentsEnabled ||
        incomingFrame[0] != SouthFrameFragmentReassembler.fragmentFrameType) {
      if (_southFrameFragmentsEnabled) {
        _southQueuedFragmentAckTracker.takeSyncResponseContext(
          incomingFrame,
          isAcceptedQueuedFragment: false,
        );
      }
      _handleCompanionFrame(incomingFrame);
      return;
    }

    _bleDebugLogService?.logFrame(
      incomingFrame,
      outgoing: false,
      note: 'raw FR01 fragment len=${incomingFrame.length}',
    );
    final result = _southFrameFragmentReassembler.ingestDetailed(incomingFrame);
    final acceptedFragment = result.acceptedFragment;
    final isResponseToSyncNextMessage = _southQueuedFragmentAckTracker
        .takeSyncResponseContext(
          incomingFrame,
          isAcceptedQueuedFragment: acceptedFragment?.isQueued == true,
        );
    if (isResponseToSyncNextMessage && acceptedFragment != null) {
      _southQueuedFragmentAckTracker.recordQueuedFragment(
        acceptedFragment,
        enabled: true,
      );
      if (result.frames.isEmpty) _handleQueuedMessageReceived();
    }
    for (final frame in result.frames) {
      _handleCompanionFrame(frame);
    }
  }

  void _handleCompanionFrame(Uint8List frame) {
    if (frame.isEmpty) return;
    _receivedFramesController.add(frame);
    _bleDebugLogService?.logFrame(frame, outgoing: false);

    final code = frame[0];
    // debugPrint('RX frame: code=$code len=${frame.length}');

    switch (code) {
      case respCodeOk:
        _handleOk();
        break;
      case respCodeDeviceInfo:
        _handleDeviceInfo(frame);
        break;
      case respCodeSelfInfo:
        debugPrint('Got SELF_INFO');
        _handleSelfInfo(frame);
        break;
      case respCodeContactsStart:
        debugPrint('Got CONTACTS_START');
        _armContactSyncTimeout();
        if (!_preserveContactsOnRefresh &&
            _contactMessageSummarySnapshot.isEmpty) {
          _captureContactMessageSummarySnapshot();
        }
        if (!_preserveContactsOnRefresh) {
          _contacts.clear();
        }
        _isLoadingContacts = true;
        _contactSyncIndexes = {
          for (var i = 0; i < _contacts.length; i++)
            _contacts[i].publicKeyHex: i,
        };
        _discoveredContactSyncIndexes = {
          for (var i = 0; i < _discoveredContacts.length; i++)
            _discoveredContacts[i].publicKeyHex: i,
        };
        _contactSyncReceived = 0;
        // Firmware v3+ includes total contacts after CONTACTS_START.
        // Incremental sync reports total contacts, not filtered result count.
        if (frame.length >= 5 && !_contactSyncUsesSinceFilter) {
          final reader = BufferReader(frame);
          reader.skipBytes(1);
          _contactSyncTotal = reader.readUInt32LE();
        } else if (!_contactSyncUsesSinceFilter) {
          // Older firmwares may omit the count; use the nRF node capacity as
          // a conservative progress fallback instead of hiding the progress.
          _contactSyncTotal = _defaultMaxContacts;
        } else {
          _contactSyncTotal = null;
        }
        notifyListeners();
        break;
      case pushCodeAdvert:
        // Known contact was seen again - just a pub key, no action needed
        break;
      case pushCodeNewAdvert:
        debugPrint('Got New CONTACT');
        // It's the same format as respCodeContact, so we can reuse the handler
        _handleContact(frame, isContact: false);
        break;
      case respCodeContact:
        if (_isLoadingContacts) {
          _armContactSyncTimeout();
        }
        _handleContact(frame);
        break;
      case respCodeEndOfContacts:
        debugPrint('Got END_OF_CONTACTS');
        _contactSyncTimeout?.cancel();
        _contactSyncTimeout = null;
        _isLoadingContacts = false;
        _hasLoadedContacts = true;
        _preserveContactsOnRefresh = false;
        _contactSyncUsesSinceFilter = false;
        _contactSyncIndexes = null;
        _discoveredContactSyncIndexes = null;
        _contactMessageSummarySnapshot.clear();
        _unreadStore.saveContactUnreadCount(
          Map<String, int>.from(_contactUnreadCount),
        );
        unawaited(updateKnownDiscovered());
        notifyListeners();
        unawaited(_refreshContactMessageSummaries());
        unawaited(_persistContacts());
        unawaited(_flushDeferredChannelMessageSends());
        if (PlatformInfo.isWeb &&
            _activeTransport == MeshCoreTransportType.bluetooth &&
            _isSyncingChannels &&
            !_channelSyncInFlight) {
          unawaited(_requestNextChannel());
        }
        if (_deferQueuedContactMessagesUntilContacts) {
          unawaited(_processDeferredQueuedContactMessages());
        } else if (_pendingQueueSync) {
          _pendingQueueSync = false;
          unawaited(syncQueuedMessages(force: true));
        }
        break;
      case respCodeContactMsgRecv:
      case respCodeContactMsgRecvV3:
        if (_shouldDeferQueuedContactMessage(frame)) {
          _deferredQueuedContactMessageFrames.add(Uint8List.fromList(frame));
          _handleQueuedMessageReceived();
        } else {
          unawaited(_handleIncomingMessage(frame));
        }
        break;
      case respCodeChannelMsgRecv:
      case respCodeChannelMsgRecvV3:
        _handleIncomingChannelMessage(frame);
        break;
      case respCodeChannelDataRecv:
        _handleIncomingChannelData(frame);
        break;
      case respCodeDefaultFloodScope:
        // Feature-specific callers listen to receivedFrames for this response.
        break;
      case respCodeSent:
        _handleMessageSent(frame);
        break;
      case respCodeNoMoreMessages:
        _handleNoMoreMessages();
        break;
      case pushCodeMsgWaiting:
        unawaited(syncQueuedMessages(force: true));
        break;
      case pushCodeSendConfirmed:
        _handleSendConfirmed(frame);
        break;
      case pushCodePathUpdated:
        _handlePathUpdated(frame);
        break;
      case pushCodeRawData:
      case pushCodeControlData:
        // Optional feature-specific services (for example wardrive) listen to
        // receivedFrames directly; the main connector only needs to keep these
        // push frames from falling through as unknown protocol traffic.
        break;
      case pushCodeLoginSuccess:
        _handleLoginSuccess(frame);
        break;
      case pushCodeLoginFail:
      case pushCodeStatusResponse:
        break;
      case pushCodeLogRxData:
        _lastRadioRxTime = DateTime.now();
        _handleRxData(frame);
        _handleLogRxData(frame);
        break;
      case respCodeChannelInfo:
        unawaited(_handleChannelInfo(frame));
        break;
      case respCodeSignStart:
      case respCodeSignature:
        // MCMP signing sessions (signWithNode) listen to receivedFrames
        // directly; keep these from falling through as unknown traffic.
        break;
      case respCodeAutoAddConfig:
        _handleAutoAddConfig(frame);
        _checkManualAddContacts();
        break;
      case respCodeBattAndStorage:
        _handleBatteryAndStorage(frame);
        break;
      case respCodeStats:
        _handleStatsFrame(frame);
        break;
      case respCodeCustomVars:
        _handleCustomVars(frame);
        break;
      // RESP_CODE_ERR is a defined firmware response (code 1), not an unknown frame.
      case respCodeErr:
        _handleErrorFrame(frame);
        break;
      default:
        debugPrint('Unknown frame code: $code');
    }
  }

  void _handleErrorFrame(Uint8List frame) {
    final errCode = frame.length > 1 ? frame[1] : -1;
    _appDebugLogService?.warn(
      'Firmware responded with error code: $errCode',
      tag: 'Protocol',
    );

    if (_pendingGenericAckQueue.isEmpty) {
      return;
    }

    final failedAck = _pendingGenericAckQueue.removeAt(0);
    failedAck.completer?.completeError(
      Exception('Firmware rejected command with error code $errCode'),
    );
    if ((failedAck.commandCode != cmdSendChannelTxtMsg &&
            failedAck.commandCode != cmdSendChannelData) ||
        failedAck.channelSendQueueId == null) {
      return;
    }
    _pendingChannelSentQueue.remove(failedAck.channelSendQueueId);
    _markPendingChannelMessageFailedById(failedAck.channelSendQueueId!);
  }

  void _handlePathUpdated(Uint8List frame) {
    // Frame format: [0]=code, [1-32]=pub_key
    if (frame.length >= 33 && _pathHistoryService != null) {
      final pubKey = Uint8List.fromList(frame.sublist(1, 33));
      final contact = _contacts.cast<Contact?>().firstWhere(
        (c) => c != null && listEquals(c.publicKey, pubKey),
        orElse: () => null,
      );

      if (contact != null) {
        _pathHistoryService!.handlePathUpdated(contact);
        // Refresh just this specific contact instead of all contacts.
        // This avoids race conditions with _preserveContactsOnRefresh flag
        // that can occur when using refreshContactsSinceLastmod().
        getContactByKey(pubKey);
      }
    }
  }

  void _handleSelfInfo(Uint8List frame) {
    // SELF_INFO format:
    // [0] = RESP_CODE_SELF_INFO
    // [1] = ADV_TYPE
    // [2] = tx_power_dbm
    // [3] = MAX_LORA_TX_POWER
    // [4-35] = pub_key (32 bytes)
    // [36-39] = lat (int32 LE)
    // [40-43] = lon (int32 LE)
    // [44] = multi_acks
    // [45] = advert_loc_policy
    // [46] = telemetry modes
    // [47] = manual_add_contacts
    // [48-51] = freq (uint32 LE, in Hz)
    // [52-55] = bw (uint32 LE, in Hz)
    // [56] = sf
    // [57] = cr
    // [58+] = node_name
    final wasAwaitingSelfInfo = _awaitingSelfInfo;
    final previousSelfPublicKeyHex = selfPublicKeyHex;
    final reader = BufferReader(frame);
    var parsedSelfInfo = false;
    try {
      reader.skipBytes(2);
      _currentTxPower = reader.readInt8();
      _maxTxPower = reader.readInt8();
      _selfPublicKey = reader.readBytes(pubKeySize);
      _selfLatitude = reader.readInt32LE() / 1000000.0;
      _selfLongitude = reader.readInt32LE() / 1000000.0;
      _multiAcks = reader.readByte();
      _advertLocPolicy = reader.readByte();
      final telemetryFlag = reader.readByte();
      _telemetryModeBase = telemetryFlag & 0x03;
      _telemetryModeLoc = telemetryFlag >> 2 & 0x03;
      _telemetryModeEnv = telemetryFlag >> 4 & 0x03;

      _manualAddContacts = reader.readByte() & 0x01 == 0x00;

      _currentFreqHz = reader.readUInt32LE();
      _currentBwHz = reader.readUInt32LE();
      _currentSf = reader.readByte();
      _currentCr = reader.readByte();

      _selfName = reader.readCString();
      parsedSelfInfo = true;
    } catch (e) {
      _appDebugLogService?.error(
        'Error parsing SELF_INFO frame: $e',
        tag: 'Connector',
      );
    }
    _completeSelfInfoRefreshWaiters();

    const locationChangeEpsilon = 2.25e-4; // ~25 meters in degrees.
    final lastAdvertLatitude = _lastZeroHopAdvertLatitude;
    final lastAdvertLongitude = _lastZeroHopAdvertLongitude;
    final currentLatitude = _selfLatitude;
    final currentLongitude = _selfLongitude;
    final latChanged =
        lastAdvertLatitude != null &&
        currentLatitude != null &&
        (currentLatitude - lastAdvertLatitude).abs() >= locationChangeEpsilon;
    final lonChanged =
        lastAdvertLongitude != null &&
        currentLongitude != null &&
        (currentLongitude - lastAdvertLongitude).abs() >= locationChangeEpsilon;
    final gpsSampleChanged =
        hasValidLocation(currentLatitude, currentLongitude) &&
        (!hasValidLocation(lastAdvertLatitude, lastAdvertLongitude) ||
            latChanged ||
            lonChanged);
    final effectiveGpsIntervalSeconds =
        _appSettingsService?.resolvedGpsIntervalSeconds(_currentCustomVars) ??
        0;
    final timeSinceLastZeroHopAdvert = DateTime.now().difference(
      _lastZeroHopAdvertAt,
    );
    final shouldAutoSendZeroHopAdvert =
        (gpsSampleChanged || (_clientRepeat ?? false)) &&
        _advertLocPolicy == 1 &&
        (_appSettingsService?.settings.autoSendZeroHopAdvertOnGpsUpdate ??
            false) &&
        effectiveGpsIntervalSeconds > 0 &&
        timeSinceLastZeroHopAdvert.inSeconds >= effectiveGpsIntervalSeconds;
    if (shouldAutoSendZeroHopAdvert) {
      unawaited(sendSelfAdvert(flood: false));
    }
    final selfName = _selfName?.trim();
    if (_activeTransport == MeshCoreTransportType.usb &&
        selfName != null &&
        selfName.isNotEmpty) {
      _usbManager.updateConnectedLabel(selfName);
    }

    // GPS poll responses arrive as RESP_CODE_SELF_INFO but are not the real
    // handshake — only update location and notify, skip store reloads and
    // contact sync which would clear and re-fetch contacts every minute.
    if (!wasAwaitingSelfInfo) {
      notifyListeners();
      return;
    }

    if (previousSelfPublicKeyHex != selfPublicKeyHex) {
      _clearSharedMessageHistoryState();
    }

    //set all the stores' public key so they can load the correct data
    _channelMessageStore.setPublicKeyHex = selfPublicKeyHex;
    _messageStore.setPublicKeyHex = selfPublicKeyHex;
    _channelOrderStore.setPublicKeyHex = selfPublicKeyHex;
    _channelSettingsStore.setPublicKeyHex = selfPublicKeyHex;
    _channelRegionStore.setPublicKeyHex = selfPublicKeyHex;
    _contactSettingsStore.setPublicKeyHex = selfPublicKeyHex;
    _contactStore.setPublicKeyHex = selfPublicKeyHex;
    _channelStore.setPublicKeyHex = selfPublicKeyHex;
    _nodeIdentityStore.setPublicKeyHex = selfPublicKeyHex;
    _unreadStore.setPublicKeyHex = selfPublicKeyHex;
    _settingsSectionsService?.setActiveDeviceKey(selfPublicKeyHex);
    _channelMessageStore.beginLegacyIndexMigration();
    _channelSettingsStore.beginLegacyIndexMigration();
    _channelRegionStore.beginLegacyIndexMigration();
    _replaceChannelStorageBindings(const []);
    unawaited(_nodeIdentityStore.saveName(_selfName));

    // Now that we have self info, we can load all the persisted data for this node.
    // Pass the current public key into async loads so a quick reconnect to a
    // different node cannot apply stale channel state to the new node.
    final storagePublicKeyHex = selfPublicKeyHex;
    _loadChannelOrder(publicKeyHex: storagePublicKeyHex);
    final contactCacheLoadGeneration = ++_contactCacheLoadGeneration;
    _contactCacheLoadFuture = _loadContactCacheForNode(
      storagePublicKeyHex,
      contactCacheLoadGeneration,
    );
    unawaited(_prepareCachedChannelStorage(storagePublicKeyHex));
    loadUnreadState();
    _loadDiscoveredContactCache();

    _awaitingSelfInfo = false;
    _hasCompletedSelfInfoHandshake = parsedSelfInfo;
    if (parsedSelfInfo) {
      unawaited(_backgroundService?.setConnectionLost(false));
    }
    _selfInfoRetryTimer?.cancel();
    _selfInfoRetryTimer = null;
    notifyListeners();

    // Start the serialized initial sync pipeline after SELF_INFO.
    _maybeStartInitialChannelSync();
  }

  void _completeSelfInfoRefreshWaiters() {
    final waiters = List<Completer<void>>.from(_selfInfoRefreshWaiters);
    _selfInfoRefreshWaiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }

  /// Reads a null-padded UTF-8 string from [frame] at [offset] up to
  /// [maxLength] bytes (stops at the first NUL), or null when out of range.
  String? _readNullPaddedString(Uint8List frame, int offset, int maxLength) {
    if (frame.length <= offset) return null;
    final end = (offset + maxLength) > frame.length
        ? frame.length
        : offset + maxLength;
    var terminator = offset;
    while (terminator < end && frame[terminator] != 0) {
      terminator++;
    }
    if (terminator == offset) return null;
    try {
      return utf8.decode(frame.sublist(offset, terminator));
    } catch (_) {
      return null;
    }
  }

  void _handleDeviceInfo(Uint8List frame) {
    if (frame.length < 4) return;
    if (_shouldGateInitialChannelSync) {
      _hasReceivedDeviceInfo = true;
    }
    _firmwareVerCode = frame[1];

    // RESP_CODE_DEVICE_INFO layout: [0]=code [1]=ver_code [2]=maxContacts/2
    // [3]=maxChannels [4..7]=ble_pin [8..19]=build date (12B, null-padded)
    // [20..59]=manufacturer (40B) [60..79]=firmware version (20B).
    _firmwareBuildDate = _readNullPaddedString(frame, 8, 12);
    _boardName = _readNullPaddedString(frame, 20, 40);
    _firmwareVersion = _readNullPaddedString(frame, 60, 20);

    // Parse client_repeat from firmware v9+ (byte 80)
    if (frame.length >= 81) {
      _clientRepeat = frame[80] != 0;
    }
    // Path hash mode v10+ (byte 81): width = mode + 1 byte(s) per hop
    final previousPathHashByteWidth = _pathHashByteWidth;
    if (frame.length >= 82) {
      final mode = (frame[81] & 0xFF).clamp(0, 3);
      _pathHashByteWidth = mode + 1;
    } else {
      _pathHashByteWidth = 1;
    }
    if (_pathHashByteWidth != previousPathHashByteWidth) {
      _directRepeaters.clear();
      _activeRepeaters.clear();
    }

    // Firmware reports MAX_CONTACTS / 2 for v3+ device info.
    final reportedContacts = frame[2];
    final reportedChannels = frame[3];
    final nextMaxContacts = reportedContacts > 0
        ? reportedContacts * 2
        : _maxContacts;
    final nextMaxChannels = reportedChannels > 0
        ? reportedChannels
        : _maxChannels;
    final previousMaxChannels = _maxChannels;
    if (nextMaxContacts != _maxContacts || nextMaxChannels != _maxChannels) {
      _maxContacts = nextMaxContacts;
      _maxChannels = nextMaxChannels;
      if (nextMaxChannels > previousMaxChannels) {
        final storagePublicKeyHex = selfPublicKeyHex;
        unawaited(
          loadChannelSettings(
            maxChannels: nextMaxChannels,
            publicKeyHex: storagePublicKeyHex,
          ),
        );
        unawaited(
          loadAllChannelMessages(
            maxChannels: nextMaxChannels,
            publicKeyHex: storagePublicKeyHex,
          ),
        );
        if (isConnected &&
            _selfPublicKey != null &&
            !_pendingInitialChannelSync) {
          unawaited(getChannels(maxChannels: nextMaxChannels));
        }
      }
    }
    notifyListeners();
    if (_shouldGateInitialChannelSync) {
      _maybeStartInitialChannelSync();
    }
  }

  void _maybeStartInitialChannelSync() {
    if (!_pendingInitialChannelSync || !isConnected) {
      return;
    }
    if (_selfPublicKey == null ||
        !_hasLoadedCachedChannelStorage ||
        (_shouldGateInitialChannelSync && !_hasReceivedDeviceInfo)) {
      return;
    }

    _pendingInitialChannelSync = false;
    unawaited(getChannels(maxChannels: _maxChannels, force: true));
  }

  void _handleNoMoreMessages() {
    debugPrint('[QueueSync] No more messages, sync complete');
    _queueSyncTimeout?.cancel();
    _isSyncingQueuedMessages = false;
    _isInitialBacklogDrain = false;
    _queuedMessageSyncInFlight = false;
    _queueSyncRetries = 0; // Reset retry counter on successful completion
    notifyListeners();
    _continueAfterQueuedMessageSync();
  }

  /// receivedAt to assign to a queued channel message. During the initial
  /// backlog drain the node replays everything "now", so we order queued
  /// messages by their original send time instead; live deliveries (and all
  /// incremental syncs after the drain) keep the real arrival time.
  DateTime _channelMessageReceivedAt(DateTime sendTimestamp, DateTime now) {
    return _isInitialBacklogDrain ? sendTimestamp : now;
  }

  bool _shouldDeferQueuedContactMessage(Uint8List frame) {
    if (!_deferQueuedContactMessagesUntilContacts ||
        !_isSyncingQueuedMessages) {
      return false;
    }
    if (frame.isEmpty) return false;
    return frame[0] == respCodeContactMsgRecv ||
        frame[0] == respCodeContactMsgRecvV3;
  }

  void _continueAfterQueuedMessageSync() {
    if (!_deferQueuedContactMessagesUntilContacts) return;
    if (_pendingInitialContactsSync && isConnected) {
      _pendingInitialContactsSync = false;
      unawaited(getContacts());
      return;
    }
    unawaited(_processDeferredQueuedContactMessages());
  }

  Future<void> _processDeferredQueuedContactMessages() async {
    if (!_deferQueuedContactMessagesUntilContacts ||
        _isProcessingDeferredQueuedContactMessages) {
      return;
    }
    if (_deferredQueuedContactMessageFrames.isEmpty) {
      _deferQueuedContactMessagesUntilContacts = false;
      notifyListeners();
      if (_pendingQueueSync && isConnected) {
        _pendingQueueSync = false;
        unawaited(syncQueuedMessages(force: true));
      }
      return;
    }

    _isProcessingDeferredQueuedContactMessages = true;
    notifyListeners();
    try {
      // Replay direct/room queued messages only after contacts are loaded, so
      // sender prefixes can be resolved against the current contact list.
      while (_deferredQueuedContactMessageFrames.isNotEmpty) {
        final frame = _deferredQueuedContactMessageFrames.removeAt(0);
        await _handleIncomingMessage(frame);
      }
    } finally {
      _deferQueuedContactMessagesUntilContacts = false;
      _isProcessingDeferredQueuedContactMessages = false;
      notifyListeners();
    }

    if (_pendingQueueSync && isConnected) {
      _pendingQueueSync = false;
      unawaited(syncQueuedMessages(force: true));
    }
  }

  void _handleQueuedMessageReceived() {
    if (!_isSyncingQueuedMessages) return;
    debugPrint('[QueueSync] Message received, requesting next');
    _queueSyncTimeout?.cancel(); // Cancel timeout - message arrived
    _queuedMessageSyncInFlight = false;
    _queueSyncRetries = 0; // Reset retry counter on successful message
    notifyListeners();
    unawaited(_requestNextQueuedMessage());
  }

  void _handleStatsFrame(Uint8List frame) {
    final stats = CompanionRadioStats.tryParse(frame);
    if (stats == null) return;
    final total = stats.txAirSecs + stats.rxAirSecs;
    if (total > _prevTotalAirSecs) {
      (_airtimeBumpStopwatch ??= Stopwatch()).reset();
      _airtimeBumpStopwatch!.start();
    }
    _prevTotalAirSecs = total;
    _latestRadioStats = stats;
    radioStatsNotifier.value = stats;
  }

  void _handleBatteryAndStorage(Uint8List frame) {
    // Frame format from C++:
    // [0] = RESP_CODE_BATT_AND_STORAGE
    // [1-2] = battery_mv (uint16 LE)
    // [3-6] = storage_used_kb (uint32 LE)
    // [7-10] = storage_total_kb (uint32 LE)
    try {
      final reader = BufferReader(frame);
      reader.skipBytes(1);
      _batteryMillivolts = reader.readUInt16LE();
      _storageUsedKb = reader.readUInt32LE();
      _storageTotalKb = reader.readUInt32LE();
      final volts = (_batteryMillivolts! / 1000.0).toStringAsFixed(2);
      _appDebugLogService?.info(
        'Pulled battery: $volts V ($_batteryMillivolts mV)',
        tag: 'Battery',
      );
      notifyListeners();
    } catch (e) {
      _appDebugLogService?.error(
        'Error parsing battery and storage frame: $e',
        tag: 'Connector',
      );
    }
  }

  void _checkManualAddContacts() async {
    // If manual add contacts is enabled, set auto add config and other params.
    // and disable it after
    if (_manualAddContacts) {
      await sendFrame(
        buildSetAutoAddConfigFrame(
          autoAddChat: true,
          autoAddRepeater: true,
          autoAddRoomServer: true,
          autoAddSensor: true,
          overwriteOldest: _overwriteOldest,
        ),
      );
      await sendFrame(
        buildSetOtherParamsFrame(
          (_telemetryModeEnv << 4) |
              (_telemetryModeLoc << 2) |
              (_telemetryModeBase),
          _advertLocPolicy,
          _multiAcks,
        ),
      );
      _manualAddContacts = false;
    }
  }

  /// Estimate single-packet airtime in ms from radio settings, or a fallback.
  int _estimateAirtimeMs(int messageBytes) {
    if (_currentFreqHz != null &&
        _currentBwHz != null &&
        _currentSf != null &&
        _currentCr != null) {
      final cr = _currentCr! <= 4 ? _currentCr! : _currentCr! - 4;
      return calculateLoRaAirtime(
        payloadBytes: messageBytes,
        spreadingFactor: _currentSf!,
        bandwidthHz: _currentBwHz!,
        codingRate: cr,
        lowDataRateOptimize: _currentSf! >= 11,
      );
    }
    return 50; // fallback: ~SF7/BW125 for 100 bytes
  }

  /// Physics-based worst-case timeout (ceiling).
  int _physicsMaxTimeout(int pathLength, int airtime) {
    if (pathLength < 0) {
      // Match firmware: SEND_TIMEOUT_BASE_MILLIS + (FLOOD_SEND_TIMEOUT_FACTOR * airtime)
      return 500 + (16 * airtime);
    } else {
      return 500 + ((airtime * 6 + 250) * (pathLength + 1));
    }
  }

  int _physicsMinTimeout(int pathLength, int airtime) {
    if (pathLength < 0) {
      // Same as max for flood — firmware uses a single formula
      return 500 + (16 * airtime);
    } else {
      // Include firmware base (500ms) and per-hop processing (6*airtime+250)
      // so ML cannot clamp below a physically plausible round-trip.
      return 500 + ((airtime * 6 + 250) * pathLength);
    }
  }

  /// Hard ceiling on any ML-derived or physics-fallback timeout (ms).
  /// Prevents the flood formula (500 + 16·airtime at SF12 ≈ 150s) and an
  /// unstable OLS model from producing multi-minute waits.
  static const int _hardMaxTimeoutMs = 45000;

  /// Calculate timeout for a message based on radio settings and path length.
  /// Returns timeout in milliseconds, considering number of hops.
  ///
  /// [deviceTimeoutMs] is the firmware's own est_timeout from RESP_CODE_SENT.
  /// When ML is absent it is used as the fallback (clamped to physicsMin).
  /// When ML is present it is used as an additional ceiling alongside physicsMax.
  int calculateTimeout({
    required int pathLength,
    int messageBytes = 100,
    String? contactKey,
    int? deviceTimeoutMs,
  }) {
    final airtime = _estimateAirtimeMs(messageBytes);
    final physicsMin = _physicsMinTimeout(pathLength, airtime);
    final physicsMax = _physicsMaxTimeout(pathLength, airtime);

    // Try ML-based prediction
    final secSinceRx = DateTime.now().difference(_lastRxTime).inSeconds;
    final mlTimeout = _timeoutPredictionService?.predictTimeout(
      contactKey: contactKey,
      pathLength: pathLength,
      messageBytes: messageBytes,
      secondsSinceLastRx: secSinceRx,
    );
    if (mlTimeout != null) {
      // Use device est_timeout as a baseline floor when available —
      // the firmware computed it from real airtime. Let the learned ML
      // estimate widen above it up to the hard cap, but never below it.
      final floor = deviceTimeoutMs != null && deviceTimeoutMs > physicsMin
          ? deviceTimeoutMs.clamp(physicsMin, _hardMaxTimeoutMs)
          : physicsMin.clamp(0, _hardMaxTimeoutMs);
      if (pathLength < 0) {
        // Flood: trust ML, only enforce firmware estimate as floor
        if (mlTimeout < floor) {
          return floor.clamp(0, _hardMaxTimeoutMs);
        }
      }
      return mlTimeout.clamp(floor, _hardMaxTimeoutMs);
    }

    // No ML data — prefer device est_timeout (it used real airtime), then physics.
    // Cap the floor to the hard maximum so slow-flood physicsMin cannot exceed
    // the upper bound and make clamp() throw.
    if (deviceTimeoutMs != null && deviceTimeoutMs > 0) {
      final floor = physicsMin.clamp(0, _hardMaxTimeoutMs);
      return deviceTimeoutMs.clamp(floor, _hardMaxTimeoutMs);
    }
    return physicsMax.clamp(0, _hardMaxTimeoutMs);
  }

  void _registerContactInActiveSync(String publicKeyHex, int index) {
    if (!_isLoadingContacts || index < 0 || index >= _contacts.length) return;
    _contactSyncIndexes?[publicKeyHex] = index;
  }

  void _handleContact(Uint8List frame, {bool isContact = true}) {
    final contactTmp = Contact.fromFrame(frame);
    if (contactTmp != null) {
      final isContactSync = isContact && _isLoadingContacts;
      if (isContact && _isLoadingContacts) {
        _contactSyncReceived++;
      }
      if (listEquals(contactTmp.publicKey, _selfPublicKey)) {
        appLogger.info(
          'Ignoring contact with self public key: ${contactTmp.name}',
          tag: 'Connector',
        );
        notifyListeners();
        unawaited(
          removeContact(contactTmp).catchError(
            (e) => appLogger.warn(
              'Failed to remove self contact: $e',
              tag: 'Connector',
            ),
          ),
        );
        return;
      }
      final contact = _withContactMessageSummarySnapshot(
        getFromDiscovered(contactTmp),
      );
      _handleDiscovery(
        contact,
        frame,
        noNotify: true,
        addActive: true,
        persist: !isContactSync,
        notifyChange: !isContactSync,
      );

      if (contact.type == advTypeRepeater) {
        final removedCount = _contactUnreadCount[contact.publicKeyHex] ?? 0;
        _cachedContactsUnreadTotal = (_cachedContactsUnreadTotal - removedCount)
            .clamp(0, _cachedContactsUnreadTotal);
        _contactUnreadCount.remove(contact.publicKeyHex);
        if (!isContactSync) {
          _unreadStore.saveContactUnreadCount(
            Map<String, int>.from(_contactUnreadCount),
          );
        }
      }
      // Check if this is a new contact
      final isNewContact = !_knownContactKeys.contains(contact.publicKeyHex);
      final existingIndex = isContactSync
          ? findAndRepairContactIndex(
              contacts: _contacts,
              indexesByPublicKey: _contactSyncIndexes,
              publicKeyHex: contact.publicKeyHex,
            )
          : _contacts.indexWhere((c) => c.publicKeyHex == contact.publicKeyHex);

      if (existingIndex >= 0) {
        final existing = _contacts[existingIndex];
        final messageSummary = _mergedContactMessageSummary(existing, contact);

        if (!isContactSync) {
          appLogger.info(
            'Refreshing contact ${contact.name}: devicePath=${contact.pathLength}, existingOverride=${existing.pathOverride}',
            tag: 'Connector',
          );
        }

        // Preserve user-selected path settings and previously known GPS when
        // refreshed frames omit coordinates (lat/lon encoded as 0,0).
        _contacts[existingIndex] = contact.copyWith(
          lastMessageAt: messageSummary.lastMessageAt,
          hasMessages: messageSummary.hasMessages,
          pathOverride: existing.pathOverride, // Preserve user's path choice
          pathOverrideBytes: existing.pathOverrideBytes,
          latitude: contact.latitude ?? existing.latitude,
          longitude: contact.longitude ?? existing.longitude,
        );
        _registerContactInActiveSync(contact.publicKeyHex, existingIndex);

        if (!isContactSync) {
          appLogger.info(
            'After merge: pathOverride=${_contacts[existingIndex].pathOverride}, devicePath=${_contacts[existingIndex].pathLength}',
            tag: 'Connector',
          );
        }
      } else {
        if ((_autoAddUsers && contact.type == advTypeChat) ||
            (_autoAddRepeaters && contact.type == advTypeRepeater) ||
            (_autoAddRoomServers && contact.type == advTypeRoom) ||
            (_autoAddSensors && contact.type == advTypeSensor) ||
            isContact) {
          _contacts.add(contact);
          _registerContactInActiveSync(
            contact.publicKeyHex,
            _contacts.length - 1,
          );
          if (!isContactSync) {
            appLogger.info(
              'Added new contact ${contact.name}: pathLen=${contact.pathLength}',
              tag: 'Connector',
            );
          }
        } else {
          appLogger.info(
            "Discovered contact ${contact.name} (type ${contact.typeLabelRaw}) not added due to auto-add settings",
            tag: 'Connector',
          );
          notifyListeners();
          return;
        }
      }
      _knownContactKeys.add(contact.publicKeyHex);

      // Add path to history if we have a valid path
      if (!isContactSync &&
          _pathHistoryService != null &&
          contact.pathLength >= 0) {
        _pathHistoryService!.handlePathUpdated(contact);
      }

      if (!isContactSync || _contactSyncReceived % 8 == 0) {
        notifyListeners();
      }

      // Show notification for new contact (advertisement)
      if (!isContactSync && isNewContact && _appSettingsService != null) {
        final settings = _appSettingsService!.settings;
        if (settings.notificationsEnabled && settings.notifyOnNewAdvert) {
          _notificationService.showAdvertNotification(
            contactName: contact.name,
            contactType: contact.typeLabelRaw,
            contactId: contact.publicKeyHex,
          );
        }
      }

      if (!_isLoadingContacts) {
        unawaited(_persistContacts());
      }
    }
  }

  void _handleContactAdvert(Contact contact) {
    if (listEquals(contact.publicKey, _selfPublicKey)) {
      return;
    }

    if (contact.type == advTypeRepeater) {
      final removedCount = _contactUnreadCount[contact.publicKeyHex] ?? 0;
      _cachedContactsUnreadTotal = (_cachedContactsUnreadTotal - removedCount)
          .clamp(0, _cachedContactsUnreadTotal);
      _contactUnreadCount.remove(contact.publicKeyHex);
      _unreadStore.saveContactUnreadCount(
        Map<String, int>.from(_contactUnreadCount),
      );
    }
    // Check if this is a new contact
    final isNewContact = !_knownContactKeys.contains(contact.publicKeyHex);
    final existingIndex = _contacts.indexWhere(
      (c) => c.publicKeyHex == contact.publicKeyHex,
    );

    if (existingIndex >= 0) {
      final existing = _contacts[existingIndex];
      final messageSummary = _mergedContactMessageSummary(existing, contact);

      appLogger.info(
        'Refreshing contact ${contact.name}: devicePath=${contact.pathLength}, existingOverride=${existing.pathOverride}',
        tag: 'Connector',
      );

      // CRITICAL: Preserve user's path override when contact is refreshed from device
      _contacts[existingIndex] = contact.copyWith(
        lastMessageAt: messageSummary.lastMessageAt,
        hasMessages: messageSummary.hasMessages,
        pathOverride: existing.pathOverride, // Preserve user's path choice
        pathOverrideBytes: existing.pathOverrideBytes,
      );
      _registerContactInActiveSync(contact.publicKeyHex, existingIndex);

      appLogger.info(
        'After merge: pathOverride=${_contacts[existingIndex].pathOverride}, devicePath=${_contacts[existingIndex].pathLength}',
        tag: 'Connector',
      );
    } else {
      _contacts.add(contact);
      _registerContactInActiveSync(contact.publicKeyHex, _contacts.length - 1);
      appLogger.info(
        'Added new contact ${contact.name}: pathLen=${contact.pathLength}',
        tag: 'Connector',
      );
    }
    _knownContactKeys.add(contact.publicKeyHex);
    _loadMessagesForContact(contact.publicKeyHex);

    // Add path to history if we have a valid path
    if (_pathHistoryService != null && contact.pathLength >= 0) {
      _pathHistoryService!.handlePathUpdated(contact);
    }

    notifyListeners();

    // Show notification for new contact (advertisement)
    if (isNewContact && _appSettingsService != null) {
      final settings = _appSettingsService!.settings;
      if (settings.notificationsEnabled && settings.notifyOnNewAdvert) {
        _notificationService.showAdvertNotification(
          contactName: contact.name,
          contactType: contact.typeLabelRaw,
          contactId: contact.publicKeyHex,
        );
      }
    }

    if (!_isLoadingContacts) {
      unawaited(_persistContacts());
    }
  }

  Future<void> _persistContacts() async {
    final normalizedContacts = deduplicateContactsByPublicKey(_contacts);
    if (normalizedContacts.length != _contacts.length) {
      _contacts
        ..clear()
        ..addAll(normalizedContacts);
      _knownContactKeys
        ..clear()
        ..addAll(_contacts.map((contact) => contact.publicKeyHex));
    }
    await _contactStore.saveContacts(_contacts);
  }

  Future<void> _persistDiscoveredContacts() async {
    await _discoveryContactStore.saveContacts(_discoveredContacts);
  }

  int _latestContactLastmod() {
    if (_contacts.isEmpty) return 0;
    var latest = 0;
    for (final contact in _contacts) {
      // prefer lastmod per spec, fallback to lastseen
      final source = contact.lastModified ?? contact.lastSeen;
      final seconds = source.millisecondsSinceEpoch ~/ 1000;
      if (seconds > latest) {
        latest = seconds;
      }
    }
    return latest;
  }

  bool _setContactLastMessageAt(
    int index,
    DateTime timestamp, {
    bool markHasMessages = true,
  }) {
    final contact = _contacts[index];
    if (!_supportsContactMessageSummary(contact)) return false;
    final timestampChanged = timestamp.isAfter(contact.lastMessageAt);
    final hasMessagesChanged = markHasMessages && !contact.hasMessages;
    if (!timestampChanged && !hasMessagesChanged) return false;
    _contacts[index] = contact.copyWith(
      lastMessageAt: timestampChanged ? timestamp : contact.lastMessageAt,
      hasMessages: contact.hasMessages || markHasMessages,
    );
    return true;
  }

  void _updateContactLastMessageAt(
    String contactKeyHex,
    DateTime timestamp, {
    bool notify = false,
  }) {
    final index = _contacts.indexWhere((c) => c.publicKeyHex == contactKeyHex);
    if (index < 0) return;
    if (!_setContactLastMessageAt(index, timestamp)) return;
    unawaited(_persistContacts());
    if (notify) {
      notifyListeners();
    }
  }

  void _updateContactLastMessageAtByName(
    String senderName,
    DateTime timestamp, {
    String? authenticatedSenderKeyHex,
    Uint8List? pathBytes,
    int? pathHashWidth,
    bool notify = false,
  }) {
    int? matchedIndex;
    final authenticatedKey = authenticatedSenderKeyHex?.trim().toLowerCase();
    if (authenticatedKey != null && authenticatedKey.isNotEmpty) {
      final index = _contacts.indexWhere(
        (contact) =>
            contact.type == advTypeChat &&
            contact.publicKeyHex.toLowerCase() == authenticatedKey,
      );
      if (index < 0) return;
      matchedIndex = index;
    }

    final normalized = senderName.trim().toLowerCase();
    final hasName = normalized.isNotEmpty && normalized != 'unknown';
    var matchedByName = false;

    if (matchedIndex == null && hasName) {
      final matches = <int>[];
      for (var i = 0; i < _contacts.length; i++) {
        final contact = _contacts[i];
        if (contact.type != advTypeChat) continue;
        if (contact.name.trim().toLowerCase() == normalized) {
          matches.add(i);
        }
      }
      matchedByName = matches.isNotEmpty;
      if (matches.length == 1) {
        matchedIndex = matches.single;
      }
    }

    final effectivePathHashWidth = (pathHashWidth ?? _pathHashByteWidth)
        .clamp(1, 4)
        .toInt();
    if (matchedIndex == null &&
        !matchedByName &&
        effectivePathHashWidth >= 2 &&
        pathBytes != null &&
        pathBytes.isNotEmpty) {
      final matches = <int>[];
      for (var i = 0; i < _contacts.length; i++) {
        final contact = _contacts[i];
        if (contact.type != advTypeChat) continue;
        if (_pathMatchesContact(
          pathBytes,
          contact.publicKey,
          pathHashWidth: effectivePathHashWidth,
        )) {
          matches.add(i);
        }
      }
      if (matches.length == 1) {
        matchedIndex = matches.single;
      }
    }

    if (matchedIndex == null ||
        !_setContactLastMessageAt(
          matchedIndex,
          timestamp,
          markHasMessages: false,
        )) {
      return;
    }
    unawaited(_persistContacts());
    if (notify) {
      notifyListeners();
    }
  }

  bool _pathMatchesContact(
    Uint8List pathBytes,
    Uint8List publicKey, {
    int? pathHashWidth,
  }) {
    final w = pathHashWidth ?? _pathHashByteWidth;
    if (pathBytes.isEmpty || publicKey.length < w) return false;
    for (int i = 0; i + w <= pathBytes.length; i += w) {
      final prefix = pathBytes.sublist(i, i + w);
      if (_matchesPrefix(publicKey, prefix)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _handleIncomingMessage(Uint8List frame) async {
    if (_selfPublicKey == null) return;

    // If we're syncing the queued messages, advance the queue immediately
    // before any potentially long async work (like translation/notifications).
    if (_isSyncingQueuedMessages) {
      _handleQueuedMessageReceived();
    }

    var message = _parseContactMessage(frame);

    // If message parsing failed due to unknown contact, refresh contacts and retry
    if (message == null && !_isLoadingContacts) {
      final senderPrefix = _extractSenderPrefix(frame);
      if (senderPrefix != null) {
        final hasContact = _contacts.any(
          (c) => _matchesPrefix(c.publicKey, senderPrefix),
        );
        if (!hasContact) {
          debugPrint(
            'Received message from unknown contact, refreshing contacts...',
          );
          await refreshContactsSinceLastmod();
          // Retry parsing after refresh
          message = _parseContactMessage(frame);
          if (message != null) {
            debugPrint('Successfully parsed message after contact refresh');
          }
        }
      }
    }

    if (message != null) {
      final receivedAt = DateTime.now();
      if (!message.isOutgoing) {
        _lastContactMsgRxTime = receivedAt;
      }
      // Ignore messages from self (device hearing its own broadcast)
      // BUT allow repeated messages (pathLength indicates it went through repeater)
      if (_selfPublicKey != null &&
          message.senderKeyHex == pubKeyToHex(_selfPublicKey!) &&
          (message.pathLength == null || message.pathLength == 0)) {
        debugPrint('Ignoring direct message from self');
        return;
      }

      final contact = _contacts.cast<Contact?>().firstWhere(
        (c) => c?.publicKeyHex == message!.senderKeyHex,
        orElse: () => null,
      );
      if (contact != null) {
        message = message.copyWith(
          pathLength: contact.pathLength < 0 ? -1 : contact.pathLength,
          pathBytes: contact.pathLength < 0 ? Uint8List(0) : contact.path,
        );
        // Record the air receive time for incoming DMs from regular contacts.
        // Room-server posts intentionally keep receivedAt null (shown as "—").
        if (!message.isOutgoing && contact.type != advTypeRoom) {
          message = message.copyWith(receivedAt: receivedAt);
        }
      }
      if (contact != null && !message.isOutgoing && !message.isCli) {
        message = await _applyContactMcmpVerification(message, contact);
      }
      if (contact != null) {
        _updateContactLastMessageAt(contact.publicKeyHex, receivedAt);
      }
      await _loadMessagesForContact(message.senderKeyHex);
      if (contact != null && !message.isOutgoing && !message.isCli) {
        message = _resolveContactReplyReference(message, contact);
      }
      if (!message.isOutgoing) {
        final existing = _conversations[message.senderKeyHex];
        final incomingTimestamp = message.timestamp.millisecondsSinceEpoch;
        if (existing != null && existing.isNotEmpty) {
          final last = existing.last;
          if (!last.isOutgoing &&
              last.timestamp.millisecondsSinceEpoch == incomingTimestamp &&
              last.text == message.text) {
            return;
          }
        }
      }
      _addMessage(message.senderKeyHex, message);
      _maybeIncrementContactUnread(message);
      notifyListeners();

      // Show notification for new incoming message (run async with translation)
      if (!message.isOutgoing &&
          !message.isCli &&
          _appSettingsService != null) {
        final settings = _appSettingsService!.settings;
        if (settings.notificationsEnabled && settings.notifyOnNewMessage) {
          final msg = message; // capture for closure
          final c = contact; // capture contact reference
          unawaited(() async {
            final translationResult = await translateContactMessage(
              msg.senderKeyHex,
              msg,
            );
            if (c?.type == advTypeChat) {
              final resolvedText =
                  (translationResult != null &&
                      translationResult.status ==
                          MessageTranslationStatus.completed &&
                      translationResult.translatedText.trim().isNotEmpty)
                  ? translationResult.translatedText.trim()
                  : msg.text.trim();
              await _notificationService.showMessageNotification(
                contactName: c?.name ?? 'Unknown',
                message: resolvedText,
                contactId: msg.senderKeyHex,
                badgeCount: getTotalUnreadCount(),
              );
            } else if (c?.type == advTypeRoom) {
              final resolvedText =
                  (translationResult != null &&
                      translationResult.status ==
                          MessageTranslationStatus.completed &&
                      translationResult.translatedText.trim().isNotEmpty)
                  ? translationResult.translatedText.trim()
                  : msg.text.trim();
              await _notificationService.showMessageNotification(
                contactName: c?.name ?? 'Unknown Room',
                message: resolvedText,
                contactId: msg.senderKeyHex,
                badgeCount: getTotalUnreadCount(),
              );
            }
          }());
        }
      }
      _handleQueuedMessageReceived();
    } else if (_isSyncingQueuedMessages) {
      _handleQueuedMessageReceived();
    }
  }

  Message? _parseContactMessage(Uint8List frame) {
    if (frame.isEmpty) {
      appLogger.warn('Received empty frame, ignoring');
      return null;
    }
    final reader = BufferReader(frame);

    try {
      final code = reader.readByte();
      if (code != respCodeContactMsgRecv && code != respCodeContactMsgRecvV3) {
        appLogger.warn(
          'Unexpected message code: $code, expected contact message receive codes',
        );
        return null;
      }

      // Companion radio layout:
      // [code][snr?][res?][res?][prefix x6][path_len][txt_type][timestamp x4][extra?][text...]
      // double snr = 0;
      if (code == respCodeContactMsgRecvV3) {
        // Older firmware layout with SNR as a signed byte after the code
        // snr = reader.readInt8().toDouble() * 4; // SNR in dB, scaled by 4
        reader.skipBytes(1); // Skip SNR byte
        reader.skipBytes(2); // Skip reserved bytes
      }

      final senderPrefix = reader.readBytes(6);
      final pathLength = reader.readByte();
      final txtType = reader.readByte();
      final timestampRaw = reader.readUInt32LE();
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        timestampRaw * 1000,
      );

      final flags = txtType;
      final shiftedType = flags >> 2;
      final rawType = flags;
      final isSigned = shiftedType == txtTypeSigned || rawType == txtTypeSigned;
      final Uint8List? roomAuthorPrefix;
      if (isSigned) {
        // Room-server pushed posts use signed/plain contact messages where this
        // 4-byte "signature" field is actually the original author's pubkey
        // prefix. Keep it as metadata; the text starts after these bytes.
        roomAuthorPrefix = reader.readBytes(4);
      } else {
        roomAuthorPrefix = null;
      }

      final msgText = reader.readCString();

      final isPlain =
          shiftedType == txtTypePlain || rawType == txtTypePlain || isSigned;
      final isCli = shiftedType == txtTypeCliData || rawType == txtTypeCliData;
      if (!isPlain && !isCli) {
        appLogger.warn(
          'Unknown message type received: txtType=$txtType, shifted=$shiftedType, raw=$rawType',
        );
        return null;
      }

      if (msgText.isEmpty) {
        appLogger.warn('Received message with empty text, ignoring');
        return null;
      }
      final decodedDetails = isCli
          ? null
          : MessageTextCodec.tryDecodeKnownCompressionDetails(msgText);
      final decodedText = isCli ? msgText : (decodedDetails?.text ?? msgText);
      final compression = isCli
          ? null
          : MessageCompressionMetadata.fromEncodedText(
              encodedText: msgText,
              decodedText: decodedText,
            );

      final contact = _contacts.cast<Contact?>().firstWhere(
        (c) => c != null && _matchesPrefix(c.publicKey, senderPrefix),
        orElse: () => null,
      );
      if (contact == null) {
        appLogger.warn(
          'Received message from unknown contact with prefix: ${senderPrefix.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('')}',
        );
        return null;
      }

      final mcmpMessage = decodedDetails?.mcmpMessage;
      return Message(
        senderKey: contact.publicKey,
        text: decodedText,
        timestamp: timestamp,
        isOutgoing: false,
        isCli: isCli,
        status: MessageStatus.delivered,
        wasMcmpCompressed: !isCli && _isMcmpEncodedText(msgText),
        compressionType: compression?.type,
        compressionSavingsPercent: compression?.savingsPercent,
        compressionOriginalBytes: compression?.originalBytes,
        compressionPayloadBytes: compression?.payloadBytes,
        mcmpSignatureStatus:
            mcmpMessage?.signatureStatus ?? McmpSignatureStatus.none,
        mcmpTimestamp: mcmpMessage?.timestamp,
        mcmpSenderName: mcmpMessage?.senderName,
        mcmpIsSigned: mcmpMessage?.isSigned ?? false,
        mcmpSignature: mcmpMessage?.signature,
        mcmpReplyAuthorName: mcmpMessage?.replyAuthorName,
        mcmpReplyTimestamp: mcmpMessage?.replyTimestamp,
        pathLength: pathLength == 0xFF ? -1 : (pathLength & 0x3F),
        pathBytes: Uint8List(0),
        fourByteRoomContactKey: roomAuthorPrefix,
      );
    } catch (e) {
      appLogger.warn('Error parsing contact direct message: $e');
      return null;
    }
  }

  bool _matchesPrefix(Uint8List fullKey, Uint8List prefix) {
    if (fullKey.length < prefix.length) return false;
    for (int i = 0; i < prefix.length; i++) {
      if (fullKey[i] != prefix[i]) return false;
    }
    return true;
  }

  Uint8List? _extractSenderPrefix(Uint8List frame) {
    if (frame.isEmpty) return null;
    final code = frame[0];
    if (code != respCodeContactMsgRecv && code != respCodeContactMsgRecvV3) {
      return null;
    }

    final prefixOffset = code == respCodeContactMsgRecvV3 ? 4 : 1;
    const prefixLen = 6;

    if (frame.length < prefixOffset + prefixLen) return null;

    return frame.sublist(prefixOffset, prefixOffset + prefixLen);
  }

  void _ensureContactMcmpSettingLoaded(String contactKeyHex) {
    if (_contactMcmpEnabled.containsKey(contactKeyHex)) return;
    _contactSettingsStore.loadMcmpEnabled(contactKeyHex).then((enabled) {
      if (_contactMcmpEnabled[contactKeyHex] == enabled) return;
      _contactMcmpEnabled[contactKeyHex] = enabled;
      notifyListeners();
    });
  }

  void _ensureContactMcmpVersionLoaded(String contactKeyHex) {
    if (_contactMcmpVersion.containsKey(contactKeyHex)) return;
    _contactSettingsStore.loadMcmpVersion(contactKeyHex).then((version) {
      final normalized = version == 3 ? 3 : 2;
      if (_contactMcmpVersion[contactKeyHex] == normalized) return;
      _contactMcmpVersion[contactKeyHex] = normalized;
      notifyListeners();
    });
  }

  void _ensureContactMcmpUseSignLoaded(String contactKeyHex) {
    if (_contactMcmpUseSign.containsKey(contactKeyHex)) return;
    _contactSettingsStore.loadMcmpUseSign(contactKeyHex).then((useSign) {
      if (_contactMcmpUseSign[contactKeyHex] == useSign) return;
      _contactMcmpUseSign[contactKeyHex] = useSign;
      notifyListeners();
    });
  }

  void _ensureContactSmazSettingLoaded(String contactKeyHex) {
    if (_contactSmazEnabled.containsKey(contactKeyHex)) return;
    _contactSettingsStore.loadSmazEnabled(contactKeyHex).then((enabled) {
      if (_contactSmazEnabled[contactKeyHex] == enabled) return;
      _contactSmazEnabled[contactKeyHex] = enabled;
      notifyListeners();
    });
  }

  void _ensureContactCyr2LatSettingLoaded(String contactKeyHex) {
    if (_contactCyr2LatEnabled.containsKey(contactKeyHex)) return;
    _contactSettingsStore.loadCyr2LatEnabled(contactKeyHex).then((enabled) {
      if (_contactCyr2LatEnabled[contactKeyHex] == enabled) return;
      _contactCyr2LatEnabled[contactKeyHex] = enabled;
      notifyListeners();
    });
  }

  void _ensureContactSendingDelaySettingLoaded(String contactKeyHex) {
    if (_contactSendingDelayEnabled.containsKey(contactKeyHex)) return;
    _contactSettingsStore.loadSendingDelayEnabled(contactKeyHex).then((
      enabled,
    ) {
      if (_contactSendingDelayEnabled[contactKeyHex] == enabled) return;
      _contactSendingDelayEnabled[contactKeyHex] = enabled;
      notifyListeners();
    });
  }

  void _ensureContactQuickAnswerIdsLoaded(String contactKeyHex) {
    if (_contactQuickAnswerIds.containsKey(contactKeyHex)) return;
    _contactSettingsStore.loadQuickAnswerIds(contactKeyHex).then((answerIds) {
      if (listEquals(_contactQuickAnswerIds[contactKeyHex], answerIds)) return;
      _contactQuickAnswerIds[contactKeyHex] = answerIds;
      notifyListeners();
    });
  }

  void _ensureContactCyr2LatProfileLoaded(String contactKeyHex) {
    if (_contactCyr2LatProfileId.containsKey(contactKeyHex)) return;
    _contactSettingsStore.loadCyr2LatProfileId(contactKeyHex).then((profileId) {
      if (_contactCyr2LatProfileId[contactKeyHex] == profileId) return;
      _contactCyr2LatProfileId[contactKeyHex] = profileId;
      notifyListeners();
    });
  }

  void _ensureChannelCyr2LatSettingLoaded(int channelIndex) {
    if (_channelCyr2LatEnabled.containsKey(channelIndex)) return;
    _channelSettingsStore.loadCyr2LatEnabled(channelIndex).then((enabled) {
      if (_channelCyr2LatEnabled[channelIndex] == enabled) return;
      _channelCyr2LatEnabled[channelIndex] = enabled;
      notifyListeners();
    });
  }

  void _ensureChannelSendingDelaySettingLoaded(int channelIndex) {
    if (_channelSendingDelayEnabled.containsKey(channelIndex)) return;
    _channelSettingsStore.loadSendingDelayEnabled(channelIndex).then((enabled) {
      if (_channelSendingDelayEnabled[channelIndex] == enabled) return;
      _channelSendingDelayEnabled[channelIndex] = enabled;
      notifyListeners();
    });
  }

  void _ensureChannelQuickAnswerIdsLoaded(int channelIndex) {
    if (_channelQuickAnswerIds.containsKey(channelIndex)) return;
    _channelSettingsStore.loadQuickAnswerIds(channelIndex).then((answerIds) {
      if (listEquals(_channelQuickAnswerIds[channelIndex], answerIds)) return;
      _channelQuickAnswerIds[channelIndex] = answerIds;
      notifyListeners();
    });
  }

  void _ensureChannelCyr2LatProfileLoaded(int channelIndex) {
    if (_channelCyr2LatProfileId.containsKey(channelIndex)) return;
    _channelSettingsStore.loadCyr2LatProfileId(channelIndex).then((profileId) {
      if (_channelCyr2LatProfileId[channelIndex] == profileId) return;
      _channelCyr2LatProfileId[channelIndex] = profileId;
      notifyListeners();
    });
  }

  void _ensureChannelWidgetColorLoaded(int channelIndex) {
    if (_channelWidgetColor.containsKey(channelIndex)) return;
    _channelSettingsStore.loadWidgetColor(channelIndex).then((colorValue) {
      if (_channelWidgetColor.containsKey(channelIndex) &&
          _channelWidgetColor[channelIndex] == colorValue) {
        return;
      }
      _channelWidgetColor[channelIndex] = colorValue;
      notifyListeners();
    });
  }

  void _ensureChannelWidgetTextColorLoaded(int channelIndex) {
    if (_channelWidgetTextColor.containsKey(channelIndex)) return;
    _channelSettingsStore.loadWidgetTextColor(channelIndex).then((colorValue) {
      if (_channelWidgetTextColor.containsKey(channelIndex) &&
          _channelWidgetTextColor[channelIndex] == colorValue) {
        return;
      }
      _channelWidgetTextColor[channelIndex] = colorValue;
      notifyListeners();
    });
  }

  String? getChannelCyr2LatProfileId(int channelIndex) {
    _ensureChannelCyr2LatProfileLoaded(channelIndex);
    return _channelCyr2LatProfileId[channelIndex];
  }

  int? getChannelWidgetColor(int channelIndex) {
    _ensureChannelWidgetColorLoaded(channelIndex);
    return _channelWidgetColor[channelIndex];
  }

  int? getChannelWidgetTextColor(int channelIndex) {
    _ensureChannelWidgetTextColorLoaded(channelIndex);
    return _channelWidgetTextColor[channelIndex];
  }

  Future<void> setChannelCyr2LatProfileId(
    int channelIndex,
    String? profileId,
  ) async {
    if (_channelCyr2LatProfileId[channelIndex] == profileId) return;
    _channelCyr2LatProfileId[channelIndex] = profileId;
    await _channelSettingsStore.saveCyr2LatProfileId(channelIndex, profileId);
    notifyListeners();
  }

  Future<void> setChannelWidgetColor(int channelIndex, int? colorValue) async {
    if (_channelWidgetColor.containsKey(channelIndex) &&
        _channelWidgetColor[channelIndex] == colorValue) {
      return;
    }
    _channelWidgetColor[channelIndex] = colorValue;
    await _channelSettingsStore.saveWidgetColor(channelIndex, colorValue);
    notifyListeners();
  }

  Future<void> setChannelWidgetTextColor(
    int channelIndex,
    int? colorValue,
  ) async {
    if (_channelWidgetTextColor.containsKey(channelIndex) &&
        _channelWidgetTextColor[channelIndex] == colorValue) {
      return;
    }
    _channelWidgetTextColor[channelIndex] = colorValue;
    await _channelSettingsStore.saveWidgetTextColor(channelIndex, colorValue);
    notifyListeners();
  }

  String? getContactCyr2LatProfileId(String contactKeyHex) {
    _ensureContactCyr2LatProfileLoaded(contactKeyHex);
    return _contactCyr2LatProfileId[contactKeyHex];
  }

  Future<void> setContactCyr2LatProfileId(
    String contactKeyHex,
    String? profileId,
  ) async {
    if (_contactCyr2LatProfileId[contactKeyHex] == profileId) return;
    _contactCyr2LatProfileId[contactKeyHex] = profileId;
    await _contactSettingsStore.saveCyr2LatProfileId(contactKeyHex, profileId);
    notifyListeners();
  }

  /// True when [text] is a plain user message eligible for MCMP v3 encoding
  /// and signing (not an image payload, structured payload, or an already
  /// encoded container).
  bool _isMcmpSignableText(String text) {
    if (text.isEmpty) return false;
    final trimmedLeft = text.trimLeft();
    final trimmed = text.trim();
    return !MCOImageV3Codec.isTextPayload(trimmedLeft) &&
        !trimmedLeft.startsWith(MCOImageCodec.prefix) &&
        !trimmed.startsWith('g:') &&
        !trimmed.startsWith('m:') &&
        !trimmed.startsWith('V1|') &&
        // Shared contact payloads (<pubkey:type:name>) must travel as plain
        // text so receivers can parse them.
        parseSharedContactText(trimmed) == null &&
        !MeshCompressor.instance.hasPrefix(trimmed) &&
        !McmpAppCodec.isTextPayload(trimmed);
  }

  void _notifyMcmpSigningFailed() {
    if (!_mcmpSigningFailedController.isClosed) {
      _mcmpSigningFailedController.add(null);
    }
  }

  /// Requests a node signature over the MCMP v3 canonical bytes.
  /// Returns null when signing fails; callers should then send unsigned.
  Future<Uint8List?> _signMcmpCanonical({
    required McmpSigningContext context,
    required Uint8List binding,
    required String senderName,
    required int timestamp,
    required bool hasSenderNameInBody,
    required String text,
    String? replyAuthorName,
    int? replyTimestamp,
  }) async {
    try {
      final canonical = McmpAppCodec.canonicalSigningBytes(
        context: context,
        binding: binding,
        senderName: senderName,
        timestamp: timestamp,
        flags: McmpAppCodec.packFlags(
          hasReply: replyAuthorName != null,
          isSigned: true,
          hasSenderName: hasSenderNameInBody,
        ),
        text: text,
        replyAuthorName: replyAuthorName,
        replyTimestamp: replyTimestamp,
      );
      return await signWithNode(canonical);
    } catch (e) {
      appLogger.warn('MCMP canonical signing failed: $e');
      return null;
    }
  }

  /// Async variant of [prepareContactOutboundText] used by the real send
  /// paths. For room servers with MCMP v3 it embeds the sender name in the
  /// body (the room transport carries only a pubkey prefix) and, when
  /// enabled, signs the message with the node identity key.
  Future<String> prepareContactOutboundTextAsync(
    Contact contact,
    String text, {
    String? replyAuthorName,
    int? replyTimestamp,
  }) async {
    final hasReplyPair = replyAuthorName != null && replyTimestamp != null;
    final effectiveReplyName = hasReplyPair ? replyAuthorName : null;
    final effectiveReplyTimestamp = hasReplyPair ? replyTimestamp : null;

    if (isContactMcmpEnabled(contact.publicKeyHex) &&
        contactMcmpVersion(contact.publicKeyHex) == 3 &&
        _isMcmpSignableText(text)) {
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (contact.type == advTypeRoom) {
        final senderName = _selfName ?? 'Me';
        Uint8List? signature;
        if (contactMcmpUseSign(contact.publicKeyHex)) {
          signature = await _signMcmpCanonical(
            context: McmpSigningContext.room,
            binding: McmpAppCodec.roomSigningBinding(contact.publicKey),
            senderName: senderName,
            timestamp: timestamp,
            hasSenderNameInBody: true,
            text: text,
            replyAuthorName: effectiveReplyName,
            replyTimestamp: effectiveReplyTimestamp,
          );
          if (signature == null) _notifyMcmpSigningFailed();
        }
        return McmpAppCodec.encodeTextTransport(
          text: text,
          timestamp: timestamp,
          senderName: senderName,
          signature: signature,
          replyAuthorName: effectiveReplyName,
          replyTimestamp: effectiveReplyTimestamp,
        );
      }
      // Direct contacts: the ECDH transport authenticates the sender, so the
      // body is never signed and carries no name. Reply anchors travel with
      // an empty author name — both identities are known, resolution relies
      // on the timestamp alone.
      return McmpAppCodec.encodeTextTransport(
        text: text,
        timestamp: timestamp,
        replyAuthorName: hasReplyPair ? '' : null,
        replyTimestamp: effectiveReplyTimestamp,
      );
    }
    return prepareContactOutboundText(contact, text);
  }

  /// Prepares contact outbound text by applying SMAZ encoding if enabled.
  /// This should be used to transform text before computing ACK hashes.
  ///
  /// For MCMP v3 this is a synchronous *estimation*: real sends go through
  /// [prepareContactOutboundTextAsync], which signs via the node. When
  /// [estimateSignatureOverhead] is true (composer counters, length guards)
  /// a zero-filled placeholder signature of the exact wire size is included
  /// so byte counts reflect the signed container. Never send the placeholder
  /// variant to the wire.
  String prepareContactOutboundText(
    Contact contact,
    String text, {
    bool estimateSignatureOverhead = true,
  }) {
    final trimmedLeft = text.trimLeft();
    final trimmed = text.trim();
    final isStructuredPayload =
        MCOImageV3Codec.isTextPayload(trimmedLeft) ||
        trimmedLeft.startsWith(MCOImageCodec.prefix) ||
        trimmed.startsWith('g:') ||
        trimmed.startsWith('m:') ||
        trimmed.startsWith('V1|') ||
        parseSharedContactText(trimmed) != null ||
        MeshCompressor.instance.hasPrefix(trimmed) ||
        McmpAppCodec.isTextPayload(trimmed);
    if (!isStructuredPayload) {
      if (isContactMcmpEnabled(contact.publicKeyHex)) {
        if (contactMcmpVersion(contact.publicKeyHex) != 3) {
          return MeshCompressor.instance.encodeIfSmaller(text);
        }
        final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (contact.type == advTypeRoom) {
          final placeholderSignature =
              estimateSignatureOverhead &&
                  contactMcmpUseSign(contact.publicKeyHex)
              ? Uint8List(signatureSize)
              : null;
          return McmpAppCodec.encodeTextTransport(
            text: text,
            timestamp: timestamp,
            senderName: _selfName ?? 'Me',
            signature: placeholderSignature,
          );
        }
        return McmpAppCodec.encodeDirectContactText(
          text: text,
          timestamp: timestamp,
        );
      }
      if (isContactSmazEnabled(contact.publicKeyHex)) {
        return Smaz.encodeIfSmaller(text);
      } else if (isContactCyr2LatEnabled(contact.publicKeyHex)) {
        final profileId = getContactCyr2LatProfileId(contact.publicKeyHex);
        final profile = profileId != null && _appSettingsService != null
            ? _appSettingsService!.getCyr2LatProfileById(profileId)
            : null;
        if (profile != null) {
          Cyr2Lat.setCharMap(profile.charMap);
        } else {
          // Use global profile
          final globalProfile = _appSettingsService
              ?.getSelectedCyr2LatProfile();
          if (globalProfile != null) {
            Cyr2Lat.setCharMap(globalProfile.charMap);
          }
        }
        return Cyr2Lat.encode(text);
      }
    }
    return text;
  }

  /// Synchronous channel outbound estimation; see
  /// [prepareContactOutboundText] for the [estimateSignatureOverhead]
  /// placeholder semantics. Real MCMP v3 sends encode (and sign) inline in
  /// [sendChannelMessage].
  String prepareChannelOutboundText(
    int channelIndex,
    String text, {
    bool estimateSignatureOverhead = true,
  }) {
    final trimmedLeft = text.trimLeft();
    final trimmed = text.trim();
    final isStructuredPayload =
        MCOImageV3Codec.isTextPayload(trimmedLeft) ||
        trimmedLeft.startsWith(MCOImageCodec.prefix) ||
        trimmed.startsWith('g:') ||
        trimmed.startsWith('m:') ||
        parseSharedContactText(trimmed) != null ||
        MeshCompressor.instance.hasPrefix(trimmed) ||
        McmpAppCodec.isTextPayload(trimmed);
    if (!isStructuredPayload) {
      if (isChannelMcmpEnabled(channelIndex)) {
        if (channelMcmpVersion(channelIndex) == 3) {
          final placeholderSignature =
              estimateSignatureOverhead && channelMcmpUseSign(channelIndex)
              ? Uint8List(signatureSize)
              : null;
          return McmpAppCodec.encodeTextTransport(
            text: text,
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            signature: placeholderSignature,
          );
        }
        return MeshCompressor.instance.encodeIfSmaller(text);
      }
      if (isChannelSmazEnabled(channelIndex)) {
        return Smaz.encodeIfSmaller(text);
      } else if (isChannelCyr2LatEnabled(channelIndex)) {
        final profileId = getChannelCyr2LatProfileId(channelIndex);
        final profile = profileId != null && _appSettingsService != null
            ? _appSettingsService!.getCyr2LatProfileById(profileId)
            : null;
        if (profile != null) {
          Cyr2Lat.setCharMap(profile.charMap);
        } else {
          // Use global profile
          final globalProfile = _appSettingsService
              ?.getSelectedCyr2LatProfile();
          if (globalProfile != null) {
            Cyr2Lat.setCharMap(globalProfile.charMap);
          }
        }
        return Cyr2Lat.encode(text);
      }
    }
    return text;
  }

  MessageCompressionMetadata? _contactCompressionMetadata(
    Contact contact,
    String originalText,
    String outboundText,
  ) {
    final trimmed = originalText.trim();
    if (trimmed.startsWith('g:') ||
        trimmed.startsWith('m:') ||
        trimmed.startsWith('V1|')) {
      return null;
    }
    MessageCompressionType? type;
    if (isContactMcmpEnabled(contact.publicKeyHex) &&
        _isMcmpEncodedText(outboundText)) {
      type = MessageCompressionType.mcmp;
      // MCMP v3: ratio over the compressed text segment only, without
      // container metadata.
      final mcmpV3TextBytes = McmpAppCodec.compressedTextBytesFromTextPayload(
        outboundText,
      );
      if (mcmpV3TextBytes != null) {
        return MessageCompressionMetadata.fromByteLengths(
          type: type,
          originalBytes: utf8.encode(originalText).length,
          compressedBytes: mcmpV3TextBytes,
        );
      }
    } else if (isContactSmazEnabled(contact.publicKeyHex) &&
        Smaz.hasPrefix(outboundText)) {
      type = MessageCompressionType.smaz;
    } else if (isContactCyr2LatEnabled(contact.publicKeyHex) &&
        outboundText != originalText) {
      type = MessageCompressionType.cyr2lat;
    }
    if (type == null) return null;
    return MessageCompressionMetadata.fromText(
      type: type,
      originalText: originalText,
      compressedText: outboundText,
    );
  }

  bool _isMcmpEncodedText(String text) {
    return MeshCompressor.instance.hasPrefix(text) ||
        McmpAppCodec.isTextPayload(text);
  }

  _McmpReplyReference? _resolveMcmpReplyReference(
    int channelIndex,
    DecodedMcmpAppMessage? mcmpMessage,
  ) {
    if (mcmpMessage == null || !mcmpMessage.isReply) return null;
    return _resolveChannelReplyAnchor(
      channelIndex,
      mcmpMessage.replyAuthorName,
      mcmpMessage.replyTimestamp,
    );
  }

  /// Tolerance for reply-anchor timestamp matching. Kept at 0 so only an exact
  /// timestamp match resolves a quoted message; the delta mechanism is retained
  /// for compatibility/tests but never accepts an approximate candidate.
  static const int _replyAnchorToleranceSeconds = 0;

  /// Resolves a reply anchor ("author name + timestamp" as transmitted in the
  /// MCMP v3 body of the *replying* message) against the channel history. The
  /// quoted message may be any message that carries a timestamp visible in the
  /// chat history: plain group_text via its outer packet timestamp, MCMP v3 via
  /// its body timestamp, or binary payloads such as MCOimg via their stored
  /// packet/log timestamp. A candidate matches when its author is
  /// [replyAuthorName] and one of its timestamps equals [replyTimestamp]
  /// exactly. When nothing matches exactly, returns an author-name-only
  /// reference (rendered as an @mention).
  _McmpReplyReference? _resolveChannelReplyAnchor(
    int channelIndex,
    String? replyAuthorName,
    int? replyTimestamp,
  ) {
    final replySender = replyAuthorName?.trim();
    if (replySender == null || replySender.isEmpty || replyTimestamp == null) {
      return null;
    }

    final messages = _channelMessages[channelIndex] ?? const <ChannelMessage>[];
    ChannelMessage? closest;
    int? closestDelta;
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.senderName.trim() != replySender) continue;
      final outerTimestamp = message.timestamp.millisecondsSinceEpoch ~/ 1000;
      if (outerTimestamp == replyTimestamp ||
          message.mcmpTimestamp == replyTimestamp) {
        return _McmpReplyReference(
          messageId: message.messageId,
          senderName: message.senderName,
          text: message.text,
        );
      }
      var delta = (outerTimestamp - replyTimestamp).abs();
      final mcmpTimestamp = message.mcmpTimestamp;
      if (mcmpTimestamp != null) {
        final mcmpDelta = (mcmpTimestamp - replyTimestamp).abs();
        if (mcmpDelta < delta) delta = mcmpDelta;
      }
      if (delta <= _replyAnchorToleranceSeconds &&
          (closestDelta == null || delta < closestDelta)) {
        closest = message;
        closestDelta = delta;
      }
    }

    if (closest != null) {
      return _McmpReplyReference(
        messageId: closest.messageId,
        senderName: closest.senderName,
        text: closest.text,
      );
    }
    return _McmpReplyReference(senderName: replySender);
  }

  Uint8List? _channelPskForIndex(int channelIndex) {
    final channels = _channels.isNotEmpty ? _channels : _cachedChannels;
    for (final channel in channels) {
      if (channel.index == channelIndex && !channel.isEmpty) {
        return channel.psk;
      }
    }
    return null;
  }

  /// Verifies the MCMP v3 signature of an inbound channel message using the
  /// verbatim meta stored on the model, and stamps the verification result.
  Future<ChannelMessage> _verifyInboundChannelMessage(
    ChannelMessage message,
  ) async {
    if (!message.mcmpIsSigned ||
        message.mcmpSignature == null ||
        message.mcmpTimestamp == null ||
        message.channelIndex == null) {
      return message;
    }
    final psk = _channelPskForIndex(message.channelIndex!);
    if (psk == null) {
      return message.copyWith(
        mcmpSignatureStatus: McmpSignatureStatus.unverifiable,
      );
    }
    final decoded = DecodedMcmpAppMessage(
      text: message.text,
      timestamp: message.mcmpTimestamp!,
      senderName: message.mcmpSenderName,
      signature: message.mcmpSignature,
      replyAuthorName: message.mcmpReplyAuthorName,
      replyTimestamp: message.mcmpReplyTimestamp,
    );
    final result = await McmpSignatureVerifier.verifyChannelMessage(
      message: decoded,
      // Prefer the name embedded in the signed body (foreign clients may set
      // it even for channels); otherwise the outer envelope/text name.
      senderName: message.mcmpSenderName ?? message.senderName,
      channelPsk: psk,
      contacts: List<Contact>.from(_contacts),
    );
    return message.copyWith(
      mcmpSignatureStatus: result.status,
      verifiedSenderKeyHex: result.verifiedSenderKeyHex,
      mcmpNameCollision: result.nameCollision,
    );
  }

  /// Stamps the MCMP verification result on an inbound contact message.
  ///
  /// Direct messages are authenticated by the ECDH transport itself; room
  /// posts are relayed by the room server and require the embedded Ed25519
  /// signature (author located by the 4-byte pubkey prefix, signed name must
  /// match the local contact name).
  Future<Message> _applyContactMcmpVerification(
    Message message,
    Contact contact,
  ) async {
    if (message.mcmpTimestamp == null) return message;
    final isRoomPost =
        contact.type == advTypeRoom &&
        message.fourByteRoomContactKey.isNotEmpty;
    if (!isRoomPost) {
      return message.copyWith(
        mcmpSignatureStatus: McmpSignatureStatus.transportAuthenticated,
      );
    }
    if (!message.mcmpIsSigned || message.mcmpSignature == null) {
      return message.copyWith(
        mcmpSignatureStatus: McmpSignatureStatus.unsigned,
      );
    }
    final decoded = DecodedMcmpAppMessage(
      text: message.text,
      timestamp: message.mcmpTimestamp!,
      senderName: message.mcmpSenderName,
      signature: message.mcmpSignature,
      replyAuthorName: message.mcmpReplyAuthorName,
      replyTimestamp: message.mcmpReplyTimestamp,
    );
    final result = await McmpSignatureVerifier.verifyRoomMessage(
      message: decoded,
      authorPrefix: message.fourByteRoomContactKey,
      roomPublicKey: contact.publicKey,
      contacts: List<Contact>.from(_contacts),
    );
    return message.copyWith(
      mcmpSignatureStatus: result.status,
      verifiedSenderKeyHex: result.verifiedSenderKeyHex,
      mcmpNameCollision: result.nameCollision,
    );
  }

  /// Manually re-checks the signature of a stored channel message against the
  /// current contact list (e.g. after adding the author as a contact).
  /// Updates the stored verification result, including the name-collision
  /// flag, and returns the new status (null when the message is not a signed
  /// MCMP v3 payload).
  Future<McmpSignatureStatus?> recheckChannelMessageSignature(
    int channelIndex,
    String messageId,
  ) async {
    final messages = _channelMessages[channelIndex];
    if (messages == null) return null;
    final index = messages.indexWhere((m) => m.messageId == messageId);
    if (index < 0) return null;
    final message = messages[index];
    if (message.isOutgoing ||
        !message.mcmpIsSigned ||
        message.mcmpSignature == null) {
      return null;
    }

    final reverified = await _verifyInboundChannelMessage(message);
    final currentIndex = messages.indexWhere((m) => m.messageId == messageId);
    if (currentIndex < 0) return reverified.mcmpSignatureStatus;
    messages[currentIndex] = reverified;
    unawaited(_channelMessageStore.saveChannelMessages(channelIndex, messages));
    notifyListeners();
    return reverified.mcmpSignatureStatus;
  }

  /// Manually re-checks the signature of a stored room-server message.
  /// Returns the new status (null when the message is not a signed MCMP v3
  /// payload or the contact is unknown).
  Future<McmpSignatureStatus?> recheckContactMessageSignature(
    String contactKeyHex,
    String messageId,
  ) async {
    final messages = _conversations[contactKeyHex];
    if (messages == null) return null;
    final index = messages.indexWhere((m) => m.messageId == messageId);
    if (index < 0) return null;
    final message = messages[index];
    if (message.isOutgoing ||
        !message.mcmpIsSigned ||
        message.mcmpSignature == null) {
      return null;
    }
    final contact = _contacts.cast<Contact?>().firstWhere(
      (c) => c?.publicKeyHex == contactKeyHex,
      orElse: () => null,
    );
    if (contact == null) return null;

    final reverified = await _applyContactMcmpVerification(message, contact);
    final currentIndex = messages.indexWhere((m) => m.messageId == messageId);
    if (currentIndex < 0) return reverified.mcmpSignatureStatus;
    messages[currentIndex] = reverified;
    await _messageStore.saveMessages(contactKeyHex, messages);
    notifyListeners();
    return reverified.mcmpSignatureStatus;
  }

  /// Resolves the MCMP reply anchor of an inbound DM/room message against the
  /// stored conversation. Room posts match the transmitted "author name +
  /// timestamp" pair; direct messages carry an empty author name (both
  /// identities are known) and resolve by timestamp alone.
  Message _resolveContactReplyReference(Message message, Contact contact) {
    final isRoom = contact.type == advTypeRoom;
    final replySender = message.mcmpReplyAuthorName?.trim();
    final replyTimestamp = message.mcmpReplyTimestamp;
    if (replyTimestamp == null) return message;
    if (isRoom && (replySender == null || replySender.isEmpty)) {
      return message;
    }

    String? authorNameFor(Message candidate) {
      if (candidate.mcmpSenderName != null) return candidate.mcmpSenderName;
      if (candidate.isOutgoing) return _selfName;
      if (candidate.fourByteRoomContactKey.isNotEmpty) {
        final author = _contacts.cast<Contact?>().firstWhere(
          (c) =>
              c != null &&
              _matchesPrefix(c.publicKey, candidate.fourByteRoomContactKey),
          orElse: () => null,
        );
        return author?.name;
      }
      return contact.name;
    }

    final messages = _conversations[contact.publicKeyHex] ?? const <Message>[];
    Message? closest;
    String? closestName;
    int? closestDelta;
    for (var i = messages.length - 1; i >= 0; i--) {
      final candidate = messages[i];
      final candidateName = authorNameFor(candidate)?.trim();
      // Rooms match the transmitted author name; direct messages resolve by
      // timestamp alone (the anchor carries an empty name).
      if (isRoom && (candidateName == null || candidateName != replySender)) {
        continue;
      }
      final outerTimestamp = candidate.timestamp.millisecondsSinceEpoch ~/ 1000;
      if (candidate.mcmpTimestamp == replyTimestamp ||
          outerTimestamp == replyTimestamp) {
        return message.copyWith(
          replyToMessageId: candidate.messageId,
          replyToSenderName: candidateName,
          replyToText: candidate.text,
        );
      }
      var delta = (outerTimestamp - replyTimestamp).abs();
      final mcmpTimestamp = candidate.mcmpTimestamp;
      if (mcmpTimestamp != null) {
        final mcmpDelta = (mcmpTimestamp - replyTimestamp).abs();
        if (mcmpDelta < delta) delta = mcmpDelta;
      }
      if (delta <= _replyAnchorToleranceSeconds &&
          (closestDelta == null || delta < closestDelta)) {
        closest = candidate;
        closestName = candidateName;
        closestDelta = delta;
      }
    }
    if (closest != null) {
      return message.copyWith(
        replyToMessageId: closest.messageId,
        replyToSenderName: closestName,
        replyToText: closest.text,
      );
    }
    if (isRoom) {
      return message.copyWith(replyToSenderName: replySender);
    }
    return message;
  }

  MessageCompressionMetadata? _channelCompressionMetadata(
    int channelIndex,
    String originalText,
    String outboundText, {
    required String senderName,
    int? binaryPayloadBytes,
  }) {
    final trimmed = originalText.trim();
    if (trimmed.startsWith('g:') || trimmed.startsWith('m:')) return null;
    // MCMP v3: the ratio is computed over the compressed text segment only,
    // excluding container metadata (timestamp, signature, reply anchor). The
    // segment is identical for the binary and Base91 transports.
    if (isChannelMcmpEnabled(channelIndex)) {
      final mcmpV3TextBytes = McmpAppCodec.compressedTextBytesFromTextPayload(
        outboundText,
      );
      if (mcmpV3TextBytes != null) {
        return MessageCompressionMetadata.fromByteLengths(
          type: MessageCompressionType.mcmp,
          originalBytes: utf8.encode(originalText).length,
          compressedBytes: mcmpV3TextBytes,
        );
      }
    }
    if (binaryPayloadBytes != null) {
      return MessageCompressionMetadata.fromByteLengths(
        type: MessageCompressionType.mcmp,
        originalBytes: ChannelBinaryDataHelper.uncompressedBinaryPayloadLength(
          originalText,
          senderName,
        ),
        compressedBytes: ChannelBinaryDataHelper.finalBinaryPayloadLength(
          binaryPayloadBytes,
        ),
      );
    }

    MessageCompressionType? type;
    if (isChannelMcmpEnabled(channelIndex) &&
        _isMcmpEncodedText(outboundText)) {
      type = MessageCompressionType.mcmp;
    } else if (isChannelSmazEnabled(channelIndex) &&
        Smaz.hasPrefix(outboundText)) {
      type = MessageCompressionType.smaz;
    } else if (isChannelCyr2LatEnabled(channelIndex) &&
        outboundText != originalText) {
      type = MessageCompressionType.cyr2lat;
    }
    if (type == null) return null;
    return MessageCompressionMetadata.fromText(
      type: type,
      originalText: originalText,
      compressedText: outboundText,
      sharedPayloadBytes:
          _appSettingsService?.settings.compressionRatioWithSenderName == true
          ? utf8.encode('$senderName: ').length
          : 0,
    );
  }

  MessageCompressionMetadata? _incomingChannelTextCompression(
    String encodedText,
    String decodedText,
    String senderName,
  ) {
    return MessageCompressionMetadata.fromEncodedText(
      encodedText: encodedText,
      decodedText: decodedText,
      sharedPayloadBytes:
          _appSettingsService?.settings.compressionRatioWithSenderName == true
          ? utf8.encode('$senderName: ').length
          : 0,
    );
  }

  MessageCompressionMetadata? _incomingBinaryCompression(
    ChannelBinaryDataInbound decoded,
  ) {
    if (!decoded.wasMcmpCompressed) return null;
    return MessageCompressionMetadata.fromByteLengths(
      type: MessageCompressionType.mcmp,
      originalBytes: ChannelBinaryDataHelper.uncompressedBinaryPayloadLength(
        decoded.text,
        decoded.senderName,
      ),
      compressedBytes: ChannelBinaryDataHelper.finalBinaryPayloadLength(
        decoded.payloadLength,
      ),
    );
  }

  MessageCompressionMetadata? _incomingAppDataCompression(
    ChannelAppDataInbound decoded,
  ) {
    if (!decoded.wasMcmpCompressed || decoded.text == null) return null;
    // MCMP v3 binary envelope: ratio over the compressed text segment only,
    // without envelope and container metadata.
    try {
      return MessageCompressionMetadata.fromByteLengths(
        type: MessageCompressionType.mcmp,
        originalBytes: utf8.encode(decoded.text!).length,
        compressedBytes: McmpAppCodec.compressedTextBytesFromBody(decoded.body),
      );
    } catch (_) {
      return null;
    }
  }

  String _appDataMessageText(ChannelAppDataInbound decoded) {
    return decoded.text ?? MCOImageV3Codec.textFromBody(decoded.body);
  }

  String _channelDisplayName(int channelIndex) {
    for (final channel in _channels) {
      if (channel.index != channelIndex) continue;
      return channel.name.isEmpty ? 'Channel $channelIndex' : channel.name;
    }
    return 'Channel $channelIndex';
  }

  bool _channelMessageMentionsSelf(String text) {
    final name = _selfName?.trim();
    if (name == null || name.isEmpty) return false;
    return RegExp(
      '@\\[\\s*${RegExp.escape(name)}\\s*\\]',
      caseSensitive: false,
    ).hasMatch(text);
  }

  void _maybeNotifyChannelMessage(
    ChannelMessage message, {
    String? channelName,
    TranslationResult? translationResult,
  }) {
    if (message.isOutgoing || _appSettingsService == null) return;
    final channelIndex = message.channelIndex;
    if (channelIndex == null) return;

    final settings = _appSettingsService!.settings;
    if (!settings.notificationsEnabled || !settings.notifyOnNewChannelMessage) {
      return;
    }

    final label = channelName ?? _channelDisplayName(channelIndex);
    final isMuted = _appSettingsService!.isChannelMuted(label);
    if (isMuted && !_channelMessageMentionsSelf(message.text)) return;

    // Reuse translation result only if completed and non-empty; else use original text
    final resolvedText =
        (translationResult != null &&
            translationResult.status == MessageTranslationStatus.completed &&
            translationResult.translatedText.trim().isNotEmpty)
        ? translationResult.translatedText.trim()
        : message.text.trim();
    unawaited(() async {
      await _notificationService.showChannelMessageNotification(
        channelName: label,
        senderName: message.senderName,
        message: resolvedText,
        channelIndex: message.channelIndex,
        badgeCount: getTotalUnreadCount(),
      );
    }());
  }

  void _handleIncomingChannelMessage(Uint8List frame) async {
    // If we're syncing the queued messages, advance the queue immediately
    // before any potentially long async work (like translation/notifications).
    if (_isSyncingQueuedMessages) {
      _handleQueuedMessageReceived();
    }
    final parsed = ChannelMessage.fromFrame(
      frame,
      includeSenderNameInCompressionRatio:
          _appSettingsService?.settings.compressionRatioWithSenderName == true,
    );
    if (parsed != null && parsed.channelIndex != null) {
      final channelName = _channelDisplayName(parsed.channelIndex!);
      if (_shouldDropSelfChannelMessage(
        parsed.senderName,
        parsed.pathBytes,
        channelName: channelName,
      )) {
        return;
      }
      _lastChannelMsgRxTime = parsed.receivedAt;
      final contentHash = _computeContentHash(
        parsed.channelIndex!,
        parsed.timestamp.millisecondsSinceEpoch ~/ 1000,
        '${parsed.senderName}: ${parsed.text}',
      );
      var message = parsed.copyWith(
        packetHash: contentHash,
        // During the initial backlog drain, order text messages by their send
        // time (the packet timestamp); live/incremental deliveries keep the
        // real arrival time.
        receivedAt: _channelMessageReceivedAt(
          parsed.timestamp,
          parsed.receivedAt,
        ),
      );
      final textReplyReference = _resolveChannelReplyAnchor(
        parsed.channelIndex!,
        message.mcmpReplyAuthorName,
        message.mcmpReplyTimestamp,
      );
      if (textReplyReference != null) {
        message = message.copyWith(
          replyToMessageId: textReplyReference.messageId,
          replyToSenderName: textReplyReference.senderName,
          replyToText: textReplyReference.text,
        );
      }
      message = await _verifyInboundChannelMessage(message);
      _updateContactLastMessageAtByName(
        message.senderName,
        message.receivedAt,
        authenticatedSenderKeyHex:
            message.mcmpSignatureStatus == McmpSignatureStatus.valid
            ? message.verifiedSenderKeyHex
            : null,
        pathBytes: message.pathBytes,
        pathHashWidth: message.pathHashWidth,
      );
      final isNew = _addChannelMessage(message.channelIndex!, message);
      _maybeIncrementChannelUnread(message, isNew: isNew);
      notifyListeners();
      if (isNew && !message.isOutgoing) {
        final msg = message; // capture for closure
        unawaited(() async {
          final translationResult = await translateChannelMessage(
            msg.channelIndex!,
            msg,
          );
          _maybeNotifyChannelMessage(msg, translationResult: translationResult);
        }());
      }
      _handleQueuedMessageReceived();
    } else if (_isSyncingQueuedMessages) {
      _handleQueuedMessageReceived();
    }
  }

  void _handleIncomingChannelData(Uint8List frame) async {
    if (_isSyncingQueuedMessages) {
      _handleQueuedMessageReceived();
    }

    final dataFrame = parseChannelDataReceivedFrame(frame);
    if (dataFrame == null) {
      if (_isSyncingQueuedMessages) _handleQueuedMessageReceived();
      return;
    }

    final decoded = ChannelBinaryDataHelper.tryDecodeInbound(
      dataType: dataFrame.dataType,
      payload: dataFrame.payload,
    );
    final appDecoded = decoded == null
        ? ChannelBinaryDataHelper.tryDecodeAppData(
            dataType: dataFrame.dataType,
            payload: dataFrame.payload,
          )
        : null;
    if (decoded == null && appDecoded == null) {
      if (_isSyncingQueuedMessages) _handleQueuedMessageReceived();
      return;
    }
    final appData = appDecoded;

    final channelName = _channelDisplayName(dataFrame.channelIndex);
    final senderName = decoded?.senderName ?? appData!.senderName;
    // In received channel-data frames, raw 0xFF means direct route.
    // The parser maps it to -1; pathLength == 0 is a valid zero-hop flood.
    final isSelfDirect =
        dataFrame.pathLength == -1 &&
        senderName.trim() == (_selfName ?? '').trim();
    if (isSelfDirect && !_isSelfChannelFilterBypassed(channelName)) {
      return;
    }

    final receivedAt = DateTime.now();
    _lastChannelMsgRxTime = receivedAt;
    final contentHash = _computeChannelDataHash(
      dataFrame.channelIndex,
      dataFrame.dataType,
      dataFrame.payload,
    );
    final compression = decoded != null
        ? _incomingBinaryCompression(decoded)
        : _incomingAppDataCompression(appData!);
    final messageText = decoded != null
        ? decoded.text
        : _appDataMessageText(appData!);
    final replyReference = _resolveMcmpReplyReference(
      dataFrame.channelIndex,
      appData?.mcmpMessage,
    );
    final mcmpMessage = appData?.mcmpMessage;
    // During the initial backlog drain, order by send time. MCMP v3 carries a
    // send timestamp in its body; MCOimg / legacy binary datagrams carry none,
    // so those fall back to arrival (delivery) order.
    final mcmpSendSeconds = mcmpMessage?.timestamp;
    final binarySendTime = mcmpSendSeconds != null
        ? DateTime.fromMillisecondsSinceEpoch(mcmpSendSeconds * 1000)
        : receivedAt;
    final storedReceivedAt = _channelMessageReceivedAt(
      binarySendTime,
      receivedAt,
    );
    var message = ChannelMessage(
      senderName: senderName,
      text: messageText,
      wasMcmpCompressed: decoded != null
          ? decoded.wasMcmpCompressed
          : appData!.wasMcmpCompressed,
      compressionType: compression?.type,
      compressionSavingsPercent: compression?.savingsPercent,
      compressionOriginalBytes: compression?.originalBytes,
      compressionPayloadBytes: compression?.payloadBytes,
      mcmpSignatureStatus: decoded != null
          ? decoded.mcmpSignatureStatus
          : appData!.mcmpSignatureStatus,
      mcmpTimestamp: mcmpMessage?.timestamp,
      mcmpSenderName: mcmpMessage?.senderName,
      mcmpIsSigned: mcmpMessage?.isSigned ?? false,
      mcmpSignature: mcmpMessage?.signature,
      mcmpReplyAuthorName: mcmpMessage?.replyAuthorName,
      mcmpReplyTimestamp: mcmpMessage?.replyTimestamp,
      wasBinaryTransport: true,
      binaryPacketBytes: dataFrame.payload.length,
      timestamp: decoded?.timestamp ?? receivedAt,
      receivedAt: storedReceivedAt,
      isOutgoing: false,
      status: ChannelMessageStatus.sent,
      pathLength: dataFrame.pathLength,
      channelIndex: dataFrame.channelIndex,
      packetHash: contentHash,
      replyToMessageId: replyReference?.messageId,
      replyToSenderName: replyReference?.senderName,
      replyToText: replyReference?.text,
    );
    message = await _verifyInboundChannelMessage(message);

    _updateContactLastMessageAtByName(
      message.senderName,
      message.receivedAt,
      authenticatedSenderKeyHex:
          message.mcmpSignatureStatus == McmpSignatureStatus.valid
          ? message.verifiedSenderKeyHex
          : null,
      pathHashWidth: message.pathHashWidth,
    );
    final isNew = _addChannelMessage(dataFrame.channelIndex, message);
    _maybeIncrementChannelUnread(message, isNew: isNew);
    notifyListeners();
    if (isNew && !message.isOutgoing) {
      final msg = message;
      unawaited(() async {
        final translationResult = await translateChannelMessage(
          msg.channelIndex!,
          msg,
        );
        _maybeNotifyChannelMessage(
          msg,
          channelName: channelName,
          translationResult: translationResult,
        );
      }());
    }
    _handleQueuedMessageReceived();
  }

  void _handleLogRxData(Uint8List frame) async {
    if (frame.length < 4) return;
    try {
      final reader = BufferReader(frame);
      reader.skipBytes(3); // Skip header

      final raw = reader.readRemainingBytes();
      final packet = _parseRawPacket(raw);
      if (packet == null ||
          (packet.payloadType != _payloadTypeGroupText &&
              packet.payloadType != _payloadTypeGroupData)) {
        return;
      }

      final payload = BufferReader(packet.payload);
      final channelHash = payload.readByte();
      final encrypted = Uint8List.fromList(payload.readRemainingBytes());

      // Use cached channels as fallback if live channels not yet loaded
      final channelsToSearch = _channels.isNotEmpty
          ? _channels
          : _cachedChannels;
      for (final channel in channelsToSearch) {
        if (channel.isEmpty) continue;
        final hash = _computeChannelHash(channel.psk);
        if (hash != channelHash) continue;
        try {
          final decryptedBytes = _decryptPayload(channel.psk, encrypted);
          if (decryptedBytes == null) return;
          if (packet.payloadType == _payloadTypeGroupData) {
            final packetRegion = _resolvePacketRegion(packet);
            final parsedMessage = _parseLogRxChannelData(
              packet,
              channel.index,
              decryptedBytes,
              packetRegion: packetRegion.region,
              packetRegionInfoAvailable: true,
              packetRegionNotMatched: packetRegion.notMatched,
            );
            if (parsedMessage == null) return;
            final message = await _verifyInboundChannelMessage(parsedMessage);

            _updateContactLastMessageAtByName(
              message.senderName,
              message.receivedAt,
              authenticatedSenderKeyHex:
                  message.mcmpSignatureStatus == McmpSignatureStatus.valid
                  ? message.verifiedSenderKeyHex
                  : null,
              pathBytes: message.pathBytes,
              pathHashWidth: message.pathHashWidth,
            );
            final isNew = _addChannelMessage(channel.index, message);
            _maybeIncrementChannelUnread(message, isNew: isNew);
            notifyListeners();
            if (isNew) {
              unawaited(() async {
                final translationResult = await translateChannelMessage(
                  channel.index,
                  message,
                );
                final label = channel.name.isEmpty
                    ? 'Channel ${channel.index}'
                    : channel.name;
                _maybeNotifyChannelMessage(
                  message,
                  channelName: label,
                  translationResult: translationResult,
                );
              }());
            }
            return;
          }

          if (decryptedBytes.length < 6) return;
          final decrypted = BufferReader(decryptedBytes);

          final timestampRaw = decrypted.readUInt32LE();
          final txtType = decrypted.readByte();
          if ((txtType >> 2) != 0) {
            return;
          }

          final text = decrypted.readCString();
          final parsed = _splitSenderText(text);
          final decoded = MessageTextCodec.tryDecodeKnownCompressionDetails(
            parsed.text,
          );
          final decodedText = decoded?.text ?? parsed.text;
          final compression = _incomingChannelTextCompression(
            parsed.text,
            decodedText,
            parsed.senderName,
          );
          final replyReference = _resolveMcmpReplyReference(
            channel.index,
            decoded?.mcmpMessage,
          );
          final label = channel.name.isEmpty
              ? 'Channel ${channel.index}'
              : channel.name;
          if (_shouldDropSelfChannelMessage(
            parsed.senderName,
            packet.pathBytes,
            channelName: label,
          )) {
            return;
          }

          final contentHash = _computeContentHash(
            channel.index,
            timestampRaw,
            '${parsed.senderName}: $decodedText',
          );

          final logRxMcmpMessage = decoded?.mcmpMessage;
          final packetRegion = _resolvePacketRegion(packet);
          final unverifiedMessage = ChannelMessage(
            senderKey: null,
            senderName: parsed.senderName,
            text: decodedText,
            wasMcmpCompressed: _isMcmpEncodedText(parsed.text),
            compressionType: compression?.type,
            compressionSavingsPercent: compression?.savingsPercent,
            compressionOriginalBytes: compression?.originalBytes,
            compressionPayloadBytes: compression?.payloadBytes,
            mcmpSignatureStatus:
                logRxMcmpMessage?.signatureStatus ?? McmpSignatureStatus.none,
            mcmpTimestamp: logRxMcmpMessage?.timestamp,
            mcmpSenderName: logRxMcmpMessage?.senderName,
            mcmpIsSigned: logRxMcmpMessage?.isSigned ?? false,
            mcmpSignature: logRxMcmpMessage?.signature,
            mcmpReplyAuthorName: logRxMcmpMessage?.replyAuthorName,
            mcmpReplyTimestamp: logRxMcmpMessage?.replyTimestamp,
            timestamp: DateTime.fromMillisecondsSinceEpoch(timestampRaw * 1000),
            isOutgoing: false,
            status: ChannelMessageStatus.sent,
            pathLength: packet.isFlood ? packet.hopCount : 0,
            pathHashWidth: packet.pathHashWidth,
            pathBytes: packet.pathBytes,
            channelIndex: channel.index,
            packetRegion: packetRegion.region,
            packetRegionInfoAvailable: true,
            packetRegionNotMatched: packetRegion.notMatched,
            packetHash: contentHash,
            replyToMessageId: replyReference?.messageId,
            replyToSenderName: replyReference?.senderName,
            replyToText: replyReference?.text,
          );
          final message = await _verifyInboundChannelMessage(unverifiedMessage);

          _updateContactLastMessageAtByName(
            parsed.senderName,
            message.receivedAt,
            authenticatedSenderKeyHex:
                message.mcmpSignatureStatus == McmpSignatureStatus.valid
                ? message.verifiedSenderKeyHex
                : null,
            pathBytes: message.pathBytes,
            pathHashWidth: message.pathHashWidth,
          );
          final isNew = _addChannelMessage(channel.index, message);
          _maybeIncrementChannelUnread(message, isNew: isNew);
          notifyListeners();
          if (isNew) {
            // Run translation + notification asynchronously to avoid blocking
            unawaited(() async {
              final translationResult = await translateChannelMessage(
                channel.index,
                message,
              );
              final label = channel.name.isEmpty
                  ? 'Channel ${channel.index}'
                  : channel.name;
              _maybeNotifyChannelMessage(
                message,
                channelName: label,
                translationResult: translationResult,
              );
            }());
          }
          return;
        } catch (e) {
          appLogger.warn('Decryption failed for channel ${channel.index}: $e');
        }
      }
    } catch (e) {
      appLogger.warn('Error handling log RX data frame: $e');
    }
  }

  ChannelMessage? _parseLogRxChannelData(
    _RawPacket packet,
    int channelIndex,
    Uint8List decryptedBytes, {
    String? packetRegion,
    bool packetRegionInfoAvailable = false,
    bool packetRegionNotMatched = false,
  }) {
    if (decryptedBytes.length < 3) return null;
    final decrypted = BufferReader(decryptedBytes);
    final dataType = decrypted.readByte() | (decrypted.readByte() << 8);
    final dataLength = decrypted.readByte();
    if (dataLength > decrypted.remaining) return null;
    final dataPayload = decrypted.readBytes(dataLength);
    final decoded = ChannelBinaryDataHelper.tryDecodeInbound(
      dataType: dataType,
      payload: dataPayload,
    );
    final appDecoded = decoded == null
        ? ChannelBinaryDataHelper.tryDecodeAppData(
            dataType: dataType,
            payload: dataPayload,
          )
        : null;
    if (decoded == null && appDecoded == null) return null;
    final appData = appDecoded;

    final contentHash = _computeChannelDataHash(
      channelIndex,
      dataType,
      dataPayload,
    );
    final compression = decoded != null
        ? _incomingBinaryCompression(decoded)
        : _incomingAppDataCompression(appData!);
    final senderName = decoded?.senderName ?? appData!.senderName;
    final messageText = decoded != null
        ? decoded.text
        : _appDataMessageText(appData!);
    final timestamp = decoded?.timestamp ?? DateTime.now();
    final replyReference = _resolveMcmpReplyReference(
      channelIndex,
      appData?.mcmpMessage,
    );
    final mcmpMessage = appData?.mcmpMessage;
    return ChannelMessage(
      senderKey: null,
      senderName: senderName,
      text: messageText,
      wasMcmpCompressed: decoded != null
          ? decoded.wasMcmpCompressed
          : appData!.wasMcmpCompressed,
      compressionType: compression?.type,
      compressionSavingsPercent: compression?.savingsPercent,
      compressionOriginalBytes: compression?.originalBytes,
      compressionPayloadBytes: compression?.payloadBytes,
      mcmpSignatureStatus: decoded != null
          ? decoded.mcmpSignatureStatus
          : appData!.mcmpSignatureStatus,
      mcmpTimestamp: mcmpMessage?.timestamp,
      mcmpSenderName: mcmpMessage?.senderName,
      mcmpIsSigned: mcmpMessage?.isSigned ?? false,
      mcmpSignature: mcmpMessage?.signature,
      mcmpReplyAuthorName: mcmpMessage?.replyAuthorName,
      mcmpReplyTimestamp: mcmpMessage?.replyTimestamp,
      wasBinaryTransport: true,
      binaryPacketBytes: dataPayload.length,
      timestamp: timestamp,
      isOutgoing: false,
      status: ChannelMessageStatus.sent,
      pathLength: packet.isFlood ? packet.hopCount : 0,
      pathHashWidth: packet.pathHashWidth,
      pathBytes: packet.pathBytes,
      channelIndex: channelIndex,
      packetRegion: packetRegion,
      packetRegionInfoAvailable: packetRegionInfoAvailable,
      packetRegionNotMatched: packetRegionNotMatched,
      packetHash: contentHash,
      replyToMessageId: replyReference?.messageId,
      replyToSenderName: replyReference?.senderName,
      replyToText: replyReference?.text,
    );
  }

  void _handleMessageSent(Uint8List frame) {
    // Frame format from C++:
    // [0] = RESP_CODE_SENT
    // [1] = is_flood (1 or 0)
    // [2-5] = expected_ack_hash (uint32)
    // [6-9] = estimated_timeout_ms (uint32)

    try {
      final reader = BufferReader(frame);
      reader.skipBytes(2); //Skip code and is_flood
      final ackHash = reader.readUInt32LE();
      final timeoutMs = reader.readUInt32LE();

      // Check if this is a CLI command ACK - if so, ignore it
      if (_lastSentWasCliCommand) {
        final ackHashHex = ackHashToHex(ackHash);
        debugPrint('Ignoring CLI command ACK (sent): $ackHashHex');
        _lastSentWasCliCommand = false;
        return;
      }

      if (_handleRepeaterCommandSent(ackHash, timeoutMs)) {
        return;
      }

      final retryService = _retryService;
      if (retryService != null &&
          retryService.updateMessageFromSent(ackHash, timeoutMs)) {
        return;
      }

      if (_markNextPendingChannelMessageSent()) {
        return;
      }
    } catch (e) {
      appLogger.warn('Error handling message sent frame: $e');
      // Fallback to old behavior
      for (var messages in _conversations.values) {
        for (int i = messages.length - 1; i >= 0; i--) {
          if (messages[i].isOutgoing &&
              messages[i].status == MessageStatus.pending) {
            messages[i] = messages[i].copyWith(status: MessageStatus.sent);
            notifyListeners();
            return;
          }
        }
      }
    }
  }

  bool _markNextPendingChannelMessageSent() {
    while (_pendingChannelSentQueue.isNotEmpty) {
      final queuedMessageId = _pendingChannelSentQueue.removeAt(0);
      if (_isReactionSendQueueId(queuedMessageId)) {
        return true;
      }
      if (_markPendingChannelMessageSentById(queuedMessageId)) {
        return true;
      }
    }
    return false;
  }

  bool _markPendingChannelMessageSentById(String messageId) {
    for (final entry in _channelMessages.entries) {
      final channelMessages = entry.value;
      for (int i = channelMessages.length - 1; i >= 0; i--) {
        final message = channelMessages[i];
        if (message.messageId != messageId) {
          continue;
        }
        if (!message.isOutgoing ||
            message.status != ChannelMessageStatus.pending) {
          return false;
        }
        channelMessages[i] = message.copyWith(
          status: ChannelMessageStatus.sent,
        );
        _retriableChannelMessageSends.remove(messageId);
        _pendingChannelSentQueue.remove(messageId);
        unawaited(
          _channelMessageStore.saveChannelMessages(entry.key, channelMessages),
        );
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  void _markPendingChannelMessageFailedById(String messageId) {
    _retriableChannelMessageSends.remove(messageId);
    for (final entry in _channelMessages.entries) {
      final channelMessages = entry.value;
      for (int i = channelMessages.length - 1; i >= 0; i--) {
        final message = channelMessages[i];
        if (message.messageId != messageId) {
          continue;
        }
        if (!message.isOutgoing ||
            message.status != ChannelMessageStatus.pending) {
          return;
        }
        _cancelChannelNoRetransmissionWarning(messageId);
        channelMessages[i] = message.copyWith(
          status: ChannelMessageStatus.failed,
          noRetransmissionWarningSeconds: null,
        );
        unawaited(
          _channelMessageStore.saveChannelMessages(entry.key, channelMessages),
        );
        notifyListeners();
        return;
      }
    }
  }

  void _handleOk() {
    if (_pendingGenericAckQueue.isEmpty) {
      return;
    }

    final pendingAck = _pendingGenericAckQueue.removeAt(0);
    pendingAck.completer?.complete();
    if ((pendingAck.commandCode != cmdSendChannelTxtMsg &&
            pendingAck.commandCode != cmdSendChannelData) ||
        pendingAck.channelSendQueueId == null) {
      return;
    }

    final queueId = pendingAck.channelSendQueueId!;
    _pendingChannelSentQueue.remove(queueId);
    if (_isReactionSendQueueId(queueId)) {
      return;
    }
    _markPendingChannelMessageSentById(queueId);
  }

  void _handleSendConfirmed(Uint8List frame) {
    // Frame format from C++:
    // [0] = PUSH_CODE_SEND_CONFIRMED
    // [1-4] = ack_hash (uint32)
    // [5-8] = trip_time_ms (uint32)

    try {
      final reader = BufferReader(frame);
      reader.skipBytes(1); // Skip code
      final ackHash = reader.readUInt32LE();
      final tripTimeMs = reader.readUInt32LE();

      // CLI command ACKs are already filtered in _handleMessageSent, so this should only see real messages

      if (_handleRepeaterCommandAck(ackHash, tripTimeMs)) {
        return;
      }

      // Handle ACK in retry service
      if (_retryService != null) {
        _retryService!.handleAckReceived(ackHash, tripTimeMs);
      }
    } catch (e) {
      appLogger.warn('Error handling send confirmed frame: $e');
      // Fallback to old behavior
      for (var messages in _conversations.values) {
        for (int i = messages.length - 1; i >= 0; i--) {
          if (messages[i].isOutgoing &&
              messages[i].status == MessageStatus.sent) {
            messages[i] = messages[i].copyWith(status: MessageStatus.delivered);
            notifyListeners();
            return;
          }
        }
      }
    }
  }

  bool _handleRepeaterCommandSent(int ackHash, int timeoutMs) {
    final ackHashHex = ackHashToHex(ackHash);
    final entry = _pendingRepeaterAcks[ackHashHex];
    if (entry == null) return false;

    entry.timeout?.cancel();
    final effectiveTimeoutMs = timeoutMs > 0
        ? timeoutMs
        : calculateTimeout(
            pathLength: entry.pathLength,
            messageBytes: entry.messageBytes,
          );
    entry.timeout = Timer(Duration(milliseconds: effectiveTimeoutMs), () {
      _recordPathResult(entry.contactKeyHex, entry.selection, false, null);
      _pendingRepeaterAcks.remove(ackHashHex);
    });
    return true;
  }

  bool _handleRepeaterCommandAck(int ackHash, int tripTimeMs) {
    final ackHashHex = ackHashToHex(ackHash);
    final entry = _pendingRepeaterAcks.remove(ackHashHex);
    if (entry == null) return false;
    entry.timeout?.cancel();
    _recordPathResult(entry.contactKeyHex, entry.selection, true, tripTimeMs);
    return true;
  }

  Future<void> _handleChannelInfo(Uint8List frame) async {
    final channel = Channel.fromFrame(frame);
    if (channel == null) return;

    debugPrint(
      '[ChannelSync] Received channel ${channel.index}: ${channel.isEmpty ? "empty" : channel.name}',
    );

    // Preserve unread count from cached channel
    final cachedChannel = _cachedChannels.cast<Channel?>().firstWhere(
      (c) => c?.index == channel.index,
      orElse: () => null,
    );
    if (cachedChannel != null) {
      channel.unreadCount = cachedChannel.unreadCount;
    }

    // If we're syncing and this is the channel we're waiting for
    if (_isSyncingChannels && _channelSyncInFlight) {
      if (channel.index == _nextChannelIndexToRequest) {
        // Expected channel arrived
        _channelSyncTimeout?.cancel();
        _channelSyncInFlight = false;
        _channelSyncRetries = 0; // Reset retry counter on success

        // Only add non-empty channels
        if (!channel.isEmpty) {
          await _applySyncedChannel(channel);
        } else {
          await _applySyncedChannel(channel);
        }

        // Move to next channel
        _nextChannelIndexToRequest++;
        notifyListeners();
        unawaited(_requestNextChannel());
        return;
      } else {
        // Received a channel but not the one we're waiting for
        // This can happen if device sends unsolicited updates
        debugPrint(
          '[ChannelSync] Received unexpected channel ${channel.index}, expected $_nextChannelIndexToRequest',
        );
        // Add it anyway but don't advance sync
        if (!channel.isEmpty &&
            !_channels.any((c) => c.index == channel.index)) {
          await _applySyncedChannel(channel);
        }
        return;
      }
    }

    // Not syncing, or received unsolicited update - handle normally
    await _applySyncedChannel(channel);

    // Only notify if not in loading state
    if (!_isLoadingChannels) {
      _applyChannelOrder();
      notifyListeners();
    }
  }

  Future<void> _applySyncedChannel(Channel channel) async {
    final existingAtIndex = _channels.cast<Channel?>().firstWhere(
      (entry) => entry?.index == channel.index,
      orElse: () => null,
    );
    _channels.removeWhere((entry) => entry.index == channel.index);

    if (channel.isEmpty) {
      _registerChannelStorageBinding(channel);
      _channelMessages.remove(channel.index);
      _channelMcmpEnabled.remove(channel.index);
      _channelMcmpVersion.remove(channel.index);
      _channelMcmpUseSign.remove(channel.index);
      _channelSmazEnabled.remove(channel.index);
      _channelCyr2LatEnabled.remove(channel.index);
      _channelCyr2LatProfileId.remove(channel.index);
      _channelSendingDelayEnabled.remove(channel.index);
      _channelQuickAnswerIds.remove(channel.index);
      _channelWidgetColor.remove(channel.index);
      _channelWidgetTextColor.remove(channel.index);
      _channelRegions.remove(channel.index);
      return;
    }

    final cachedByName = _previousChannelsCache.cast<Channel?>().firstWhere(
      (entry) => entry?.name == channel.name,
      orElse: () => null,
    );
    channel.unreadCount =
        cachedByName?.unreadCount ??
        existingAtIndex?.unreadCount ??
        channel.unreadCount;
    _channels.add(channel);
    _registerChannelStorageBinding(channel);

    await _loadChannelSettingsForIndex(channel.index);
    _channelMessages.remove(channel.index);
    await _loadChannelMessages(channel.index, notify: false);
  }

  void _applyChannelOrder() {
    if (_channelOrder.isEmpty) {
      _channels.sort((a, b) => a.index.compareTo(b.index));
      return;
    }

    final orderIndex = <int, int>{};
    for (int i = 0; i < _channelOrder.length; i++) {
      orderIndex[_channelOrder[i]] = i;
    }

    _channels.sort((a, b) {
      final aPos = orderIndex[a.index];
      final bPos = orderIndex[b.index];
      if (aPos != null && bPos != null) return aPos.compareTo(bPos);
      if (aPos != null) return -1;
      if (bPos != null) return 1;
      return a.index.compareTo(b.index);
    });
  }

  Future<void> setChannelOrder(List<int> order) async {
    _channelOrder = List<int>.from(order);
    _applyChannelOrder();
    notifyListeners();
    await _channelOrderStore.saveChannelOrder(_channelOrder);
  }

  bool _shouldTrackUnreadForContactKey(String contactKeyHex) {
    final contact = _contacts.cast<Contact?>().firstWhere(
      (c) => c?.publicKeyHex == contactKeyHex,
      orElse: () => null,
    );
    if (contact == null) return true;
    return contact.type != advTypeRepeater;
  }

  Channel? _findChannelByIndex(int index) {
    return _channels.cast<Channel?>().firstWhere(
          (c) => c?.index == index,
          orElse: () => null,
        ) ??
        _cachedChannels.cast<Channel?>().firstWhere(
          (c) => c?.index == index,
          orElse: () => null,
        );
  }

  void _maybeIncrementChannelUnread(
    ChannelMessage message, {
    required bool isNew,
  }) {
    if (!isNew || message.isOutgoing) {
      _appDebugLogService?.info(
        'Skip unread increment: isNew=$isNew, isOutgoing=${message.isOutgoing}',
        tag: 'Unread',
      );
      return;
    }
    final channelIndex = message.channelIndex;
    if (channelIndex == null) {
      _appDebugLogService?.info(
        'Skip unread increment: channelIndex is null',
        tag: 'Unread',
      );
      return;
    }
    // Don't increment if user is viewing this channel
    if (_activeChannelIndex == channelIndex) {
      _appDebugLogService?.info(
        'Skip unread increment: channel $channelIndex is active',
        tag: 'Unread',
      );
      return;
    }

    final channel = _findChannelByIndex(channelIndex);
    if (channel != null) {
      channel.unreadCount++;
      _cachedChannelsUnreadTotal++;
      _appDebugLogService?.info(
        'Channel ${channel.name.isNotEmpty ? channel.name : channelIndex} unread count incremented to ${channel.unreadCount}',
        tag: 'Unread',
      );
      unawaited(
        _channelStore.saveChannels(
          _channels.isNotEmpty ? _channels : _cachedChannels,
        ),
      );
    } else {
      _appDebugLogService?.info(
        'Channel $channelIndex not found in _channels (${_channels.length}) or _cachedChannels (${_cachedChannels.length})',
        tag: 'Unread',
      );
    }
  }

  void _maybeIncrementContactUnread(Message message) {
    if (message.isOutgoing || message.isCli) {
      _appDebugLogService?.info(
        'Skip contact unread increment: isOutgoing=${message.isOutgoing}, isCli=${message.isCli}',
        tag: 'Unread',
      );
      return;
    }
    final contactKey = message.senderKeyHex;
    if (!_shouldTrackUnreadForContactKey(contactKey)) {
      _appDebugLogService?.info(
        'Skip contact unread increment: should not track for $contactKey',
        tag: 'Unread',
      );
      return;
    }
    // Don't increment if user is viewing this contact
    if (_activeContactKey == contactKey) {
      _appDebugLogService?.info(
        'Skip contact unread increment: contact $contactKey is active',
        tag: 'Unread',
      );
      return;
    }

    final currentCount = _contactUnreadCount[contactKey] ?? 0;
    _contactUnreadCount[contactKey] = currentCount + 1;
    _cachedContactsUnreadTotal++;
    _appDebugLogService?.info(
      'Contact $contactKey unread count incremented to ${currentCount + 1}',
      tag: 'Unread',
    );
    _unreadStore.saveContactUnreadCount(
      Map<String, int>.from(_contactUnreadCount),
    );
  }

  void _addMessage(String pubKeyHex, Message message) {
    if (!message.isCli) {
      _updateContactLastMessageAt(
        pubKeyHex,
        message.isOutgoing ? message.timestamp : DateTime.now(),
      );
    }
    _conversations.putIfAbsent(pubKeyHex, () => []);
    final messages = _conversations[pubKeyHex]!;

    // Parse reaction info
    final reactionInfo = Message.parseReaction(message.text);
    if (reactionInfo != null) {
      // Check if we've already processed this exact reaction
      _processedContactReactions.putIfAbsent(pubKeyHex, () => {});
      final reactionIdentifier =
          '${reactionInfo.targetHash}_${reactionInfo.emoji}';

      final isDuplicate = _processedContactReactions[pubKeyHex]!.contains(
        reactionIdentifier,
      );

      if (!isDuplicate) {
        // New reaction - process it
        _processContactReaction(messages, reactionInfo, pubKeyHex);
        _messageStore.saveMessages(pubKeyHex, messages);

        // Mark as processed
        _processedContactReactions[pubKeyHex]!.add(reactionIdentifier);

        notifyListeners();
      }
      return; // Don't add reaction as a visible message
    }

    messages.add(message);
    if (messages.length > _messageWindowSize) {
      messages.removeRange(0, messages.length - _messageWindowSize);
    }
    _messageStore.saveMessages(pubKeyHex, messages);
    notifyListeners();
  }

  void _processContactReaction(
    List<Message> messages,
    ReactionInfo reactionInfo,
    String contactPubKeyHex,
  ) {
    final contact = _contacts.cast<Contact?>().firstWhere(
      (c) => c?.publicKeyHex == contactPubKeyHex,
      orElse: () => null,
    );
    final isRoomServer = contact?.type == advTypeRoom;

    ReactionHelper.applyReaction<Message>(
      messages: messages,
      reactionInfo: reactionInfo,
      // Incoming reactions in 1:1: match against outgoing messages only
      shouldSkip: (msg) => isRoomServer != true && !msg.isOutgoing,
      getTimestampSecs: (msg) => msg.timestamp.millisecondsSinceEpoch ~/ 1000,
      getSenderName: (msg) =>
          _resolveContactSenderName(msg, contact, isRoomServer == true),
      getMessageText: (msg) => msg.text,
      getReactions: (msg) => msg.reactions,
      updateMessage: (i, reactions) {
        messages[i] = messages[i].copyWith(reactions: reactions);
      },
    );
  }

  void _processOutgoingContactReaction(
    List<Message> messages,
    ReactionInfo reactionInfo,
    Contact contact,
  ) {
    final isRoomServer = contact.type == advTypeRoom;

    ReactionHelper.applyReaction<Message>(
      messages: messages,
      reactionInfo: reactionInfo,
      // Outgoing reactions in 1:1: match against incoming messages
      shouldSkip: (msg) => !isRoomServer && msg.isOutgoing,
      getTimestampSecs: (msg) => msg.timestamp.millisecondsSinceEpoch ~/ 1000,
      getSenderName: (msg) =>
          _resolveContactSenderName(msg, contact, isRoomServer),
      getMessageText: (msg) => msg.text,
      getReactions: (msg) => msg.reactions,
      updateMessage: (i, reactions) {
        messages[i] = messages[i].copyWith(reactions: reactions);
      },
    );
  }

  void _setReactionStatus(
    String pubKeyHex,
    ReactionInfo reactionInfo,
    MessageStatus status,
  ) {
    final messages = _conversations[pubKeyHex];
    if (messages == null) return;
    final contact = _contacts.cast<Contact?>().firstWhere(
      (c) => c?.publicKeyHex == pubKeyHex,
      orElse: () => null,
    );
    final isRoomServer = contact?.type == advTypeRoom;
    for (int i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];
      final timestampSecs = msg.timestamp.millisecondsSinceEpoch ~/ 1000;
      final msgHash = ReactionHelper.computeReactionHash(
        timestampSecs,
        _resolveContactSenderName(msg, contact, isRoomServer == true),
        msg.text,
      );
      if (msgHash == reactionInfo.targetHash) {
        final statuses = Map<String, MessageStatus>.from(msg.reactionStatuses);
        statuses[reactionInfo.emoji] = status;
        messages[i] = msg.copyWith(reactionStatuses: statuses);
        break;
      }
    }
  }

  String? _resolveContactSenderName(
    Message msg,
    Contact? contact,
    bool isRoomServer,
  ) {
    if (!isRoomServer) return null;
    if (!msg.isOutgoing) {
      // Saved contacts first, then discovery-only nodes, so reaction matching
      // resolves the author's name even when they haven't been saved.
      final senderContact = allContactsUnfiltered.cast<Contact?>().firstWhere(
        (c) =>
            c != null &&
            _matchesPrefix(c.publicKey, msg.fourByteRoomContactKey),
        orElse: () => null,
      );
      return senderContact?.name;
    }
    return selfName;
  }

  _RawPacket? _parseRawPacket(Uint8List raw) {
    try {
      final reader = BufferReader(raw);
      final header = reader.readByte();
      final routeType = header & _phRouteMask;
      final hasTransport =
          routeType == _routeTransportFlood ||
          routeType == _routeTransportDirect;
      int? transportCode1;
      if (hasTransport) {
        transportCode1 = reader.readUInt16LE();
        reader.skipBytes(2); // transport_code_2 is reserved for now.
      }
      final pathLenRaw = reader.readByte();
      final pathByteLen = _decodePathByteLen(pathLenRaw);
      final pathBytes = reader.readBytes(pathByteLen);
      final payload = reader.readBytes(reader.remaining);

      return _RawPacket(
        header: header,
        routeType: routeType,
        payloadType: (header >> _phTypeShift) & _phTypeMask,
        payloadVer: (header >> _phVerShift) & _phVerMask,
        transportCode1: transportCode1,
        pathLenRaw: pathLenRaw,
        pathBytes: pathBytes,
        payload: payload,
      );
    } catch (e) {
      appLogger.warn('Error parsing raw packet: $e');
      return null;
    }
  }

  int _computeChannelHash(Uint8List psk) {
    final digest = crypto.sha256.convert(psk).bytes;
    return digest[0];
  }

  _PacketRegionResolution _resolvePacketRegion(_RawPacket packet) {
    final transportCode = packet.transportCode1;
    if (transportCode == null || transportCode == 0) {
      return const _PacketRegionResolution();
    }

    for (final region in RegionStore().loadRegions()) {
      final normalized = region.trim();
      if (normalized.isEmpty || normalized.startsWith(r'$')) continue;
      final regionTransportCode = _computeRegionTransportCode(
        normalized,
        packet.payloadType,
        packet.payload,
      );
      if (regionTransportCode == transportCode) {
        return _PacketRegionResolution(
          region: _displayPacketRegion(normalized),
        );
      }
    }
    return const _PacketRegionResolution(notMatched: true);
  }

  String? _displayPacketRegion(String region) {
    final normalized = region.trim();
    if (normalized.isEmpty) return null;
    return normalized.startsWith('#') ? normalized.substring(1) : normalized;
  }

  int _computeRegionTransportCode(
    String region,
    int payloadType,
    Uint8List payload,
  ) {
    final name = region.startsWith('#') ? region : '#$region';
    final regionKey = crypto.sha256
        .convert(utf8.encode(name))
        .bytes
        .sublist(0, 16);
    final input = Uint8List(1 + payload.length);
    input[0] = payloadType;
    input.setRange(1, input.length, payload);
    final digest = crypto.Hmac(crypto.sha256, regionKey).convert(input).bytes;
    var code = digest[0] | (digest[1] << 8);
    if (code == 0) {
      code = 1;
    } else if (code == 0xFFFF) {
      code = 0xFFFE;
    }
    return code;
  }

  /// Content-based dedup hash for sync queue messages (no raw payload available).
  /// Prefixed with 'c:' to avoid collisions with packet hashes.
  String _computeContentHash(
    int channelIdx,
    int timestampSecs,
    String fullText,
  ) {
    final textBytes = utf8.encode(fullText);
    final input = Uint8List(5 + textBytes.length);
    input[0] = channelIdx;
    input[1] = timestampSecs & 0xFF;
    input[2] = (timestampSecs >> 8) & 0xFF;
    input[3] = (timestampSecs >> 16) & 0xFF;
    input[4] = (timestampSecs >> 24) & 0xFF;
    input.setRange(5, 5 + textBytes.length, textBytes);
    final digest = crypto.sha256.convert(input).bytes;
    return 'c:${digest.sublist(0, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  /// Binary channel data has no protocol timestamp, so deduplicate repeats by
  /// the received channel, data type, and raw payload.
  String _computeChannelDataHash(
    int channelIdx,
    int dataType,
    Uint8List payload,
  ) {
    final input = Uint8List(3 + payload.length);
    input[0] = channelIdx;
    input[1] = dataType & 0xFF;
    input[2] = (dataType >> 8) & 0xFF;
    input.setRange(3, input.length, payload);
    final digest = crypto.sha256.convert(input).bytes;
    return 'd:${digest.sublist(0, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  Uint8List? _decryptPayload(Uint8List psk, Uint8List encrypted) {
    if (encrypted.length <= _cipherMacSize) return null;
    final mac = encrypted.sublist(0, _cipherMacSize);
    final cipherText = encrypted.sublist(_cipherMacSize);

    final key32 = Uint8List(32);
    final copyLen = psk.length < 32 ? psk.length : 32;
    key32.setRange(0, copyLen, psk);

    final hmac = crypto.Hmac(crypto.sha256, key32).convert(cipherText).bytes;
    if (hmac[0] != mac[0] || hmac[1] != mac[1]) {
      return null;
    }

    if (cipherText.isEmpty || cipherText.length % 16 != 0) return null;
    final key16 = Uint8List(16);
    final keyLen = psk.length < 16 ? psk.length : 16;
    key16.setRange(0, keyLen, psk);

    final cipher = ECBBlockCipher(AESEngine());
    cipher.init(false, KeyParameter(key16));
    final out = Uint8List(cipherText.length);
    for (var i = 0; i < cipherText.length; i += 16) {
      cipher.processBlock(cipherText, i, out, i);
    }
    return out;
  }

  _ParsedText _splitSenderText(String text) {
    final colonIndex = text.indexOf(':');
    if (colonIndex > 0 && colonIndex < text.length - 1 && colonIndex < 50) {
      final potentialSender = text.substring(0, colonIndex);
      if (RegExp(r'[:\[\]]').hasMatch(potentialSender)) {
        return _ParsedText(senderName: 'Unknown', text: text);
      }
      final offset =
          (colonIndex + 1 < text.length && text[colonIndex + 1] == ' ')
          ? colonIndex + 2
          : colonIndex + 1;
      return _ParsedText(
        senderName: potentialSender,
        text: text.substring(offset),
      );
    }
    return _ParsedText(senderName: 'Unknown', text: text);
  }

  bool _addChannelMessage(int channelIndex, ChannelMessage message) {
    _channelMessages.putIfAbsent(channelIndex, () => []);
    final messages = _channelMessages[channelIndex]!;

    // Parse reaction info
    final reactionInfo = ChannelMessage.parseReaction(message.text);
    if (reactionInfo != null) {
      // Check if we've already processed this exact reaction
      _processedChannelReactions.putIfAbsent(channelIndex, () => {});
      final reactionIdentifier =
          '${reactionInfo.targetHash}_${reactionInfo.emoji}';

      final isDuplicate = _processedChannelReactions[channelIndex]!.contains(
        reactionIdentifier,
      );

      if (!isDuplicate) {
        // New reaction - process it
        _processReaction(messages, reactionInfo);
        // Save updated messages
        _channelMessageStore.saveChannelMessages(channelIndex, messages);

        // Mark as processed
        _processedChannelReactions[channelIndex]!.add(reactionIdentifier);
      }
      return false; // Don't add reaction as a visible message
    }

    // Parse reply info from message text
    final replyInfo = ChannelMessage.parseReplyMention(message.text);
    ChannelMessage processedMessage = message;

    if (replyInfo != null) {
      var replyToMessageId = message.replyToMessageId;
      var replyToSenderName = message.replyToSenderName;
      var replyToText = message.replyToText;

      if ((replyToSenderName == null || replyToText == null) &&
          message.mcmpReplyTimestamp == null) {
        // Fallback for incoming/legacy messages where only the @mention
        // exists. Messages with an MCMP reply anchor must never fall back to
        // "most recent from this sender": if the anchor did not resolve, a
        // name-only reply banner is more honest than a wrong quote.
        final originalMessage = _findMessageBySender(
          messages,
          replyInfo.mentionedNode,
        );
        if (originalMessage != null) {
          replyToMessageId ??= originalMessage.messageId;
          replyToSenderName ??= originalMessage.senderName;
          replyToText ??= originalMessage.text;
        }
      }

      // Create new message with reply metadata
      processedMessage = ChannelMessage(
        senderKey: message.senderKey,
        senderName: message.senderName,
        text: replyInfo.actualMessage,
        originalText: message.originalText,
        translatedText: message.translatedText,
        translatedLanguageCode: message.translatedLanguageCode,
        translationStatus: message.translationStatus,
        translationModelId: message.translationModelId,
        wasMcmpCompressed: message.wasMcmpCompressed,
        compressionType: message.compressionType,
        compressionSavingsPercent: message.compressionSavingsPercent,
        compressionOriginalBytes: message.compressionOriginalBytes,
        compressionPayloadBytes: message.compressionPayloadBytes,
        mcmpSignatureStatus: message.mcmpSignatureStatus,
        mcmpTimestamp: message.mcmpTimestamp,
        mcmpSenderName: message.mcmpSenderName,
        mcmpIsSigned: message.mcmpIsSigned,
        mcmpSignature: message.mcmpSignature,
        mcmpReplyAuthorName: message.mcmpReplyAuthorName,
        mcmpReplyTimestamp: message.mcmpReplyTimestamp,
        verifiedSenderKeyHex: message.verifiedSenderKeyHex,
        mcmpNameCollision: message.mcmpNameCollision,
        wasBinaryTransport: message.wasBinaryTransport,
        binaryPacketBytes: message.binaryPacketBytes,
        timestamp: message.timestamp,
        receivedAt: message.receivedAt,
        sentByRadioAt: message.sentByRadioAt,
        isOutgoing: message.isOutgoing,
        status: message.status,
        repeats: message.repeats,
        repeatCount: message.repeatCount,
        pathLength: message.pathLength,
        pathHashWidth: message.pathHashWidth,
        pathBytes: message.pathBytes,
        pathVariants: message.pathVariants,
        channelIndex: message.channelIndex,
        packetRegion: message.packetRegion,
        packetRegionInfoAvailable: message.packetRegionInfoAvailable,
        packetRegionNotMatched: message.packetRegionNotMatched,
        noRetransmissionWarningSeconds: message.noRetransmissionWarningSeconds,
        messageId: message.messageId,
        packetHash: message.packetHash,
        replyToMessageId: replyToMessageId,
        replyToSenderName: replyToSenderName ?? replyInfo.mentionedNode,
        replyToText: replyToText,
        reactions: message.reactions,
      );
    }

    final existingIndex = _findChannelRepeatIndex(messages, processedMessage);
    var isNew = true;
    if (existingIndex >= 0) {
      isNew = false;
      final existing = messages[existingIndex];
      final mergedPathBytes = _selectPreferredPathBytes(
        existing.pathBytes,
        processedMessage.pathBytes,
      );
      final mergedPathVariants = _mergePathVariants(
        existing.pathVariants,
        processedMessage.pathVariants,
      );
      final mergedPathLength = _mergePathLength(
        existing.pathLength,
        processedMessage.pathLength,
        mergedPathBytes.length,
      );
      final newRepeatCount = existing.repeatCount + 1;
      final promotedFromPending =
          newRepeatCount == 1 &&
          existing.status == ChannelMessageStatus.pending;
      _cancelChannelNoRetransmissionWarning(existing.messageId);
      messages[existingIndex] = existing.copyWith(
        repeatCount: newRepeatCount,
        pathLength: mergedPathLength,
        pathHashWidth: existing.pathHashWidth ?? processedMessage.pathHashWidth,
        pathBytes: mergedPathBytes,
        pathVariants: mergedPathVariants,
        packetRegion: existing.packetRegion ?? processedMessage.packetRegion,
        packetRegionInfoAvailable:
            existing.packetRegionInfoAvailable ||
            processedMessage.packetRegionInfoAvailable,
        packetRegionNotMatched:
            existing.packetRegionNotMatched ||
            processedMessage.packetRegionNotMatched,
        packetHash: existing.packetHash ?? processedMessage.packetHash,
        // Mark as sent when first repeat is heard
        status: promotedFromPending
            ? ChannelMessageStatus.sent
            : existing.status,
        noRetransmissionWarningSeconds: null,
      );
      if (promotedFromPending) {
        _retriableChannelMessageSends.remove(existing.messageId);
        _pendingChannelSentQueue.remove(existing.messageId);
      }
    } else {
      messages.add(processedMessage);
    }

    final orderMessages = _isSyncingQueuedMessages;
    if (orderMessages) {
      messages.sort(_compareChannelMessages);
    }

    // Save to persistent storage
    _channelMessageStore.saveChannelMessages(
      channelIndex,
      messages,
      orderMessages: orderMessages,
    );
    return isNew;
  }

  ChannelMessage? _findMessageBySender(
    List<ChannelMessage> messages,
    String mentionedNode,
  ) {
    // Search backwards for most recent message from this sender
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].senderName == mentionedNode) {
        return messages[i];
      }
    }
    return null;
  }

  void _processReaction(
    List<ChannelMessage> messages,
    ReactionInfo reactionInfo,
  ) {
    ReactionHelper.applyReaction<ChannelMessage>(
      messages: messages,
      reactionInfo: reactionInfo,
      shouldSkip: (_) => false,
      getTimestampSecs: (msg) => msg.timestamp.millisecondsSinceEpoch ~/ 1000,
      getSenderName: (msg) => msg.senderName,
      getMessageText: (msg) => msg.text,
      getReactions: (msg) => msg.reactions,
      updateMessage: (i, reactions) {
        messages[i] = messages[i].copyWith(reactions: reactions);
        notifyListeners();
      },
    );
  }

  int _findChannelRepeatIndex(
    List<ChannelMessage> messages,
    ChannelMessage incoming,
  ) {
    // Binary channel-data messages have no protocol timestamp. Outgoing
    // messages store the hash of the exact payload submitted to the radio, so
    // a returned flood copy should match here before any heuristic checks.
    final incomingHash = incoming.packetHash;
    if (incomingHash != null) {
      for (int i = messages.length - 1; i >= 0; i--) {
        final existingHash = messages[i].packetHash;
        if (existingHash != null && existingHash == incomingHash) {
          return i;
        }
      }
    }

    // Fallback for text messages and older stored messages without a hash.
    for (int i = messages.length - 1; i >= 0; i--) {
      if (_isChannelRepeat(messages[i], incoming)) {
        return i;
      }
    }
    return -1;
  }

  bool _isChannelRepeat(ChannelMessage existing, ChannelMessage incoming) {
    if (existing.text != incoming.text) return false;
    if (existing.isOutgoing && incoming.isOutgoing) {
      return false; // manual resend workaround
    }

    // Self-echo: an outgoing message coming back via a repeater. The send is
    // delayed by _waitForRadioQuiet (often 10s+) and propagation can add more,
    // so the timestamp gap can easily exceed the cross-peer window.
    final selfName = _selfName ?? 'Me';
    final isSelfEcho =
        existing.isOutgoing &&
        !incoming.isOutgoing &&
        (incoming.senderName == selfName && existing.senderName == selfName);

    // This repeat detector intentionally does not use
    // AppSettings.defaultChannelResendTimeoutSeconds: manual resend delay and
    // radio self-echo deduplication are separate timing concerns.
    final windowMs = isSelfEcho ? 10 * 60 * 1000 : 30000;
    final existingRepeatAnchor = existing.sentByRadioAt ?? existing.timestamp;
    final diffMs =
        (existingRepeatAnchor.millisecondsSinceEpoch -
                incoming.timestamp.millisecondsSinceEpoch)
            .abs();
    if (diffMs > windowMs) return false;

    if (existing.senderName == incoming.senderName) return true;
    if (isSelfEcho) return true;

    return false;
  }

  bool _shouldDropSelfChannelMessage(
    String senderName,
    Uint8List pathBytes, {
    String? channelName,
  }) {
    final trimmed = senderName.trim();
    if (trimmed.isEmpty) return false;

    final selfName = _selfName?.trim();
    if (selfName == null || selfName.isEmpty) return false;

    // If sender name doesn't match, keep the message
    if (trimmed != selfName) return false;

    // Name matches - this is from self
    if (_isSelfChannelFilterBypassed(channelName)) return false;

    // Drop only if pathBytes is empty (direct broadcast)
    // Keep if pathBytes has data (repeated through another node)
    return pathBytes.isEmpty;
  }

  bool _isSelfChannelFilterBypassed(String? channelName) {
    return _isChannelListedInDoNotFilterSetting(channelName);
  }

  bool _isChannelAckAndRetryBypassed(String? channelName) {
    return _isChannelListedInDoNotFilterSetting(channelName);
  }

  bool _isChannelListedInDoNotFilterSetting(String? channelName) {
    final normalizedChannelName = channelName?.trim();
    if (normalizedChannelName == null || normalizedChannelName.isEmpty) {
      return false;
    }

    final settings = _appSettingsService?.settings;
    if (settings == null) return false;

    return settings.doNotFilterMessagesOnChannels
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .contains(normalizedChannelName);
  }

  Uint8List _selectPreferredPathBytes(Uint8List existing, Uint8List incoming) {
    if (incoming.isEmpty) return existing;
    if (existing.isEmpty) return incoming;
    if (incoming.length > existing.length) return incoming;
    return existing;
  }

  int? _mergePathLength(int? existing, int? incoming, int observedLength) {
    if (existing == null) {
      if (incoming == null) return observedLength > 0 ? observedLength : null;
      return incoming >= observedLength ? incoming : observedLength;
    }
    if (incoming == null) {
      return existing >= observedLength ? existing : observedLength;
    }
    final merged = existing >= incoming ? existing : incoming;
    return merged >= observedLength ? merged : observedLength;
  }

  List<Uint8List> _mergePathVariants(
    List<Uint8List> existing,
    List<Uint8List> incoming,
  ) {
    if (incoming.isEmpty) return existing;
    if (existing.isEmpty) return incoming;

    final merged = <Uint8List>[...existing];
    for (final candidate in incoming) {
      var already = false;
      for (final current in merged) {
        if (_pathsEqual(current, candidate)) {
          already = true;
          break;
        }
      }
      if (!already && candidate.isNotEmpty) {
        merged.add(candidate);
      }
    }
    return merged;
  }

  bool _pathsEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _handleDisconnection() {
    _isRecoveringConnection = _shouldAutoReconnect;
    if (_isRecoveringConnection) {
      unawaited(_backgroundService?.setConnectionLost(true));
    }
    _shouldReplayRetriableChannelMessageSends =
        _isRecoveringConnection && _retriableChannelMessageSends.isNotEmpty;
    pausePendingOutgoingMessages();
    _stopBatteryPolling();
    _stopGpsLocationPolling();
    _stopRadioStatsPolling();
    _stopRxWatchdog();
    _southFrameFragmentReassembler.clear();
    _southQueuedFragmentAckTracker.clear();
    _latestRadioStats = null;
    radioStatsNotifier.value = null;
    _prevTotalAirSecs = 0;
    _airtimeBumpStopwatch?.stop();
    _airtimeBumpStopwatch = null;

    for (final entry in _pendingRepeaterAcks.values) {
      entry.timeout?.cancel();
    }
    _pendingRepeaterAcks.clear();

    _notifySubscription?.cancel();
    _notifySubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;

    _device = null;
    _rxCharacteristic = null;
    _txCharacteristic = null;
    // Preserve deviceId and displayName for UI display during reconnection
    // They're only cleared on manual disconnect via disconnect() method
    _hasReceivedDeviceInfo = false;
    // Device capability flags must not leak into the next connection; they
    // are re-fetched with custom vars during the replacement handshake.
    _currentCustomVars = null;
    _settingsSectionsService?.setDeviceRawVars(null);
    _settingsSectionsService?.setActiveDeviceKey(null);
    // Handshake flags must not survive an unexpected drop: a stale
    // _awaitingSelfInfo makes _requestDeviceInfo a no-op on the next connect,
    // and a stale CLI flag swallows the next real RESP_CODE_SENT.
    _awaitingSelfInfo = false;
    _hasCompletedSelfInfoHandshake = false;
    _selfInfoRetryTimer?.cancel();
    _selfInfoRetryTimer = null;
    _lastSentWasCliCommand = false;
    _maxContacts = _defaultMaxContacts;
    _maxChannels = _defaultMaxChannels;
    _resetSyncProgressState();
    _cancelAllChannelNoRetransmissionTimers();
    _pendingChannelSentQueue.clear();
    _pendingGenericAckQueue.clear();
    // Keep pending and already-started channel sends across an unexpected BLE
    // drop. They are replayed only after the replacement session is ready.
    _reactionSendQueueSequence = 0;

    _setState(MeshCoreConnectionState.disconnected);
    _scheduleReconnect();
  }

  _PendingCommandAck? _trackPendingGenericAck(
    Uint8List data, {
    String? channelSendQueueId,
    required bool expectsGenericAck,
    required bool waitForAck,
  }) {
    if (!expectsGenericAck || data.isEmpty) return null;
    final pendingAck = _PendingCommandAck(
      commandCode: data[0],
      channelSendQueueId: channelSendQueueId,
      completer: waitForAck ? Completer<void>() : null,
    );
    if (pendingAck.completer != null) {
      // sendFrame awaits this future after transport I/O; attach an error
      // handler immediately in case USB returns an error response first.
      unawaited(pendingAck.completer!.future.catchError((_) {}));
    }
    _pendingGenericAckQueue.add(pendingAck);
    return pendingAck;
  }

  String _nextReactionSendQueueId() {
    _reactionSendQueueSequence++;
    return '$_reactionSendQueuePrefix$_reactionSendQueueSequence';
  }

  bool _isReactionSendQueueId(String queueId) {
    return queueId.startsWith(_reactionSendQueuePrefix);
  }

  Map<String, String> _parseKeyValueString(String input) {
    final result = <String, String>{};

    // Split on commas first – empty entries are ignored.
    for (final pair in input.split(',')) {
      final trimmedPair = pair.trim();
      if (trimmedPair.isEmpty) continue;

      // Each pair must contain exactly one ':'.
      final separatorIndex = trimmedPair.indexOf(':');
      if (separatorIndex == -1) continue; // malformed, skip

      final key = trimmedPair.substring(0, separatorIndex).trim();
      final value = trimmedPair.substring(separatorIndex + 1).trim();

      if (key.isNotEmpty) {
        result[key] = value;
      }
    }

    return result;
  }

  /// Parse PUSH_CODE_LOGIN_SUCCESS (0x85) frame and stash the repeater's
  /// reported clock. Frame layout (firmware companion_radio/MyMesh.cpp:678+):
  ///   [0]=0x85, [1]=permissions, [2..7]=pubkey prefix (6 bytes),
  ///   [8..11]=repeater RTC unix seconds (LE), [12]=ACL perms, [13]=fw level
  /// The timestamp is only present in the v7+ "new login response" — older
  /// firmware emits a shorter frame that we silently skip.
  void _handleLoginSuccess(Uint8List frame) {
    if (frame.length < 12) return;
    final prefix = pubKeyToHex(frame.sublist(2, 8));
    final ts = ByteData.sublistView(frame, 8, 12).getUint32(0, Endian.little);
    if (ts == 0) return;
    _repeaterLoginClocks[prefix] = DateTime.fromMillisecondsSinceEpoch(
      ts * 1000,
      isUtc: true,
    );
    notifyListeners();
  }

  void _handleCustomVars(Uint8List frame) {
    final buf = BufferReader(frame.sublist(1));
    try {
      final rawVars = buf.readCString();
      _currentCustomVars = _parseKeyValueString(rawVars);
      _settingsSectionsService?.setDeviceRawVars(
        _currentCustomVars,
        raw: rawVars,
      );
      // Reflect current GPS state in the polling timer (handles initial
      // device state on connect as well as external CLI/USB toggles).
      if (_currentCustomVars?['gps'] == '1') {
        _startGpsLocationPolling();
      } else {
        _stopGpsLocationPolling();
      }
    } catch (e) {
      appLogger.warn('Malformed custom vars frame: $e', tag: 'Connector');
    }
  }

  void _setState(MeshCoreConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      if (newState == MeshCoreConnectionState.connected) {
        _isRecoveringConnection = false;
        unawaited(_transportPreferenceStore.save(_activeTransport.name));
      }
      notifyListeners();
    }
  }

  void markNotifyDirty() {
    if (_notifyListenersDirty && _notifyListenersTimer != null) {
      return;
    }

    _notifyListenersDirty = true;
    _notifyListenersTimer ??= Timer(
      _notifyListenersDebounce,
      _flushBatchedNotify,
    );
  }

  void _flushBatchedNotify() {
    _notifyListenersTimer = null;
    if (!_notifyListenersDirty) {
      return;
    }

    _notifyListenersDirty = false;
    super.notifyListeners();

    if (_notifyListenersDirty && _notifyListenersTimer == null) {
      _notifyListenersTimer = Timer(
        _notifyListenersDebounce,
        _flushBatchedNotify,
      );
    }
  }

  @override
  void notifyListeners() {
    markNotifyDirty();
  }

  @override
  void dispose() {
    _appSettingsService?.removeListener(_handleAppSettingsChanged);
    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _connectionSubscription?.cancel();
    _usbFrameSubscription?.cancel();
    _notifySubscription?.cancel();
    _notifyListenersTimer?.cancel();
    _reconnectTimer?.cancel();
    _batteryPollTimer?.cancel();
    _rxWatchdogTimer?.cancel();
    _gpsLocationPollTimer?.cancel();
    _radioStatsPollTimer?.cancel();
    for (final pending in _pendingContactSends.values) {
      pending.timer?.cancel();
    }
    for (final pending in _pendingChannelSends.values) {
      pending.timer?.cancel();
    }
    _cancelAllChannelNoRetransmissionTimers();
    radioStatsNotifier.dispose();
    _receivedFramesController.close();
    _mcmpSigningFailedController.close();
    _usbManager.dispose();
    _tcpConnector.dispose();

    // Flush pending unread writes before disposal
    _unreadStore.flush();

    super.dispose();
  }

  void _handleRxData(Uint8List frame) {
    final packet = BufferReader(frame);
    try {
      packet.skipBytes(1); // Skip frame type byte
      final snr = packet.readInt8() / 4.0;
      packet.skipBytes(1); // Skip RSSI byte
      //final rssi = packet.readByte();
      final header = packet.readByte();
      final routeType = header & 0x03;
      final payloadType = (header >> 2) & 0x0F;
      if (routeType == _routeTransportFlood ||
          routeType == _routeTransportDirect) {
        packet.skipBytes(4); // Skip transport-specific bytes
      }
      //final payloadVer = (header >> 6) & 0x03;
      final pathLenRaw = packet.readByte();
      final pathByteLen = _decodePathByteLen(pathLenRaw);
      final pathHashWidth = _decodePathHashWidth(pathLenRaw);
      final pathBytes = packet.readBytes(pathByteLen);
      final payload = packet.readBytes(packet.remaining);

      _recordRepeaterActivity(pathBytes, pathHashWidth, snr);

      final rawPacket = frame.sublist(3);
      switch (payloadType) {
        case payloadTypeADVERT:
          _handlePayloadAdvertReceived(
            rawPacket,
            payload,
            pathBytes,
            pathHashWidth,
            routeType,
            snr,
          );
          break;
        default:
      }
    } catch (e) {
      appLogger.warn('Malformed RX frame: $e', tag: 'Connector');
      return;
    }
  }

  void importContact(Uint8List frame) {
    final packet = BufferReader(frame);
    int payloadType = 0;
    Uint8List pathBytes = Uint8List(0);
    int pathHashWidth = 1;
    try {
      packet.skipBytes(1); // Skip frame type byte
      packet.skipBytes(1); // Skip SNR byte
      packet.skipBytes(1); // Skip RSSI byte
      final header = packet.readByte();
      final routeType = header & 0x03;
      payloadType = (header >> 2) & 0x0F;
      if (routeType == _routeTransportFlood ||
          routeType == _routeTransportDirect) {
        packet.skipBytes(4); // Skip transport-specific bytes
      }
      //final payloadVer = (header >> 6) & 0x03;
      final pathLenRaw = packet.readByte();
      final pathByteLen = _decodePathByteLen(pathLenRaw);
      pathHashWidth = _decodePathHashWidth(pathLenRaw);
      pathBytes = packet.readBytes(pathByteLen);
    } catch (e) {
      appLogger.warn('Malformed RX frame: $e', tag: 'Connector');
      return;
    }
    double? latitude;
    double? longitude;
    String name = '';
    Uint8List publicKey = Uint8List(0);
    int type = 0;
    int timestamp = 0;
    bool hasLocation = false;
    bool hasName = false;
    if (payloadType != payloadTypeADVERT) {
      appLogger.warn('Unexpected payload type: $payloadType', tag: 'Connector');
      return;
    }
    try {
      publicKey = packet.readBytes(32);
      timestamp = packet.readInt32LE();
      //TODO add signature verification
      packet.skipBytes(64); // Skip signature for now
      final flags = packet.readByte();
      type = flags & 0x0F;
      hasLocation = (flags & 0x10) != 0;
      // For future use:
      //final hasFeature1 = (flags & 0x20) != 0;
      //final hasFeature2 = (flags & 0x40) != 0;
      hasName = (flags & 0x80) != 0;
      if (hasLocation && packet.remaining >= 8) {
        latitude = packet.readInt32LE() / 1e6;
        longitude = packet.readInt32LE() / 1e6;
      }
      if (hasName && packet.remaining > 0) {
        name = packet.readCString();
      }
    } catch (e) {
      appLogger.warn('Malformed advert frame: $e', tag: 'Connector');
      return;
    }

    importDiscoveredContact(
      Contact(
        rawPacket: frame,
        publicKey: publicKey,
        name: name,
        type: type,
        pathLength: pathBytes.isEmpty
            ? -1
            : (pathBytes.length ~/ pathHashWidth),
        // Store hop order reversed for easier outgoing messages; keep bytes
        // inside each multi-byte hop in their original order.
        path: _reversePathByHop(pathBytes, pathHashWidth),
        latitude: latitude,
        longitude: longitude,
        lastSeen: DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
      ),
    );
  }

  bool hasValidLocation(double? latitude, double? longitude) {
    const double epsilon = 1e-6;
    final lat = latitude ?? 0.0;
    final lon = longitude ?? 0.0;
    return (lat.abs() > epsilon || lon.abs() > epsilon) &&
        lat >= -90.0 &&
        lat <= 90.0 &&
        lon >= -180.0 &&
        lon <= 180.0;
  }

  void _handlePayloadAdvertReceived(
    Uint8List rawPacket,
    Uint8List payload,
    Uint8List path,
    int pathHashWidth,
    int routeType,
    double snr,
  ) {
    final advert = BufferReader(payload);
    double? latitude;
    double? longitude;
    String name = '';
    String contactKeyHex = '';
    Uint8List publicKey = Uint8List(0);
    int type = 0;
    int timestamp = 0;
    bool hasLocation = false;
    bool hasName = false;
    try {
      publicKey = advert.readBytes(32);
      contactKeyHex = publicKey
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      timestamp = advert.readInt32LE();
      //TODO add signature verification
      advert.skipBytes(64); // Skip signature for now
      final flags = advert.readByte();
      type = flags & 0x0F;
      hasLocation = (flags & 0x10) != 0;
      // For future use:
      //final hasFeature1 = (flags & 0x20) != 0;
      //final hasFeature2 = (flags & 0x40) != 0;
      hasName = (flags & 0x80) != 0;
      if (hasLocation && advert.remaining >= 8) {
        latitude = advert.readInt32LE() / 1e6;
        longitude = advert.readInt32LE() / 1e6;
      }
      // Validate location values if present
      hasLocation = hasValidLocation(latitude, longitude);

      if (hasName && advert.remaining > 0) {
        name = advert.readCString();
      }
    } catch (e) {
      appLogger.warn('Malformed advert frame: $e', tag: 'Connector');
      return;
    }

    //We ignore our own adverts
    if (listEquals(publicKey, _selfPublicKey)) {
      return;
    }

    // Check if this is a new contact
    final isNewContact = !_knownContactKeys.contains(contactKeyHex);

    if (isNewContact) {
      final newContact = Contact(
        rawPacket: rawPacket,
        publicKey: publicKey,
        name: name,
        type: type,
        pathLength: path.isEmpty ? -1 : (path.length ~/ pathHashWidth),
        // Store hop order reversed for easier outgoing messages; keep bytes
        // inside each multi-byte hop in their original order.
        path: _reversePathByHop(path, pathHashWidth),
        latitude: latitude,
        longitude: longitude,
        lastSeen: DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
      );
      if ((_autoAddUsers && type == advTypeChat) ||
          (_autoAddRepeaters && type == advTypeRepeater) ||
          (_autoAddRoomServers && type == advTypeRoom) ||
          (_autoAddSensors && type == advTypeSensor)) {
        _handleContactAdvert(newContact);
        _handleDiscovery(
          newContact,
          rawPacket,
          noNotify: true,
          addActive: true,
        );
      } else {
        _handleDiscovery(newContact, rawPacket);
      }
      _updateDirectRepeater(
        newContact,
        snr,
        path,
        pathHashWidth: pathHashWidth,
      );
      return;
    }

    final existingIndex = _contacts.indexWhere(
      (c) => c.publicKeyHex == contactKeyHex,
    );

    if (existingIndex >= 0) {
      final existing = _contacts[existingIndex];
      final mergedLastMessageAt = existing.lastMessageAt.isAfter(DateTime.now())
          ? DateTime.now()
          : existing.lastMessageAt;

      appLogger.info(
        'Refreshing contact ${existing.name}: devicePath=${existing.pathLength}, existingOverride=${existing.pathOverride}',
        tag: 'Connector',
      );

      // CRITICAL: Preserve user's path override when contact is refreshed from device
      _contacts[existingIndex] = existing.copyWith(
        latitude: hasLocation ? latitude : existing.latitude,
        longitude: hasLocation ? longitude : existing.longitude,
        name: hasName ? name : existing.name,
        path: _reversePathByHop(path, pathHashWidth),
        pathLength: path.isEmpty ? -1 : (path.length ~/ pathHashWidth),
        lastMessageAt: mergedLastMessageAt,
        lastSeen: DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
        pathOverride: existing.pathOverride, // Preserve user's path choice
        pathOverrideBytes: existing.pathOverrideBytes,
      );

      // Add path to history if we have a valid path
      if (_pathHistoryService != null &&
          _contacts[existingIndex].pathLength >= 0) {
        _pathHistoryService!.handlePathUpdated(_contacts[existingIndex]);
      }

      _updateDirectRepeater(
        _contacts[existingIndex],
        snr,
        path,
        pathHashWidth: pathHashWidth,
      );

      appLogger.info(
        'After merge: pathOverride=${_contacts[existingIndex].pathOverride}, devicePath=${_contacts[existingIndex].pathLength}',
        tag: 'Connector',
      );
    }
  }

  // Records the last-hop repeater of ANY received packet (message, ack,
  // advert, …) with its SNR, ranked by signal quality and capped at
  // [_maxActiveRepeaters]. Feeds the "all repeater activity" SNR indicator.
  void _recordRepeaterActivity(
    Uint8List pathBytes,
    int pathHashWidth,
    double snr,
  ) {
    final width = pathHashWidth.clamp(1, 4).toInt();
    // A non-empty path means a repeater relayed the packet to us; its hash is
    // the last hop. Directly-heard (0-hop) packets have no relaying repeater.
    if (pathBytes.length < width) return;
    final lastHop = pathBytes.sublist(pathBytes.length - width);
    final contactKeyHex = _resolveActivityRepeaterContactKeyHex(lastHop);

    _activeRepeaters.removeWhere((r) => r.isStale());

    DirectRepeater? existing;
    for (final r in _activeRepeaters) {
      if (contactKeyHex != null && r.contactKeyHex != null) {
        if (r.contactKeyHex == contactKeyHex) {
          existing = r;
          break;
        }
      } else if (r.pathHashWidth == width && r.matchesPrefix(lastHop)) {
        existing = r;
        break;
      }
    }

    if (existing != null) {
      // Refreshes lastUpdated to now, so it floats back to the top of the
      // recency-ordered list.
      existing.update(
        snr,
        pubkeyPrefix: lastHop,
        pathHashWidth: width,
        contactKeyHex: contactKeyHex,
      );
    } else {
      // On overflow drop the oldest entry to make room for the newest.
      if (_activeRepeaters.length >= _maxActiveRepeaters) {
        _activeRepeaters.sort((a, b) => a.lastUpdated.compareTo(b.lastUpdated));
        _activeRepeaters.removeAt(0);
      }
      _activeRepeaters.add(
        DirectRepeater(
          pubkeyPrefix: lastHop,
          pathHashWidth: width,
          contactKeyHex: contactKeyHex,
          snr: snr,
        ),
      );
    }
    notifyListeners();
  }

  String? _resolveActivityRepeaterContactKeyHex(List<int> pubkeyPrefix) {
    final prefixMatches = allContacts
        .where(
          (c) =>
              (c.type == advTypeRepeater || c.type == advTypeRoom) &&
              _contactKeyMatchesPrefix(c.publicKeyHex, pubkeyPrefix),
        )
        .toList();
    if (prefixMatches.length == 1) {
      return prefixMatches.first.publicKeyHex;
    }
    return null;
  }

  void _updateDirectRepeater(
    Contact contact,
    double snr,
    Uint8List path, {
    required int pathHashWidth,
  }) {
    final hashWidth = pathHashWidth.clamp(1, 4).toInt();
    if (path.isNotEmpty && path.length < hashWidth) {
      return;
    }
    final pathStartIndex = path.isNotEmpty ? path.length - hashWidth : 0;
    final publicKeyPrefixEnd = math
        .min(hashWidth, contact.publicKey.length)
        .toInt();
    final pubkeyPrefix = path.isNotEmpty
        ? path.sublist(pathStartIndex)
        : contact.publicKey.sublist(0, publicKeyPrefixEnd);
    final contactKeyHex = _resolveDirectRepeaterContactKeyHex(
      contact,
      pubkeyPrefix,
      path.isEmpty,
    );
    final knownRepeaters = contactKeyHex == null
        ? _directRepeaters
              .where(
                (r) =>
                    r.contactKeyHex != null &&
                    _contactKeyMatchesPrefix(r.contactKeyHex!, pubkeyPrefix),
              )
              .toList()
        : const <DirectRepeater>[];
    final knownRepeater = knownRepeaters.length == 1
        ? knownRepeaters.first
        : null;
    final effectiveContactKeyHex =
        contactKeyHex ?? knownRepeater?.contactKeyHex;

    _directRepeaters.removeWhere((r) => r.isStale());

    //We can use adverts from chat and sensor nodes, but only if the advert has a path to get the last hop.
    if ((contact.type == advTypeChat || contact.type == advTypeSensor) &&
        path.isEmpty) {
      notifyListeners();
      return;
    }

    final isTracked = _directRepeaters.where((r) {
      if (knownRepeater != null) {
        return identical(r, knownRepeater);
      }
      if (effectiveContactKeyHex != null) {
        return r.contactKeyHex == effectiveContactKeyHex ||
            (r.contactKeyHex == null &&
                _contactKeyMatchesPrefix(
                  effectiveContactKeyHex,
                  r.pubkeyPrefix,
                ));
      }
      if (r.contactKeyHex == null &&
          r.pathHashWidth == hashWidth &&
          r.matchesPrefix(pubkeyPrefix)) {
        return true;
      }
      return false;
    }).toList();

    final sortedRepeaters = List<DirectRepeater>.from(_directRepeaters)
      ..sort((a, b) => b.snr.compareTo(a.snr));
    final weakestRepeater = sortedRepeaters.isNotEmpty
        ? sortedRepeaters.last
        : null;

    if (_directRepeaters.length >= 5 &&
        weakestRepeater != null &&
        isTracked.isEmpty) {
      _directRepeaters.remove(weakestRepeater);
    }

    if (isTracked.isNotEmpty) {
      final repeater = isTracked.first;
      repeater.update(
        snr,
        pubkeyPrefix: pubkeyPrefix,
        pathHashWidth: hashWidth,
        contactKeyHex: effectiveContactKeyHex,
      );
      if (effectiveContactKeyHex != null) {
        _directRepeaters.removeWhere(
          (r) =>
              !identical(r, repeater) &&
              (r.contactKeyHex == effectiveContactKeyHex ||
                  (r.contactKeyHex == null &&
                      _contactKeyMatchesPrefix(
                        effectiveContactKeyHex,
                        r.pubkeyPrefix,
                      ))),
        );
      }
    } else if (_directRepeaters.length < 5) {
      _directRepeaters.add(
        DirectRepeater(
          pubkeyPrefix: pubkeyPrefix,
          pathHashWidth: hashWidth,
          contactKeyHex: effectiveContactKeyHex,
          snr: snr,
        ),
      );
    }
    notifyListeners();
  }

  String? _resolveDirectRepeaterContactKeyHex(
    Contact contact,
    List<int> pubkeyPrefix,
    bool pathIsEmpty,
  ) {
    if (pathIsEmpty &&
        (contact.type == advTypeRepeater || contact.type == advTypeRoom)) {
      return contact.publicKeyHex;
    }

    final prefixMatches = allContacts
        .where(
          (c) =>
              (c.type == advTypeRepeater || c.type == advTypeRoom) &&
              _contactKeyMatchesPrefix(c.publicKeyHex, pubkeyPrefix),
        )
        .toList();
    if (prefixMatches.length == 1) {
      return prefixMatches.first.publicKeyHex;
    }

    return null;
  }

  bool _contactKeyMatchesPrefix(String contactKeyHex, List<int> pubkeyPrefix) {
    // Normalize both sides to upper-case hex to avoid case-sensitive mismatches.
    final normalizedPrefixHex = pubkeyPrefix
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();
    final normalizedContactKeyHex = contactKeyHex.toUpperCase();
    return normalizedContactKeyHex.startsWith(normalizedPrefixHex);
  }

  void _handleAutoAddConfig(Uint8List frame) {
    final reader = BufferReader(frame);
    try {
      reader.skipBytes(1); // Skip the response code byte
      final flags = reader.readByte();
      _autoAddUsers = (flags & autoAddChatFlag) != 0;
      _autoAddRepeaters = (flags & autoAddRepeaterFlag) != 0;
      _autoAddRoomServers = (flags & autoAddRoomServerFlag) != 0;
      _autoAddSensors = (flags & autoAddSensorFlag) != 0;
      _overwriteOldest = (flags & autoAddOverwriteOldestFlag) != 0;
    } catch (e) {
      appLogger.error('Failed to parse auto-add config: $e', tag: 'Connector');
    }
  }

  void _handleDiscovery(
    Contact contact,
    Uint8List rawPacket, {
    bool noNotify = false,
    bool addActive = false,
    bool persist = true,
    bool notifyChange = true,
  }) {
    if (notifyChange || persist) {
      appLogger.info(
        'Discovered new contact: ${contact.name}',
        tag: 'Connector',
      );
    }

    final isDeferredContactSyncUpdate = !persist && !notifyChange;
    final existingIndex = isDeferredContactSyncUpdate
        ? (_discoveredContactSyncIndexes?[contact.publicKeyHex] ?? -1)
        : _discoveredContacts.indexWhere(
            (c) => c.publicKeyHex == contact.publicKeyHex,
          );

    // Update existing contact
    if (existingIndex >= 0) {
      final existing = _discoveredContacts[existingIndex];
      final messageSummary = _mergedContactMessageSummary(existing, contact);
      _discoveredContacts[existingIndex] = existing.copyWith(
        rawPacket: rawPacket,
        name: contact.name,
        type: contact.type,
        pathLength: contact.pathLength,
        path: contact.path,
        latitude: contact.latitude,
        longitude: contact.longitude,
        lastSeen: contact.lastSeen,
        lastMessageAt: messageSummary.lastMessageAt,
        hasMessages: messageSummary.hasMessages,
        flags: 0,
        isActive: addActive,
      );
      if (notifyChange) notifyListeners();
      if (persist) unawaited(_persistDiscoveredContacts());
      return;
    }

    final disContact = Contact(
      rawPacket: rawPacket,
      publicKey: contact.publicKey,
      name: contact.name,
      type: contact.type,
      pathLength: contact.pathLength,
      path: contact.path,
      latitude: contact.latitude,
      longitude: contact.longitude,
      lastSeen: contact.lastSeen,
      lastMessageAt: contact.lastMessageAt,
      hasMessages: contact.hasMessages,
      isActive: addActive,
      flags: 0,
    );

    if (_discoveredContacts.length >= _maxDiscoveredContacts) {
      _evictStalestDiscoveredContact();
    }
    _discoveredContacts.add(disContact);
    if (isDeferredContactSyncUpdate) {
      _discoveredContactSyncIndexes?[contact.publicKeyHex] =
          _discoveredContacts.length - 1;
    }

    if (persist) unawaited(_persistDiscoveredContacts());

    // Show notification for new contact (advertisement)
    if (_appSettingsService != null && !noNotify) {
      final settings = _appSettingsService!.settings;
      if (settings.notificationsEnabled && settings.notifyOnNewAdvert) {
        _notificationService.showAdvertNotification(
          contactName: contact.name,
          contactType: contact.typeLabelRaw,
          contactId: contact.publicKeyHex,
        );
      }
    }
  }

  void _evictStalestDiscoveredContact() {
    if (_discoveredContacts.isEmpty) return;
    var stalestIndex = 0;
    for (int i = 1; i < _discoveredContacts.length; i++) {
      if (_discoveredContacts[i].lastSeen.isBefore(
        _discoveredContacts[stalestIndex].lastSeen,
      )) {
        stalestIndex = i;
      }
    }
    final removed = _discoveredContacts.removeAt(stalestIndex);
    final syncIndexes = _discoveredContactSyncIndexes;
    if (syncIndexes != null) {
      syncIndexes.remove(removed.publicKeyHex);
      for (var i = stalestIndex; i < _discoveredContacts.length; i++) {
        syncIndexes[_discoveredContacts[i].publicKeyHex] = i;
      }
    }
  }

  void removeAllDiscoveredContacts() {
    _discoveredContacts.clear();
    unawaited(_persistDiscoveredContacts());
    notifyListeners();
  }

  void clearMessagesForContact(Contact contact) {
    final contactKeyHex = contact.publicKeyHex;
    final messages = _conversations.putIfAbsent(
      contactKeyHex,
      () => <Message>[],
    );
    messages.clear();
    _sharedContactSecondaryMessages.remove(contactKeyHex);
    _contactMessagePreviews.remove(contactKeyHex);
    _hiddenSharedContactKeys.add(contactKeyHex);
    unawaited(_messageStore.saveMessages(contactKeyHex, messages));
    markContactRead(contactKeyHex);
    notifyListeners();
  }

  void clearMessagesForChannel(int channelIndex) {
    final messages = _channelMessages.putIfAbsent(
      channelIndex,
      () => <ChannelMessage>[],
    );
    messages.clear();
    _sharedChannelSecondaryMessages.remove(channelIndex);
    _sharedChannelSecondaryIdentityKeys.remove(channelIndex);
    final channel = _findChannelByIndex(channelIndex);
    if (channel != null) {
      _hiddenSharedChannelIdentityKeys[channelIndex] =
          _sharedChannelIdentityKey(channel);
    }
    unawaited(_channelMessageStore.saveChannelMessages(channelIndex, messages));
    markChannelRead(channelIndex);
    notifyListeners();
  }

  Future<void> deleteAllPaths() async {
    var contactsChanged = false;
    for (var index = 0; index < _contacts.length; index++) {
      final contact = _contacts[index];
      if (contact.pathOverride == null && contact.pathOverrideBytes == null) {
        continue;
      }
      final updatedContact = contact.copyWith(clearPathOverride: true);
      _contacts[index] = updatedContact;
      _retryService?.updatePendingContact(updatedContact);
      contactsChanged = true;
    }

    _retryService?.clearPathAttemptHistory();
    if (contactsChanged) {
      await _persistContacts();
    }
    await _pathHistoryService?.clearAllHistories();
    notifyListeners();
  }
}

const int _phRouteMask = 0x03;
const int _phTypeShift = 2;
const int _phTypeMask = 0x0F;
const int _phVerShift = 6;
const int _phVerMask = 0x03;

const int _routeTransportFlood = 0x00;
const int _routeFlood = 0x01;
const int _routeTransportDirect = 0x03;

const int _payloadTypeGroupText = 0x05;
const int _payloadTypeGroupData = 0x06;
const int _cipherMacSize = 2;

/// Decodes the firmware's encoded path_len byte into actual byte length.
/// Bits 0-5: hash count (0-63), Bits 6-7: hash size code (0=1byte ... 3=4bytes).
int _decodePathByteLen(int pathLenRaw) {
  if (pathLenRaw == 0xFF || pathLenRaw == 0) return 0;
  final hashCount = pathLenRaw & 63;
  final hashSize = _decodePathHashWidth(pathLenRaw);
  return hashCount * hashSize;
}

int _decodePathHashWidth(int pathLenRaw) {
  if (pathLenRaw == 0xFF) return 1;
  return ((pathLenRaw >> 6) & 0x03) + 1;
}

bool _isPathLenValidForMode(
  int pathLen,
  List<int> pathBytes,
  int pathHashWidth,
) {
  if (pathLen < 0 || pathLen > 0x3F) return false;
  final width = pathHashWidth.clamp(1, 4).toInt();
  final maxHopCountByBytes = maxPathSize ~/ width;
  if (pathLen > maxHopCountByBytes) return false;
  return pathBytes.length <= maxPathSize && pathBytes.length == pathLen * width;
}

Uint8List _reversePathByHop(Uint8List pathBytes, int pathHashWidth) {
  if (pathBytes.isEmpty) return Uint8List(0);
  final width = pathHashWidth.clamp(1, 4).toInt();
  final reversed = <int>[];
  for (var i = pathBytes.length; i > 0; i -= width) {
    final start = (i - width).clamp(0, pathBytes.length).toInt();
    reversed.addAll(pathBytes.sublist(start, i));
  }
  return Uint8List.fromList(reversed);
}

class _RawPacket {
  final int header;
  final int routeType;
  final int payloadType;
  final int payloadVer;
  final int? transportCode1;
  final int pathLenRaw;
  final Uint8List pathBytes;
  final Uint8List payload;

  _RawPacket({
    required this.header,
    required this.routeType,
    required this.payloadType,
    required this.payloadVer,
    this.transportCode1,
    required this.pathLenRaw,
    required this.pathBytes,
    required this.payload,
  });

  bool get isFlood =>
      routeType == _routeFlood || routeType == _routeTransportFlood;

  int get hopCount => pathLenRaw & 63;
  int get pathHashWidth => ((pathLenRaw >> 6) & 0x03) + 1;
}

class _PacketRegionResolution {
  final String? region;
  final bool notMatched;

  const _PacketRegionResolution({this.region, this.notMatched = false});
}

class _ParsedText {
  final String senderName;
  final String text;

  _ParsedText({required this.senderName, required this.text});
}

class _McmpReplyReference {
  final String? messageId;
  final String senderName;
  final String? text;

  _McmpReplyReference({this.messageId, required this.senderName, this.text});
}

class _RepeaterAckContext {
  final String contactKeyHex;
  final PathSelection selection;
  final int pathLength;
  final int messageBytes;
  Timer? timeout;

  _RepeaterAckContext({
    required this.contactKeyHex,
    required this.selection,
    required this.pathLength,
    required this.messageBytes,
  });
}

class _PendingContactSend {
  final Contact contact;
  final Message message;
  final String text;
  final String inputText;
  final String uncompressedText;
  final String? originalText;
  final String? translatedLanguageCode;
  final String? translationModelId;
  final int delaySeconds;
  final DateTime sendAt;
  Timer? timer;

  _PendingContactSend({
    required this.contact,
    required this.message,
    required this.text,
    required this.inputText,
    required this.uncompressedText,
    required this.originalText,
    required this.translatedLanguageCode,
    required this.translationModelId,
    required this.delaySeconds,
    required this.sendAt,
  });
}

class _PendingChannelSend {
  final Channel channel;
  final ChannelMessage message;
  final String text;
  final EncodedMCOImageV3? mcoImageV3;
  final ChannelBinaryDataOutbound? mcoImageV3Outbound;
  final String inputText;
  final String uncompressedText;
  final String? originalText;
  final String? translatedLanguageCode;
  final String? translationModelId;
  final String? replyToMessageId;
  final String? replyToSenderName;
  final String? replyToText;
  final int? replyToTimestamp;
  final int delaySeconds;
  final DateTime sendAt;
  Timer? timer;

  _PendingChannelSend({
    required this.channel,
    required this.message,
    required this.text,
    required this.mcoImageV3,
    required this.mcoImageV3Outbound,
    required this.inputText,
    required this.uncompressedText,
    required this.originalText,
    required this.translatedLanguageCode,
    required this.translationModelId,
    required this.replyToMessageId,
    required this.replyToSenderName,
    required this.replyToText,
    required this.replyToTimestamp,
    required this.delaySeconds,
    required this.sendAt,
  });
}

class _DeferredChannelMessageSend {
  final Channel channel;
  final String messageId;
  final String text;
  final ChannelBinaryDataOutbound? binaryOutbound;

  /// Exact text-transport payload prepared (and possibly signed) at compose
  /// time. Reused verbatim on flush so deferral never re-encodes or re-signs.
  final String? preparedOutboundText;
  final String? uncompressedText;
  final String? originalText;
  final String? translatedLanguageCode;
  final String? translationModelId;
  final String? replyToMessageId;
  final String? replyToSenderName;
  final String? replyToText;
  final int? replyToTimestamp;

  _DeferredChannelMessageSend({
    required this.channel,
    required this.messageId,
    required this.text,
    required this.binaryOutbound,
    this.preparedOutboundText,
    required this.uncompressedText,
    required this.originalText,
    required this.translatedLanguageCode,
    required this.translationModelId,
    required this.replyToMessageId,
    required this.replyToSenderName,
    required this.replyToText,
    required this.replyToTimestamp,
  });
}

class _PendingCommandAck {
  final int commandCode;
  final String? channelSendQueueId;
  final Completer<void>? completer;

  _PendingCommandAck({
    required this.commandCode,
    this.channelSendQueueId,
    this.completer,
  });
}
