import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:mco_service/mco_service.dart';
import 'package:meshcore_open/storage/region_store.dart';
import 'package:pointycastle/export.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';

import '../models/channel.dart';
import '../models/channel_message.dart';
import '../models/companion_radio_stats.dart';
import '../models/contact.dart';
import '../models/direct_echo_observation.dart';
import '../models/message.dart';
import '../models/message_compression.dart';
import '../models/app_settings.dart';
import '../models/path_selection.dart';
import '../models/translation_support.dart';
import '../helpers/blocked_senders.dart';
import '../helpers/background_work_tracker.dart';
import '../helpers/frame_background_work.dart';
import '../helpers/packet_background_work.dart';
import '../helpers/image_transfer_background_work.dart';
import '../helpers/message_processing_background_work.dart';
import '../helpers/outgoing_queue_background_work.dart';
import '../helpers/queued_message_request_background_work.dart';
import '../helpers/radio_send_background_work.dart';
import '../helpers/sync_background_work.dart';
import '../helpers/channel_path_signal_helper.dart';
import '../helpers/channel_message_timeline_helper.dart';
import '../helpers/reaction_helper.dart';
import '../helpers/room_message_timeline_helper.dart';
import '../helpers/shared_marker_deletions.dart';
import '../helpers/channel_binary_data_helper.dart';
import '../helpers/channel_echo_recovery.dart';
import '../helpers/channel_raw_packet.dart';
import '../helpers/channel_key_hash_cache.dart';
import '../helpers/channel_sender_name.dart';
import '../helpers/channel_identity_reconciler.dart';
import '../helpers/contact_history_candidates.dart';
import '../helpers/connection_cleanup.dart';
import '../helpers/connection_teardown_background_work.dart';
import '../helpers/device_polling_intervals.dart';
import '../helpers/radio_stats_send_polling.dart';
import '../helpers/reconnect_backoff.dart';
import '../helpers/reconnect_power_settings.dart';
import '../helpers/ui_notification_batcher.dart';
import '../helpers/heard_channel_packets.dart';
import '../helpers/direct_echo_crypto.dart';
import '../helpers/direct_echo_recovery.dart';
import '../helpers/direct_flood_repeats.dart';
import '../helpers/direct_message_progress_helper.dart';
import '../helpers/channel_app_data_helper.dart';
import '../helpers/contact_share_helper.dart';
import '../helpers/contact_merge_helper.dart';
import '../helpers/key_indexed_list.dart';
import '../helpers/key_prefix_match.dart';
import '../helpers/versioned_map.dart';
import '../helpers/channel_resend_coverage.dart';
import '../helpers/channel_resend_warning.dart';
import '../helpers/cyr2lat.dart';
import '../helpers/exact_quote_helper.dart';
import '../helpers/mesh_compressor.dart';
import '../helpers/message_text_codec.dart';
import '../helpers/mcoimg_codec.dart';
import '../helpers/mcoimg_v3_codec.dart';
import '../helpers/mcoimg_v4_codec.dart';
import '../helpers/mcmp_app_codec.dart';
import '../helpers/mcotxt_app_codec.dart';
import '../helpers/mcmp_signature_verifier.dart';
import '../helpers/south_frame_fragment_reassembler.dart';
import '../helpers/south_queued_fragment_ack_tracker.dart';
import '../helpers/smaz.dart';
import '../services/app_debug_log_service.dart';
import '../services/ble_debug_log_service.dart';
import '../services/linux_ble_error_classifier.dart';
import '../services/linux_ble_pairing_service_stub.dart'
    if (dart.library.io) '../services/linux_ble_pairing_service.dart';
import '../services/image_chunk_transport.dart'
    show
        ImageChunkOutcome,
        ImageChunkTransport,
        dataTypeAeicImage,
        senderPrefixFromKey;
import '../services/image_codec_service.dart';
import '../services/received_image_store.dart';
import '../services/message_retry_service.dart';
import '../services/path_history_service.dart';
import '../services/app_settings_service.dart';
import '../services/background_service.dart';
import '../services/timeout_prediction_service.dart';
import '../services/translation_service.dart';
import '../services/notification_reply.dart';
import '../services/notification_service.dart';
import 'meshcore_connector_usb.dart';
import 'meshcore_connector_tcp.dart';
import '../storage/channel_message_store.dart';
import '../storage/channel_identity_store.dart';
import '../storage/contact_identity_store.dart';
import '../storage/channel_order_store.dart';
import '../storage/channel_settings_store.dart';
import '../storage/channel_region_store.dart';
import '../storage/contact_region_store.dart';
import '../storage/channel_store.dart';
import '../storage/connection_transport_preference_store.dart';
import '../storage/contact_location_estimate_store.dart';
import '../storage/contact_discovery_store.dart';
import '../storage/contact_settings_store.dart';
import '../storage/contact_store.dart';
import '../storage/message_store.dart';
import '../storage/message_history_storage.dart';
import '../storage/node_identity_store.dart';
import '../storage/shared_message_history_helper.dart';
import '../storage/unread_store.dart';
import '../review_mode/review_mode_storage.dart';
import '../review_mode/review_radio.dart';
import '../utils/app_logger.dart';
import '../utils/battery_utils.dart';
import '../utils/platform_info.dart';
import 'meshcore_uuids.dart';
import 'meshcore_protocol.dart';
import 'pending_command_replies.dart';
import 'raw_packet.dart';

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

enum MeshCoreTransportType { bluetooth, usb, tcp, review }

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

class MeshCoreConnector extends ChangeNotifier with WidgetsBindingObserver {
  // Focused chats may grow past these windows while the user pages upward.
  // Once a chat is no longer active, older rows remain in SQLite and its
  // in-memory list is reduced to the most recent window.
  static const int _initialContactHistorySize = 300;
  static const int _initialChannelHistorySize = 300;
  static const int _offlineSharedHistoryWindowSize = 1000;

  // Cap on discovered (non-contact) nodes retained in memory. Adverts arrive
  // continuously from the whole mesh, so without a bound this list grows for
  // as long as the app stays connected. When full, the stalest node (oldest
  // lastSeen) is evicted to make room for a newly heard one.
  static const int maxDiscoveredContacts = 1000;

  /// The cap while the "evict discovered contacts" toggle of the auto-add
  /// dialog is on (upstream's toggle, taken 2026-10-13 with this cap).
  static const int evictingDiscoveredContactsCap = 350;

  /// The discovered list's cap as the setting has it now.
  int get _discoveredContactsLimit =>
      (_appSettingsService?.settings.evictDiscoveredContactsEnabled ?? false)
      ? evictingDiscoveredContactsCap
      : maxDiscoveredContacts;

  MeshCoreConnectionState _state = MeshCoreConnectionState.disconnected;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _rxCharacteristic;
  BluetoothCharacteristic? _txCharacteristic;
  String? _deviceDisplayName;
  String? _deviceId;
  BluetoothDevice? _lastDevice;
  String? _lastDeviceId;
  String? _lastDeviceDisplayName;
  String? _lastTcpHost;
  int? _lastTcpPort;
  MeshCoreTransportType? _reconnectTransport;
  bool _transportRestartInProgress = false;
  bool _manualDisconnect = false;
  bool _isRecoveringConnection = false;
  MeshCoreTransportType? _lastManualDisconnectTransport;
  // Bumped by every BLE connect attempt so a superseded attempt can tell it
  // no longer owns the connector.
  int _bleConnectGeneration = 0;

  /// Non-null while [disconnect] is tearing the transport down. Connect paths
  /// join it so a teardown cannot finish after a new connection and reset the
  /// state to `disconnected`. USB made this reachable: its native close now
  /// waits out the kernel's closing_wait off the UI isolate, so the teardown
  /// can outlive the tap that starts the next connection.
  Future<void>? _activeDisconnect;
  Duration _disconnectStepTimeout = ConnectionCleanup.defaultTimeout;

  /// Set by [dispose]. A teardown started before disposal can still be running
  /// (the USB native close waits out the kernel's closing_wait off the UI
  /// isolate), so state publication is suppressed once the connector is gone.
  bool _disposed = false;
  final MeshCoreUsbManager _usbManager;
  final LinuxBlePairingService _linuxBlePairingService =
      LinuxBlePairingService();
  StreamSubscription<Uint8List>? _usbFrameSubscription;
  final MeshCoreTcpConnector _tcpConnector;
  final BackgroundWorkTracker _backgroundWork = BackgroundWorkTracker();
  late final FrameBackgroundWork _frameBackgroundWork = FrameBackgroundWork(_backgroundWork);
  late final PacketBackgroundWork _packetBackgroundWork =
      PacketBackgroundWork(_backgroundWork);
  late final MessageProcessingBackgroundWork _messageProcessingBackgroundWork =
      MessageProcessingBackgroundWork(_backgroundWork);
  late final QueuedMessageRequestBackgroundWork _queuedMessageRequestWork =
      QueuedMessageRequestBackgroundWork(_backgroundWork);
  late final SyncBackgroundWork _contactSyncWork =
      SyncBackgroundWork(_backgroundWork, BackgroundWorkKind.contactSync);
  late final SyncBackgroundWork _channelSyncWork =
      SyncBackgroundWork(_backgroundWork, BackgroundWorkKind.channelSync);
  late final SyncBackgroundWork _selfInfoWork =
      SyncBackgroundWork(_backgroundWork, BackgroundWorkKind.transportSetup);
  late final ConnectionTeardownBackgroundWork _teardownWork =
      ConnectionTeardownBackgroundWork(_backgroundWork);
  late final RadioSendBackgroundWork _radioSendBackgroundWork =
      RadioSendBackgroundWork(_backgroundWork, _radioStatsSendPolling);
  late final OutgoingQueueBackgroundWork _outgoingQueueWork =
      OutgoingQueueBackgroundWork(_backgroundWork);
  late final ImageTransferBackgroundWork _imageTransferWork =
      ImageTransferBackgroundWork(_backgroundWork);
  Future<void> Function(Uint8List)? _frameWriterForTest;
  MeshCoreTransportType _activeTransport = MeshCoreTransportType.bluetooth;
  ReviewRadio? _reviewRadio;
  StreamSubscription<Uint8List>? _reviewFrameSubscription;
  int _reviewConnectGeneration = 0;

  final List<ScanResult> _scanResults = [];
  final List<ScanResult> _linuxSystemScanResults = [];
  // Indexed by key so the per-contact lookups the screens run on every
  // rebuild do not scan the whole list; see _shouldTrackUnreadForContactKey.
  final KeyIndexedList<Contact> _contacts = KeyIndexedList<Contact>(
    (contact) => contact.publicKeyHex,
  );
  // Indexed for the same reason, and versioned: the contact list shows the
  // repeaters in it that the node does not hold (localRepeaters).
  final KeyIndexedList<Contact> _discoveredContacts = KeyIndexedList<Contact>(
    (contact) => contact.publicKeyHex,
  );
  Future<void>? _contactCacheLoadFuture;
  int _contactCacheLoadGeneration = 0;
  final List<Channel> _channels = [];
  final Map<String, List<Message>> _conversations = {};
  final Map<int, List<ChannelMessage>> _channelMessages = {};
  final ChannelMessageTimelineCache _channelMessageTimelineCache =
      ChannelMessageTimelineCache();
  final List<String> _pendingChannelSentQueue = [];
  final PendingCommandReplies _pendingGenericAckQueue = PendingCommandReplies(
    staleAfter: _commandAckTimeout * 2,
  );
  static const String _reactionSendQueuePrefix = '__reaction_send__';
  // TXT_TYPE_CLI_COMMAND (firmware TxtDataHelpers.h).
  static const int _txtTypeCliCommand = 3;
  // ERR_CODE_NOT_FOUND (companion MyMesh.cpp).
  static const int _errCodeNotFound = 2;
  int _reactionSendQueueSequence = 0;
  final Set<String> _loadedConversationKeys = {};

  /// Guards [ensureContactHistoryLoaded] against overlapping passes.
  bool _warmingContactHistory = false;

  /// Contacts already examined by [ensureContactHistoryLoaded]. Kept apart
  /// from [_loadedConversationKeys]: a conversation with no pins is never
  /// decoded by the sweep, so it stays unloaded until its chat is opened, and
  /// a later sweep must still skip it in one lookup.
  final Set<String> _markerScannedContactKeys = {};
  final Map<String, Future<void>> _conversationLoadFutures = {};
  int _conversationLoadGeneration = 0;
  // Self public key of the radio whose messages are held in memory.
  String? _messageStateOwnerKey;
  // Self public key whose persisted stores were loaded this link session.
  // Later SELF_INFO replies (refreshDeviceInfo after a settings change) skip
  // the reload while it still matches.
  String? _persistedStateLoadedKey;
  final Map<int, Set<String>> _processedChannelReactions =
      {}; // channelIndex -> Set of "targetHash_emoji"
  final Map<String, Set<String>> _processedContactReactions =
      {}; // contactPubKeyHex -> Set of "targetHash_emoji"

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _isScanningSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<dynamic>? _iosBleCentralSubscription;
  StreamSubscription<NotificationReply>? _notificationReplySubscription;
  Timer? _selfInfoRetryTimer;
  ReconnectWait? _reconnectTimer;
  ReconnectPowerSettings? _reconnectPowerSettings;
  Duration Function()? _reconnectClock;
  Timer? _batteryPollTimer;
  Timer? _rxWatchdogTimer;
  DateTime _rxSilenceAnchor = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastRxWatchdogTickAt;
  int _rxWatchdogReconnects = 0;
  Timer? _gpsLocationPollTimer;
  Duration get _gpsLocationPollInterval => _devicePollingIntervals.gps;
  final List<Completer<void>> _selfInfoRefreshWaiters = [];
  Timer? _radioStatsPollTimer;
  int _radioStatsPollRefCount = 0;
  final _radioStatsPollingOwners = ValueNotifier<int>(0);
  ValueListenable<int> get radioStatsPollingOwners => _radioStatsPollingOwners;
  late final RadioStatsSendPolling _radioStatsSendPolling = RadioStatsSendPolling(
    isConnected: () => isConnected && supportsCompanionRadioStats,
    hasPendingWork: () => hasPendingRadioStatsWork,
    acquire: acquireRadioStatsPolling,
    release: releaseRadioStatsPolling,
  );
  bool get hasPendingRadioStatsWork =>
      _radioStatsSendPolling.hasActiveOperations ||
      (_retryService?.hasPendingMessages ?? false) ||
      _pendingContactSends.isNotEmpty ||
      _pendingChannelSends.isNotEmpty ||
      _pendingChannelSentQueue.isNotEmpty ||
      _channelHopChecks.isNotEmpty;
  final ValueNotifier<CompanionRadioStats?> radioStatsNotifier =
      ValueNotifier<CompanionRadioStats?>(null);

  /// Bumped whenever [activeRepeaters] or [directRepeaters] change, which is
  /// on every relayed packet the radio hears. Their readers (the SNR
  /// indicators, the routing sheet) listen here rather than to
  /// [notifyListeners], so a relay no longer rebuilds every listener of the
  /// connector for a signal-strength number.
  final ValueNotifier<int> repeaterActivity = ValueNotifier<int>(0);
  int _reconnectAttempts = 0;
  int _uiRevision = 0;
  late final _uiNotifications = UiNotificationBatcher(onNotify: _flushBatchedNotify);
  Object? _lastNotifyConnectionState;

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
  // Hex of [_selfPublicKey], computed when the key is set: the getter runs
  // per candidate inside per-packet scans.
  String _selfPublicKeyHex = '';

  void _setSelfPublicKey(Uint8List? key) {
    _selfPublicKey = key;
    _selfPublicKeyHex = key == null ? '' : pubKeyToHex(key);
  }
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

  /// What the air-activity dot shows: whether the last radio-stats frame of
  /// this polling run found the node's airtime grown over the frame before
  /// it, held until the next frame. The first frame of a run has no frame
  /// before it, its totals counting from the node's boot, so it lights
  /// nothing; stopping the poll starts the next run afresh. The send path's
  /// radio-quiet wait reads [_airtimeBumpStopwatch] instead, left as it was.
  int? _airtimeBaselineSecs;
  bool _airtimeGrewInLastPoll = false;

  int? _batteryMillivolts;
  double? _selfLatitude;
  double? _selfLongitude;
  final List<DirectRepeater> _directRepeaters = List.empty(growable: true);
  // Signal activity of repeaters seen as the last hop of any received packet
  // (not just adverts). Used by the "all repeater activity" SNR indicator.
  final List<DirectRepeater> _activeRepeaters = List.empty(growable: true);
  static const int _maxActiveRepeaters = 10;
  bool _isLoadingContacts = false;
  DateTime? _contactSyncRequestedAt;
  bool _hasLoadedContacts = false;
  Map<String, int>? _contactSyncIndexes;
  Map<String, int>? _discoveredContactSyncIndexes;
  bool _isLoadingChannels = false;
  bool _hasLoadedChannels = false;
  TimeoutPredictionService? _timeoutPredictionService;
  TranslationService? _translationService;
  ImageCodecService? _imageCodecService;
  // Holds the ImageReassembler, so partially received images survive across
  // frames (chunks of one image arrive in separate GRP_DATA frames, and via the
  // firmware offline queue they may be minutes apart).
  ImageChunkTransport? _imageTransport;
  ReceivedImageStore? _receivedImageStore;
  void Function(ImageChunkOutcome outcome)? _onImageChunk;
  // The images of a channel are those stamped with the IDs of its identity
  // group; the slot names only those written before the IDs existed.
  Future<void> Function(int channelIndex, Set<String> channelIds)?
  _deleteImagesForChannel;
  Future<void> Function(Map<int, String> slotIds)? _stampImageChannelIds;
  void Function(int channelIndex)? _forgetImageSlot;

  /// Called with the raw body of an AEIC image chunk seen in the RX log.
  /// See [_countImageChunkRepeat] for why that log, and not the decoded
  /// channel-data path, is where a repeat of our own packet shows up.
  void Function(Uint8List blob, int channelIndex)? _onImageChunkRepeat;
  void Function(int senderPrefix)? _onImageSenderPrefix;
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
  DateTime? _lastBleConnectStartedAt;
  DateTime? _lastBleConnectedAt;
  DateTime? _lastBleRxAt;
  DateTime? _lastBleTxAt;
  AppLifecycleState? _lastAppLifecycleState;
  DateTime? _lastAppLifecycleStateAt;
  bool _iosBleResumeProbeInFlight = false;
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
  bool _awaitingSelfInfoValue = false;
  bool get _awaitingSelfInfo => _awaitingSelfInfoValue;
  set _awaitingSelfInfo(bool value) {
    _awaitingSelfInfoValue = value;
    // Прежний флаг владеет логическим ожиданием, отдельно от actual Futures.
    if (value) {
      _selfInfoWork.ensureStarted();
    } else {
      _selfInfoWork.finishCurrent();
    }
  }
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
  int? _autoAddMaxHops;
  bool _deviceConfigRequested = false;
  List<RepeatFreqRange>? _allowedRepeatFreqRanges;
  bool _contactsStorageFull = false;
  final StreamController<void> _contactsFullController =
      StreamController<void>.broadcast();
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

  /// During a full contact sync, the contacts listed before it began that no
  /// CONTACT frame has named since: what is left at END_OF_CONTACTS is not
  /// on the node. Null outside a full sync.
  Set<String>? _contactsUnconfirmedBySync;
  Timer? _contactSyncTimeout;
  static const Duration _contactSyncIdleTimeout = Duration(seconds: 10);
  bool _isSyncingQueuedMessages = false;

  /// True only while draining the backlog accumulated before this connection.
  /// The firmware replays it in FIFO order but exposes only the untrusted
  /// sender timestamp, so channel messages receive a monotonic local time.
  bool _isInitialBacklogDrain = false;
  DateTime? _lastInitialBacklogChannelReceivedAt;
  bool _initialSyncNotificationSummaryActive = false;
  int _initialSyncMessageNotifications = 0;
  int _initialSyncChannelMessageNotifications = 0;
  bool _deferQueuedContactMessagesUntilContacts = false;
  bool _isProcessingDeferredQueuedContactMessages = false;
  bool _queuedMessageSyncInFlight = false;
  final List<Uint8List> _deferredQueuedContactMessageFrames = [];
  bool _pendingQueueSync = false;
  // CMD_APP_START stops the firmware's contact iterator (END_OF_CONTACTS is
  // then never sent), so APP_START requested during a contact sync is held
  // until the sync ends.
  bool _appStartDeferredForContactSync = false;
  // Contact messages whose sender was not a known contact yet. The firmware
  // already removed them from its offline queue, so they are held and
  // replayed once the sender's CONTACT frame arrives (or the sync ends).
  final List<Uint8List> _unknownSenderMessageFrames = [];
  static const int _maxUnknownSenderMessageFrames = 32;
  Timer? _queueSyncTimeout;
  bool _resumeQueueSyncScheduled = false;
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
  // Slots whose GET_CHANNEL timed out in the last sync with no cached copy:
  // their contents are unknown, so UI must not treat them as free.
  final Set<int> _unconfirmedChannelSlots = {};
  static const int _maxChannelSyncRetries = 3;
  static const int _channelSyncTimeoutMs = 2000; // 2 second timeout per channel
  DevicePollingIntervals _devicePollingIntervals = const DevicePollingIntervals();
  Duration get _batteryPollInterval => _devicePollingIntervals.battery;
  static const Duration _rxWatchdogCheckInterval =
      DevicePollingIntervals.watchdogCheck;
  // Battery polling is expected to produce request-response traffic every
  // poll interval, which makes prolonged RX silence anomalous on a quiet mesh.
  // Threshold = two missed battery cycles plus one check window, and must
  // keep tracking the polling cadence if it ever changes.
  Duration get _rxWatchdogSilence => _devicePollingIntervals.watchdogSilence;
  static const int _rxWatchdogMaxConsecutive = 3;

  // Services
  MessageRetryService? _retryService;
  PathHistoryService? _pathHistoryService;
  AppSettingsService? _appSettingsService;
  SettingsSectionsService? _settingsSectionsService;
  bool _lastSouthNodeEnableFragmentedFrames = false;

  double get _initialRouteWeight =>
      _appSettingsService?.settings.initialRouteWeight ?? 1.0;
  BackgroundService? _backgroundService;
  bool _usingIosNativeBleCentral = false;
  static const bool _iosNativeBleCentralEnabled = true;
  static const MethodChannel _iosBleCentralMethod = MethodChannel(
    'mco_service/ios_ble_central',
  );
  static const EventChannel _iosBleCentralEvents = EventChannel(
    'mco_service/ios_ble_central/events',
  );
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
  final ContactRegionStore _contactRegionStore = ContactRegionStore();
  final ContactStore _contactStore = ContactStore();
  final ContactDiscoveryStore _discoveryContactStore = ContactDiscoveryStore();
  final ContactLocationEstimateStore _contactLocationEstimateStore =
      ContactLocationEstimateStore();

  /// The located keys whose estimates the store was told to drop, one set
  /// per list (see [_clearEstimatesOfNewlyLocated]).
  final Set<String> _contactEstimatesCleared = {};
  final Set<String> _discoveredEstimatesCleared = {};

  final ChannelStore _channelStore = ChannelStore();
  final ConnectionTransportPreferenceStore _transportPreferenceStore =
      ConnectionTransportPreferenceStore();
  final NodeIdentityStore _nodeIdentityStore = NodeIdentityStore();
  final UnreadStore _unreadStore = UnreadStore();
  List<Channel> _cachedChannels = [];
  final Map<int, bool> _channelMcmpEnabled = {};
  final Map<int, int> _channelMcmpVersion = {};
  final Map<int, bool> _channelMcmpUseSign = {};
  /// The name each channel sends under instead of the node's, as stored:
  /// absent when never set, '' for the node's own set here (see
  /// channelSenderNameFromSetting).
  final Map<int, String> _channelSenderNames = {};
  final Map<int, bool> _channelMCOtxtEnabled = {};
  final Map<int, bool> _channelMCOtxtPlainWhenSmaller = {};
  final Map<int, bool> _channelSmazEnabled = {};
  final Map<int, bool> _channelCyr2LatEnabled = {};
  final Map<int, bool> _channelUrlImagesEnabled = {};
  final Map<int, String?> _channelCyr2LatProfileId = {};
  final Map<int, int?> _channelWidgetColor = {};
  final Map<int, int?> _channelWidgetTextColor = {};
  final Map<int, Region> _channelRegions = {};

  /// The region each contact's flood sends are scoped with, keyed by contact
  /// key; a contact absent here goes out under the node's default scope.
  final Map<String, Region> _contactRegions = {};
  String? _defaultRegionScope;
  bool _hasLoadedDefaultRegionScope = false;
  Future<void>? _defaultRegionScopeRefreshFuture;
  final Map<String, bool> _contactMcmpEnabled = {};
  final Map<String, int> _contactMcmpVersion = {};
  final Map<String, bool> _contactMcmpUseSign = {};
  final Map<String, bool> _contactMCOtxtEnabled = {};
  final Map<String, bool> _contactMCOtxtPlainWhenSmaller = {};
  final Map<String, bool> _contactSmazEnabled = {};
  final Map<String, bool> _contactCyr2LatEnabled = {};
  final Map<String, bool> _contactUrlImagesEnabled = {};
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
  bool _lastDirectEchoRecovery = false;
  bool _lastEvictDiscoveredContacts = false;
  final Map<String, _PendingContactSend> _pendingContactSends = {};
  final Map<String, _PendingChannelSend> _pendingChannelSends = {};
  bool _isOfflineMode = false;
  bool _isOfflineSharedMode = false;
  String? _offlineHistoryScope;
  String? _offlinePublicKeyHex;
  List<String> _offlineSharedScopes = const [];
  bool _isFlushingPendingOutgoingMessages = false;
  final Set<String> _committingPendingChannelSends = {};
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
  // Versioned so a screen can tell whether any count changed without
  // comparing them; see contactUnreadRevision.
  final VersionedMap<String, int> _contactUnreadCount =
      VersionedMap<String, int>();
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

  MeshCoreConnector({
    MeshCoreTcpConnector? tcpConnector,
    MeshCoreUsbManager? usbManager,
  }) : _usbManager = usbManager ?? MeshCoreUsbManager(),
       _tcpConnector = tcpConnector ?? MeshCoreTcpConnector() {
    MessageHistoryStorage.instance.attachBackgroundWorkTracker(_backgroundWork);
    _notificationService.attachBackgroundWorkTracker(_backgroundWork);
    _lastNotifyConnectionState = _notificationConnectionState;
    if (PlatformInfo.isIOS) {
      _lastAppLifecycleState = WidgetsBinding.instance.lifecycleState;
      _lastAppLifecycleStateAt = DateTime.now();
      WidgetsBinding.instance.addObserver(this);
    }
  }

  // Getters
  /// Частичный наблюдательный учёт: пустота пока не разрешает сон CPU.
  BackgroundWorkSnapshot get backgroundWorkSnapshot => _backgroundWork.snapshot;

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
  Object? get activeTcpConnectionIdentity => _tcpConnector.activeConnectionIdentity;
  bool get isTcpTransportConnected =>
      _state == MeshCoreConnectionState.connected &&
      _activeTransport == MeshCoreTransportType.tcp;
  bool shouldSuppressAutoconnect(MeshCoreTransportType transport) =>
      _manualDisconnect && _lastManualDisconnectTransport == transport;
  bool get isReviewMode =>
      _activeTransport == MeshCoreTransportType.review &&
      _state != MeshCoreConnectionState.disconnected;

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

  /// Increases once for each actual batched UI notification. Screens can use
  /// it to refresh derived view data without repeating the work on layout-only
  /// rebuilds, such as window resizing.
  int get uiRevision => _uiRevision;

  /// Changes whenever the saved contacts change, whichever code path changes
  /// them, and on nothing else. A screen deriving data from every contact
  /// keys its cache on this rather than on [uiRevision], which also moves for
  /// radio traffic, battery readings and every other notification.
  int get contactsRevision => _contacts.version;

  /// Changes whenever a contact's unread count may have changed, including
  /// the unread state being loaded or dropped. It is -1 while that state is
  /// not loaded, when every count reads as zero.
  int get contactUnreadRevision =>
      _unreadStateLoaded ? _contactUnreadCount.version : -1;

  List<Contact> get contacts {
    final selfKey = _selfPublicKey;
    if (selfKey == null) {
      return List.unmodifiable(_contacts);
    }
    return List.unmodifiable(
      _contacts.where((contact) => !listEquals(contact.publicKey, selfKey)),
    );
  }

  Contact? getContactByPubKeyHex(String contactPubKeyHex) {
    return _contacts.cast<Contact?>().firstWhere(
      (c) => c?.publicKeyHex == contactPubKeyHex,
      orElse: () => null,
    );
  }

  Contact? _findContactByPubKeyHex(
    String contactPubKeyHex, {
    bool includeDiscoveredFallback = false,
  }) {
    final contact = getContactByPubKeyHex(contactPubKeyHex);
    if (contact != null || !includeDiscoveredFallback) return contact;
    return _discoveredContacts.cast<Contact?>().firstWhere(
      (c) => c?.publicKeyHex == contactPubKeyHex,
      orElse: () => null,
    );
  }

  Contact? _findContactByPrefix(
    Uint8List prefix, {
    bool includeDiscoveredFallback = false,
  }) {
    final contact = _contacts.cast<Contact?>().firstWhere(
      (c) => c != null && _matchesPrefix(c.publicKey, prefix),
      orElse: () => null,
    );
    if (contact != null || !includeDiscoveredFallback) return contact;
    return _discoveredContacts.cast<Contact?>().firstWhere(
      (c) => c != null && _matchesPrefix(c.publicKey, prefix),
      orElse: () => null,
    );
  }

  Contact _restoreDiscoveredContact(Contact contact) {
    final existing = getContactByPubKeyHex(contact.publicKeyHex);
    if (existing != null) return existing;

    final restored = contact.copyWith(isActive: true);
    _contacts.add(restored);
    _knownContactKeys.add(restored.publicKeyHex);

    final discoveredIndex = _discoveredContacts.indexWhere(
      (c) => c.publicKeyHex == restored.publicKeyHex,
    );
    if (discoveredIndex >= 0) {
      _discoveredContacts[discoveredIndex] =
          _discoveredContacts[discoveredIndex].copyWith(isActive: true);
    }

    appLogger.info(
      'Restored contact ${restored.name} from local discovery cache',
      tag: 'Connector',
    );
    unawaited(_persistContacts());
    unawaited(_persistDiscoveredContacts());
    return restored;
  }

  List<Contact> get allContacts {
    final selfHex = selfPublicKeyHex;
    return List.unmodifiable([
      ..._contacts,
      ..._discoveredContacts.where(
        (c) => !c.isActive && c.publicKeyHex != selfHex,
      ),
    ]);
  }

  List<Contact> get allContactsUnfiltered =>
      List.unmodifiable([..._contacts, ..._discoveredContacts]);

  /// Changes whenever the discovered list changes, whichever path changes it.
  int get discoveredRevision => _discoveredContacts.version;

  /// Repeaters the app has heard whose adverts the node did not keep, listed
  /// with the node's own contacts. They live in the app's discovered list,
  /// not on any node: a ping reaches them as they are, while a login, a
  /// request or a share asks to add them to the node first
  /// (ensureContactOnNode).
  List<Contact> get localRepeaters {
    final selfKey = selfPublicKeyHex;
    return List.unmodifiable(
      _discoveredContacts.where(
        (contact) =>
            contact.type == advTypeRepeater &&
            contact.publicKeyHex != selfKey &&
            _contacts.byKey(contact.publicKeyHex) == null,
      ),
    );
  }

  List<Contact> get discoveredContacts {
    return List.unmodifiable(_discoveredContacts);
  }

  /// Adds a full-key zero-hop discovery response to the local discovery list.
  /// The response does not contain an advert, so existing contact details are
  /// retained when available and otherwise a minimal entry is created.
  void recordZeroHopDiscoveredContact({
    required Uint8List publicKey,
    required int type,
    String? name,
  }) {
    if (publicKey.length != pubKeySize ||
        listEquals(publicKey, _selfPublicKey)) {
      return;
    }

    final publicKeyHex = pubKeyToHex(publicKey);
    final now = DateTime.now();
    final discoveredName = name?.trim() ?? '';
    final contactIndex = _contacts.indexWhere(
      (contact) => contact.publicKeyHex == publicKeyHex,
    );
    final discoveredIndex = _discoveredContacts.indexWhere(
      (contact) => contact.publicKeyHex == publicKeyHex,
    );

    if (discoveredIndex >= 0) {
      final existing = _discoveredContacts[discoveredIndex];
      final known = contactIndex >= 0 ? _contacts[contactIndex] : null;
      _discoveredContacts[discoveredIndex] = existing.copyWith(
        name: discoveredName.isNotEmpty
            ? discoveredName
            : known != null && known.name.isNotEmpty
            ? known.name
            : existing.name,
        type: type,
        pathLength: 0,
        path: Uint8List(0),
        latitude: known?.latitude ?? existing.latitude,
        longitude: known?.longitude ?? existing.longitude,
        lastSeen: now,
        isActive: known != null,
        rawPacket: known?.rawPacket ?? existing.rawPacket,
      );
    } else {
      final known = contactIndex >= 0 ? _contacts[contactIndex] : null;
      if (_discoveredContacts.length >= _discoveredContactsLimit) {
        _evictStalestDiscoveredContact();
      }
      _discoveredContacts.add(
        Contact(
          publicKey: Uint8List.fromList(publicKey),
          name: discoveredName.isNotEmpty ? discoveredName : known?.name ?? '',
          type: type,
          pathLength: 0,
          path: Uint8List(0),
          latitude: known?.latitude,
          longitude: known?.longitude,
          lastSeen: now,
          lastMessageAt: known?.lastMessageAt,
          hasMessages: known?.hasMessages ?? false,
          isActive: known != null,
          rawPacket: known?.rawPacket,
        ),
      );
    }

    unawaited(_persistDiscoveredContacts());
    notifyListeners();
  }

  String exportDiscoveredContactsJson() =>
      _discoveryContactStore.exportContactsJson(_discoveredContacts);

  /// Imports an export file into the discovered contacts. Throws
  /// [FormatException] when the file is not a contacts list.
  Future<DiscoveredContactsImportResult> importDiscoveredContactsJson(
    String json,
  ) async {
    if (!isConnected) return DiscoveredContactsImportResult.empty;
    final result = _discoveryContactStore.importContactsJson(
      json: json,
      existingContacts: _discoveredContacts,
      knownContactKeys: _knownContactKeys,
      selfPublicKeyHex: selfPublicKeyHex,
    );
    if (result.imported == 0) return result;
    while (_discoveredContacts.length > _discoveredContactsLimit) {
      _evictStalestDiscoveredContact();
    }
    await _persistDiscoveredContacts();
    notifyListeners();
    return result;
  }

  List<Channel> get channels => List.unmodifiable(_channels);
  bool get isConnected => _state == MeshCoreConnectionState.connected;
  bool get isOfflineMode => _isOfflineMode;
  bool get isOfflineSharedMode => _isOfflineMode && _isOfflineSharedMode;
  String? get offlineHistoryScope => _offlineHistoryScope;
  bool get hasReadableSession => isConnected || isOfflineMode;
  bool get wasManuallyDisconnected => _manualDisconnect;
  bool get isRecoveringConnection => _isRecoveringConnection;

  /// Whether the link is being torn down to come straight back
  /// (`_restartActiveTransport`, which the optional module behind
  /// `SettingsSectionsService` asks for after a command that changes the
  /// node's session, or when a client of its own needs the node's frames
  /// unframed): a manual disconnect in the connector's terms, which neither
  /// the app shell nor `DisconnectNavigationMixin` may take for the user's.
  bool get isRestartingTransport => _transportRestartInProgress;
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
  Set<int> get unconfirmedChannelSlots =>
      Set.unmodifiable(_unconfirmedChannelSlots);
  Stream<Uint8List> get receivedFrames => _receivedFramesController.stream;

  /// Broadcast of MCMP v3 channel/room signing failures; see
  /// [_mcmpSigningFailedController].
  Stream<void> get mcmpSigningFailures => _mcmpSigningFailedController.stream;
  Uint8List? get selfPublicKey => _selfPublicKey;
  String get selfPublicKeyHex => _offlinePublicKeyHex ?? _selfPublicKeyHex;

  /// First 2 bytes of the local public key, big-endian: the `senderPrefix`
  /// stamped into every outgoing image chunk header. Null until SELF_INFO.
  int? get imageSenderPrefix => senderPrefixFromKey(_selfPublicKey);

  String? get selfName => _selfName;
  String? get manufacturerName => _boardName;
  String? get firmwareVersionString => _firmwareVersion;
  double? get selfLatitude => _selfLatitude;
  double? get selfLongitude => _selfLongitude;
  List<DirectRepeater> get directRepeaters => _directRepeaters;
  List<DirectRepeater> get activeRepeaters => _activeRepeaters;
  int? get currentTxPower => _currentTxPower;
  int? get maxTxPower => _maxTxPower;

  int get pathHashByteWidth => _pathHashByteWidth;

  CompanionRadioStats? get latestRadioStats => _latestRadioStats;

  bool get supportsCompanionRadioStats => (_firmwareVerCode ?? 0) >= 8;

  /// Whether the last poll window saw the air busy
  /// ([_airtimeGrewInLastPoll]): every dot built in that window, on any
  /// screen, reads the same answer until the next stats frame.
  bool get radioStatsAirActivityPulse => _airtimeGrewInLastPoll;

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

  /// autoadd_max_hops from GET_AUTOADD_CONFIG (0 = no limit), null when the
  /// firmware did not report it (pre-v1.13).
  int? get autoAddMaxHops => _autoAddMaxHops;

  /// CMD_GET/SET_AUTOADD_CONFIG exist from companion v1.12.0 (ver code 8).
  bool get supportsAutoAddConfig => (_firmwareVerCode ?? 0) >= 8;

  /// CMD_GET_ALLOWED_REPEAT_FREQ exists from ver code 9 (client repeat).
  bool get supportsAllowedRepeatFreq => (_firmwareVerCode ?? 0) >= 9;

  /// CMD_SET_FLOOD_SCOPE `[54,1]` (send unscoped, overriding the radio's
  /// default scope) exists from ver code 12.
  bool get supportsExplicitUnscopedFlood => (_firmwareVerCode ?? 0) >= 12;

  /// Frequency ranges (kHz, inclusive) on which the firmware accepts client
  /// repeat mode. Null until RESP_ALLOWED_REPEAT_FREQ has been received.
  List<RepeatFreqRange>? get allowedRepeatFreqRanges =>
      _allowedRepeatFreqRanges;

  /// True after PUSH_CODE_CONTACTS_FULL: the firmware could not store a new
  /// contact. Cleared when a contact is removed or deleted.
  bool get contactsStorageFull => _contactsStorageFull;

  /// Fires on each PUSH_CODE_CONTACTS_FULL.
  Stream<void> get contactsFullEvents => _contactsFullController.stream;
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
    _contactRegionStore.setPublicKeyHex = publicKeyHex;
    _contactSettingsStore.setPublicKeyHex = publicKeyHex;
    _contactStore.setPublicKeyHex = publicKeyHex;
    _channelStore.setPublicKeyHex = publicKeyHex;
    _nodeIdentityStore.setPublicKeyHex = publicKeyHex;
    _unreadStore.setPublicKeyHex = publicKeyHex;
    _pathHistoryService?.setDevicePublicKey(publicKeyHex);
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
    _markerScannedContactKeys.clear();
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
        final storedMessages = await messageStore.loadLatestChannelMessages(
          channel.index,
          limit: _offlineSharedHistoryWindowSize,
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
      final mergedMessages = _orderedChannelMessages(
        (messagesByIdentity[entry.key] ?? const [])
            .map((message) => message.copyWith(channelIndex: syntheticIndex))
            .toList(),
      );
      _channelMessages[syntheticIndex] =
          mergedMessages.length > _offlineSharedHistoryWindowSize
          ? mergedMessages.sublist(
              mergedMessages.length - _offlineSharedHistoryWindowSize,
            )
          : mergedMessages;
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

    final summaries = <String, MessageStoreSummary>{};
    for (final scope in scopes) {
      final scopeSummaries = await (MessageStore()..setPublicKeyHex = scope)
          .loadMessageSummaries(contactKeys, includeLegacyUnscoped: false);
      for (final entry in scopeSummaries.entries) {
        final existing = summaries[entry.key];
        final current = entry.value;
        summaries[entry.key] = MessageStoreSummary(
          messageCount: (existing?.messageCount ?? 0) + current.messageCount,
          latestMessageAt:
              existing == null ||
                  current.latestMessageAt.isAfter(existing.latestMessageAt)
              ? current.latestMessageAt
              : existing.latestMessageAt,
          latestMessageText:
              existing == null ||
                  current.latestMessageAt.isAfter(existing.latestMessageAt)
              ? current.latestMessageText
              : existing.latestMessageText,
        );
      }
    }

    for (var i = 0; i < contactKeys.length; i++) {
      if (i > 0 && i % 8 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final contactKeyHex = contactKeys[i];
      final latestSummary = summaries[contactKeyHex];

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

  /// Like [getLoadedChannelMessages], plus shared history that is already in
  /// memory. Still starts no load of its own — call
  /// [ensureSharedChannelHistoryLoaded] for that — so an aggregate screen can
  /// read other nodes' messages without pulling every channel on every build.
  List<ChannelMessage> getLoadedChannelMessagesWithShared(Channel channel) {
    final primary = _channelMessages[channel.index] ?? const <ChannelMessage>[];
    if (isOfflineMode || !_sharedChannelsEnabled) return primary;
    final secondary = _sharedChannelSecondaryMessages[channel.index];
    if (secondary == null || secondary.isEmpty) return primary;
    return _mergeChannelMessages(primary, secondary);
  }

  /// Contact-chat counterpart of [getLoadedChannelMessagesWithShared].
  List<Message> getLoadedMessagesWithShared(Contact contact) {
    final primary = _conversations[contact.publicKeyHex] ?? const <Message>[];
    if (isOfflineMode || !_sharedContactsEnabled) return primary;
    final secondary = _sharedContactSecondaryMessages[contact.publicKeyHex];
    if (secondary == null || secondary.isEmpty) return primary;
    return _mergeContactMessages(primary, secondary);
  }

  /// Warms shared history for every channel, so a screen that shows all
  /// channels at once — the map and its shared markers — sees other nodes'
  /// messages. Each channel loads once; repeat calls are no-ops.
  void ensureSharedChannelHistoryLoaded() {
    if (!_sharedChannelsEnabled) return;
    for (final channel in _channels) {
      if (channel.isEmpty) continue;
      _ensureSharedChannelHistory(channel);
    }
  }

  /// Warms message history for every contact, for the same reason: a screen
  /// showing all of them at once should not need each chat to have been
  /// opened first. Unlike channels, whose messages arrive with the session,
  /// a conversation is read from storage only when something asks for it —
  /// which is why markers shared by contacts used to appear on the map only
  /// after visiting the chat. Repeaters are skipped: their history is CLI
  /// traffic, never markers.
  ///
  /// A conversation is one JSON blob, so warming them back to back decodes
  /// the whole message store in a single frame. Three things keep that off the
  /// frame at a few hundred contacts:
  ///
  /// * only conversations that could hold a pin are decoded at all — cached
  ///   marker keys reject the rest before their database rows are loaded;
  /// * `knownScopes()` is read once for the whole sweep, not per contact — it
  ///   walks every known storage key, so that alone dominated the cost;
  /// * each contact is examined once ever ([_markerScannedContactKeys]), and
  ///   the pass yields to the event loop as it goes.
  ///
  /// A conversation skipped this way is left unloaded rather than marked
  /// loaded, so opening its chat still reads it as before; the map does not
  /// need it, since a marker arriving later loads the conversation on the
  /// receive path anyway.
  ///
  /// Safe to call from `build`: once everything is warm the pass finds nothing
  /// to do, stops yielding and — importantly — does not notify, so it cannot
  /// drive a rebuild that starts it again.
  void ensureContactHistoryLoaded() {
    if (_warmingContactHistory) return;
    _warmingContactHistory = true;
    unawaited(() async {
      var warmed = false;
      try {
        final scopes = _sharedContactsEnabled
            ? SharedMessageHistoryHelper.knownScopes()
            : const <String>{};
        var sinceYield = 0;
        for (final contact in List<Contact>.from(_contacts)) {
          if (contact.type == advTypeRepeater) continue;
          final contactKeyHex = contact.publicKeyHex;
          if (!_markerScannedContactKeys.add(contactKeyHex)) continue;

          var opened = false;
          if (!_loadedConversationKeys.contains(contactKeyHex) &&
              _messageStore.mayContainMarker(contactKeyHex)) {
            await _loadMessagesForContact(contactKeyHex);
            opened = true;
          }
          if (scopes.isNotEmpty &&
              contact.type != advTypeRoom &&
              SharedMessageHistoryHelper.secondaryMayContainMarker(
                currentPublicKeyHex: selfPublicKeyHex,
                contactKeyHex: contactKeyHex,
                scopes: scopes,
              ) &&
              _ensureSharedContactHistory(contact)) {
            opened = true;
          }
          if (opened) warmed = true;
          // Yield after anything that decoded, and periodically anyway: the
          // scans are cheap each but there are hundreds of them.
          if (opened || ++sinceYield >= 25) {
            sinceYield = 0;
            await Future<void>.delayed(Duration.zero);
          }
        }
      } finally {
        _warmingContactHistory = false;
      }
      // An empty conversation loads without notifying, so the pass reports
      // its own result rather than relying on the loaders to have done it.
      if (warmed) notifyListeners();
    }());
  }

  Future<void> deleteMessage(Message message) async {
    final pending = _pendingContactSends.remove(message.messageId);
    if (pending != null) {
      pending.timer?.cancel();
      notifyListeners();
      return;
    }
    final contactKeyHex = message.senderKeyHex;
    var changed = false;
    final messages = _conversations[contactKeyHex];
    if (messages != null && messages.remove(message)) {
      _retryService?.untrack(message.messageId);
      unawaited(
        _messageStore
            .deleteMessage(contactKeyHex, message.messageId)
            .catchError((error, stackTrace) {
              appLogger.warn(
                'Could not delete contact message ${message.messageId}: '
                '$error\n$stackTrace',
                tag: 'MessageHistory',
              );
            }),
      );
      changed = true;
    }
    if (_deleteSharedContactMessage(contactKeyHex, message)) {
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Contact-chat counterpart of [_deleteSharedChannelMessage].
  bool _deleteSharedContactMessage(
    String contactKeyHex,
    Message message,
  ) {
    final secondary = _sharedContactSecondaryMessages[contactKeyHex];
    if (secondary == null || secondary.isEmpty) return false;
    final before = secondary.length;
    secondary.removeWhere((current) => current.messageId == message.messageId);
    if (secondary.length == before) return false;
    unawaited(
      () async {
        try {
          await _sharedMessageHistoryHelper.deleteSecondaryContactMessage(
            currentPublicKeyHex: selfPublicKeyHex,
            contactKeyHex: contactKeyHex,
            messageId: message.messageId,
          );
        } catch (error, stackTrace) {
          appLogger.warn(
            'Could not delete shared contact message ${message.messageId}: '
            '$error\n$stackTrace',
            tag: 'MessageHistory',
          );
        }
      }(),
    );
    return true;
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

  void _loadMessagesForContactInBackground(String contactKeyHex) {
    if (_activeContactKey != contactKeyHex) {
      return;
    }
    if (_loadedConversationKeys.contains(contactKeyHex) ||
        _conversationLoadFutures.containsKey(contactKeyHex)) {
      return;
    }

    unawaited(
      _loadMessagesForContact(contactKeyHex).catchError((error, stackTrace) {
        appLogger.error(
          'Failed to warm contact messages for $contactKeyHex: $error\n$stackTrace',
          tag: 'Connector',
        );
      }),
    );
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
            .loadLatestMessages(
              contactKeyHex,
              limit: _offlineSharedHistoryWindowSize,
            );
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
      if (_isRoomConversation(contactKeyHex)) {
        merged.sort(RoomMessageTimelineHelper.compare);
      } else {
        merged.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      }
      final windowedMessages = merged.length > _offlineSharedHistoryWindowSize
          ? merged.sublist(
              merged.length - _offlineSharedHistoryWindowSize,
            )
          : merged;
      _conversations[contactKeyHex] = windowedMessages;
      _applyContactMessageSummaryFromMessages(contactKeyHex, windowedMessages);
      notifyListeners();
      return;
    }
    final allMessages = List<Message>.of(
      await _messageStore.loadLatestMessages(
        contactKeyHex,
        limit: _initialContactHistorySize,
      ),
    );
    if (generation != _conversationLoadGeneration) return;
    if (_isRoomConversation(contactKeyHex)) {
      allMessages.sort(RoomMessageTimelineHelper.compare);
    }
    _applyContactMessageSummaryFromMessages(contactKeyHex, allMessages);
    if (allMessages.isNotEmpty) {
      // Keep only the most recent N messages in memory to bound memory usage
      final windowedMessages = allMessages.length > _initialContactHistorySize
          ? allMessages.sublist(
              allMessages.length - _initialContactHistorySize,
            )
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
      if (_isRoomConversation(contactKeyHex)) {
        mergedMessages.sort(RoomMessageTimelineHelper.compare);
      } else {
        mergedMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      }
      final windowedMergedMessages =
          mergedMessages.length > _initialContactHistorySize
          ? mergedMessages.sublist(
              mergedMessages.length - _initialContactHistorySize,
            )
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

  bool _isRoomConversation(String contactKeyHex) => _contacts.any(
    (contact) =>
        contact.publicKeyHex == contactKeyHex && contact.type == advTypeRoom,
  );

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
    final persistedSummaries = await _messageStore.loadMessageSummaries(
      contactKeys.keys,
      includeLegacyUnscoped: !isOfflineMode,
    );
    final sharedContactKeys = contactEntries
        .where((entry) => entry.value)
        .map((entry) => entry.key);
    final sharedSummaries = selfPublicKeyHex.isEmpty
        ? const <String, MessageStoreSummary>{}
        : await _sharedMessageHistoryHelper
              .loadSecondaryContactMessageSummaries(
                currentPublicKeyHex: selfPublicKeyHex,
                contactKeyHexes: sharedContactKeys,
              );
    var changed = false;
    var previewChanged = stalePreviewKeys.isNotEmpty;
    for (var i = 0; i < contactEntries.length; i++) {
      if (i > 0 && i % 8 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final entry = contactEntries[i];
      final contactKeyHex = entry.key;
      var latestSummary = _loadedContactMessageSummary(contactKeyHex);
      latestSummary ??= persistedSummaries[contactKeyHex];
      if (entry.value) {
        final sharedSummary = sharedSummaries[contactKeyHex];
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
  Future<List<Message>> loadLatestPersistedMessages(
    String contactKeyHex, {
    required int limit,
  }) {
    return _messageStore.loadLatestMessages(contactKeyHex, limit: limit);
  }

  Future<List<Message>> loadOlderMessages(
    String contactKeyHex, {
    int count = 50,
  }) async {
    if (isOfflineSharedMode) return const [];
    final currentMessages = _conversations[contactKeyHex] ?? [];
    if (currentMessages.isEmpty) return const [];
    final olderMessages = await _messageStore.loadMessagesBefore(
      contactKeyHex,
      before: currentMessages.first,
      limit: count,
    );
    if (olderMessages.isEmpty) return const [];

    // Prepend to current conversation
    final expandedMessages = [...olderMessages, ...currentMessages];
    if (_isRoomConversation(contactKeyHex)) {
      expandedMessages.sort(RoomMessageTimelineHelper.compare);
    }
    _conversations[contactKeyHex] = expandedMessages;
    notifyListeners();

    return olderMessages;
  }

  /// Appends the next persisted page after the newest loaded direct message.
  /// Kept as a dormant counterpart to [loadOlderMessages] until a screen needs
  /// bidirectional history navigation.
  Future<List<Message>> loadNewerMessages(
    String contactKeyHex, {
    int count = 50,
  }) async {
    if (isOfflineSharedMode) return const [];
    final currentMessages = _conversations[contactKeyHex] ?? [];
    if (currentMessages.isEmpty) return const [];
    final newerMessages = await _messageStore.loadMessagesAfter(
      contactKeyHex,
      after: currentMessages.last,
      limit: count,
    );
    if (newerMessages.isEmpty) return const [];

    final expandedMessages = [...currentMessages, ...newerMessages];
    if (_isRoomConversation(contactKeyHex)) {
      expandedMessages.sort(RoomMessageTimelineHelper.compare);
    }
    _conversations[contactKeyHex] = expandedMessages;
    notifyListeners();
    return newerMessages;
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

  /// Stable, filtered timeline for one channel's transcript.
  ///
  /// The source lists contain immutable message snapshots. Comparing their
  /// identities is enough to detect a real history change without rebuilding
  /// the merged and sorted view for unrelated connector notifications.
  List<ChannelMessage> getChannelMessageTimeline(Channel channel) {
    final primary = _channelMessages[channel.index] ?? const <ChannelMessage>[];
    var secondary = const <ChannelMessage>[];
    if (!isOfflineMode && _sharedChannelsEnabled) {
      _ensureSharedChannelHistory(channel);
      secondary =
          _sharedChannelSecondaryMessages[channel.index] ??
          const <ChannelMessage>[];
    }
    final pending = getPendingChannelMessages(channel.index);
    final channelName = _channelDisplayName(channel.index);
    return _channelMessageTimelineCache.resolve(
      channelIndex: channel.index,
      primary: primary,
      secondary: secondary,
      pending: pending,
      filterRevision: BlockedSenders.instance.revision,
      filterKey: channelName,
      merge: _mergeChannelMessages,
      include: (message) =>
          !BlockedSenders.instance.hidesMessageWidget(message, channelName),
    );
  }

  /// The history [getChannelMessageTimeline] is filtered from: own messages
  /// merged with the shared ones, no pending sends, no blocked-sender filter,
  /// the same content [getChannelMessages] merges anew on every call. This one
  /// comes from the timeline cache and is a new object only when the timeline
  /// is rebuilt, so a caller may index it by identity.
  List<ChannelMessage> getChannelMergedMessages(Channel channel) {
    getChannelMessageTimeline(channel);
    return _channelMessageTimelineCache.merged(channel.index);
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

  /// Returns true when this call actually started a load, so a caller
  /// warming many contacts can tell a real read from a no-op.
  bool _ensureSharedContactHistory(Contact contact) {
    if (!_sharedContactsEnabled || contact.type == advTypeRoom) return false;
    final contactKeyHex = contact.publicKeyHex;
    if (_hiddenSharedContactKeys.contains(contactKeyHex)) return false;
    if (_loadingSharedContactKeys.contains(contactKeyHex)) return false;
    if (_sharedContactSecondaryMessages.containsKey(contactKeyHex)) {
      return false;
    }
    if (selfPublicKeyHex.isEmpty || contactKeyHex.isEmpty) return false;

    final expectedPublicKeyHex = selfPublicKeyHex;
    _loadingSharedContactKeys.add(contactKeyHex);
    unawaited(() async {
      try {
        final secondary = await _sharedMessageHistoryHelper
            .loadSecondaryContactMessages(
              currentPublicKeyHex: expectedPublicKeyHex,
              contactKeyHex: contactKeyHex,
              isCancelled: () => expectedPublicKeyHex != selfPublicKeyHex,
            );
        if (expectedPublicKeyHex != selfPublicKeyHex) return;
        _sharedContactSecondaryMessages[contactKeyHex] = secondary;
        notifyListeners();
      } finally {
        _loadingSharedContactKeys.remove(contactKeyHex);
      }
    }());
    return true;
  }

  List<ChannelMessage> _mergeChannelMessages(
    List<ChannelMessage> primary,
    List<ChannelMessage> secondary,
  ) {
    return mergeChannelMessagesPreservingPrimaryOrder(primary, secondary);
  }

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
    return ChannelMessageTimelineHelper.compare(a, b);
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
    // The identity table's revision is part of it: a channel that gains a
    // name has more shared history to fetch.
    return '${channel.name.trim().toLowerCase()}|'
        '${channel.pskHex.toLowerCase()}|'
        '${ChannelIdentities.instance.revision}';
  }

  Future<void> deleteChannelMessage(
    Channel channel,
    ChannelMessage message,
  ) async {
    _retriableChannelMessageSends.remove(message.messageId);
    final pending = _pendingChannelSends.remove(message.messageId);
    if (pending != null) {
      pending.timer?.cancel();
      notifyListeners();
      return;
    }
    final channelIndex = channel.index;
    var changed = false;
    final messages = _channelMessages[channelIndex];
    if (messages != null && messages.remove(message)) {
      _cancelChannelNoRetransmissionWarning(message.messageId);
      unawaited(
        _channelMessageStore
            .deleteChannelMessage(
              channelIndex,
              message.messageId,
            )
            .catchError((error, stackTrace) {
              appLogger.warn(
                'Could not delete channel message ${message.messageId}: '
                '$error\n$stackTrace',
                tag: 'MessageHistory',
              );
            }),
      );
      changed = true;
    }
    if (_deleteSharedChannelMessage(channel, message)) {
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Marks one already-received channel message as blocked.
  ///
  /// A block otherwise reaches forward only. The message the block was ordered
  /// from is the exception: it is the one the user was looking at, so it is
  /// hidden with everything that follows and any command it carried — a marker
  /// or a `del:` — stops counting. Marked in both scopes for the same reason
  /// deletes are: the same message can sit in this node's store and in a
  /// shared one, and flagging only the local copy lets the merge uncover the
  /// unflagged twin.
  /// The room-server twin of [markChannelMessageBlocked], with the same walk
  /// from the newest post back to the anchor.
  Future<void> markContactMessageBlocked(
    Contact contact,
    Message message,
  ) async {
    if (message.isOutgoing || message.wasBlocked) return;
    final contactKeyHex = contact.publicKeyHex;
    var changed = false;
    final flagged = <String>{message.messageId};
    final messages = _conversations[contactKeyHex];
    if (messages != null) {
      final anchor = messages.indexWhere(
        (current) => current.messageId == message.messageId,
      );
      if (anchor >= 0) {
        var touched = false;
        for (var i = messages.length - 1; i >= anchor; i--) {
          final current = messages[i];
          if (current.wasBlocked) continue;
          if (i != anchor &&
              !BlockedSenders.instance.isRoomAuthorBlocked(current)) {
            continue;
          }
          messages[i] = current.copyWith(wasBlocked: true);
          flagged.add(current.messageId);
          touched = true;
        }
        if (touched) {
          await _messageStore.saveMessages(contactKeyHex, messages);
          changed = true;
        }
      }
    }
    for (final messageId in flagged) {
      if (await _sharedMessageHistoryHelper.markSecondaryContactMessageBlocked(
        currentPublicKeyHex: selfPublicKeyHex,
        contactKeyHex: contactKeyHex,
        messageId: messageId,
      )) {
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Flags the message a block was ordered from, and everything that sender
  /// posted after it.
  ///
  /// A rule on its own only decides what arrives once it exists, so the posts
  /// that landed while the user was reading his way up to the one he finally
  /// long-pressed would stay visible — commands and all. The walk runs from
  /// the newest message backwards and stops at that anchor, so it costs only
  /// what the user actually saw, never the whole conversation. Everything
  /// older than the anchor is deliberately left alone: a block still does not
  /// rewrite history the user had already read past.
  ///
  /// The anchor itself is flagged whatever the rule says — the user pointed at
  /// it. The messages above it are flagged only if the rule really covers
  /// them, so a namesake exempted by a verified key stays visible.
  Future<void> markChannelMessageBlocked(
    Channel channel,
    ChannelMessage message,
  ) async {
    if (message.isOutgoing || message.wasBlocked) return;
    var changed = false;
    final flagged = <ChannelMessage>[];
    final messages = _channelMessages[channel.index];
    if (messages != null) {
      final label = _channelDisplayName(channel.index);
      final anchor = messages.indexWhere(
        (current) => current.messageId == message.messageId,
      );
      if (anchor >= 0) {
        for (var i = messages.length - 1; i >= anchor; i--) {
          final current = messages[i];
          if (current.wasBlocked) continue;
          if (i != anchor &&
              !BlockedSenders.instance.isSenderBlocked(current, label)) {
            continue;
          }
          messages[i] = current.copyWith(wasBlocked: true);
          flagged.add(current);
        }
        if (flagged.isNotEmpty) {
          await _channelMessageStore.saveChannelMessages(
            channel.index,
            messages,
          );
          changed = true;
        }
      }
    }
    // The anchor may exist only in a shared scope, so it is offered there even
    // when the loop above found nothing to flag.
    for (final blocked in {message, ...flagged}) {
      if (await _markSharedChannelMessageBlocked(channel, blocked)) {
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  Future<bool> _markSharedChannelMessageBlocked(
    Channel channel,
    ChannelMessage message,
  ) async {
    final secondary = _sharedChannelSecondaryMessages[channel.index];
    if (secondary == null || secondary.isEmpty) return false;
    final index = secondary.indexWhere(
      (current) => current.messageId == message.messageId,
    );
    if (index < 0 || secondary[index].wasBlocked) return false;
    secondary[index] = secondary[index].copyWith(wasBlocked: true);
    await _sharedMessageHistoryHelper.markSecondaryChannelMessageBlocked(
      currentPublicKeyHex: selfPublicKeyHex,
      channel: channel,
      messageId: message.messageId,
    );
    return true;
  }

  /// Deletes the shared-history copies of [message], both the merged-in list
  /// and the other node's store it was read from. Matching by message id also
  /// catches the copy the merge hid when the same message exists in both
  /// scopes — otherwise deleting the local one just uncovers it again.
  bool _deleteSharedChannelMessage(
    Channel channel,
    ChannelMessage message,
  ) {
    final secondary = _sharedChannelSecondaryMessages[channel.index];
    if (secondary == null || secondary.isEmpty) return false;
    final before = secondary.length;
    secondary.removeWhere((current) => current.messageId == message.messageId);
    if (secondary.length == before) return false;
    unawaited(
      () async {
        try {
          await _sharedMessageHistoryHelper.deleteSecondaryChannelMessage(
            currentPublicKeyHex: selfPublicKeyHex,
            channel: channel,
            messageId: message.messageId,
          );
        } catch (error, stackTrace) {
          appLogger.warn(
            'Could not delete shared channel message ${message.messageId}: '
            '$error\n$stackTrace',
            tag: 'MessageHistory',
          );
        }
      }(),
    );
    return true;
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

  /// Mirrors the store default (v3) for the window before the stored value
  /// has been read back; keep the two in step.
  int channelMcmpVersion(int channelIndex) {
    return _channelMcmpVersion[channelIndex] ?? 3;
  }

  /// Mirrors the store default (unsigned); keep the two in step.
  bool channelMcmpUseSign(int channelIndex) {
    return _channelMcmpUseSign[channelIndex] ?? false;
  }

  /// Whether the channel signs its MCMP v3 bodies, which receivers verify
  /// against the node's own name: the one setting a sender name of the
  /// channel's own cannot coexist with (see channel_sender_name.dart).
  bool channelSendsSignedMcmp(int channelIndex) =>
      isChannelMcmpEnabled(channelIndex) &&
      channelMcmpVersion(channelIndex) == 3 &&
      channelMcmpUseSign(channelIndex);

  /// Whether the node sends a packet the app built (CMD_SEND_RAW_PACKET):
  /// stock firmware has the command from version code 13. It arrived at 12,
  /// on 2026-05-13, so a 12 may or may not have it.
  bool get supportsRawPacketSend => (_firmwareVerCode ?? 0) >= 13;

  /// The name the channel is set to send under instead of the node's, as
  /// stored, whatever holds it back: null when none.
  String? channelSenderName(int channelIndex) =>
      channelSenderNameFromSetting(_channelSenderNames[channelIndex]);

  /// Why the channel cannot send under a name of its own, or none.
  ChannelSenderNameLock channelSenderNameLock(int channelIndex) =>
      resolveChannelSenderNameLock(
        signsMcmp: channelSendsSignedMcmp(channelIndex),
        firmwareSendsRawPackets: supportsRawPacketSend,
        scope: _outgoingChannelRegion(channelIndex),
      );

  /// The channel's own sender name while it is in effect, else null: the
  /// node's name is what the channel sends under then.
  String? channelSenderNameInEffect(int channelIndex) =>
      channelSenderNameLock(channelIndex) == ChannelSenderNameLock.none
      ? channelSenderName(channelIndex)
      : null;

  /// The name a message to the channel goes out under.
  String channelSendName(int channelIndex) =>
      channelSenderNameInEffect(channelIndex) ?? _selfName ?? 'Me';

  /// The bytes of text a message to the channel may carry under the name it
  /// goes out with. A packet built by the app (see [ChannelRawPacket]) has
  /// to fit the companion frame with its own header: 160 bytes of plaintext
  /// where the node's command takes 165, so the channel's own name costs
  /// five bytes of text on top of its length.
  int maxChannelTextBytes(int channelIndex) {
    final name = channelSendName(channelIndex);
    final limit = maxChannelMessageBytes(name);
    if (channelSenderNameInEffect(channelIndex) == null) return limit;
    return math.max(
      0,
      math.min(
        limit,
        ChannelRawPacket.maxGroupTextBytes - channelSenderPrefixBytes(name),
      ),
    );
  }

  /// Whether [name] names this node in the channel: the node's own name, or
  /// the sender name the channel keeps, which earlier messages may carry
  /// whether or not it is in effect now.
  bool isChannelSenderNameOurs(int channelIndex, String? name) {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return false;
    return trimmed == _selfName?.trim() ||
        trimmed == channelSenderName(channelIndex);
  }

  bool isChannelUrlImagesEnabled(int channelIndex) {
    return _channelUrlImagesEnabled[channelIndex] ?? false;
  }

  bool isContactUrlImagesEnabled(String contactKeyHex) {
    _ensureContactUrlImagesSettingLoaded(contactKeyHex);
    return _contactUrlImagesEnabled[contactKeyHex] ?? false;
  }

  bool isChannelMCOtxtEnabled(int channelIndex) {
    return _channelMCOtxtEnabled[channelIndex] ?? false;
  }

  /// Mirrors the store default (on), as [channelMcmpVersion] does.
  bool isChannelMCOtxtPlainWhenSmaller(int channelIndex) {
    return _channelMCOtxtPlainWhenSmaller[channelIndex] ?? true;
  }

  bool isChannelSmazEnabled(int channelIndex) {
    return _channelSmazEnabled[channelIndex] ?? false;
  }

  bool isContactMcmpEnabled(String contactKeyHex) {
    return _contactMcmpEnabled[contactKeyHex] ?? false;
  }

  /// Mirrors the store default (v3), as [channelMcmpVersion] does.
  int contactMcmpVersion(String contactKeyHex) {
    return _contactMcmpVersion[contactKeyHex] ?? 3;
  }

  /// Mirrors the store default (unsigned), as [channelMcmpUseSign] does.
  bool contactMcmpUseSign(String contactKeyHex) {
    return _contactMcmpUseSign[contactKeyHex] ?? false;
  }

  bool isContactMCOtxtEnabled(String contactKeyHex) {
    return _contactMCOtxtEnabled[contactKeyHex] ?? false;
  }

  /// Mirrors the store default (on), as [contactMcmpVersion] does.
  bool isContactMCOtxtPlainWhenSmaller(String contactKeyHex) {
    return _contactMCOtxtPlainWhenSmaller[contactKeyHex] ?? true;
  }

  bool isContactSmazEnabled(String contactKeyHex) {
    return _contactSmazEnabled[contactKeyHex] ?? false;
  }

  void ensureContactMcmpSettingLoaded(String contactKeyHex) {
    _ensureContactMcmpSettingLoaded(contactKeyHex);
    _ensureContactMcmpVersionLoaded(contactKeyHex);
    _ensureContactMcmpUseSignLoaded(contactKeyHex);
  }

  void ensureContactMCOtxtSettingLoaded(String contactKeyHex) {
    _ensureContactMCOtxtSettingLoaded(contactKeyHex);
    _ensureContactMCOtxtPlainWhenSmallerLoaded(contactKeyHex);
  }

  /// True when the channel has its own (real) region assigned.
  bool hasChannelRegion(int channelIndex) {
    return getChannelRegion(channelIndex).isNotEmpty;
  }

  /// The channel's own region, or '' when it follows the node's default
  /// scope or is set to "no region" (see [isChannelExplicitlyUnscoped]).
  Region getChannelRegion(int channelIndex) {
    final region = _channelRegions[channelIndex] ?? '';
    return region == kUnscopedRegion ? '' : region;
  }

  /// True when the user picked "no region" for this channel: its floods
  /// carry no scope at all, the node's default scope included, on firmware
  /// that takes the no-scope flag (see [_runScopedChannelSend]).
  bool isChannelExplicitlyUnscoped(int channelIndex) =>
      _channelRegions[channelIndex] == kUnscopedRegion;

  /// True when a send on this channel goes out with no scope at all.
  bool _sendsChannelUnscoped(int channelIndex) =>
      isChannelExplicitlyUnscoped(channelIndex) &&
      supportsExplicitUnscopedFlood &&
      !_unscopedSendUnsupported;

  /// True when floods on this channel go out under the node's default scope:
  /// the channel has no region of its own, and "no region" cannot override
  /// the default on this firmware.
  bool channelUsesRadioDefaultScope(int channelIndex) =>
      _defaultRegionScope != null &&
      !hasChannelRegion(channelIndex) &&
      !_sendsChannelUnscoped(channelIndex);

  /// What [_runScopedChannelSend] is handed for the channel: its region,
  /// [kUnscopedRegion], or '' for the node's default scope.
  Region _channelSendScope(int channelIndex) =>
      _channelRegions[channelIndex] ?? '';

  /// The region [contactKeyHex]'s flood sends are scoped with, empty when the
  /// node's default scope applies.
  Region getContactRegion(String contactKeyHex) =>
      _contactRegions[contactKeyHex] ?? '';

  /// Whether the node has answered what its default flood scope is; until
  /// then [defaultRegionScopeLabel] says nothing.
  bool get hasLoadedDefaultRegionScope => _hasLoadedDefaultRegionScope;

  /// The node's default flood scope as the region screen shows it, null when
  /// the node has none or has not answered yet.
  String? get defaultRegionScopeLabel => _hasLoadedDefaultRegionScope
      ? _displayPacketRegion(_defaultRegionScope ?? '')
      : null;

  Future<void> setContactRegion(String contactKeyHex, String region) async {
    final normalized = await _contactRegionStore.saveRegion(
      contactKeyHex,
      region,
    );
    if (normalized.isEmpty) {
      _contactRegions.remove(contactKeyHex);
    } else {
      _contactRegions[contactKeyHex] = normalized;
    }
    notifyListeners();
  }

  Future<void> _loadContactRegions(String expectedPublicKeyHex) async {
    final regions = await _contactRegionStore.loadRegions();
    if (expectedPublicKeyHex != selfPublicKeyHex) return;
    _contactRegions
      ..clear()
      ..addAll(regions);
    if (regions.isNotEmpty) notifyListeners();
  }

  Region _outgoingChannelRegion(int channelIndex) {
    final channelRegion = getChannelRegion(channelIndex).trim();
    if (channelRegion.isNotEmpty) return channelRegion;
    if (_sendsChannelUnscoped(channelIndex)) return '';
    return _defaultRegionScope?.trim() ?? '';
  }

  /// Whether a send on this channel goes out with a flood scope, which the
  /// firmware carries as four transport-code bytes in front of the path.
  bool channelSendCarriesTransportCodes(int channelIndex) =>
      _outgoingChannelRegion(channelIndex).isNotEmpty;

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
    if (_sendsChannelUnscoped(channelIndex)) return '';
    if (!_hasLoadedDefaultRegionScope && isConnected) {
      await _refreshDefaultRegionScope();
    }
    return _outgoingChannelRegion(channelIndex);
  }

  /// The region label an outgoing channel send is stamped with: the channel's
  /// own region, or the node's default scope when the channel has none. Shaped
  /// for display — no leading `#` — and null when there is no region at all.
  ///
  /// Text messages take this through [_displayPacketRegion] on the send path;
  /// an AEIC image is not a [ChannelMessage] and carries its own copy, so it
  /// needs the same answer from outside.
  Future<String?> outgoingChannelRegionLabel(int channelIndex) async =>
      _displayPacketRegion(
        await _outgoingChannelRegionForMessage(channelIndex),
      );

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
    syncAppBadge();
  }

  /// Sets the app icon badge to the current unread total, e.g. on resume, so
  /// a badge left by delivered notifications doesn't outlive the unreads.
  void syncAppBadge() {
    if (!_unreadStateLoaded) return;
    unawaited(_notificationService.setAppBadge(getTotalUnreadCount()));
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
    final previousContactKey = _activeContactKey;
    if (previousContactKey != null && previousContactKey != contactKeyHex) {
      _trimContactHistoryWindow(previousContactKey);
    }
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
    final previousChannelIndex = _activeChannelIndex;
    if (previousChannelIndex != null && previousChannelIndex != channelIndex) {
      _trimChannelHistoryWindow(previousChannelIndex);
    }
    _activeChannelIndex = channelIndex;
    if (channelIndex != null) {
      final channel = _findChannelByIndex(channelIndex);
      if (!isOfflineMode && channel != null) {
        _ensureSharedChannelHistory(channel);
      }
      markChannelRead(channelIndex);
    }
  }

  /// Releases paged history while keeping it available in SQLite.
  ///
  /// Flutter can call this under memory pressure even while a chat is open,
  /// so the currently visible contact and channel are deliberately retained.
  void trimInactiveMessageHistoryWindows() {
    for (final contactKeyHex in _conversations.keys.toList(growable: false)) {
      if (contactKeyHex != _activeContactKey) {
        _trimContactHistoryWindow(contactKeyHex);
      }
    }
    for (final channelIndex in _channelMessages.keys.toList(growable: false)) {
      if (channelIndex != _activeChannelIndex) {
        _trimChannelHistoryWindow(channelIndex);
      }
    }
  }

  void _trimContactHistoryWindow(String contactKeyHex) {
    final messages = _conversations[contactKeyHex];
    if (messages == null || messages.length <= _initialContactHistorySize) {
      return;
    }
    _conversations[contactKeyHex] = messages.sublist(
      messages.length - _initialContactHistorySize,
    );
  }

  void _trimChannelHistoryWindow(int channelIndex) {
    final messages = _channelMessages[channelIndex];
    if (messages == null || messages.length <= _initialChannelHistorySize) {
      return;
    }
    _channelMessages[channelIndex] = messages.sublist(
      messages.length - _initialChannelHistorySize,
    );
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
    final previousCount = _contactUnreadCount[contactKeyHex] ?? 0;
    _contactUnreadCount[contactKeyHex] = count;
    if (_shouldTrackUnreadForContactKey(contactKeyHex)) {
      final total = _cachedContactsUnreadTotal + (count - previousCount);
      _cachedContactsUnreadTotal = total < 0 ? 0 : total;
    }
    _unreadStore.saveContactUnreadCount(
      Map<String, int>.from(_contactUnreadCount),
    );
    notifyListeners();
  }

  void setChannelUnreadCount(int channelIndex, int count) {
    final channel = _findChannelByIndex(channelIndex);
    if (channel != null) {
      final previousCount = channel.unreadCount;
      channel.unreadCount = count;
      final total = _cachedChannelsUnreadTotal + (count - previousCount);
      _cachedChannelsUnreadTotal = total < 0 ? 0 : total;
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
      _channelMCOtxtEnabled[channelIndex] = false;
      _channelSmazEnabled[channelIndex] = false;
      _channelCyr2LatEnabled[channelIndex] = false;
      await _channelSettingsStore.saveMCOtxtEnabled(channelIndex, false);
      await _channelSettingsStore.saveSmazEnabled(channelIndex, false);
      await _channelSettingsStore.saveCyr2LatEnabled(channelIndex, false);
    }
    await _channelSettingsStore.saveMcmpEnabled(channelIndex, enabled);
    await _dropChannelSenderNameForSigning(channelIndex);
    notifyListeners();
  }

  Future<void> setChannelMcmpVersion(int channelIndex, int version) async {
    final normalized = version == 3 ? 3 : 2;
    if (_channelMcmpVersion[channelIndex] == normalized) return;
    _channelMcmpVersion[channelIndex] = normalized;
    await _channelSettingsStore.saveMcmpVersion(channelIndex, normalized);
    await _dropChannelSenderNameForSigning(channelIndex);
    notifyListeners();
  }

  Future<void> setChannelMcmpUseSign(int channelIndex, bool useSign) async {
    if (_channelMcmpUseSign[channelIndex] == useSign) return;
    _channelMcmpUseSign[channelIndex] = useSign;
    await _channelSettingsStore.saveMcmpUseSign(channelIndex, useSign);
    await _dropChannelSenderNameForSigning(channelIndex);
    notifyListeners();
  }

  /// Sets the name the channel sends under, the node's own for an empty
  /// [name]. The empty string is stored rather than the key removed: the
  /// setting is read from the owner's other nodes like every channel
  /// setting, and a name cleared here has to shadow theirs, not uncover it.
  Future<void> setChannelSenderName(int channelIndex, String? name) async {
    final value = name?.trim() ?? '';
    if (_channelSenderNames[channelIndex] == value) return;
    _channelSenderNames[channelIndex] = value;
    await _channelSettingsStore.saveSenderName(channelIndex, value);
    notifyListeners();
  }

  /// A signed MCMP v3 body verifies by the node's own name, so switching
  /// signing on takes the channel's sender name away for good rather than
  /// holding it back: held back, it would return with the next change of
  /// the setting, and nobody would know under which name they had written.
  Future<void> _dropChannelSenderNameForSigning(int channelIndex) async {
    if (!channelSendsSignedMcmp(channelIndex)) return;
    if (channelSenderName(channelIndex) == null) return;
    _channelSenderNames[channelIndex] = '';
    await _channelSettingsStore.saveSenderName(channelIndex, '');
  }

  /// Handles a reply or mark-as-read action from a message notification
  /// (notification shade, watch, or Android Auto).
  Future<void> handleNotificationReply(NotificationReply reply) async {
    if (reply.action == NotificationReplyAction.mute) {
      await _appSettingsService?.muteChannel(
        _channelDisplayName(reply.channelIndex!),
      );
      await _notificationService.clearChannelNotification(
        reply.channelIndex!,
        getTotalUnreadCount(),
      );
      return;
    }
    if (reply.action == NotificationReplyAction.markRead) {
      // markXRead only clears the notification when there were unread
      // messages; clear it here otherwise so the action always dismisses it.
      if (reply.isChannel) {
        final index = reply.channelIndex!;
        final hadUnread = getUnreadCountForChannelIndex(index) > 0;
        markChannelRead(index);
        if (!hadUnread) {
          await _notificationService.clearChannelNotification(
            index,
            getTotalUnreadCount(),
          );
        }
      } else {
        final key = reply.contactKeyHex!;
        final hadUnread = getUnreadCountForContactKey(key) > 0;
        markContactRead(key);
        if (!hadUnread) {
          await _notificationService.clearContactNotification(
            key,
            getTotalUnreadCount(),
          );
        }
      }
      return;
    }

    if (!isConnected) {
      await _notificationService.showReplyFailed(
        reply,
        NotificationReplyFailure.notConnected,
        badgeCount: getTotalUnreadCount(),
      );
      return;
    }

    final channel = reply.isChannel
        ? _findChannelByIndex(reply.channelIndex!)
        : null;
    final contact = reply.isChannel
        ? null
        : getContactByPubKeyHex(reply.contactKeyHex!);
    if (channel == null && contact == null) {
      await _notificationService.showReplyFailed(
        reply,
        NotificationReplyFailure.unavailable,
        badgeCount: getTotalUnreadCount(),
      );
      return;
    }

    // Same length limits and Cyr2Lat handling as the chat screens.
    final parts = splitMessageToFit(reply.text, (part) {
      if (channel != null) {
        return utf8
                .encode(prepareChannelOutboundText(channel.index, part))
                .length <=
            maxChannelTextBytes(channel.index);
      }
      return utf8.encode(prepareContactOutboundText(contact!, part)).length <=
          maxContactMessageBytes();
    });
    if (parts == null) {
      await _notificationService.showReplyFailed(
        reply,
        NotificationReplyFailure.tooLong,
        badgeCount: getTotalUnreadCount(),
      );
      return;
    }

    _appDebugLogService?.info(
      'Sending notification reply in ${parts.length} part(s)',
      tag: 'Notification',
    );
    for (final part in parts) {
      // sendMessage/sendChannelMessage silently do nothing when disconnected,
      // so check before every part in case the link dropped mid-reply.
      if (!isConnected) {
        await _notificationService.showReplyFailed(
          reply,
          NotificationReplyFailure.notConnected,
          badgeCount: getTotalUnreadCount(),
        );
        return;
      }
      // The chat screens transliterate before handing text over, under the
      // channel's or the contact's own cyr2lat profile; a reply from the
      // notification shade does the same here.
      var text = part;
      try {
        if (channel != null) {
          if (isChannelCyr2LatEnabled(channel.index)) {
            text = _encodeChannelCyr2Lat(channel.index, part);
          }
        } else if (isContactCyr2LatEnabled(contact!.publicKeyHex)) {
          text = _encodeContactCyr2Lat(contact, part);
        }
      } catch (_) {}
      try {
        if (channel != null) {
          await sendChannelMessage(channel, text);
        } else {
          await sendMessage(contact!, text);
        }
      } catch (e) {
        appLogger.warn('Notification reply send failed: $e');
        await _notificationService.showReplyFailed(
          reply,
          isConnected
              ? NotificationReplyFailure.sendFailed
              : NotificationReplyFailure.notConnected,
          badgeCount: getTotalUnreadCount(),
        );
        return;
      }
    }
    await _notificationService.showOwnReply(
      reply,
      reply.text,
      badgeCount: getTotalUnreadCount(),
    );
  }

  Future<void> setChannelSmazEnabled(int channelIndex, bool enabled) async {
    _channelSmazEnabled[channelIndex] = enabled;
    if (enabled) {
      _channelMcmpEnabled[channelIndex] = false;
      _channelMCOtxtEnabled[channelIndex] = false;
      _channelCyr2LatEnabled[channelIndex] = false;
      await _channelSettingsStore.saveMcmpEnabled(channelIndex, false);
      await _channelSettingsStore.saveMCOtxtEnabled(channelIndex, false);
      await _channelSettingsStore.saveCyr2LatEnabled(channelIndex, false);
    }
    await _channelSettingsStore.saveSmazEnabled(channelIndex, enabled);
    notifyListeners();
  }

  Future<void> setChannelMCOtxtEnabled(int channelIndex, bool enabled) async {
    _channelMCOtxtEnabled[channelIndex] = enabled;
    if (enabled) {
      _channelMcmpEnabled[channelIndex] = false;
      _channelSmazEnabled[channelIndex] = false;
      _channelCyr2LatEnabled[channelIndex] = false;
      await _channelSettingsStore.saveMcmpEnabled(channelIndex, false);
      await _channelSettingsStore.saveSmazEnabled(channelIndex, false);
      await _channelSettingsStore.saveCyr2LatEnabled(channelIndex, false);
    }
    await _channelSettingsStore.saveMCOtxtEnabled(channelIndex, enabled);
    notifyListeners();
  }

  Future<void> setChannelMCOtxtPlainWhenSmaller(
    int channelIndex,
    bool enabled,
  ) async {
    if (_channelMCOtxtPlainWhenSmaller[channelIndex] == enabled) return;
    _channelMCOtxtPlainWhenSmaller[channelIndex] = enabled;
    await _channelSettingsStore.saveMCOtxtPlainWhenSmaller(
      channelIndex,
      enabled,
    );
    notifyListeners();
  }

  Future<void> setContactMcmpEnabled(String contactKeyHex, bool enabled) async {
    _contactMcmpEnabled[contactKeyHex] = enabled;
    if (enabled) {
      _contactMCOtxtEnabled[contactKeyHex] = false;
      _contactSmazEnabled[contactKeyHex] = false;
      _contactCyr2LatEnabled[contactKeyHex] = false;
      await _contactSettingsStore.saveMCOtxtEnabled(contactKeyHex, false);
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
      _contactMCOtxtEnabled[contactKeyHex] = false;
      _contactCyr2LatEnabled[contactKeyHex] = false;
      await _contactSettingsStore.saveMcmpEnabled(contactKeyHex, false);
      await _contactSettingsStore.saveMCOtxtEnabled(contactKeyHex, false);
      await _contactSettingsStore.saveCyr2LatEnabled(contactKeyHex, false);
    }
    await _contactSettingsStore.saveSmazEnabled(contactKeyHex, enabled);
    notifyListeners();
  }

  Future<void> setContactMCOtxtEnabled(
    String contactKeyHex,
    bool enabled,
  ) async {
    _contactMCOtxtEnabled[contactKeyHex] = enabled;
    if (enabled) {
      _contactMcmpEnabled[contactKeyHex] = false;
      _contactSmazEnabled[contactKeyHex] = false;
      _contactCyr2LatEnabled[contactKeyHex] = false;
      await _contactSettingsStore.saveMcmpEnabled(contactKeyHex, false);
      await _contactSettingsStore.saveSmazEnabled(contactKeyHex, false);
      await _contactSettingsStore.saveCyr2LatEnabled(contactKeyHex, false);
    }
    await _contactSettingsStore.saveMCOtxtEnabled(contactKeyHex, enabled);
    notifyListeners();
  }

  Future<void> setContactMCOtxtPlainWhenSmaller(
    String contactKeyHex,
    bool enabled,
  ) async {
    if (_contactMCOtxtPlainWhenSmaller[contactKeyHex] == enabled) return;
    _contactMCOtxtPlainWhenSmaller[contactKeyHex] = enabled;
    await _contactSettingsStore.saveMCOtxtPlainWhenSmaller(
      contactKeyHex,
      enabled,
    );
    notifyListeners();
  }

  Future<void> setChannelUrlImagesEnabled(
    int channelIndex,
    bool enabled,
  ) async {
    _channelUrlImagesEnabled[channelIndex] = enabled;
    await _channelSettingsStore.saveUrlImagesEnabled(channelIndex, enabled);
    notifyListeners();
  }

  Future<void> setContactUrlImagesEnabled(
    String contactKeyHex,
    bool enabled,
  ) async {
    _contactUrlImagesEnabled[contactKeyHex] = enabled;
    await _contactSettingsStore.saveUrlImagesEnabled(contactKeyHex, enabled);
    notifyListeners();
  }

  Future<void> setChannelCyr2LatEnabled(int channelIndex, bool enabled) async {
    if (_channelCyr2LatEnabled[channelIndex] == enabled) return;
    _channelCyr2LatEnabled[channelIndex] = enabled;
    if (enabled) {
      _channelMcmpEnabled[channelIndex] = false;
      _channelMCOtxtEnabled[channelIndex] = false;
      _channelSmazEnabled[channelIndex] = false;
      await _channelSettingsStore.saveMcmpEnabled(channelIndex, false);
      await _channelSettingsStore.saveMCOtxtEnabled(channelIndex, false);
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
      _contactMCOtxtEnabled[contactKeyHex] = false;
      _contactSmazEnabled[contactKeyHex] = false;
      await _contactSettingsStore.saveMcmpEnabled(contactKeyHex, false);
      await _contactSettingsStore.saveMCOtxtEnabled(contactKeyHex, false);
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
        .loadLatestChannelMessages(
          channelIndex,
          limit: _initialChannelHistorySize,
          allowLegacyMigration: allowLegacyMigration,
        );
    if (expectedPublicKeyHex != null &&
        expectedPublicKeyHex != selfPublicKeyHex) {
      return false;
    }
    if (allMessages.isNotEmpty) {
      // Keep only the most recent N messages in memory to bound memory usage
      final orderedMessages = _orderedChannelMessages(allMessages);
      final windowedMessages =
          orderedMessages.length > _initialChannelHistorySize
          ? orderedMessages.sublist(
              orderedMessages.length - _initialChannelHistorySize,
            )
          : orderedMessages;

      _channelMessages[channelIndex] = windowedMessages;
      // A stored or shared-history row may predate receive-time stamping.
      await applyBlockedSenderRules(channelIndex: channelIndex);
      if (notify) notifyListeners();
      return true;
    } else {
      final removed = _channelMessages.remove(channelIndex) != null;
      if (removed && notify) notifyListeners();
      return removed;
    }
  }

  /// Load older channel messages (pagination)
  Future<List<ChannelMessage>> loadLatestPersistedChannelMessages(
    int channelIndex, {
    required int limit,
  }) {
    return _channelMessageStore.loadLatestChannelMessages(
      channelIndex,
      limit: limit,
      allowLegacyMigration: !isOfflineMode,
    );
  }

  Future<List<ChannelMessage>> loadOlderChannelMessages(
    int channelIndex, {
    int count = 50,
  }) async {
    if (isOfflineSharedMode) return const [];
    final currentMessages = _channelMessages[channelIndex] ?? [];
    if (currentMessages.isEmpty) return const [];
    final olderMessages = await _channelMessageStore.loadChannelMessagesBefore(
      channelIndex,
      before: currentMessages.first,
      limit: count,
      allowLegacyMigration: !isOfflineMode,
    );
    if (olderMessages.isEmpty) return const [];

    // Prepend to current conversation
    _channelMessages[channelIndex] = _orderedChannelMessages([
      ...olderMessages,
      ...currentMessages,
    ]);
    notifyListeners();

    return olderMessages;
  }

  /// Appends the next persisted page after the newest loaded channel message.
  /// No screen calls this yet; it is the forward half of cursor pagination.
  Future<List<ChannelMessage>> loadNewerChannelMessages(
    int channelIndex, {
    int count = 50,
  }) async {
    if (isOfflineSharedMode) return const [];
    final currentMessages = _channelMessages[channelIndex] ?? [];
    if (currentMessages.isEmpty) return const [];
    final newerMessages = await _channelMessageStore
        .loadChannelMessagesAfter(
          channelIndex,
          after: currentMessages.last,
          limit: count,
          allowLegacyMigration: !isOfflineMode,
        );
    if (newerMessages.isEmpty) return const [];

    _channelMessages[channelIndex] = _orderedChannelMessages([
      ...currentMessages,
      ...newerMessages,
    ]);
    notifyListeners();
    return newerMessages;
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

  /// Привязка учёта; начатая работа прежнего store завершается независимо.
  void bindImageReceiveBackgroundWork(ReceivedImageStore? store) {
    _receivedImageStore?.detachBackgroundWorkTracker(_backgroundWork);
    _receivedImageStore = store;
    store?.attachBackgroundWorkTracker(_backgroundWork);
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
    ImageCodecService? imageCodecService,
    ImageChunkTransport? imageTransport,
    ReceivedImageStore? receivedImageStore,
    void Function(ImageChunkOutcome outcome)? onImageChunk,
    void Function(Uint8List blob, int channelIndex)? onImageChunkRepeat,
    void Function(int senderPrefix)? onImageSenderPrefix,
    Future<void> Function(int channelIndex, Set<String> channelIds)?
    deleteImagesForChannel,
    Future<void> Function(Map<int, String> slotIds)? stampImageChannelIds,
    void Function(int channelIndex)? forgetImageSlot,
  }) {
    _retryService?.pendingMessageCount.removeListener(_syncRadioStatsSendPolling);
    _retryService = retryService;
    retryService.pendingMessageCount.addListener(_syncRadioStatsSendPolling);
    _pathHistoryService = pathHistoryService;
    _appSettingsService?.removeListener(_handleAppSettingsChanged);
    _appSettingsService?.removeListener(_syncPowerSavingSettings);
    _appSettingsService = appSettingsService;
    _syncPowerSavingSettings();
    _lastSharedMessageHistoryMode =
        appSettingsService?.settings.sharedMessageHistoryMode ??
        SharedMessageHistoryMode.disabled;
    _lastNoRetransmissionWarningSeconds =
        appSettingsService?.settings.noRetransmissionWarningSeconds ?? 0;
    _lastDirectEchoRecovery =
        appSettingsService?.settings.directEchoRecovery ?? false;
    _appSettingsService?.addListener(_handleAppSettingsChanged);
    // The block table is app-wide and has no provider, so the screens cannot
    // watch it themselves. Re-emitting it here redraws the chat, the channels
    // list and the map at once, since all three already watch the connector.
    BlockedSenders.instance.removeListener(_handleBlockedSendersChanged);
    BlockedSenders.instance.addListener(_handleBlockedSendersChanged);
    _settingsSectionsService?.removeListener(_handleSettingsSectionsChanged);
    _settingsSectionsService = settingsSectionsService;
    settingsSectionsService?.mcoX0(
      a: _writeFrameToActiveTransport,
      b: (frame, label) => _handleCompanionFrame(
        frame,
        notifyExtensions: false,
        localSourceLabel: label,
      ),
      c: () => isConnected,
      d: _restartActiveTransport,
      e: () => this,
      f: (a, b) =>
          ChannelBinaryDataHelper.tryDecodeAppData(dataType: a, payload: b),
      g: (text, timestamp) => MessageTextCodec.tryDecodeKnownCompressionDetails(
        text,
        inheritedTimestamp: timestamp,
      ),
    );
    settingsSectionsService?.setDeviceVarsRequester(() async {
      if (!isConnected) return;
      await sendFrame(buildGetCustomVarsFrame());
    });
    _lastSouthNodeEnableFragmentedFrames =
        settingsSectionsService?.southFrameFragmentsEnabled ?? false;
    _settingsSectionsService?.addListener(_handleSettingsSectionsChanged);
    _translationService = translationService;
    _imageCodecService = imageCodecService;
    _imageTransport = imageTransport;
    bindImageReceiveBackgroundWork(receivedImageStore);
    _onImageChunk = onImageChunk;
    _onImageChunkRepeat = onImageChunkRepeat;
    _onImageSenderPrefix = onImageSenderPrefix;
    _deleteImagesForChannel = deleteImagesForChannel;
    _stampImageChannelIds = stampImageChannelIds;
    _forgetImageSlot = forgetImageSlot;
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
    _notificationReplySubscription ??= _notificationService.replies.listen(
      (reply) => unawaited(
        handleNotificationReply(reply).catchError((Object e) {
          appLogger.warn('Notification action failed: $e');
        }),
      ),
    );
    _loadChannelOrder();

    // Initialize retry service callbacks
    _retryService?.initialize(_retryServiceConfig());
    final maxRetries = _appSettingsService?.settings.maxMessageRetries ?? 5;
    _retryService?.setMaxRetries(maxRetries);
  }

  /// The connector's side of the retry service: how an attempt goes out,
  /// where the messages are kept, and what the connector knows about
  /// contacts, routes and timeouts.
  RetryServiceConfig _retryServiceConfig() => RetryServiceConfig(
    backgroundWorkTracker: _backgroundWork,
    sendMessage: _sendMessageDirect,
    addMessage: _addMessage,
    updateMessage: _updateMessage,
    findContact: getContactByPubKeyHex,
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
    calculatePhysicsMaxTimeout:
        (pathLength, pathBytes, messageBytes, attempt) =>
            _calculatePhysicsMaxTimeout(
              pathLength: pathLength,
              pathBytes: pathBytes,
              messageBytes: messageBytes,
              attempt: attempt,
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
    appSettingsService: _appSettingsService,
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
  );

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
    _syncPowerSavingSettings();
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
    final directEchoRecovery = settings?.directEchoRecovery ?? false;
    if (directEchoRecovery != _lastDirectEchoRecovery) {
      _lastDirectEchoRecovery = directEchoRecovery;
      if (directEchoRecovery) {
        unawaited(_requestDirectEchoKey());
      } else {
        _clearDirectEchoKey('option switched off');
      }
    }
    final evictDiscovered = settings?.evictDiscoveredContactsEnabled ?? false;
    if (evictDiscovered != _lastEvictDiscoveredContacts) {
      _lastEvictDiscoveredContacts = evictDiscovered;
      _trimDiscoveredContactsToLimit();
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
      await _sendAppStart();
    } catch (error) {
      _appDebugLogService?.warn(
        'Could not renegotiate FR01 support: $error',
        tag: 'Protocol',
      );
    }
  }

  bool get _shouldKeepTcpInBackground {
    return PlatformInfo.isAndroid &&
        (_activeTransport == MeshCoreTransportType.tcp ||
            _reconnectTransport == MeshCoreTransportType.tcp) &&
        (_state == MeshCoreConnectionState.connected ||
            _isRecoveringConnection) &&
        (_appSettingsService?.settings.backgroundTcpEnabled ?? false);
  }

  void _syncBackgroundTcpService() {
    if (_shouldKeepTcpInBackground) {
      unawaited(_backgroundService?.start(reason: _backgroundTcpReason));
      unawaited(_backgroundService?.setTcpWifiLock(true));
    } else {
      unawaited(_backgroundService?.stop(reason: _backgroundTcpReason));
      unawaited(_backgroundService?.setTcpWifiLock(false));
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
    _contactUrlImagesEnabled.clear();
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
      await _loadDiscoveredContactCache(
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

  Future<void> _loadDiscoveredContactCache({
    String? publicKeyHex,
    int? loadGeneration,
  }) async {
    final expectedPublicKeyHex = publicKeyHex ?? selfPublicKeyHex;
    final cached = await _discoveryContactStore.loadContacts();
    if (expectedPublicKeyHex != selfPublicKeyHex ||
        (loadGeneration != null &&
            loadGeneration != _contactCacheLoadGeneration)) {
      return;
    }
    // Trim a previously-saved oversized list down to the freshest entries so a
    // device that grew unbounded before the cap existed recovers on load.
    final discoveredLimit = _discoveredContactsLimit;
    if (cached.length > discoveredLimit) {
      cached.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
      cached.removeRange(discoveredLimit, cached.length);
      unawaited(_discoveryContactStore.saveContacts(cached));
    }
    // Discovered nodes stay discovered: the contact list is the node's, and
    // a discovered entry never turns into a contact by itself, whatever its
    // isActive, favourite or message flags say. Merging them in once put
    // every node the firmware had declined to store into the list.
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
    _channelSenderNames.clear();
    _channelMCOtxtEnabled.clear();
    _channelMCOtxtPlainWhenSmaller.clear();
    _channelSmazEnabled.clear();
    _channelCyr2LatEnabled.clear();
    _channelCyr2LatProfileId.clear();
    _channelSendingDelayEnabled.clear();
    _channelQuickAnswerIds.clear();
    _channelWidgetColor.clear();
    _channelWidgetTextColor.clear();
    _channelUrlImagesEnabled.clear();
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
    final senderName = await channelSettingsStore.loadSenderName(
      channelIndex,
    );
    final mcotxtEnabled = await channelSettingsStore.loadMCOtxtEnabled(
      channelIndex,
    );
    final mcotxtPlainWhenSmaller = await channelSettingsStore
        .loadMCOtxtPlainWhenSmaller(channelIndex);
    final smazEnabled = await channelSettingsStore.loadSmazEnabled(
      channelIndex,
    );
    final cyr2LatEnabled = await channelSettingsStore.loadCyr2LatEnabled(
      channelIndex,
    );
    final urlImagesEnabled = await channelSettingsStore.loadUrlImagesEnabled(
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
    if (senderName == null) {
      _channelSenderNames.remove(channelIndex);
    } else {
      _channelSenderNames[channelIndex] = senderName;
    }
    _channelMCOtxtEnabled[channelIndex] = mcotxtEnabled;
    _channelMCOtxtPlainWhenSmaller[channelIndex] = mcotxtPlainWhenSmaller;
    _channelSmazEnabled[channelIndex] = smazEnabled;
    _channelCyr2LatEnabled[channelIndex] = cyr2LatEnabled;
    _channelUrlImagesEnabled[channelIndex] = urlImagesEnabled;
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

  /// One attempt of a direct message, under the same lock as channel sends:
  /// the flood scope is a single field on the node, so an attempt must never
  /// fall inside a channel's scoped window, nor a channel send inside the
  /// window this one opens for a contact with a region of its own. Returns
  /// the moment the frame went to the node, or null when a scope command
  /// went unanswered and nothing went out. The node's ERR and a lost link
  /// are thrown: the retry service fails the message on the first and keeps
  /// it for the reconnect on the second, sending being paused by then.
  Future<DateTime?> _sendMessageDirect(
    Contact contact,
    String text,
    int attempt,
    int timestampSeconds, {
    required bool useFlood,
  }) async {
    if (!isConnected) throw StateError('Not connected');
    if (text.isEmpty) throw ArgumentError('Empty message text');
    return _runChannelCommandLocked(() async {
      try {
        await _waitForRadioQuiet(lastInboundRxTime: _lastContactMsgRxTime);
        final outboundText = prepareContactOutboundText(
          contact,
          text,
          estimateSignatureOverhead: false,
        );
        final frame = buildSendTextMsgFrame(
          contact.publicKey,
          outboundText,
          attempt: attempt,
          timestampSeconds: timestampSeconds,
        );
        final region = useFlood ? getContactRegion(contact.publicKeyHex) : '';
        if (region.isNotEmpty) {
          return await _sendScopedContactFrame(frame, region);
        }
        final sentByRadioAt = DateTime.now();
        // Waiting for SENT lets an ERR (unknown contact, packet pool full,
        // text too long for this attempt) fail the message at once instead
        // of after its ACK timeout.
        try {
          await _sendFrameAndWaitForCommandAck(frame);
        } on TimeoutException catch (e) {
          appLogger.warn('No SENT reply for message: $e', tag: 'Connector');
        }
        return sentByRadioAt;
      } on TimeoutException catch (e) {
        // The node left the scope command unanswered, so nothing went out;
        // the retry service tries again shortly.
        appLogger.warn('Message not sent: $e', tag: 'Connector');
        return null;
      } catch (e) {
        appLogger.error('Failed to send message: $e', tag: 'Connector');
        rethrow;
      }
    });
  }

  /// Set once the node has refused CMD_SET_FLOOD_SCOPE sub-command 1, which
  /// firmware before version 12 does not know; later unscoped sends go out
  /// under the node's default scope instead of failing, until the link goes
  /// (`disconnect`, `_handleDisconnection`).
  bool _unscopedSendUnsupported = false;

  /// Sets the node's no-scope flag for the next send (CMD_SET_FLOOD_SCOPE
  /// sub-command 1), so the packet carries no scope, the default one
  /// included. Returns false when the firmware refused the command, now or
  /// earlier in this connection: the send then goes out under the node's
  /// default scope, as it did before the flag existed.
  Future<bool> _sendFloodUnscopedFrame() async {
    if (_unscopedSendUnsupported) return false;
    try {
      await _sendFrameAndWaitForCommandAck(buildSetFloodUnscopedFrame());
      return true;
    } on CommandFailedException catch (error) {
      // Firmware before version 12 answers ERR_CODE_UNSUPPORTED_CMD, and
      // an ERR with no code before March 2025. Any other failure, a lost
      // link or a timeout included, goes to the caller as a region's scope
      // command does and says nothing about the firmware.
      if (error.errCode != errCodeUnsupportedCmd && error.errCode >= 0) {
        rethrow;
      }
      _unscopedSendUnsupported = true;
      appLogger.warn(
        'Unscoped flood sends are not supported by this firmware ($error); '
        'channels and contacts marked "no region" go out under the default '
        'scope until the next connection',
        tag: 'Connector',
      );
      return false;
    }
  }

  /// A flood send to a contact with a flood choice of its own, a text
  /// message, a login or a status request alike: the scope is set before the
  /// frame and cleared once RESP_CODE_SENT says the packet was built under
  /// it, as `_runScopedChannelSend` does for a channel. The unscoped choice
  /// sets the node's no-scope flag instead, which the same clearing frame
  /// resets.
  Future<DateTime?> _sendScopedContactFrame(
    Uint8List frame,
    String region,
  ) async {
    if (!ContactRegionStore.isUnscoped(region)) {
      await _sendFrameAndWaitForCommandAck(buildSetFloodScopeFrame(region));
    } else {
      await _sendFloodUnscopedFrame();
    }
    final sentByRadioAt = DateTime.now();
    try {
      await _sendFrameAndWaitForCommandAck(frame);
    } on TimeoutException {
      // The frame was written; the retry service arms its timer on the SENT
      // it may still receive, and the scope is cleared either way.
      appLogger.warn(
        'No RESP_CODE_SENT for a scoped direct send within the ACK timeout',
        tag: 'Connector',
      );
    } finally {
      if (isConnected) {
        try {
          await _sendFrameAndWaitForCommandAck(buildSetFloodScopeFrame(''));
        } catch (error) {
          appLogger.warn(
            'Flood scope reset after a direct send failed: $error',
            tag: 'Connector',
          );
        }
      }
    }
    return sentByRadioAt;
  }

  /// Sends [frame], a command that makes the node transmit one packet to
  /// [contact], a login, a status, telemetry or neighbour request or a CLI
  /// command, the way a direct message goes out: under the channel command
  /// lock, and inside a scope window when the packet goes by flood and the
  /// contact has a flood choice of its own, so that every packet to one
  /// contact carries one region and none falls into another send's window.
  /// [useFlood] is the routing the caller has already prepared on the node.
  /// A failure is logged and rethrown, as `sendFrame` throws its own: the
  /// callers report a send that did not happen rather than wait out an
  /// answer that cannot come.
  Future<void> sendContactFrame(
    Contact contact,
    Uint8List frame, {
    required bool useFlood,
  }) => _runChannelCommandLocked(() async {
    try {
      final region = useFlood ? getContactRegion(contact.publicKeyHex) : '';
      if (region.isEmpty) {
        await sendFrame(frame);
      } else {
        await _sendScopedContactFrame(frame, region);
      }
    } catch (e) {
      appLogger.error(
        'Failed to send a command to ${contact.name}: $e',
        tag: 'Connector',
      );
      rethrow;
    }
  });

  void _updateMessage(Message message) {
    final contactKey = pubKeyToHex(message.senderKey);
    final messages = _conversations[contactKey];
    if (messages != null) {
      final index = messages.indexWhere(
        (m) => m.messageId == message.messageId,
      );
      if (index != -1) {
        // The retry service writes back its own copy of a pending message,
        // which never sees what the connector added meanwhile: the flood
        // relays counted and their routes, the flood routing and the
        // packet's region from the RX log, and the route the delivery was
        // confirmed along. The routes only grow and the rest is only ever
        // set, so the stored ones are kept when the copy is behind; the
        // count grows within an attempt only. A copy with another attempt
        // number is a retry being planned: its count starts from the copy's
        // zero, and the helper stops counting the earlier attempt's copies
        // now, not when the retry finally leaves the radio. The region stays
        // the one the last attempt went out under until the retry's
        // RESP_CODE_SENT stamps its own: an acknowledgement of that attempt
        // can still arrive during the backoff and cancel the retry, and the
        // delivered message would otherwise show an unknown region.
        final stored = messages[index];
        var updated = message;
        if (message.floodPathObservations.length <
            stored.floodPathObservations.length) {
          updated = updated.copyWith(
            floodPathObservations: stored.floodPathObservations,
            floodPathHashWidth: stored.floodPathHashWidth,
          );
        }
        if (stored.sentByFlood && !message.sentByFlood) {
          updated = updated.copyWith(sentByFlood: true);
        }
        if (stored.packetRegionInfoAvailable &&
            !message.packetRegionInfoAvailable) {
          updated = updated.copyWith(
            packetRegion: stored.packetRegion,
            packetRegionInfoAvailable: true,
            packetRegionNotMatched: stored.packetRegionNotMatched,
          );
        }
        if (stored.deliveryPathBytes != null &&
            message.deliveryPathBytes == null) {
          updated = updated.copyWith(
            deliveryPathBytes: stored.deliveryPathBytes,
            deliveryPathHashWidth: stored.deliveryPathHashWidth,
          );
        }
        if (message.isOutgoing && message.retryCount != stored.retryCount) {
          _directFloodRepeats.planAttempt(
            target: (conversationKey: contactKey, messageId: message.messageId),
            attempt: message.retryCount,
          );
        } else if (message.repeatCount < stored.repeatCount) {
          updated = updated.copyWith(repeatCount: stored.repeatCount);
        }
        messages[index] = updated;
        if (_isRoomConversation(contactKey)) {
          messages.sort(RoomMessageTimelineHelper.compare);
        }
        _messageStore.saveMessage(contactKey, updated);
        notifyListeners();
      }
    }

    // If this is a reaction message, update the target message's reaction status
    final reactionInfo = ReactionHelper.parseReaction(message.text);
    if (reactionInfo != null &&
        (message.status == MessageStatus.delivered ||
            message.status == MessageStatus.failed)) {
      final contactKey2 = pubKeyToHex(message.senderKey);
      final changedMessage = _setReactionStatus(
        contactKey2,
        reactionInfo,
        message.status,
      );
      if (changedMessage != null) {
        _messageStore.saveMessage(contactKey2, changedMessage);
      }
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
    final updated = update(messages[index]);
    messages[index] = updated;
    _messageStore.saveMessage(contactKeyHex, updated);
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
    final updated = update(messages[index]);
    messages[index] = updated;
    _channelMessageStore.saveChannelMessage(channelIndex, updated);
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

  /// A route from the history for a direct message's retry, or null when the
  /// history has none. The history is loaded first: `getRecentPaths` answers
  /// a history not read yet with an empty list, and the attempt would miss
  /// its turn at the history.
  Future<PathSelection?> _selectAutoPathForAttempt(
    String contactPubKeyHex, {
    required int attemptIndex,
    required int maxRetries,
    List<PathSelection> recentSelections = const [],
  }) async {
    final service = _pathHistoryService;
    if (service == null) return null;
    await service.ensureLoaded([contactPubKeyHex]);
    if (service.getRecentPaths(contactPubKeyHex).isEmpty) return null;

    final selection = service.selectPathForAttempt(
      contactPubKeyHex,
      attemptIndex: attemptIndex,
      maxRetries: maxRetries,
      recentSelections: recentSelections,
    );
    if (selection.useFlood) return null;
    service.recordPathAttempt(contactPubKeyHex, selection);
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
  }) => _selfInfoWork.run(() async {
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

    await _awaitActiveDisconnect();
    // The await is a suspension point: another connect may have claimed the
    // connector while this one was waiting for the teardown.
    if (_state == MeshCoreConnectionState.connecting ||
        _state == MeshCoreConnectionState.connected) {
      _appDebugLogService?.warn(
        'connectUsb ignored: already $_state after disconnect wait',
        tag: 'USB',
      );
      return;
    }

    await stopScan();
    _cancelReconnectTimer();
    _manualDisconnect = false;
    _reconnectTransport = null;
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
  });

  Future<void> connectTcp({
    required String host,
    required int port,
    bool automaticReconnect = false,
  }) => _selfInfoWork.run(() async {
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

    if (!automaticReconnect &&
        (_appSettingsService?.settings.backgroundTcpEnabled ?? false)) {
      unawaited(
        _backgroundService?.ensureBatteryOptimizationExemption(
          reason: 'tcpConnection',
        ),
      );
    }

    _appDebugLogService?.info('connectTcp: endpoint=$host:$port', tag: 'TCP');

    await _awaitActiveDisconnect();
    // The await is a suspension point: another connect may have claimed the
    // connector while this one was waiting for the teardown.
    if (_state == MeshCoreConnectionState.connecting ||
        _state == MeshCoreConnectionState.connected) {
      _appDebugLogService?.warn(
        'connectTcp ignored: already $_state after disconnect wait',
        tag: 'TCP',
      );
      return;
    }

    await stopScan();
    if (!automaticReconnect) {
      _cancelReconnectTimer();
    }
    _manualDisconnect = false;
    _lastManualDisconnectTransport = null;
    _lastTcpHost = host.trim();
    _lastTcpPort = port;
    _reconnectTransport = MeshCoreTransportType.tcp;
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
      _rxSilenceAnchor = DateTime.now();
      _startRxWatchdog();
      _syncBackgroundTcpService();
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
  });

  Future<void> connectReview() async {
    if (_state == MeshCoreConnectionState.connecting ||
        _state == MeshCoreConnectionState.connected) {
      _appDebugLogService?.warn(
        'connectReview ignored: already $_state',
        tag: 'Review',
      );
      return;
    }

    _appDebugLogService?.info('connectReview: starting', tag: 'Review');

    await _awaitActiveDisconnect();
    // The await is a suspension point: another connect may have claimed the
    // connector while this one was waiting for the teardown.
    if (_state == MeshCoreConnectionState.connecting ||
        _state == MeshCoreConnectionState.connected) {
      _appDebugLogService?.warn(
        'connectReview ignored: already $_state after disconnect wait',
        tag: 'Review',
      );
      return;
    }

    await stopScan();
    _cancelReconnectTimer();
    _manualDisconnect = false;
    _resetConnectionHandshakeState();
    _activeTransport = MeshCoreTransportType.review;
    _setState(MeshCoreConnectionState.connecting);

    // A disconnect (or a newer connect) bumps the generation, so this attempt
    // can tell after every await whether it still owns the connector.
    final generation = ++_reviewConnectGeneration;
    bool isCancelled() =>
        generation != _reviewConnectGeneration ||
        _activeTransport != MeshCoreTransportType.review ||
        _state == MeshCoreConnectionState.disconnecting ||
        _state == MeshCoreConnectionState.disconnected;

    try {
      // Every review session starts from a clean slate.
      await beginReviewModeSession(_appSettingsService);
      if (isCancelled()) return;
      await _reviewFrameSubscription?.cancel();
      _reviewFrameSubscription = null;
      _reviewRadio?.dispose();
      final radio = reviewRadioFactoryForTest?.call() ?? ReviewRadio();
      _reviewRadio = radio;
      _reviewFrameSubscription = radio.frames.listen(
        _handleFrame,
        onError: (error, stackTrace) {
          _appDebugLogService?.error(
            'Review radio error: $error',
            tag: 'Review',
          );
          unawaited(disconnect(manual: false));
        },
      );

      _setState(MeshCoreConnectionState.connected);
      unawaited(_backgroundService?.start());
      _pendingInitialChannelSync = true;
      _pendingInitialQueuedMessageSync = true;
      _pendingInitialContactsSync = true;
      await _requestDeviceInfo();
      _startBatteryPolling();
      if (_radioStatsPollRefCount > 0) _startRadioStatsPolling();

      var gotSelfInfo = await _waitForSelfInfo(
        timeout: const Duration(seconds: 3),
      );
      if (isCancelled()) return;
      if (!gotSelfInfo) {
        await refreshDeviceInfo();
        gotSelfInfo = await _waitForSelfInfo(
          timeout: const Duration(seconds: 3),
        );
      }
      if (isCancelled()) return;
      if (!gotSelfInfo) {
        throw StateError(
          'Timed out waiting for SELF_INFO during review connect',
        );
      }

      await syncTime();
      if (!isCancelled() && isConnected) {
        radio.start();
      }
    } catch (error) {
      if (isCancelled()) {
        _appDebugLogService?.info(
          'Ignoring review connect error after cancellation: $error',
          tag: 'Review',
        );
        return;
      }
      _appDebugLogService?.error(
        'Review connection error: $error',
        tag: 'Review',
      );
      await disconnect(manual: false);
      rethrow;
    }
  }

  @visibleForTesting
  ReviewRadio Function()? reviewRadioFactoryForTest;

  void sendReviewTestMessage() {
    if (!isReviewMode) return;
    _reviewRadio?.sendTestMessage();
  }

  @visibleForTesting
  void handleFrameForTest(List<int> data) => _handleFrame(data);

  /// Подменяет только физическую запись; sendFrame и очередь ответов настоящие.
  @visibleForTesting
  void setFrameWriterForTest(Future<void> Function(Uint8List)? writer) {
    _frameWriterForTest = writer;
  }

  /// Только внешний перехватчик; initialize и коммерческие службы не запускаются.
  @visibleForTesting
  void setFrameInterceptorForTest(SettingsSectionsService? service) {
    _settingsSectionsService = service;
  }

  /// Синтетическое состояние без привязки stores к ноде и чтения настоящей БД.
  @visibleForTesting
  void setPacketReplayFixtureForTest({
    required Uint8List selfKey,
    List<Contact> contacts = const [],
    List<Channel> channels = const [],
  }) {
    _setSelfPublicKey(Uint8List.fromList(selfKey));
    _contacts
      ..clear()
      ..addAll(contacts);
    _channels
      ..clear()
      ..addAll(channels);
  }

  /// Только синтетический RAM-ключ теста, без запроса/чтения ключа ноды.
  @visibleForTesting
  void setDirectEchoKeyForTest(Uint8List key) =>
      _directEchoKeys.setPrivateKey(Uint8List.fromList(key));

  /// Подменяет существующий Future загрузки, сохраняя настоящий receive path.
  @visibleForTesting
  void setConversationLoadForTest(String contactKeyHex, Future<void> load) {
    _loadedConversationKeys.remove(contactKeyHex);
    _conversationLoadFutures[contactKeyHex] = load;
  }

  @visibleForTesting
  void holdUnknownSenderMessageForTest(Uint8List frame) =>
      _holdUnknownSenderMessage(frame);

  @visibleForTesting
  Future<void> replayUnknownSenderMessagesForTest({bool onlyResolvable = false}) =>
      _replayUnknownSenderMessages(onlyResolvable: onlyResolvable);

  /// Фикстура уже принятого backlog; очередь ноды повторно не потребляется.
  @visibleForTesting
  void deferContactMessagesForTest(List<Uint8List> frames) {
    _deferQueuedContactMessagesUntilContacts = true;
    _deferredQueuedContactMessageFrames.addAll(frames.map(Uint8List.fromList));
  }

  @visibleForTesting
  Future<void> replayDeferredContactMessagesForTest() =>
      _processDeferredQueuedContactMessages();

  @visibleForTesting
  ({int unknown, int deferred, bool replaying, bool deferring})
  get packetReplayStateForTest => (
    unknown: _unknownSenderMessageFrames.length,
    deferred: _deferredQueuedContactMessageFrames.length,
    replaying: _isProcessingDeferredQueuedContactMessages,
    deferring: _deferQueuedContactMessagesUntilContacts,
  );

  /// Включает tombstone: этот счётчик не определяет активность CPU.
  @visibleForTesting
  int get pendingCommandReplyCountForTest => _pendingGenericAckQueue.length;

  /// Настоящий сброс sync-флагов и таймеров без запуска native teardown.
  @visibleForTesting
  void resetSyncProgressForTest() => _resetSyncProgressState();

  /// Общий запрос устройства без открытия BLE/USB/TCP транспорта.
  @visibleForTesting
  Future<void> requestDeviceInfoForTest() => _requestDeviceInfo();

  @visibleForTesting
  Future<bool> waitForSelfInfoForTest(Duration timeout) =>
      _waitForSelfInfo(timeout: timeout);

  @visibleForTesting
  void resetConnectionHandshakeForTest() => _resetConnectionHandshakeState();

  @visibleForTesting
  bool get awaitingSelfInfoForTest => _awaitingSelfInfo;

  @visibleForTesting
  bool get selfInfoRetryActiveForTest => _selfInfoRetryTimer?.isActive ?? false;

  @visibleForTesting
  int get selfLocationWaiterCountForTest => _selfInfoRefreshWaiters.length;

  /// Фикстура уже загруженного состояния: SELF_INFO не читает настоящую БД.
  @visibleForTesting
  void setCachedSelfInfoKeyForTest(Uint8List key) {
    _persistedStateLoadedKey = pubKeyToHex(key);
  }

  /// Продолжение после принятого фрагмента; разбор FR01 тестируется отдельно.
  @visibleForTesting
  void handleQueuedFragmentForTest() => _handleQueuedMessageReceived();

  /// Существующий async hook финализации каналов, без запуска initialize.
  @visibleForTesting
  void setChannelImageStampForTest(
    Future<void> Function(Map<int, String> slotIds)? stamp,
  ) {
    _stampImageChannelIds = stamp;
  }

  /// Настоящее продолжение очереди; подменяется лишь обработка/сохранение кадра.
  @visibleForTesting
  Future<void> processQueuedMessageForTest({
    String? localSourceLabel,
    required Future<void> Function() process,
  }) => _processPotentialQueuedMessage(
    localSourceLabel: localSourceLabel,
    frameType: 'synthetic message',
    process: process,
  );

  /// Синтетическая история без подключения ноды и загрузки БД.
  @visibleForTesting
  void setChannelMessagesForTest(int channelIndex, List<ChannelMessage> messages) {
    _channelMessages[channelIndex] = List<ChannelMessage>.of(messages);
  }

  @visibleForTesting
  void scheduleChannelNoRetransmissionWarningForTest(
    String messageId, {
    DateTime? since,
  }) => _scheduleChannelNoRetransmissionWarning(messageId, since: since);

  @visibleForTesting
  void setChannelResendClockForTest(DateTime Function() now) {
    _channelResendNow = now;
  }

  /// Настоящий loop и счётчик попыток; заменяется только передача через радио.
  @visibleForTesting
  Future<void> runChannelHopCheckForTest(
    String messageId, {
    required Future<void> Function() resend,
    required int minHops,
    required int maxResends,
  }) => _resendUntilMinHops(messageId, () async {
    _incrementChannelResendCount(messageId);
    await resend();
  }, minHops: minHops, maxResends: maxResends);

  @visibleForTesting
  ChannelMessage mergeChannelEchoForTest(int channelIndex, ChannelMessage echo) {
    final messages = _channelMessages[channelIndex]!;
    final index = messages.indexWhere((message) => message.messageId == echo.messageId);
    final merged = _mergeChannelRepeat(messages, index, echo);
    _wakeChannelHopCheck(merged.messageId);
    notifyListeners();
    return merged;
  }

  /// Переход без платформенного транспорта; connected сохраняет обычные side effects.
  @visibleForTesting
  void setConnectionStateForTest(MeshCoreConnectionState state) => _setState(state);

  /// Контекст уже известного транспорта без BLE/socket/handshake в тестах.
  @visibleForTesting
  void setReconnectContextForTest({
    required MeshCoreTransportType? transport,
    String? deviceId,
    String? tcpHost,
    int? tcpPort,
    bool manualDisconnect = false,
    bool offlineMode = false,
    MeshCoreConnectionState state = MeshCoreConnectionState.disconnected,
  }) {
    _reconnectTransport = transport;
    _activeTransport = transport ?? MeshCoreTransportType.bluetooth;
    _lastDevice = null;
    _lastDeviceId = deviceId;
    _lastTcpHost = tcpHost;
    _lastTcpPort = tcpPort;
    _manualDisconnect = manualDisconnect;
    _isOfflineMode = offlineMode;
    _state = state;
  }

  @visibleForTesting
  int nextReconnectDelayMsForTest() => _nextReconnectDelayMs();

  @visibleForTesting
  int get reconnectAttemptsForTest => _reconnectAttempts;

  @visibleForTesting
  void setReconnectClockForTest(Duration Function() now) {
    _reconnectClock = now;
  }

  @visibleForTesting
  bool get reconnectTimerActiveForTest => _reconnectTimer?.isActive ?? false;

  @visibleForTesting
  void scheduleReconnectForTest() => _scheduleReconnect();

  /// Доступ к действующему таймеру без подключения платформенного транспорта.
  @visibleForTesting
  void startBatteryPollingForTest() => _startBatteryPolling();

  @visibleForTesting
  Duration get rxWatchdogSilenceForTest => _rxWatchdogSilence;

  @visibleForTesting
  DateTime get rxSilenceAnchorForTest => _rxSilenceAnchor;

  /// Изолирует запрет APP_START от хранения контактов и их сетевой загрузки.
  @visibleForTesting
  void setContactSyncInProgressForTest(bool value) {
    _isLoadingContacts = value;
  }

  /// Один настоящий шаг watchdog с заданной предысторией, без ожидания минут.
  @visibleForTesting
  DateTime tickRxWatchdogForTest({
    required DateTime lastReceivedAt,
    required DateTime previousTickAt,
    DateTime? silenceAnchor,
    MeshCoreTransportType transport = MeshCoreTransportType.bluetooth,
  }) {
    _lastRxTime = lastReceivedAt;
    _lastRxWatchdogTickAt = previousTickAt;
    _rxSilenceAnchor = silenceAnchor ?? lastReceivedAt;
    _activeTransport = transport;
    _handleRxWatchdogTick();
    return _rxSilenceAnchor;
  }

  /// Hands the connector its settings without [initialize], which also
  /// starts the notification plugin a test host does not have.
  @visibleForTesting
  void attachAppSettingsServiceForTest(AppSettingsService service) {
    _appSettingsService?.removeListener(_syncPowerSavingSettings);
    _appSettingsService = service;
    service.addListener(_syncPowerSavingSettings);
    _syncPowerSavingSettings();
  }

  @visibleForTesting
  void attachChannelKeyHashCacheForTest(ChannelKeyHashCache cache) {
    _channelKeyHashCache.clear();
    _channelKeyHashCache = cache;
    _syncPowerSavingSettings();
  }

  /// Hands the connector the path histories without [initialize].
  @visibleForTesting
  void attachPathHistoryServiceForTest(PathHistoryService service) {
    _pathHistoryService = service;
  }

  /// Hands the connector a retry service without [initialize], wired to the
  /// same callbacks.
  @visibleForTesting
  void attachRetryServiceForTest(MessageRetryService service) {
    _retryService?.pendingMessageCount.removeListener(_syncRadioStatsSendPolling);
    _retryService = service;
    service.pendingMessageCount.addListener(_syncRadioStatsSendPolling);
    service.initialize(_retryServiceConfig());
    _syncRadioStatsSendPolling();
  }

  @visibleForTesting
  // Exercise teardown without initialize(), which starts platform plugins.
  void attachDisconnectServicesForTest({
    TranslationService? translationService,
    ImageCodecService? imageCodecService,
    AppDebugLogService? debugLog,
    Duration timeout = ConnectionCleanup.defaultTimeout,
    bool iosNativeBleCentral = false,
  }) {
    _translationService = translationService;
    _imageCodecService = imageCodecService;
    _appDebugLogService = debugLog;
    _disconnectStepTimeout = timeout;
    _usingIosNativeBleCentral = iosNativeBleCentral;
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

  bool get _shouldUseIosNativeBleCentral =>
      PlatformInfo.isIOS && _iosNativeBleCentralEnabled;

  Future<void> _connectIosNativeBleCentral(BluetoothDevice device) async {
    await _iosBleCentralSubscription?.cancel();
    _iosBleCentralSubscription = _iosBleCentralEvents
        .receiveBroadcastStream()
        .listen(_handleIosBleCentralEvent, onError: _handleIosBleCentralError);
    _usingIosNativeBleCentral = true;
    try {
      await _iosBleCentralMethod.invokeMethod<void>('connect', {
        'remoteId': device.remoteId.toString(),
        'serviceUuid': MeshCoreUuids.service,
        'rxUuid': MeshCoreUuids.rxCharacteristic,
        'txUuid': MeshCoreUuids.txCharacteristic,
        'restoreEnabled': true,
        'reconnectOnRestore': true,
      });
    } catch (_) {
      _usingIosNativeBleCentral = false;
      await _iosBleCentralSubscription?.cancel();
      _iosBleCentralSubscription = null;
      rethrow;
    }
  }

  void _handleIosBleCentralError(Object error) {
    _appDebugLogService?.warn(
      'iOS native BLE central event stream error: $error',
      tag: 'BLE iOS',
    );
  }

  void _handleIosBleCentralEvent(dynamic rawEvent) {
    if (rawEvent is! Map) return;
    final event = rawEvent.cast<dynamic, dynamic>();
    final type = event['event']?.toString();
    switch (type) {
      case 'data':
        final data = event['data'];
        final frame = switch (data) {
          Uint8List value => value,
          List<int> value => Uint8List.fromList(value),
          ByteData value => value.buffer.asUint8List(
            value.offsetInBytes,
            value.lengthInBytes,
          ),
          _ => null,
        };
        if (frame != null) {
          _handleFrame(frame);
        }
        break;
      case 'disconnected':
        _appDebugLogService?.warn(
          'iOS native BLE central disconnected: '
          'remoteId=${event['remoteId'] ?? ''} error=${event['error'] ?? ''} '
          '${_iosBleSessionSnapshot(DateTime.now())}',
          tag: 'BLE iOS',
        );
        if (isConnected && _activeTransport == MeshCoreTransportType.bluetooth) {
          _handleDisconnection();
        }
        break;
      case 'ready':
      case 'connected':
      case 'restored':
      case 'state':
      case 'rx_error':
        _appDebugLogService?.info(
          'iOS native BLE central event: $type '
          'remoteId=${event['remoteId'] ?? ''} state=${event['state'] ?? ''} '
          'error=${event['error'] ?? ''}',
          tag: 'BLE iOS',
        );
        break;
      default:
        break;
    }
  }

  Future<void> _restartActiveTransport() async {
    if (_transportRestartInProgress || !isConnected) return;

    final transport = _activeTransport;
    final bleDevice =
        _lastDevice ??
        (_lastDeviceId == null ? null : BluetoothDevice.fromId(_lastDeviceId!));
    final bleDisplayName = _lastDeviceDisplayName;
    final tcpHost = _lastTcpHost;
    final tcpPort = _lastTcpPort;
    final usbPort = _usbManager.activePortKey;

    final canRestart = switch (transport) {
      MeshCoreTransportType.bluetooth => bleDevice != null,
      MeshCoreTransportType.tcp => tcpHost != null && tcpPort != null,
      MeshCoreTransportType.usb => usbPort != null,
      MeshCoreTransportType.review => false,
    };
    if (!canRestart) return;

    _appDebugLogService?.info(
      'Transport restart requested transport=${transport.name}',
      tag: 'Connection',
    );
    _transportRestartInProgress = true;
    try {
      await disconnect(manual: true);
      switch (transport) {
        case MeshCoreTransportType.bluetooth:
          await connect(
            bleDevice!,
            displayName: bleDisplayName,
            requestBatteryOptimizationExemption: false,
          );
          break;
        case MeshCoreTransportType.tcp:
          await connectTcp(host: tcpHost!, port: tcpPort!);
          break;
        case MeshCoreTransportType.usb:
          await connectUsb(portName: usbPort!);
          break;
        case MeshCoreTransportType.review:
          break;
      }
    } catch (error) {
      _appDebugLogService?.error(
        'Transport restart failed: $error',
        tag: 'Connection',
      );
    } finally {
      _transportRestartInProgress = false;
      // Every notification of the restart was read as part of it. A link
      // that did not come back is reported once more with the flag cleared,
      // so the shell and the screens that kept their routes see the plain
      // disconnect; a restart that ended connected has nothing to add.
      if (!_disposed && !isConnected) notifyListeners();
    }
  }

  Future<void> connect(
    BluetoothDevice device, {
    String? displayName,
    Future<String?> Function()? linuxPairingPinProvider,
    bool requestBatteryOptimizationExemption = true,
  }) => _selfInfoWork.run(() async {
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

    if (requestBatteryOptimizationExemption) {
      unawaited(
        _backgroundService?.ensureBatteryOptimizationExemption(
          reason: 'bleConnection',
        ),
      );
    }

    await _awaitActiveDisconnect();
    // The await is a suspension point: another connect may have claimed the
    // connector while this one was waiting for the teardown.
    if (_state == MeshCoreConnectionState.connecting ||
        _state == MeshCoreConnectionState.connected) {
      return;
    }

    _activeTransport = MeshCoreTransportType.bluetooth;
    _reconnectTransport = MeshCoreTransportType.bluetooth;

    await stopScan();
    _setState(MeshCoreConnectionState.connecting);
    final connectGeneration = ++_bleConnectGeneration;
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
      _lastBleConnectStartedAt = DateTime.now();
      _appDebugLogService?.info(
        'Starting connect to $connectLabel',
        tag: 'BLE Connect',
      );
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;
      await _notifySubscription?.cancel();
      _notifySubscription = null;
      if (_shouldUseIosNativeBleCentral) {
        await _connectIosNativeBleCentral(device);
        _setState(MeshCoreConnectionState.connected);
        _lastBleConnectedAt = DateTime.now();
        _rxSilenceAnchor = DateTime.now();
        _startRxWatchdog();
        if (_shouldGateInitialChannelSync) {
          _hasReceivedDeviceInfo = false;
          _pendingInitialChannelSync = true;
        }
        await _startBleInitialSync();
        return;
      }
      _connectionSubscription = device.connectionState.listen((state) {
        if (PlatformInfo.isIOS) {
          _appDebugLogService?.info(
            'iOS plugin connectionState=${state.name} '
            '${_iosBleSessionSnapshot(DateTime.now())}',
            tag: 'BLE iOS',
          );
        }
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

      // Attach before enabling notifications so a fast tickle or response
      // cannot arrive in the gap between the CCCD write and Dart listening.
      _notifySubscription = _txCharacteristic!.onValueReceived.listen(
        _handleFrame,
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
      _setState(MeshCoreConnectionState.connected);
      _lastBleConnectedAt = DateTime.now();
      _rxSilenceAnchor = DateTime.now();
      _startRxWatchdog();
      if (_shouldGateInitialChannelSync) {
        _hasReceivedDeviceInfo = false;
        _pendingInitialChannelSync = true;
      }
      await _startBleInitialSync();
      if (_selfPublicKey != null) {
        _reconnectAttempts = 0;
      }
    } catch (e) {
      // The user cancelled (manual disconnect) or a newer connect took over
      // while this attempt was in flight. Tearing down again here would
      // re-arm auto-reconnect or kill the newer connection.
      if (connectGeneration != _bleConnectGeneration ||
          _manualDisconnect ||
          !identical(_device, device)) {
        _appDebugLogService?.info(
          'Ignoring error from cancelled connect attempt: $e',
          tag: 'BLE Connect',
        );
        rethrow;
      }
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
  });

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

  Future<bool> _waitForSelfInfo({required Duration timeout}) => _selfInfoWork.run(() async {
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
  });

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
    _clearDirectEchoKey('new session');
    _channelKeyHashCache.clear();
    _directFloodRepeats.clear();
    _heardChannelPackets.clear();
    _directEchoAckUnsupported = false;
    _unscopedSendUnsupported = false;
    _stoppedSendAcks.clear();
    _lastReturnedRoute = null;
    _lastHeardAck = null;
    _southFrameFragmentReassembler.clear();
    _southQueuedFragmentAckTracker.clear();
    _setSelfPublicKey(null);
    _persistedStateLoadedKey = null;
    // Partially received images belong to the previous session's sender prefix.
    _imageTransport?.reassembler.clear();
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
    _discardInitialSyncNotificationSummary();
    _contactSyncTotal = null;
    _contactSyncReceived = 0;
    _contactSyncUsesSinceFilter = false;
    _contactsUnconfirmedBySync = null;
    _contactSyncTimeout?.cancel();
    _contactSyncTimeout = null;
    _isLoadingContacts = false;
    _contactSyncWork.finishCurrent();
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
    _queuedMessageRequestWork.finishCurrent();
    _deferredQueuedContactMessageFrames.clear();
    _pendingQueueSync = false;
    _resetSyncFlowState();
    _queueSyncTimeout?.cancel();
    _queueSyncTimeout = null;
    _isSyncingChannels = false;
    _channelSyncWork.finishCurrent();
    _channelSyncInFlight = false;
    _channelSyncTimeout?.cancel();
    _channelSyncTimeout = null;
    _channelSyncRetries = 0;
    _nextChannelIndexToRequest = 0;
    _totalChannelsToRequest = 0;
    _previousChannelsCache.clear();
    _unconfirmedChannelSlots.clear();
  }

  bool _canAutoReconnect(MeshCoreTransportType? transport) {
    if (_disposed || _isOfflineMode || _manualDisconnect || transport == null) {
      return false;
    }
    return switch (transport) {
      MeshCoreTransportType.bluetooth => _lastDeviceId != null,
      MeshCoreTransportType.tcp => _lastTcpHost != null && _lastTcpPort != null,
      MeshCoreTransportType.usb => false,
      MeshCoreTransportType.review => false,
    };
  }

  bool get _shouldAutoReconnect => _canAutoReconnect(_reconnectTransport);

  bool get _shouldGateInitialChannelSync =>
      _activeTransport == MeshCoreTransportType.usb ||
      _activeTransport == MeshCoreTransportType.tcp ||
      _activeTransport == MeshCoreTransportType.review ||
      (_activeTransport == MeshCoreTransportType.bluetooth &&
          PlatformInfo.isWeb);

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  int _nextReconnectDelayMs() {
    final delayMs = _reconnectDelayMs(_reconnectAttempts);
    _reconnectAttempts += 1;
    return delayMs;
  }

  int _reconnectDelayMs(int attemptIndex) => reconnectDelayMs(
    attemptIndex,
    background: _reconnectPowerSettings?.background ?? false,
    backgroundIntervalSeconds: _reconnectPowerSettings?.intervalSeconds ?? 30,
  );

  void _refreshReconnectDelay() {
    final pending = _reconnectTimer;
    if (pending == null) return;
    pending.updateDelay(Duration(
      milliseconds: _reconnectDelayMs(pending.attemptIndex),
    ));
  }

  void _scheduleReconnect() {
    if (!_shouldAutoReconnect) return;
    if (_reconnectTimer?.isActive == true) return;

    final reconnectTransport = _reconnectTransport;
    final attemptIndex = _reconnectAttempts;
    final delayMs = _nextReconnectDelayMs();
    _reconnectTimer = ReconnectWait(
      attemptIndex: attemptIndex,
      delay: Duration(milliseconds: delayMs),
      now: _reconnectClock,
      onElapsed: () async {
        if (!_shouldAutoReconnect || reconnectTransport != _reconnectTransport) {
          return;
        }
        if (_state == MeshCoreConnectionState.connecting ||
            _state == MeshCoreConnectionState.connected) {
          return;
        }

        try {
          switch (reconnectTransport) {
            case MeshCoreTransportType.bluetooth:
              final device =
                  _lastDevice ??
                  (_lastDeviceId == null
                      ? null
                      : BluetoothDevice.fromId(_lastDeviceId!));
              if (device == null) return;
              await connect(
                device,
                displayName: _lastDeviceDisplayName,
                requestBatteryOptimizationExemption: false,
              );
              break;
            case MeshCoreTransportType.tcp:
              final host = _lastTcpHost;
              final port = _lastTcpPort;
              if (host == null || port == null) return;
              await connectTcp(host: host, port: port, automaticReconnect: true);
              break;
            case MeshCoreTransportType.usb:
            case MeshCoreTransportType.review:
            case null:
              return;
          }
        } catch (_) {
          _scheduleReconnect();
        }
      },
    );
  }

  Future<void> disconnect({
    bool manual = true,
    bool skipBleDeviceDisconnect = false,
  }) {
    final inFlight = _activeDisconnect;
    if (inFlight != null) {
      if (manual) {
        // A teardown started as automatic must still honour a later manual
        // request, otherwise _manualDisconnect stays false and its tail
        // schedules an auto-reconnect the user did not ask for.
        _manualDisconnect = true;
        _isRecoveringConnection = false;
        _reconnectTransport = null;
        _lastManualDisconnectTransport = _activeTransport;
        _cancelReconnectTimer();
        unawaited(_backgroundService?.stop());
      }
      return inFlight;
    }
    final teardown = _disconnectInternal(
      manual: manual,
      skipBleDeviceDisconnect: skipBleDeviceDisconnect,
    );
    _activeDisconnect = teardown;
    return teardown.whenComplete(() {
      if (identical(_activeDisconnect, teardown)) {
        _activeDisconnect = null;
      }
    });
  }

  /// Joins an in-flight [disconnect] so a new connection cannot be started
  /// while the previous teardown is still running.
  Future<void> _awaitActiveDisconnect() async {
    final pending = _activeDisconnect;
    if (pending == null) return;
    _appDebugLogService?.info(
      'Waiting for the in-flight disconnect to finish before connecting',
      tag: 'Connection',
    );
    try {
      await pending;
    } catch (_) {
      // Teardown failures are logged by the disconnect path.
    }
  }

  Future<void> _disconnectInternal({
    required bool manual,
    required bool skipBleDeviceDisconnect,
  }) => _teardownWork.run(() async {
    if (_isOfflineMode) {
      await exitOfflineHistory();
      return;
    }
    final transportAtDisconnect = _activeTransport;
    final wasUsingIosNativeBleCentral = _usingIosNativeBleCentral;
    final transportLabel = switch (transportAtDisconnect) {
      MeshCoreTransportType.bluetooth => 'BLE',
      MeshCoreTransportType.usb => 'USB',
      MeshCoreTransportType.tcp => 'TCP',
      MeshCoreTransportType.review => 'Review',
    };

    _appDebugLogService?.info(
      'Starting disconnect transport=$transportLabel manual=$manual',
      tag: 'Connection',
    );

    if (manual) {
      // A deliberate reconnect starts a fresh watchdog recovery budget.
      // Automatic watchdog reconnects use manual=false and retain the count.
      _rxWatchdogReconnects = 0;
      _manualDisconnect = true;
      _isRecoveringConnection = false;
      _reconnectTransport = null;
      _lastManualDisconnectTransport = transportAtDisconnect;
      _cancelReconnectTimer();
      _reconnectAttempts = 0;
      unawaited(_backgroundService?.stop());
    } else {
      _manualDisconnect = false;
      _lastManualDisconnectTransport = null;
      _reconnectTransport = transportAtDisconnect;
      _isRecoveringConnection = _canAutoReconnect(_reconnectTransport);
      if (!_isRecoveringConnection) {
        _reconnectTransport = null;
      }
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

    final cleanup = ConnectionCleanup(
      timeout: _disconnectStepTimeout,
      runAction: _teardownWork.cleanup,
      onFailure: (stage, error, stack) => _appDebugLogService?.warn(
        'Disconnect cleanup stage=$stage failed: $error', tag: 'Connection',
      ),
    );
    // Detach first. A late cancellation may only finish its captured old
    // subscription; it must not clear a subscription installed by a reconnect.
    final usbSubscription = _usbFrameSubscription;
    _usbFrameSubscription = null;
    await cleanup.run('USB frames', () => usbSubscription?.cancel());
    // Native USB close owns FFI callback lifetime; retain its existing join.
    await _usbManager.disconnect();
    await _tcpConnector.disconnect();
    final wasReviewMode = transportAtDisconnect == MeshCoreTransportType.review;
    _reviewConnectGeneration++;
    final reviewSubscription = _reviewFrameSubscription;
    _reviewFrameSubscription = null;
    await cleanup.run('Review frames', () => reviewSubscription?.cancel());
    _reviewRadio?.dispose();
    _reviewRadio = null;

    final notifySubscription = _notifySubscription;
    _notifySubscription = null;
    await cleanup.run('BLE notifications', () => notifySubscription?.cancel());

    final connectionSubscription = _connectionSubscription;
    _connectionSubscription = null;
    await cleanup.run('BLE connection events', () => connectionSubscription?.cancel());
    final iosSubscription = _iosBleCentralSubscription;
    _iosBleCentralSubscription = null;
    _usingIosNativeBleCentral = false;
    await cleanup.run('iOS BLE event stream', () => iosSubscription?.cancel());
    if (wasUsingIosNativeBleCentral) {
      await cleanup.run('iOS BLE disconnect',
          () => _iosBleCentralMethod.invokeMethod<void>('disconnect'));
    }
    _selfInfoRetryTimer?.cancel();
    _selfInfoRetryTimer = null;
    _queueSyncTimeout?.cancel();
    _queueSyncTimeout = null;
    _queuedMessageRequestWork.finishCurrent();
    _channelSyncTimeout?.cancel();
    _channelSyncTimeout = null;
    _channelSyncRetries = 0;
    final translationService = _translationService;
    await cleanup.run('Translation model', () => translationService?.releaseModel());
    // The decode graph is ~833 MB resident; drop it with the connection. The
    // connector never disposes services it does not own (main.dart does).
    //
    // Cancel first: `releaseModel` serialises behind the codec's exclusive
    // lock, so disconnecting mid-decode would otherwise block this teardown
    // for the ~1 s the inference takes and then tear the session out from
    // under a job whose result nobody is waiting for any more.
    final imageCodecService = _imageCodecService;
    // Both model services enqueue release before any later load on their own
    // serial queue, then dispose a captured session, not a future replacement.
    await cleanup.run('Image codec model', () {
      imageCodecService?.cancelCodecJob();
      return imageCodecService?.releaseModel();
    });
    // Partial images belong to this session's sender prefixes; a reconnect
    // starts over. Dropping them also stops `evictExpired` from firing "image
    // incomplete" failures into the store minutes after the radio went away.
    _imageTransport?.reassembler.clear();

    if (!skipBleDeviceDisconnect && !wasUsingIosNativeBleCentral) {
      final device = _device;
      _device = null;
      // Skip queued BLE operations and bound the platform reply, keeping the
      // call bound to the old device even if its Future completes much later.
      await cleanup.run('BLE device disconnect', () => device?.disconnect(queue: false));
    } else if (wasUsingIosNativeBleCentral) {
      _appDebugLogService?.info(
        'Skipping FlutterBluePlus disconnect for iOS native BLE central',
        tag: 'BLE iOS',
      );
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
    _directEchoAckUnsupported = false;
    _unscopedSendUnsupported = false;
    _contacts.clear();
    _discoveredContacts.clear();
    _conversations.clear();
    _loadedConversationKeys.clear();
    _markerScannedContactKeys.clear();
    _conversationLoadGeneration++;
    _conversationLoadFutures.clear();
    _clearDirectEchoKey('disconnect');
    _channelKeyHashCache.clear();
    _directFloodRepeats.clear();
    _heardChannelPackets.clear();
    _setSelfPublicKey(null);
    _persistedStateLoadedKey = null;
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
    _allowedRepeatFreqRanges = null;
    _autoAddMaxHops = null;
    _contactsStorageFull = false;
    _repeaterBatterySnapshots.clear();
    _batteryRequested = false;
    _awaitingSelfInfo = false;
    _hasCompletedSelfInfoHandshake = false;
    _hasReceivedDeviceInfo = false;
    _maxContacts = _defaultMaxContacts;
    _maxChannels = _defaultMaxChannels;
    _resetSyncProgressState();
    _clearSharedMessageHistoryState();
    _cancelAllChannelNoRetransmissionTimers();
    _pendingChannelSentQueue.clear();
    _pendingGenericAckQueue.clear();
    final preserveChannelSendsForReconnect =
        !manual &&
        _isRecoveringConnection &&
        (transportAtDisconnect == MeshCoreTransportType.bluetooth ||
            transportAtDisconnect == MeshCoreTransportType.tcp);
    _shouldReplayRetriableChannelMessageSends =
        preserveChannelSendsForReconnect &&
        _retriableChannelMessageSends.isNotEmpty;
    if (!preserveChannelSendsForReconnect) {
      _clearDeferredChannelMessageSends(markFailed: true);
      _clearRetriableChannelMessageSends(markFailed: true);
    }
    _reactionSendQueueSequence = 0;

    _activeTransport = _isRecoveringConnection
        ? transportAtDisconnect
        : MeshCoreTransportType.bluetooth;
    if (wasReviewMode) {
      // Write the debounced unread counts now so they cannot land after the
      // review data has been deleted.
      await _unreadStore.flush();
      await endReviewModeSession(_appSettingsService);
    }

    _setState(MeshCoreConnectionState.disconnected);
    _syncBackgroundTcpService();
    _appDebugLogService?.info(
      'Disconnect complete transport=$transportLabel manual=$manual',
      tag: 'Connection',
    );
    if (!manual && _isRecoveringConnection) {
      _scheduleReconnect();
    }
  });

  Future<void> sendFrame(
    Uint8List data, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) {
    final service = _settingsSectionsService;
    Future<void> sendDirect() => _sendFrameDirect(
      data,
      channelSendQueueId: channelSendQueueId,
      expectsGenericAck: expectsGenericAck,
      waitForGenericAck: waitForGenericAck,
    );
    if (service == null) return sendDirect();
    return _packetBackgroundWork.dispatch(() => service.mcoX1(data, sendDirect));
  }

  Future<void> _sendFrameDirect(
    Uint8List data, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {
    if (!isConnected) {
      throw Exception("Not connected to a MeshCore device");
    }

    // Register the expected reply before writing. Some transports can deliver
    // the response quickly enough that waiting until after write races with
    // _handleOk().
    final pendingAck = _pendingGenericAckQueue.track(
      data,
      channelSendQueueId: channelSendQueueId,
      expectsOk: expectsGenericAck || waitForGenericAck,
      waitForReply: waitForGenericAck,
    );

    await _frameBackgroundWork.command(
      awaitsReply: pendingAck?.completer != null,
      operation: () async {
        try {
          await _writeFrameToActiveTransport(data).timeout(_commandAckTimeout);
        } catch (_) {
          if (pendingAck != null) {
            _pendingGenericAckQueue.remove(pendingAck);
          }
          rethrow;
        }
        _registerChannelEchoExpectation(data);

        if (pendingAck?.completer != null) {
          try {
            await pendingAck!.completer!.future.timeout(const Duration(seconds: 5));
          } on TimeoutException {
            // Keep a tombstone: the firmware still answers this command later,
            // and that reply must not be credited to the next pending command.
            _pendingGenericAckQueue.markTimedOut(pendingAck!);
            throw TimeoutException(
              'Timed out waiting for firmware acknowledgement',
            );
          }
        }
      },
    );
  }

  // Удержание ниже внешнего timeout: исходный I/O может завершиться позже него.
  Future<void> _writeFrameToActiveTransport(Uint8List data) =>
      _frameBackgroundWork.write(() => _writeFrameToActiveTransportCore(data));

  Future<void> _writeFrameToActiveTransportCore(Uint8List data) async {
    if (!isConnected) {
      throw Exception("Not connected to a MeshCore device");
    }
    _bleDebugLogService?.logFrame(data, outgoing: true);
    final testWriter = _frameWriterForTest;
    if (testWriter != null) {
      await testWriter(data);
      return;
    }
    if (_activeTransport == MeshCoreTransportType.usb) {
      await _usbManager.write(data);
      // Brief pause so the device firmware can process each frame before the
      // next arrives. Without this, rapid-fire frames over USB can cause the
      // device to miss responses (especially on reconnect).
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return;
    }
    if (_activeTransport == MeshCoreTransportType.tcp) {
      await _tcpConnector.write(data);
      return;
    }
    if (_activeTransport == MeshCoreTransportType.review) {
      final radio = _reviewRadio;
      if (radio == null) {
        throw Exception("Review radio not available");
      }
      radio.handle(data);
      return;
    }
    if (_usingIosNativeBleCentral) {
      _lastBleTxAt = DateTime.now();
      await _iosBleCentralMethod.invokeMethod<void>('send', {'data': data});
      return;
    }
    if (_rxCharacteristic == null) {
      throw Exception("MeshCore RX characteristic not available");
    }
    if (PlatformInfo.isIOS) {
      _lastBleTxAt = DateTime.now();
    }
    final properties = _rxCharacteristic!.properties;
    final canWriteWithoutResponse = properties.writeWithoutResponse;
    final canWriteWithResponse = properties.write;
    if (!canWriteWithoutResponse && !canWriteWithResponse) {
      throw Exception("MeshCore RX characteristic does not support write");
    }
    final isDestructiveQueueRead =
        data.isNotEmpty && data.first == cmdSyncNextMessage;
    final useWriteWithoutResponse =
        canWriteWithoutResponse &&
        (!isDestructiveQueueRead || !canWriteWithResponse);
    await _rxCharacteristic!.write(
      data.toList(),
      withoutResponse: useWriteWithoutResponse,
    );
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
      unawaited(
        requestBatteryStatus(force: true).catchError(_logTimerSendError),
      );
    });
  }

  void _logTimerSendError(Object error) {
    _appDebugLogService?.warn('Periodic send failed: $error', tag: 'Connector');
  }

  void _stopBatteryPolling() {
    _batteryPollTimer?.cancel();
    _batteryPollTimer = null;
  }

  // Detects a dead BLE notify stream or TCP socket (transport still reports
  // connected, but no inbound frames despite expected battery-poll traffic)
  // and recovers through the normal disconnect -> auto-reconnect path.
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
    final watchesInboundTraffic =
        _activeTransport == MeshCoreTransportType.bluetooth ||
        _activeTransport == MeshCoreTransportType.tcp;
    if (!isConnected || !watchesInboundTraffic) {
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
    final iosBleSnapshot =
        PlatformInfo.isIOS && _activeTransport == MeshCoreTransportType.bluetooth
        ? ' ${_iosBleSessionSnapshot(now)}'
        : '';
    _appDebugLogService?.warn(
      'RX watchdog: $_activeTransport connected but no inbound frames for '
      '${silence.inSeconds}s, forcing reconnect '
      '($_rxWatchdogReconnects/$_rxWatchdogMaxConsecutive)$iosBleSnapshot',
      tag: 'Watchdog',
    );
    unawaited(disconnect(manual: false));
  }

  /// Опрос GPS ноды с выбранным периодом; по умолчанию раз в минуту.
  /// No-op if already running. Triggered when the radio reports `gps=1`.
  void _startGpsLocationPolling() {
    if (_gpsLocationPollTimer != null) return;
    _gpsLocationPollTimer = Timer.periodic(_gpsLocationPollInterval, (timer) {
      if (!isConnected) {
        timer.cancel();
        _gpsLocationPollTimer = null;
        return;
      }
      // Skipped mid contact sync: APP_START would abort the firmware's
      // contact iteration. The next tick polls again.
      if (_isLoadingContacts) return;
      unawaited(_sendAppStart().catchError(_logTimerSendError));
    });
  }

  void _stopGpsLocationPolling() {
    _gpsLocationPollTimer?.cancel();
    _gpsLocationPollTimer = null;
  }

  void _syncPowerSavingSettings() {
    final reconnectSeconds = _appSettingsService?.settings.powerSaving.effective
        .backgroundReconnectIntervalSeconds ?? 30;
    if (reconnectSeconds > 30) {
      final policy = _reconnectPowerSettings ??= ReconnectPowerSettings(
        onChanged: _refreshReconnectDelay,
      );
      policy.setInterval(reconnectSeconds);
    } else if (_reconnectPowerSettings != null) {
      _reconnectPowerSettings?.dispose();
      _reconnectPowerSettings = null;
      _refreshReconnectDelay();
    }
    _channelKeyHashCache.setEnabled(
      _appSettingsService?.settings.powerSaving.effective.cacheChannelKeyHashes ?? false,
    );
    _uiNotifications.setInterval(Duration(
      milliseconds: _appSettingsService?.settings.powerSaving.effective
          .uiNotificationIntervalMilliseconds ?? UiNotificationBatcher.minimum.inMilliseconds,
    ));
    _radioStatsSendPolling.setEnabled(
      _appSettingsService?.settings.powerSaving.effective
          .pauseHiddenRadioIndicator ?? false,
    );
    final next = DevicePollingIntervals.fromOptions(
      _appSettingsService?.settings.powerSaving.effective,
    );
    final batteryChanged = next.battery != _devicePollingIntervals.battery;
    final gpsChanged = next.gps != _devicePollingIntervals.gps;
    if (!batteryChanged && !gpsChanged) return;
    _devicePollingIntervals = next;
    if (batteryChanged) {
      // Новый период начинает новое окно ожидания ответов, в том числе
      // при возврате с редкого опроса к короткому: старая тишина не авария.
      if (isConnected) {
        _rxSilenceAnchor = DateTime.now();
      }
      if (_batteryPollTimer?.isActive ?? false) {
        if (isConnected) {
          _startBatteryPolling();
        } else {
          _stopBatteryPolling();
        }
      }
    }
    if (gpsChanged && (_gpsLocationPollTimer?.isActive ?? false)) {
      _stopGpsLocationPolling();
      if (isConnected) {
        _startGpsLocationPolling();
      }
    }
  }

  void _syncRadioStatsSendPolling() => _radioStatsSendPolling.sync();

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
    _airtimeBaselineSecs = null;
    _airtimeGrewInLastPoll = false;
  }

  void acquireRadioStatsPolling() {
    _radioStatsPollRefCount++;
    if (_radioStatsPollRefCount == 1 && isConnected) {
      _startRadioStatsPolling();
    }
    _radioStatsPollingOwners.value = _radioStatsPollRefCount;
  }

  void releaseRadioStatsPolling() {
    _radioStatsPollRefCount = (_radioStatsPollRefCount - 1).clamp(0, 999);
    if (_radioStatsPollRefCount == 0) {
      _stopRadioStatsPolling();
    }
    _radioStatsPollingOwners.value = _radioStatsPollRefCount;
  }

  Future<void> requestRadioStats() async {
    if (!isConnected) return;
    if (!supportsCompanionRadioStats) return;
    try {
      await sendFrame(buildGetStatsFrame(statsTypeRadio));
    } catch (_) {}
  }

  /// Sends CMD_SET_RADIO_PARAMS (same arguments as [buildSetRadioParamsFrame])
  /// and waits for the reply. Returns false when the firmware rejects it with
  /// ERR_ILLEGAL_ARG (values out of range, or [clientRepeat] on a frequency
  /// outside [allowedRepeatFreqRanges]) or does not answer in time.
  Future<bool> setRadioParams(
    int freqHz,
    int bwHz,
    int sf,
    int cr, {
    bool? clientRepeat,
  }) async {
    if (!isConnected) return false;
    try {
      await sendFrame(
        buildSetRadioParamsFrame(
          freqHz,
          bwHz,
          sf,
          cr,
          clientRepeat: clientRepeat,
        ),
        waitForGenericAck: true,
      );
      return true;
    } catch (e) {
      _appDebugLogService?.warn(
        'SET_RADIO_PARAMS rejected: $e',
        tag: 'Connector',
      );
      return false;
    }
  }

  Future<void> setPathHashMode(int mode) async {
    if (!isConnected) return;
    final clampedMode = mode.clamp(0, 2).toInt();
    await sendFrame(buildSetPathHashModeFrame(clampedMode));
    final nextWidth = clampedMode + 1;
    if (_pathHashByteWidth != nextWidth) {
      _pathHashByteWidth = nextWidth;
      _directRepeaters.clear();
      _activeRepeaters.clear();
      _bumpRepeaterActivity();
      notifyListeners();
    }
  }

  bool _isPathLenValidForCurrentMode(int pathLen, List<int> pathBytes) {
    return _isPathLenValidForMode(pathLen, pathBytes, _pathHashByteWidth);
  }

  int? _encodePathLenForWidth(
    int pathLen,
    List<int> pathBytes,
    int pathHashWidth,
  ) {
    if (pathLen < 0 || pathLen == 0xFF) return pathLen;
    if (!_isPathLenValidForMode(pathLen, pathBytes, pathHashWidth)) {
      appLogger.warn(
        'Invalid path_len for mode: pathLen=$pathLen, '
        'bytesLen=${pathBytes.length}, width=$pathHashWidth',
        tag: 'Connector',
      );
      return null;
    }
    final mode = (pathHashWidth - 1) & 0x03;
    return (pathLen & 0x3F) | (mode << 6);
  }

  Future<void> refreshDeviceInfo() => _selfInfoWork.run(() async {
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
    await _sendAppStart();
    await requestBatteryStatus(force: true);
    await sendFrame(buildGetCustomVarsFrame());
    _deviceConfigRequested = false;
    _maybeRequestDeviceConfig();

    _scheduleSelfInfoRetry();
  });

  Future<({double latitude, double longitude})?> refreshSelfLocation({
    Duration timeout = const Duration(seconds: 3),
  }) => _selfInfoWork.run(() async {
    if (!isConnected) return _validSelfLocationOrNull();

    final waiter = Completer<void>();
    _selfInfoRefreshWaiters.add(waiter);
    try {
      await _sendAppStart();
      await waiter.future.timeout(timeout, onTimeout: () {});
    } catch (_) {
      // Return the latest cached location below; menu actions should not throw.
    } finally {
      _selfInfoRefreshWaiters.remove(waiter);
    }

    return _validSelfLocationOrNull();
  });

  ({double latitude, double longitude})? _validSelfLocationOrNull() {
    final latitude = _selfLatitude;
    final longitude = _selfLongitude;
    if (!hasValidLocation(latitude, longitude)) return null;
    return (latitude: latitude!, longitude: longitude!);
  }

  Future<void> _requestDeviceInfo() => _selfInfoWork.run(() async {
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
    await _sendAppStart();
    await sendFrame(buildGetCustomVarsFrame());
    await requestBatteryStatus();
    _deviceConfigRequested = false;
    _maybeRequestDeviceConfig();
    _scheduleSelfInfoRetry();
  });

  /// Version-gated config queries, sent once the firmware version (DEVICE_INFO)
  /// and SELF_INFO (which the auto-add reply handler relies on) are known.
  void _maybeRequestDeviceConfig() {
    if (_deviceConfigRequested ||
        !isConnected ||
        _firmwareVerCode == null ||
        _selfPublicKey == null) {
      return;
    }
    _deviceConfigRequested = true;
    if (supportsAutoAddConfig) {
      unawaited(
        sendFrame(buildGetAutoAddFlagsFrame()).catchError(_logTimerSendError),
      );
    }
    if (supportsAllowedRepeatFreq) {
      unawaited(
        sendFrame(
          buildGetAllowedRepeatFreqFrame(),
        ).catchError(_logTimerSendError),
      );
    }
  }

  /// Sends CMD_APP_START unless a contact sync is running, in which case it is
  /// sent when the sync ends (see [_continueAfterContactSync]).
  Future<void> _sendAppStart() async {
    if (_isLoadingContacts) {
      _appStartDeferredForContactSync = true;
      return;
    }
    await sendFrame(_buildAppStartFrame());
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
          _selfInfoWork.finishCurrent();
          timer.cancel();
          return;
        }
        if (_isLoadingContacts || _isSyncingChannels || _channelSyncInFlight) {
          return;
        }
        attempts += 1;
        unawaited(
          _sendAppStart().catchError(_logTimerSendError),
        );
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
        _selfInfoWork.finishCurrent();
        timer.cancel();
        return;
      }
      if (!_awaitingSelfInfo) {
        _selfInfoWork.finishCurrent();
        timer.cancel();
        return;
      }
      unawaited(
        _sendAppStart().catchError(_logTimerSendError),
      );
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
    );
  }

  Future<void> getContacts({int? since, bool preserveExisting = false}) async {
    if (!isConnected) return;
    // The firmware answers ERR_BAD_STATE while an iteration is running, and
    // clearing here would drop the contacts already received. A sync older
    // than a minute is assumed lost (e.g. END_OF_CONTACTS never arrived).
    final requestedAt = _contactSyncRequestedAt;
    if (_isLoadingContacts &&
        requestedAt != null &&
        DateTime.now().difference(requestedAt) < const Duration(minutes: 1)) {
      return;
    }

    return _contactSyncWork.run(
      () => _getContactsCore(since: since, preserveExisting: preserveExisting),
    );
  }

  Future<void> _getContactsCore({
    int? since,
    required bool preserveExisting,
  }) async {
    final contactCacheLoad = _contactCacheLoadFuture;
    if (contactCacheLoad != null) {
      await contactCacheLoad;
      if (!isConnected) return;
    }

    _contactSyncRequestedAt = DateTime.now();
    final contactWork = _contactSyncWork.begin();
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

    try {
      await sendFrame(buildGetContactsFrame(since: since));
    } catch (_) {
      _isLoadingContacts = false;
      notifyListeners();
      _continueAfterContactSync();
      _contactSyncWork.finish(contactWork);
      rethrow;
    }
  }

  /// What waits for a contact sync to end, whether it ended with
  /// END_OF_CONTACTS, with the idle timeout or by failing to start: the
  /// APP_START held back while it ran, and the messages whose senders it
  /// may have delivered.
  void _continueAfterContactSync() {
    if (!isConnected) return;
    if (_appStartDeferredForContactSync) {
      _appStartDeferredForContactSync = false;
      unawaited(_sendAppStart().catchError(_logTimerSendError));
    }
    unawaited(_replayUnknownSenderMessages());
  }

  /// Clears the contact-sync follow-up state. Call on connection teardown.
  void _resetSyncFlowState() {
    _appStartDeferredForContactSync = false;
    _unknownSenderMessageFrames.clear();
  }

  void _holdUnknownSenderMessage(Uint8List frame) {
    if (_unknownSenderMessageFrames.length >= _maxUnknownSenderMessageFrames) {
      _unknownSenderMessageFrames.removeAt(0);
      appLogger.warn(
        'Too many messages from unknown contacts; dropping the oldest',
        tag: 'Connector',
      );
    }
    _unknownSenderMessageFrames.add(Uint8List.fromList(frame));
  }

  /// Replays held unknown-sender messages exactly once. With
  /// [onlyResolvable], frames whose sender is still unknown stay held (a
  /// single CONTACT frame arrived); otherwise unresolved frames are dropped.
  Future<void> _replayUnknownSenderMessages({
    bool onlyResolvable = false,
  }) => _packetBackgroundWork.replay(
    () => _replayUnknownSenderMessagesCore(onlyResolvable: onlyResolvable),
  );

  Future<void> _replayUnknownSenderMessagesCore({
    bool onlyResolvable = false,
  }) async {
    if (_unknownSenderMessageFrames.isEmpty) return;
    final ready = <Uint8List>[];
    _unknownSenderMessageFrames.removeWhere((frame) {
      if (onlyResolvable) {
        final prefix = _extractSenderPrefix(frame);
        if (prefix == null ||
            _findContactByPrefix(prefix, includeDiscoveredFallback: true) ==
                null) {
          return false;
        }
      }
      ready.add(frame);
      return true;
    });
    for (final frame in ready) {
      await _handleIncomingMessage(
        frame,
        alreadyAdvancedQueueSync: true,
        isUnknownSenderReplay: true,
      );
    }
  }

  void _armContactSyncTimeout() {
    _contactSyncTimeout?.cancel();
    // Contact sync has no request/response timeout and normally ends only with
    // END_OF_CONTACTS. If BLE drops that final frame, the progress indicator
    // otherwise remains active forever, so treat prolonged RX silence as end.
    _contactSyncTimeout = Timer(_contactSyncIdleTimeout, () {
      if (!_isLoadingContacts) return;
      final contactWork = _contactSyncWork.current;
      appLogger.warn(
        'Contact sync timed out after receiving $_contactSyncReceived contacts',
        tag: 'Connector',
      );
      _contactSyncTimeout = null;
      _isLoadingContacts = false;
      _hasLoadedContacts = true;
      _preserveContactsOnRefresh = false;
      _contactSyncUsesSinceFilter = false;
      _contactsUnconfirmedBySync = null;
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
      } else {
        _startPostChannelInitialQueuedMessageSync();
      }
      _continueAfterContactSync();
      _contactSyncWork.finish(contactWork);
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
    String rawText, {
    String? uncompressedText,
    String? originalText,
    String? translatedLanguageCode,
    String? translationModelId,
    String? pendingMessageId,
    DateTime? pendingTimestamp,
    String? replyToMessageId,
    String? replyToSenderName,
    String? replyToText,
    int? replyToTimestamp,
  }) => _radioSendBackgroundWork.run(() async {
    // A marker is normalised before anything else: what is stored, what goes
    // on the wire and what a later `del:` command names have to be one string.
    // Skipped when committing a queued or retried message — that text came out
    // of a message we already normalised, and a profile that also maps Latin
    // letters would rewrite it again.
    final text =
        pendingMessageId == null && SharedMarkerDeletion.isMarker(rawText)
        ? prepareContactOutboundText(contact, rawText)
        : rawText;
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
          replyToMessageId: replyToMessageId,
          replyToSenderName: replyToSenderName,
          replyToText: replyToText,
          replyToTimestamp: replyToTimestamp,
        );
      }
      return;
    }
    _loadMessagesForContactInBackground(contact.publicKeyHex);
    final body = _contactReplyBody(contact, text, replyToSenderName);

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
        body,
        originalText: originalText,
        translatedLanguageCode: translatedLanguageCode,
        translationModelId: translationModelId,
        replyToMessageId: replyToMessageId,
        replyToSenderName: replyToSenderName,
        replyToText: replyToText,
      );
      unawaited(_addMessage(contact.publicKeyHex, signingPlaceholder));
      notifyListeners();
    }

    final outboundText = await prepareContactOutboundTextAsync(
      contact,
      text,
      replyAuthorName: replyToSenderName,
      replyTimestamp: replyToTimestamp,
      replyToText: replyToText,
      replyToMessageId: replyToMessageId,
    );
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

    // Meta as carried by compressed app payloads. MCMP signs the exact body;
    // MCOtxt may inherit the timestamp from the outer text packet, which is
    // the message's own: both are read off one clock, or an anchor on this
    // message taken from the container would miss the packet by a second.
    final messageTimestamp = pendingTimestamp ?? DateTime.now();
    final mcmpMeta = McmpAppCodec.tryDecodeTextPayloadMessage(outboundText);
    final mcotxtMeta = MCOtxtAppCodec.tryDecodeTextPayloadMessage(
      outboundText,
      inheritedTimestamp: messageTimestamp.millisecondsSinceEpoch ~/ 1000,
    );
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
      appLogger.info('Sending reaction: ${reactionInfo.identifier()}');
      _conversations.putIfAbsent(contact.publicKeyHex, () => []);
      final messages = _conversations[contact.publicKeyHex]!;

      // No check for duplicates. If you want to do it again to resend, you can.
      final String reactionID = reactionInfo.identifier();
      _processedContactReactions.putIfAbsent(contact.publicKeyHex, () => {});
      _processedContactReactions[contact.publicKeyHex]!.add(reactionID);

      // Apply reaction locally with pending status
      final reactionTarget = _processOutgoingContactReaction(
        messages,
        reactionInfo,
        contact,
      );
      final changedMessage = _setReactionStatus(
        contact.publicKeyHex,
        reactionInfo,
        MessageStatus.pending,
      );
      final messageToSave = changedMessage ?? reactionTarget;
      if (messageToSave != null) {
        _messageStore.saveMessage(contact.publicKeyHex, messageToSave);
      }
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
        text: body,
        messageId: pendingMessageId,
        timestamp: messageTimestamp,
        preparedOutboundText: outboundText,
        compressionType: compression?.type,
        compressionSavingsPercent: compression?.savingsPercent,
        compressionOriginalBytes: compression?.originalBytes,
        compressionPayloadBytes: compression?.payloadBytes,
        mcmpSignatureStatus: mcmpStatus,
        containerTimestamp: mcmpMeta?.timestamp ?? mcotxtMeta?.metadataTimestamp,
        containerSenderName: mcmpMeta?.senderName ?? mcotxtMeta?.senderName,
        mcmpIsSigned: mcmpMeta?.isSigned ?? false,
        mcmpSignature: mcmpMeta?.signature,
        containerReplyAuthorName:
            mcmpMeta?.replyAuthorName ?? mcotxtMeta?.replyAuthorName,
        containerReplyTimestamp:
            mcmpMeta?.replyTimestamp ?? mcotxtMeta?.replyTimestamp,
        originalText: originalText,
        translatedLanguageCode: translatedLanguageCode,
        translationModelId: translationModelId,
        replyToMessageId: replyToMessageId,
        replyToSenderName: replyToSenderName,
        replyToText: replyToText,
      );
    } else {
      // Fallback to old behavior if retry service not initialized
      final resolved = resolvePathSelection(contact);
      final message = Message.outgoing(
        contact.publicKey,
        body,
        rawText: outboundText,
        messageId: pendingMessageId,
        timestamp: messageTimestamp,
        wasMcmpCompressed: _isMcmpEncodedText(outboundText),
        compressionType: compression?.type,
        compressionSavingsPercent: compression?.savingsPercent,
        compressionOriginalBytes: compression?.originalBytes,
        compressionPayloadBytes: compression?.payloadBytes,
        mcmpSignatureStatus: mcmpStatus,
        containerTimestamp: mcmpMeta?.timestamp ?? mcotxtMeta?.metadataTimestamp,
        containerSenderName: mcmpMeta?.senderName ?? mcotxtMeta?.senderName,
        mcmpIsSigned: mcmpMeta?.isSigned ?? false,
        mcmpSignature: mcmpMeta?.signature,
        containerReplyAuthorName:
            mcmpMeta?.replyAuthorName ?? mcotxtMeta?.replyAuthorName,
        containerReplyTimestamp:
            mcmpMeta?.replyTimestamp ?? mcotxtMeta?.replyTimestamp,
        pathLength: resolved.useFlood ? -1 : resolved.hopCount,
        pathBytes: Uint8List.fromList(resolved.pathBytes),
        originalText: originalText,
        translatedLanguageCode: translatedLanguageCode,
        translationModelId: translationModelId,
        replyToMessageId: replyToMessageId,
        replyToSenderName: replyToSenderName,
        replyToText: replyToText,
      );
      unawaited(
        _addMessage(contact.publicKeyHex, message),
      ); // recipient as "sender"
      notifyListeners();
      final sentByRadioAt = DateTime.now();
      final waitSeconds = sentByRadioAt.difference(message.timestamp).inSeconds;
      _updateMessage(
        message.copyWith(
          receivedAt: contact.type == advTypeRoom ? sentByRadioAt : null,
          sentByRadioAt: sentByRadioAt,
          sentByRadioWaitSeconds: [waitSeconds < 0 ? 0 : waitSeconds],
        ),
      );
      await sendFrame(buildSendTextMsgFrame(contact.publicKey, outboundText));
    }
  });

  /// [pathHashWidth] defaults to the width implied by [customPath], falling
  /// back to the radio's current mode (e.g. for zero-hop paths).
  Future<void> setContactPath(
    Contact contact,
    Uint8List customPath,
    int pathLen, {
    int? pathHashWidth,
    bool waitForAck = false,
  }) async {
    // Serialize path operations to prevent interleaved async calls from
    // leaving in-memory state inconsistent with the device.
    final prev = _pathOpLock;
    final completer = Completer<void>();
    _pathOpLock = completer.future;
    await prev;
    try {
      if (!isConnected) return;

      final width =
          pathHashWidth ??
          (pathLen > 0 && customPath.length % pathLen == 0
              ? customPath.length ~/ pathLen
              : _pathHashByteWidth);
      final encodedPathLen = _encodePathLenForWidth(pathLen, customPath, width);
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
          lastAdvert: _deviceLastAdvert(contact),
        ),
        waitForGenericAck: waitForAck,
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
          pathHashWidth: width,
        );
        notifyListeners();
      }
    } finally {
      completer.complete();
    }
  }

  /// The advert timestamp the firmware holds for [contact] (Contact.lastSeen
  /// is parsed from that field); the stored copy is freshest.
  DateTime _deviceLastAdvert(Contact contact) =>
      (_contacts.byKey(contact.publicKeyHex) ?? contact).lastSeen;

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

    final encodedPathLen = _encodePathLenForWidth(
      latestContact.pathLength,
      latestContact.path,
      latestContact.pathHashWidth,
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
        lastAdvert: latestContact.lastSeen,
      ),
    );

    final updatedContact = latestContact.copyWith(flags: updatedFlags);
    final index = _contacts.indexWhere(
      (c) => c.publicKeyHex == contact.publicKeyHex,
    );
    if (index >= 0) {
      _contacts[index] = mergeDuplicateContacts(
        _contacts[index],
        updatedContact.copyWith(
          isActive: true,
        ),
      ).copyWith(
        type: latestContact.type,
        name: latestContact.name,
        pathLength: latestContact.pathLength,
        path: latestContact.path,
        pathHashWidth: latestContact.pathHashWidth,
        flags: updatedFlags,
      );
    } else {
      _contacts.add(updatedContact.copyWith(isActive: true));
      _knownContactKeys.add(updatedContact.publicKeyHex);
    }
    final discoveredIndex = _discoveredContacts.indexWhere(
      (c) => c.publicKeyHex == contact.publicKeyHex,
    );
    if (discoveredIndex >= 0) {
      _discoveredContacts[discoveredIndex] = mergeDuplicateContacts(
        _discoveredContacts[discoveredIndex],
        updatedContact.copyWith(isActive: true),
      ).copyWith(flags: updatedFlags, isActive: true);
    }
    notifyListeners();
    unawaited(_persistContacts());
    unawaited(_persistDiscoveredContacts());
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

  /// Puts on the node the route a login, a status, telemetry or neighbour
  /// request or a CLI command to [contact] goes by, and returns it: the
  /// user's override, else the route the node holds, which is the one the
  /// screens show. Route rotation stays with direct messages. Picked here,
  /// it replaced the node's route with a path from the history on every
  /// request, the next one each time and never a direct one, so a repeater
  /// shown as direct was logged into over a stale hop and each command of a
  /// settings refresh went its own way.
  Future<PathSelection> preparePathForContactSend(Contact contact) async {
    final resolved = resolvePathSelection(contact);

    if (resolved.useFlood) {
      await clearContactPath(contact, waitForAck: true);
    } else {
      await setContactPath(
        contact,
        Uint8List.fromList(resolved.pathBytes),
        resolved.hopCount,
        waitForAck: true,
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
      final matchesLength = updated.path.length == expectedLength;
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
    String rawText, {
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
    // The region to send under instead of the channel's own: a reply to a
    // message heard under a region goes back there.
    String? region,
  }) => _radioSendBackgroundWork.run(() async {
    // See sendMessage: normalised up front, and only for a first send.
    var text =
        pendingMessageId == null && SharedMarkerDeletion.isMarker(rawText)
        ? prepareChannelOutboundText(channel.index, rawText)
        : rawText;
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
          region: region,
        );
      }
      return;
    }
    final shouldBypassAckAndRetry = _isChannelAckAndRetryBypassed(channel.name);
    final shouldDeferForSync =
        !shouldBypassAckAndRetry && _shouldDeferChannelSendForSync;
    // The name the message goes out under: the channel's own when it has
    // one and nothing holds it back, else the node's.
    final senderName = channelSendName(channel.index);
    final hasExplicitMcoImageV3 =
        preparedMcoImageV3Outbound?.kind == ChannelBinaryDataKind.mcoImageV3 ||
        (mcoImageV3 != null && ChannelBinaryDataHelper.canSend);

    // Check if this is a reaction - if so, process it immediately instead of adding as a message.
    // An explicit MCOimg v3 object can never be a reaction payload.
    final reactionInfo = hasExplicitMcoImageV3
        ? null
        : ReactionHelper.parseReaction(text);
    if (reactionInfo != null) {
      if (pendingMessageId != null) {
        _pendingChannelSends.remove(pendingMessageId)?.timer?.cancel();
      }
      reactionInfo.senderName = selfName;
      // Check if we've already processed this reaction
      _processedChannelReactions.putIfAbsent(channel.index, () => {});
      final reactionIdentifier = reactionInfo.identifier();

      // Maybe we should allow resending. Recipients can drop duplicates.
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
      appLogger.info('Adding sent channel reaction, id: $reactionIdentifier');
      final changedMessage = _processReaction(messages, reactionInfo);
      if (changedMessage != null) {
        await _channelMessageStore.saveChannelMessage(
          channel.index,
          changedMessage,
        );

        // Mark this reaction as processed
        _processedChannelReactions[channel.index]!.add(reactionIdentifier);

        notifyListeners();

        // Send the reaction to the device (don't add as a visible message)
        final reactionQueueId = _nextReactionSendQueueId();
        _pendingChannelSentQueue.add(reactionQueueId);
        try {
          await _runScopedChannelSend(() async {
            await _waitForRadioQuiet(lastInboundRxTime: _lastChannelMsgRxTime);
            await _sendFrameAndWaitForCommandAck(
              _channelTextFrame(
                channel,
                text,
                senderName: senderName,
                region: _outgoingChannelRegion(channel.index),
              ),
              channelSendQueueId: reactionQueueId,
            );
          }, region: _channelSendScope(channel.index));
        } catch (_) {
          // e.g. SET_FLOOD_SCOPE rejected or timed out: nothing was sent.
          _pendingChannelSentQueue.remove(reactionQueueId);
          rethrow;
        }
        return;
      }
      // It looks like a reaction, but we did not find its target, so
      // we continue to process it normally.
    }

    final outgoingRegion =
        region ??
        (shouldDeferForSync
            ? _outgoingChannelRegion(channel.index)
            : await _outgoingChannelRegionForMessage(channel.index));
    if (!isConnected) return;

    // MCMP v3: the reply pair travels only when both parts are known, and the
    // signature covers the exact same flags/reply data as the encoded body.
    final hasReplyPair = replyToSenderName != null && replyToTimestamp != null;
    final containerReplyAuthorName = hasReplyPair ? replyToSenderName : null;
    final containerReplyTimestamp = hasReplyPair ? replyToTimestamp : null;
    final mcmpV3Applies =
        !hasExplicitMcoImageV3 &&
        isChannelMcmpEnabled(channel.index) &&
        channelMcmpVersion(channel.index) == 3 &&
        _isMcmpSignableText(
          text,
          allowMarkerPayload: channelMcmpUseSign(channel.index),
        );
    final mcmpV3Timestamp = mcmpV3Applies
        ? DateTime.now().millisecondsSinceEpoch ~/ 1000
        : null;
    var mcotxtApplies =
        !hasExplicitMcoImageV3 &&
        isChannelMCOtxtEnabled(channel.index) &&
        _isMcmpSignableText(text);
    var mcotxtTimestamp = mcotxtApplies
        ? DateTime.now().millisecondsSinceEpoch ~/ 1000
        : null;
    // "Plain when smaller": both packets are costed as the firmware builds
    // them and the plain one wins ties. A reply gets its exact-quote fragment
    // back, which the composer left out for the container's anchor.
    var mcotxtPlainFallback = false;
    if (mcotxtApplies) {
      final plain = _channelPlainIfSmallerThanMCOtxt(
        channel,
        text,
        timestamp: mcotxtTimestamp!,
        replyToSenderName: replyToSenderName,
        replyToText: replyToText,
        replyToMessageId: replyToMessageId,
        replyToTimestamp: replyToTimestamp,
      );
      if (plain != null) {
        text = plain;
        mcotxtApplies = false;
        mcotxtTimestamp = null;
        mcotxtPlainFallback = true;
      }
    }
    final containerText = (mcmpV3Applies || mcotxtApplies)
        ? _containerReplyBody(text, replyToSenderName)
        : text;
    Uint8List? mcmpSignature;
    if (mcmpV3Applies && channelMcmpUseSign(channel.index)) {
      // Signing round-trips to the node (up to a few seconds). Show the
      // message right away in the pending state so it does not visually
      // disappear while we wait; it is finalized (badges/state) below once
      // the signature result is known, and only then actually transmitted.
      ChannelMessage? signingPlaceholder;
      if (pendingMessageId == null) {
        signingPlaceholder = ChannelMessage.outgoing(
          containerText,
          senderName,
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
        await _addChannelMessage(channel.index, signingPlaceholder);
        notifyListeners();
      }

      mcmpSignature = await _signMcmpCanonical(
        context: McmpSigningContext.channel,
        binding: McmpAppCodec.channelSigningBinding(channel.psk),
        senderName: senderName,
        timestamp: mcmpV3Timestamp!,
        hasSenderNameInBody: false,
        text: containerText,
        replyAuthorName: containerReplyAuthorName,
        replyTimestamp: containerReplyTimestamp,
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

    // A marker or a `del:` command gives up plain text only for a signature:
    // that envelope is what proves who ordered a pin placed or removed, and
    // it is the one thing worth hiding the payload from clients that cannot
    // decode MCMP. A node that refused to sign sends it plain instead.
    final isMarkerPayload = SharedMarkerDeletion.isMarkerPayload(text);
    var mcmpV3Sent =
        mcmpV3Applies && (!isMarkerPayload || mcmpSignature != null);

    final binaryOutbound =
        preparedMcoImageV3Outbound ??
        (hasExplicitMcoImageV3
            ? ChannelBinaryDataHelper.tryEncodeMcoImageV3Outbound(
                image: mcoImageV3!,
                senderName: senderName,
              )
            : ChannelBinaryDataHelper.tryEncodeOutbound(
                text: containerText,
                senderName: senderName,
                mcmpEnabled: isChannelMcmpEnabled(channel.index),
                mcotxtEnabled: mcotxtApplies,
                mcmpVersion: channelMcmpVersion(channel.index),
                mcmpUseSign: channelMcmpUseSign(channel.index),
                timestamp:
                    mcmpV3Timestamp ??
                    mcotxtTimestamp ??
                    DateTime.now().millisecondsSinceEpoch ~/ 1000,
                signature: mcmpSignature,
                replyAuthorName: replyToSenderName,
                replyTimestamp: replyToTimestamp,
                allowMarkerPayload: mcmpV3Sent,
              ));
    if (hasExplicitMcoImageV3 && binaryOutbound == null) return;

    final isMcoImageBinary =
        binaryOutbound?.kind == ChannelBinaryDataKind.mcoImageV3 ||
        binaryOutbound?.kind == ChannelBinaryDataKind.mcoImageV4;
    final messageText =
        binaryOutbound?.canonicalText ??
        ((mcmpV3Applies || mcotxtApplies) ? containerText : text);
    final String outboundText;
    if (isMcoImageBinary) {
      outboundText = messageText;
    } else if (mcmpV3Sent && binaryOutbound == null) {
      // Text transport carries the signed body in the mcmp3: Base91 wrapper;
      // the sender name stays in the outer "Name: text" layer (no bit2).
      final wrapped = McmpAppCodec.encodeTextTransport(
        text: containerText,
        timestamp: mcmpV3Timestamp!,
        signature: mcmpSignature,
        replyAuthorName: containerReplyAuthorName,
        replyTimestamp: containerReplyTimestamp,
      );
      // Base91 hands back most of what the compressor won and the signature
      // costs 64 bytes on top, so a long marker can end up over the frame.
      // A plain pin beats one the length guard below refuses to send; a plain
      // message has no such alternative and keeps failing loudly.
      if (isMarkerPayload &&
          utf8.encode(wrapped).length >
              maxChannelTextBytes(channel.index)) {
        mcmpV3Sent = false;
        outboundText = text;
      } else {
        outboundText = wrapped;
      }
    } else if (mcotxtApplies && binaryOutbound == null) {
      outboundText = MCOtxtAppCodec.encodeTextTransport(
        text: containerText,
        timestamp: mcotxtTimestamp!,
        replyAuthorName: containerReplyAuthorName,
        replyTimestamp: containerReplyTimestamp,
      );
    } else if (mcotxtPlainFallback) {
      // Not through prepareChannelOutboundText, which would wrap it again.
      outboundText = text;
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
    final isBinaryCompressedTextTransport =
        binaryOutbound?.kind == ChannelBinaryDataKind.mcmp ||
        binaryOutbound?.kind == ChannelBinaryDataKind.mcotxt;
    final compression = isMcoImageBinary
        ? null
        : _channelCompressionMetadata(
            channel.index,
            uncompressedText ?? text,
            outboundText,
            binaryPayloadBytes: isBinaryCompressedTextTransport
                ? binaryOutbound?.payload.length
                : null,
            senderName: senderName,
          );
    final packetHash = binaryOutbound == null
        ? null
        : _computeChannelDataHash(
            channel.index,
            binaryOutbound.dataType,
            binaryOutbound.payload,
          );
    final mcotxtMeta = binaryOutbound?.kind == ChannelBinaryDataKind.mcotxt
        ? ChannelBinaryDataHelper.tryDecodeAppData(
            dataType: binaryOutbound!.dataType,
            payload: binaryOutbound.payload,
          )?.mcotxtMessage
        : MCOtxtAppCodec.tryDecodeTextPayloadMessage(
            outboundText,
            inheritedTimestamp: mcotxtTimestamp,
          );
    final packetRegion = _displayPacketRegion(outgoingRegion);
    if (pendingMessageId != null) {
      _pendingChannelSends.remove(pendingMessageId)?.timer?.cancel();
    }
    final baseMessage = ChannelMessage.outgoing(
      messageText,
      senderName,
      channel.index,
      rawText: isBinaryTransport ? null : outboundText,
      messageId: pendingMessageId,
      timestamp: pendingTimestamp,
      receivedAt: pendingReceivedAt,
      wasMcmpCompressed:
          (!isMcoImageBinary && _isMcmpEncodedText(outboundText)) ||
          isBinaryCompressedTextTransport,
      compressionType: compression?.type,
      compressionSavingsPercent: compression?.savingsPercent,
      compressionOriginalBytes: compression?.originalBytes,
      compressionPayloadBytes: compression?.payloadBytes,
      // Keyed on what actually went out, not on what was eligible: a marker
      // that fell back to plain text must not claim an envelope it lost.
      mcmpSignatureStatus: mcmpV3Sent
          ? (mcmpSignature != null
                ? McmpSignatureStatus.valid
                : McmpSignatureStatus.unsigned)
          : (binaryOutbound?.kind == ChannelBinaryDataKind.mcmp
                ? binaryOutbound!.mcmpSignatureStatus
                : McmpAppCodec.signatureStatusFromTextPayload(outboundText)),
      containerTimestamp: mcmpV3Sent
          ? mcmpV3Timestamp
          : mcotxtMeta?.metadataTimestamp,
      mcmpIsSigned: mcmpV3Sent && mcmpSignature != null,
      mcmpSignature: mcmpV3Sent ? mcmpSignature : null,
      containerReplyAuthorName: mcmpV3Sent
          ? containerReplyAuthorName
          : mcotxtMeta?.replyAuthorName,
      containerReplyTimestamp: mcmpV3Sent
          ? containerReplyTimestamp
          : mcotxtMeta?.replyTimestamp,
      originalText: originalText,
      translatedLanguageCode: translatedLanguageCode,
      translationModelId: translationModelId,
      wasBinaryTransport: isBinaryTransport,
      binaryPacketBytes: binaryOutbound?.payload.length,
      rawPayload: binaryOutbound?.payload,
      packetRegion: packetRegion,
      packetRegionInfoAvailable: true,
      replyToMessageId: replyToMessageId,
      replyToSenderName: replyToSenderName,
      replyToText: replyToText,
    );
    final message = packetHash == null
        ? baseMessage
        : baseMessage.copyWith(packetHash: packetHash);
    await _addChannelMessage(
      channel.index,
      message,
      awaitPersistence: false,
    );
    if (!isBinaryTransport &&
        utf8.encode(outboundText).length >
            maxChannelTextBytes(channel.index)) {
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
        senderName: senderName,
        binaryOutbound: binaryOutbound,
        preparedOutboundText: isMcoImageBinary ? null : outboundText,
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
          _markChannelMessageSentByRadio(message.messageId, sentByRadioAt);
          _updateChannelMessagePacketTimestamp(
            channel.index,
            message.messageId,
            sentTimestampSeconds,
            packetHash: binaryFrame == null
                ? _computeContentHash(
                    channel.index,
                    sentTimestampSeconds,
                    '$senderName: $messageText',
                  )
                : null,
          );
          _markPendingChannelMessageSentById(message.messageId);
          await sendFrame(
            binaryFrame ??
                _channelTextFrame(
                  channel,
                  outboundText,
                  senderName: senderName,
                  region: outgoingRegion,
                  timestampSeconds: sentTimestampSeconds,
                ),
          );
        },
        region: region ?? _channelSendScope(channel.index),
        waitForScopeReset: false,
      );
      return;
    }
    _retriableChannelMessageSends[message.messageId] =
        _DeferredChannelMessageSend(
          channel: channel,
          messageId: message.messageId,
          text: messageText,
          senderName: senderName,
          binaryOutbound: binaryOutbound,
          preparedOutboundText: isMcoImageBinary ? null : outboundText,
          uncompressedText: uncompressedText,
          originalText: originalText,
          translatedLanguageCode: translatedLanguageCode,
          translationModelId: translationModelId,
          replyToMessageId: replyToMessageId,
          replyToSenderName: replyToSenderName,
          replyToText: replyToText,
          replyToTimestamp: replyToTimestamp,
          region: region,
        );
    _pendingChannelSentQueue.add(message.messageId);
    notifyListeners();

    // A resend reuses the packet time, so it is the same packet: repeaters
    // that forwarded it already drop the copy and recipients see it once. The
    // echo registry and the heard-packet map were fed by the first send, and
    // the same frame bytes feed them nothing new.
    int? sentTimestampSeconds;
    Future<void> transmit({bool isResend = false}) =>
        _runScopedChannelSend(() async {
          await _waitForRadioQuiet(lastInboundRxTime: _lastChannelMsgRxTime);
          if (!isResend) {
            final sentByRadioAt = DateTime.now();
            final resendSettings = _appSettingsService?.settings;
            final resendUntilMinHops =
                resendSettings?.channelMinHopsEnabled ?? false;
            _markChannelMessageSentByRadio(
              message.messageId,
              sentByRadioAt,
              // Under the resend setting the warning waits for the resends.
              deferNoRetransmissionWarning: resendUntilMinHops,
            );
            if (resendUntilMinHops) {
              // The attempt badge spins from the radio transmission on; the
              // resend loop keeps the entry once the node has taken the frame.
              _channelHopChecks[message.messageId] = (
                resends: 0,
                maxResends: resendSettings?.channelMinHopsRetries ?? 1,
              );
              _channelResendRevision++;
            }
            final seconds = sentByRadioAt.millisecondsSinceEpoch ~/ 1000;
            sentTimestampSeconds = seconds;
            _updateChannelMessagePacketTimestamp(
              channel.index,
              message.messageId,
              seconds,
              packetHash: binaryFrame == null
                  ? _computeContentHash(
                      channel.index,
                      seconds,
                      '$senderName: $messageText',
                    )
                  : null,
            );
          }
          if (isResend) _incrementChannelResendCount(message.messageId);
          if (binaryFrame != null) {
            await _sendFrameAndWaitForCommandAck(
              binaryFrame,
              channelSendQueueId: isResend ? null : message.messageId,
            );
            return;
          }
          // Stamp the outgoing packet with the actual send time and align the
          // stored message.timestamp to the exact value that went on the air,
          // so replies to our own message resolve by exact-timestamp matching.
          await _sendFrameAndWaitForCommandAck(
            _channelTextFrame(
              channel,
              outboundText,
              senderName: senderName,
              region: outgoingRegion,
              timestampSeconds: sentTimestampSeconds,
              registerEcho: !isResend,
            ),
            channelSendQueueId: isResend ? null : message.messageId,
          );
        }, region: region ?? _channelSendScope(channel.index));
    final settings = _appSettingsService?.settings;
    final minHopsSettings = settings != null && settings.channelMinHopsEnabled
        ? settings
        : null;
    try {
      await transmit();
    } catch (_) {
      // The hop check registered at the radio transmission, if it got there.
      _channelHopChecks.remove(message.messageId);
      _channelResendRevision++;
      // A failed or timed-out SET_FLOOD_SCOPE (or text send) means no OK/ERR
      // will resolve this message, so fail it here instead of leaving it
      // pending forever.
      _pendingChannelSentQueue.remove(message.messageId);
      _markPendingChannelMessageFailedById(message.messageId);
      rethrow;
    }

    if (minHopsSettings != null) {
      unawaited(
        _resendUntilMinHops(
          message.messageId,
          () => transmit(isResend: true),
          minHops: minHopsSettings.channelMinHops,
          maxResends: minHopsSettings.channelMinHopsRetries,
        ),
      );
    }
  });

  /// How long to listen for a channel message to come back through the mesh
  /// before resending it: the "wait before resending" setting under the hop
  /// count, read anew at every wait so a change reaches a running loop.
  Duration get _channelHopCheckDelay => Duration(
    seconds: _appSettingsService?.settings.channelMinHopsDelaySeconds ?? 30,
  );

  DateTime Function() _channelResendNow = DateTime.now;

  /// Повторяет до достижения хопов либо nearby-порога; исчерпание — warning,
  /// поскольку отсутствие достаточного эхо не доказывает потерю сообщения.
  Future<void> _resendUntilMinHops(
    String messageId,
    Future<void> Function() resend, {
    required int minHops,
    required int maxResends,
  }) => _outgoingQueueWork.runRetry(() async {
    _channelHopChecks[messageId] = (resends: 0, maxResends: maxResends);
    _channelResendRevision++;
    notifyListeners();
    var hops = 0;
    // The no-retransmission warning of the mod settings waits for the
    // resends and then counts from the last attempt (Denis, 2026-10-13).
    var lastAttemptAt =
        _findChannelMessageById(messageId)?.sentByRadioAt ?? _channelResendNow();
    try {
      for (var attempt = 0; ; attempt++) {
        // Wait out the delay, but look again at every echo that comes in:
        // the condition may be met long before the delay ends, and the
        // spinner must stop with it. An echo that does not meet it leaves
        // the rest of the delay to run.
        // Counted from the transmission, the first one the radio's.
        final deadline = lastAttemptAt.add(_channelHopCheckDelay);
        ChannelMessage? message;
        var satisfied = false;
        while (true) {
          final remaining = deadline.difference(_channelResendNow());
          if (remaining > Duration.zero) {
            final wakeup = Completer<void>();
            _channelHopWakeups[messageId] = wakeup;
            await Future.any<void>([
              Future<void>.delayed(remaining),
              wakeup.future,
            ]);
            if (identical(_channelHopWakeups[messageId], wakeup)) {
              _channelHopWakeups.remove(messageId);
            }
          }
          message = _findChannelMessageById(messageId);
          if (message == null) return;
          if (message.status == ChannelMessageStatus.failed) return;
          hops = message.pathLength ?? 0;
          // Read live so changing the nearby-repeater controls takes effect.
          final coverageSettings = _appSettingsService?.settings;
          satisfied = channelResendSatisfied(
            message,
            minHops: minHops,
            countDistinctRepeaters:
                coverageSettings?.channelMinHopsCountRepeaters ?? false,
            minRepeaters: coverageSettings?.channelMinHopsRepeaterCount ?? 2,
            selfPublicKey: _selfPublicKey,
          );
          if (satisfied || !_channelResendNow().isBefore(deadline)) break;
        }
        if (satisfied) {
          _channelHopShortfalls.remove(messageId);
          _appDebugLogService?.info(
            hops >= minHops
                ? 'Channel message reached $hops hops after $attempt resends'
                : 'Channel message heard via ${distinctFirstHopRepeaters(message, selfPublicKey: _selfPublicKey).length} '
                      'first-hop repeaters after $attempt resends',
            tag: 'Channel resend',
          );
          return;
        }
        if (attempt >= maxResends || !isConnected) break;
        _appDebugLogService?.info(
          'Heard at $hops of $minHops hops; resending '
          '(${attempt + 1} of $maxResends)',
          tag: 'Channel resend',
        );
        _channelHopChecks[messageId] = (
          resends: attempt + 1,
          maxResends: maxResends,
        );
        _channelResendRevision++;
        notifyListeners();
        try {
          await resend();
          lastAttemptAt = _channelResendNow();
        } catch (e) {
          _appDebugLogService?.warn(
            'Channel resend failed: $e',
            tag: 'Channel resend',
          );
          break;
        }
      }
      _appDebugLogService?.warn(
        'Channel message only heard at $hops of $minHops hops; giving up',
        tag: 'Channel resend',
      );
      // It was sent and may well have travelled further than we can hear, so
      // this is a warning, not a failure.
      _channelHopShortfalls[messageId] = (hops: hops, required: minHops);
    } finally {
      _channelHopChecks.remove(messageId);
      _channelHopWakeups.remove(messageId);
      _channelResendRevision++;
      _scheduleChannelNoRetransmissionWarning(messageId, since: lastAttemptAt);
      notifyListeners();
    }
  });

  /// Moves with every change of the hop checks and shortfalls, for the
  /// transcript's selector: a notification alone does not rebuild it.
  int _channelResendRevision = 0;
  int get channelResendRevision => _channelResendRevision;

  final Map<String, ({int resends, int maxResends})> _channelHopChecks = {};
  final Map<String, Completer<void>> _channelHopWakeups = {};

  /// An echo of [messageId] arrived: the resend loop looks at its condition
  /// again instead of waiting out the rest of its delay.
  void _wakeChannelHopCheck(String messageId) {
    final wakeup = _channelHopWakeups[messageId];
    if (wakeup != null && !wakeup.isCompleted) wakeup.complete();
  }
  final Map<String, ({int hops, int required})> _channelHopShortfalls = {};

  /// Set when resending gave up before hearing the message through enough
  /// repeaters. Kept for this session only.
  ({int hops, int required})? channelHopShortfall(String messageId) =>
      _channelHopShortfalls[messageId];

  bool _retainChannelShortfallAfterEcho(ChannelMessage message) {
    final previous = _channelHopShortfalls[message.messageId];
    if (previous == null) return false;
    final settings = _appSettingsService?.settings;
    final next = channelResendShortfallAfterEcho(
      message,
      previous,
      countDistinctRepeaters: settings?.channelMinHopsCountRepeaters ?? false,
      minRepeaters: settings?.channelMinHopsRepeaterCount ?? 2,
      selfPublicKey: _selfPublicKey,
    );
    if (next != previous) {
      if (next == null) {
        _channelHopShortfalls.remove(message.messageId);
      } else {
        _channelHopShortfalls[message.messageId] = next;
      }
      _channelResendRevision++;
    }
    return next != null;
  }

  /// Resend progress for a channel message still waiting to travel far
  /// enough, or null when it is not being watched.
  ({int resends, int maxResends})? channelResendProgress(String messageId) =>
      _channelHopChecks[messageId];

  ChannelMessage? _findChannelMessageById(String messageId) {
    for (final messages in _channelMessages.values) {
      for (int i = messages.length - 1; i >= 0; i--) {
        if (messages[i].messageId == messageId) return messages[i];
      }
    }
    return null;
  }

  bool get _shouldDeferChannelSendForSync =>
      _isLoadingContacts || _isSyncingChannels || _channelSyncInFlight;

  void _deferChannelMessageSend(
    Channel channel,
    String messageId,
    String text, {
    required String senderName,
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
        senderName: senderName,
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

  Future<void> _flushDeferredChannelMessageSends() =>
      _outgoingQueueWork.runSend(() async {
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
  });

  Future<void> _sendDeferredChannelMessage(
    _DeferredChannelMessageSend pending,
  ) => _outgoingQueueWork.runSend(() async {
    final outgoingRegion =
        pending.region ??
        await _outgoingChannelRegionForMessage(pending.channel.index);
    if (!isConnected) return;
    _updatePendingChannelMessageRegion(
      pending.messageId,
      _displayPacketRegion(outgoingRegion),
    );

    // Reuse the exact binary payload that was used to create the local
    // outgoing message. In particular, do not refresh the MCOimg v3 nonce a
    // second time while a send is deferred for channel/contact sync.
    final binaryOutbound = pending.binaryOutbound;
    final isMcoImageBinary =
        binaryOutbound?.kind == ChannelBinaryDataKind.mcoImageV3 ||
        binaryOutbound?.kind == ChannelBinaryDataKind.mcoImageV4;
    final outboundText = isMcoImageBinary
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
        _markChannelMessageSentByRadio(pending.messageId, sentByRadioAt);
        _updateChannelMessagePacketTimestamp(
          pending.channel.index,
          pending.messageId,
          sentTimestampSeconds,
          packetHash: binaryFrame == null
              ? _computeContentHash(
                  pending.channel.index,
                  sentTimestampSeconds,
                  '${pending.senderName}: ${pending.text}',
                )
              : null,
        );
        if (shouldBypassAckAndRetry) {
          _markPendingChannelMessageSentById(pending.messageId);
          await sendFrame(
            binaryFrame ??
                _channelTextFrame(
                  pending.channel,
                  outboundText,
                  senderName: pending.senderName,
                  region: outgoingRegion,
                  timestampSeconds: sentTimestampSeconds,
                ),
          );
          return;
        }
        if (binaryFrame != null) {
          await _sendFrameAndWaitForCommandAck(
            binaryFrame,
            channelSendQueueId: pending.messageId,
          );
          return;
        }
        await _sendFrameAndWaitForCommandAck(
          _channelTextFrame(
            pending.channel,
            outboundText,
            senderName: pending.senderName,
            region: outgoingRegion,
            timestampSeconds: sentTimestampSeconds,
          ),
          channelSendQueueId: pending.messageId,
        );
      },
      region: pending.region ?? getChannelRegion(pending.channel.index),
      waitForScopeReset: !shouldBypassAckAndRetry,
    );
  });

  void _updatePendingChannelMessageRegion(String messageId, String? region) {
    for (final entry in _channelMessages.entries) {
      final channelMessages = entry.value;
      final index = channelMessages.indexWhere(
        (message) => message.messageId == messageId,
      );
      if (index < 0) continue;

      final message = channelMessages[index];
      if (!message.isOutgoing || message.packetRegion == region) return;

      final updated = message.copyWith(
        packetRegion: region,
        packetRegionInfoAvailable: true,
      );
      channelMessages[index] = updated;
      unawaited(_channelMessageStore.saveChannelMessage(entry.key, updated));
      notifyListeners();
      return;
    }
  }

  /// Minimum companion firmware version code whose CMD_SEND_CHANNEL_DATA (62)
  /// / RESP_CODE_CHANNEL_DATA_RECV (27) layout matches ours (v1.15.0, ver 11).
  static const int _minFirmwareVerCodeForChannelData = 11;

  /// True when the connected device can send/receive GRP_DATA blobs.
  bool get supportsChannelData =>
      isConnected &&
      (_firmwareVerCode ?? 0) >= _minFirmwareVerCodeForChannelData;

  /// Sends one image's chunk [blobs] as GRP_DATA packets on [channelIndex],
  /// strictly sequentially, inside a single scoped-send scope for the whole
  /// image (the flood scope is global, so re-entering it per chunk would let
  /// another channel's send interleave mid-image).
  ///
  /// [onProgress] fires after each chunk is acked, so the UI can show
  /// "sending 2 of 3".
  ///
  /// IMPORTANT: the command ACK only proves the firmware accepted the blob and
  /// queued a packet to the radio. It says nothing about transmission or
  /// delivery — GRP_DATA is unacknowledged flood traffic, there is no
  /// PUSH_CODE_SEND_CONFIRMED for it, and a chunk may still be lost on air.
  /// That is what the XOR parity chunk is for.
  ///
  /// Returns false when the transport is unavailable (disconnected or firmware
  /// too old); throws whatever [_sendFrameAndWaitForCommandAck] throws, i.e.
  /// a [CommandFailedException] whose errCode is 1 (unsupported command),
  /// 2 (bad channel index), 3 (packet pool full, worth retrying) or 6
  /// (illegal arg — blob too long or bad data type), or a TimeoutException
  /// after _commandAckTimeout.
  Future<bool> sendImageChunks(
    List<Uint8List> blobs, {
    required int channelIndex,
    required Duration interChunkDelay,
    void Function(int sent, int total)? onProgress,
  }) => _imageTransferWork.run(() async {
    if (blobs.isEmpty) return false;
    if (!supportsChannelData) return false;
    // `return` inside the scoped callback only exits the callback, so a
    // disconnect mid-send used to fall through to `return true` below and the
    // caller would record a complete outgoing image and tell the user "sent"
    // after transmitting a prefix of the chunks. Track it explicitly.
    var sentAll = true;
    await _runScopedChannelSend(() async {
      for (var i = 0; i < blobs.length; i++) {
        if (!isConnected) {
          sentAll = false;
          return;
        }
        if (i > 0) await Future<void>.delayed(interChunkDelay);
        // Same collision avoidance as every other channel send. On a quiet mesh
        // this returns almost immediately; interChunkDelay is what actually
        // paces the chunks so we do not talk over our own previous packet.
        await _waitForRadioQuiet(lastInboundRxTime: _lastChannelMsgRxTime);
        await _sendFrameAndWaitForCommandAck(
          buildSendChannelDataFrame(channelIndex, dataTypeAeicImage, blobs[i]),
        );
        onProgress?.call(i + 1, blobs.length);
      }
    }, region: _channelSendScope(channelIndex));
    return sentAll;
  });

  Future<void> _runScopedChannelSend(
    Future<void> Function() action, {
    required String region,
    bool waitForScopeReset = true,
  }) => _runChannelCommandLocked(() async {
    // An empty channel region deliberately clears any previous app override,
    // handing scope selection back to the node's default-region setting.
    // This must happen for unscoped channels too: otherwise a stale scope
    // left by another client can leak into the outgoing packet. A channel
    // set to "no region" sets the no-scope flag instead, which overrides
    // the default as well; firmware without the flag gets the clear.
    if (region != kUnscopedRegion || !await _sendFloodUnscopedFrame()) {
      await _sendFrameAndWaitForCommandAck(
        buildSetFloodScopeFrame(region == kUnscopedRegion ? '' : region),
      );
    }
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
  });

  Future<T> _runChannelCommandLocked<T>(Future<T> Function() action) async {
    final prev = _channelScopedSendLock;
    final completer = Completer<void>();
    _channelScopedSendLock = completer.future;
    await prev;

    try {
      return await action();
    } finally {
      completer.complete();
    }
  }

  // Sends [data] and resolves once the device replies to this command. The
  // generic-ack queue pairs every reply with its command (see [_handleOk] and
  // [_handleErrorFrame]), so an OK or ERR produced by another in-flight
  // command cannot complete it. SET_FLOOD_SCOPE and both channel sends reply
  // with RESP_CODE_OK or an ERR, never with RESP_CODE_SENT, which answers a
  // send to a contact only: a direct message, a CLI command, a login or a
  // request. The firmware writes the reply after building the packet, the
  // scope's transport code included, so waiting for it before the scope is
  // reset is enough.
  Future<void> _sendFrameAndWaitForCommandAck(
    Uint8List data, {
    String? channelSendQueueId,
  }) {
    return sendFrame(
      data,
      channelSendQueueId: channelSendQueueId,
      waitForGenericAck: true,
    );
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
  Future<Uint8List?> signWithNode(Uint8List data) =>
      _signWithNode(data, attempts: _signAttempts, timeout: _signAttemptTimeout);

  Future<Uint8List?> signLicenseChallenge(Uint8List data) =>
      _signWithNode(data, attempts: 1, timeout: _signAttemptTimeout);

  Future<Uint8List?> _signWithNode(
    Uint8List data, {
    required int attempts,
    required Duration timeout,
  }) async {
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
      for (var attempt = 1; attempt <= attempts; attempt++) {
        if (!isConnected) return null;
        try {
          return await _runSignAttempt(data, timeout);
        } catch (e) {
          appLogger.warn(
            'Node sign attempt $attempt/$attempts failed: $e',
          );
        }
      }
      return null;
    } finally {
      sessionDone.complete();
    }
  }

  Future<Uint8List> _runSignAttempt(Uint8List data, Duration timeout) async {
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

    final deadline = DateTime.now().add(timeout);

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

  Future<void> resumePendingOutgoingMessages() =>
      _outgoingQueueWork.runSend(() async {
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
            () => unawaited(_commitPendingChannelSend(messageId)),
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
  });

  Future<void> _flushRetriableChannelMessageSends() =>
      _outgoingQueueWork.runSend(() async {
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
  });

  void scheduleContactMessage(
    Contact contact,
    String rawText, {
    required String inputText,
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
    // Normalised here as well as in sendMessage: a queued message is drawn
    // from this text, and it should read the way it will be transmitted.
    final text = SharedMarkerDeletion.isMarker(rawText)
        ? prepareContactOutboundText(contact, rawText)
        : rawText;
    if (text.isEmpty || delaySeconds < 0 || isOfflineMode) return;
    final resolved = resolvePathSelection(contact);
    // Preview only: the real send re-prepares (and re-signs) at commit time.
    final outboundText = prepareContactOutboundText(
      contact,
      text,
      replyAuthorName: replyToSenderName,
      replyTimestamp: replyToTimestamp,
      replyToText: replyToText,
      replyToMessageId: replyToMessageId,
    );
    final compression = _contactCompressionMetadata(
      contact,
      uncompressedText ?? text,
      outboundText,
    );
    final mcmpV3Applies =
        isContactMcmpEnabled(contact.publicKeyHex) &&
        contactMcmpVersion(contact.publicKeyHex) == 3 &&
        _isMcmpSignableText(text);
    final message = Message.outgoing(
      contact.publicKey,
      _contactReplyBody(contact, text, replyToSenderName),
      rawText: outboundText,
      wasMcmpCompressed: _isMcmpEncodedText(outboundText),
      compressionType: compression?.type,
      compressionSavingsPercent: compression?.savingsPercent,
      compressionOriginalBytes: compression?.originalBytes,
      compressionPayloadBytes: compression?.payloadBytes,
      // Pending previews never show a signature badge; the real send at
      // commit time re-prepares, signs and stamps the actual meta. The format
      // version is already decided, and the compression badge derives it from
      // this timestamp, so a queued v3 message would otherwise read as v2.
      mcmpSignatureStatus: McmpSignatureStatus.none,
      containerTimestamp: mcmpV3Applies
          ? DateTime.now().millisecondsSinceEpoch ~/ 1000
          : null,
      pathLength: resolved.useFlood ? -1 : resolved.hopCount,
      pathBytes: Uint8List.fromList(resolved.pathBytes),
      originalText: originalText,
      translatedLanguageCode: translatedLanguageCode,
      translationModelId: translationModelId,
      replyToMessageId: replyToMessageId,
      replyToSenderName: replyToSenderName,
      replyToText: replyToText,
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
        () => _commitPendingContactSend(message.messageId),
      );
    }
    _pendingContactSends[message.messageId] = pending;
    notifyListeners();
  }

  void scheduleChannelMessage(
    Channel channel,
    String rawText, {
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
    String? region,
  }) {
    // See scheduleContactMessage.
    final text = SharedMarkerDeletion.isMarker(rawText)
        ? prepareChannelOutboundText(channel.index, rawText)
        : rawText;
    if (text.isEmpty || delaySeconds < 0 || isOfflineMode) return;
    final senderName = channelSendName(channel.index);
    // The preview follows the "plain when smaller" choice the commit will
    // make; the queued text stays as typed and the commit recomputes it.
    final mcmpV3Applies =
        mcoImageV3 == null &&
        isChannelMcmpEnabled(channel.index) &&
        channelMcmpVersion(channel.index) == 3 &&
        _isMcmpSignableText(text);
    var mcotxtApplies =
        mcoImageV3 == null &&
        isChannelMCOtxtEnabled(channel.index) &&
        _isMcmpSignableText(text);
    final plainFallback = mcotxtApplies
        ? _channelPlainIfSmallerThanMCOtxt(
            channel,
            text,
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            replyToSenderName: replyToSenderName,
            replyToText: replyToText,
            replyToMessageId: replyToMessageId,
            replyToTimestamp: replyToTimestamp,
          )
        : null;
    if (plainFallback != null) mcotxtApplies = false;
    final containerText = (mcmpV3Applies || mcotxtApplies)
        ? _containerReplyBody(text, replyToSenderName)
        : text;
    var outboundText =
        plainFallback ?? prepareChannelOutboundText(channel.index, text);
    final binaryOutbound = mcoImageV3 != null
        ? ChannelBinaryDataHelper.tryEncodeMcoImageV3Outbound(
            image: mcoImageV3,
            senderName: senderName,
          )
        : ChannelBinaryDataHelper.tryEncodeOutbound(
            text: containerText,
            senderName: senderName,
            mcmpEnabled: isChannelMcmpEnabled(channel.index),
            mcotxtEnabled: mcotxtApplies,
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
    if (binaryOutbound == null && mcotxtApplies) {
      outboundText = MCOtxtAppCodec.encodeTextTransport(
        text: containerText,
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        replyAuthorName: replyToSenderName,
        replyTimestamp: replyToTimestamp,
      );
    }
    final usesBinaryTransport = binaryFrame != null;
    final usesBinaryCompressedText =
        binaryOutbound?.kind == ChannelBinaryDataKind.mcmp ||
        binaryOutbound?.kind == ChannelBinaryDataKind.mcotxt;
    final messageText =
        binaryOutbound?.canonicalText ??
        ((mcmpV3Applies || mcotxtApplies) ? containerText : text);
    final compression = _channelCompressionMetadata(
      channel.index,
      uncompressedText ?? text,
      outboundText,
      binaryPayloadBytes: usesBinaryCompressedText
          ? binaryOutbound?.payload.length
          : null,
      senderName: senderName,
    );
    final packetHash = binaryOutbound == null
        ? null
        : _computeChannelDataHash(
            channel.index,
            binaryOutbound.dataType,
            binaryOutbound.payload,
          );
    final packetRegion = _displayPacketRegion(
      region ?? _outgoingChannelRegion(channel.index),
    );
    final baseMessage = ChannelMessage.outgoing(
      messageText,
      senderName,
      channel.index,
      rawText: usesBinaryTransport ? null : outboundText,
      wasMcmpCompressed:
          _isMcmpEncodedText(outboundText) || usesBinaryCompressedText,
      compressionType: compression?.type,
      compressionSavingsPercent: compression?.savingsPercent,
      compressionOriginalBytes: compression?.originalBytes,
      compressionPayloadBytes: compression?.payloadBytes,
      // Pending previews never show a signature badge; the real send at
      // commit time re-encodes, signs and stamps the actual meta. The format
      // version is known up front, though, and the compression badge reads it
      // off this timestamp — without it a queued v3 message would sit in the
      // composer advertising itself as v2.
      mcmpSignatureStatus: McmpSignatureStatus.none,
      containerTimestamp: mcmpV3Applies || mcotxtApplies
          ? DateTime.now().millisecondsSinceEpoch ~/ 1000
          : null,
      wasBinaryTransport: usesBinaryTransport,
      binaryPacketBytes: binaryOutbound?.payload.length,
      rawPayload: binaryOutbound?.payload,
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
          binaryOutbound?.kind == ChannelBinaryDataKind.mcoImageV3 ||
              binaryOutbound?.kind == ChannelBinaryDataKind.mcoImageV4
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
      region: region,
      delaySeconds: delaySeconds,
      sendAt: DateTime.now().add(Duration(seconds: delaySeconds)),
    );
    if (delaySeconds > 0) {
      pending.timer = Timer(
        Duration(seconds: delaySeconds),
        () => unawaited(_commitPendingChannelSend(message.messageId)),
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

  /// The message behind each ACK hash a stopped send was waiting for, with
  /// the attempts sent under that hash and their routes, newest first, so a
  /// confirmation that arrives after all still marks it delivered and
  /// records the route.
  final Map<String, _StoppedSend> _stoppedSendAcks = {};

  /// A bare acknowledgement the radio heard, kept for one frame: the node
  /// logs a packet before it processes it, so the PUSH_CODE_SEND_CONFIRMED
  /// for this acknowledgement is the next frame, and the packet's fifth
  /// byte, the attempt number the recipient copied from our packet, tells
  /// apart the attempts that share a hash
  /// (`MessageRetryService.acknowledgedAttemptIndex`). An acknowledgement
  /// inside a path return is encrypted and never gets here, but a flood
  /// needs no attempt: its route is the one returned.
  ({int ackHash, int? attemptByte, int atFrame})? _lastHeardAck;

  /// Counts the node's frames, so that a PUSH_CODE_PATH_UPDATED can be told
  /// to have come in the frame right before a PUSH_CODE_SEND_CONFIRMED.
  int _companionFrameSequence = 0;

  /// The route the node last took from a recipient's answer: whose, in
  /// which frame it was announced, and the contact as read back from the
  /// node afterwards (see [_recordDeliveryRoute]).
  ({String contactKeyHex, int atFrame, Future<Contact?> contact})?
  _lastReturnedRoute;

  /// Whether the retry service is still working on [messageId]: attempts
  /// ahead, or an acknowledgement awaited.
  bool isSendInProgress(String messageId) =>
      _retryService?.isTracking(messageId) ?? false;

  /// Stops the attempts of an outgoing direct or room message and the wait
  /// for its acknowledgement, on the user's word: the message was most
  /// likely read long ago and only the ACK is missing. The retry service
  /// drops it, which frees the contact's queue and the in-flight slot for
  /// other sends; the message keeps what its attempts earned, sent once the
  /// node had taken it, failed when nothing had gone out; the node's flood
  /// scope is cleared under the command lock, after any window an attempt
  /// still holds, in case one was cut short; and an acknowledgement that
  /// arrives after all still marks the message delivered.
  Future<void> stopSending(Contact contact, Message message) async {
    final retryService = _retryService;
    if (retryService != null) {
      for (final expected in retryService.expectedAcksFor(message.messageId)) {
        _stoppedSendAcks
            .putIfAbsent(
              ackHashToHex(expected.ackHash),
              () => (
                contactKeyHex: contact.publicKeyHex,
                messageId: message.messageId,
                attempts: [],
              ),
            )
            .attempts
            .add((attempt: expected.attempt, selection: expected.selection));
      }
      while (_stoppedSendAcks.length > 64) {
        _stoppedSendAcks.remove(_stoppedSendAcks.keys.first);
      }
      retryService.untrack(message.messageId);
    }
    _updateStoredContactMessage(contact.publicKeyHex, message.messageId, (
      current,
    ) {
      if (current.status == MessageStatus.delivered) return current;
      final wentOut = current.sentAt != null || current.sentByRadioAt != null;
      return current.copyWith(
        status: wentOut ? MessageStatus.sent : MessageStatus.failed,
      );
    });
    appLogger.info(
      'Sending to ${contact.name} stopped by hand',
      tag: 'Connector',
    );
    if (!isConnected || getContactRegion(contact.publicKeyHex).isEmpty) return;
    try {
      await _runChannelCommandLocked(
        () => _sendFrameAndWaitForCommandAck(buildSetFloodScopeFrame('')),
      );
    } catch (error) {
      appLogger.warn(
        'Flood scope reset after a stopped send failed: $error',
        tag: 'Connector',
      );
    }
  }

  String? cancelPendingChannelSend(String messageId) {
    _retriableChannelMessageSends.remove(messageId);
    final pending = _pendingChannelSends.remove(messageId);
    if (pending == null) return null;
    pending.timer?.cancel();
    notifyListeners();
    return pending.inputText;
  }

  Future<void> _commitPendingContactSend(String messageId) =>
      _outgoingQueueWork.runSend(() async {
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
        replyToMessageId: pending.replyToMessageId,
        replyToSenderName: pending.replyToSenderName,
        replyToText: pending.replyToText,
        replyToTimestamp: pending.replyToTimestamp,
      );
    } catch (error) {
      appLogger.warn(
        'Deferred contact send failed before retry tracking: $error',
        tag: 'Connector',
      );
    }
  });

  Future<void> _commitPendingChannelSend(String messageId) =>
      _outgoingQueueWork.runSend(() async {
    final pending = _pendingChannelSends[messageId];
    if (pending == null) return;
    if (!_committingPendingChannelSends.add(messageId)) return;
    try {
      if (!isSessionReady) return;
      pending.timer?.cancel();
      final liveChannelIndex = _channels.indexWhere(
        (channel) => channel.index == pending.channel.index,
      );
      if (liveChannelIndex < 0) {
        _pendingChannelSends.remove(messageId);
        await _addChannelMessage(
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
          region: pending.region,
        );
        if (_pendingChannelSends.containsKey(messageId) && isSessionReady) {
          await _failPendingChannelSend(pending);
        }
      } catch (error, stackTrace) {
        appLogger.warn(
          'Deferred channel send failed: $error\n$stackTrace',
          tag: 'Connector',
        );
        if (_pendingChannelSends.containsKey(messageId)) {
          if (isSessionReady) {
            await _failPendingChannelSend(pending);
          }
        } else {
          _markPendingChannelMessageFailedById(messageId);
        }
      }
    } finally {
      _committingPendingChannelSends.remove(messageId);
    }
  });

  Future<void> _failPendingChannelSend(_PendingChannelSend pending) async {
    final removed = _pendingChannelSends.remove(pending.message.messageId);
    if (removed == null) return;
    removed.timer?.cancel();
    await _addChannelMessage(
      pending.channel.index,
      pending.message.copyWith(status: ChannelMessageStatus.failed),
      awaitPersistence: false,
    );
    notifyListeners();
  }

  void _markChannelMessageSentByRadio(
    String messageId,
    DateTime sentByRadioAt, {
    bool deferNoRetransmissionWarning = false,
  }) {
    for (final entry in _channelMessages.entries) {
      final channelMessages = entry.value;
      final index = channelMessages.indexWhere(
        (message) => message.messageId == messageId,
      );
      if (index < 0) continue;

      final message = channelMessages[index];
      if (!message.isOutgoing) return;

      final updated = ChannelMessageTimelineHelper.markFirstRadioTransmission(
        message,
        sentByRadioAt,
      );
      channelMessages[index] = updated;
      channelMessages.sort(_compareChannelMessages);
      if (!deferNoRetransmissionWarning) {
        _scheduleChannelNoRetransmissionWarning(messageId);
      }
      unawaited(_channelMessageStore.saveChannelMessage(entry.key, updated));
      notifyListeners();
      return;
    }
  }

  /// Counts a repeated transmission of an outgoing message (the
  /// resend-until-N-hops setting) on the stored message, so the count
  /// survives the session: the bubble shows it beside the repeats, the path
  /// screen as "send attempts".
  void _incrementChannelResendCount(String messageId) {
    for (final entry in _channelMessages.entries) {
      final channelMessages = entry.value;
      final index = channelMessages.indexWhere(
        (message) => message.messageId == messageId,
      );
      if (index < 0) continue;
      final message = channelMessages[index];
      if (!message.isOutgoing) return;
      final updated = message.copyWith(resendCount: message.resendCount + 1);
      channelMessages[index] = updated;
      unawaited(_channelMessageStore.saveChannelMessage(entry.key, updated));
      notifyListeners();
      return;
    }
  }

  /// Aligns an outgoing message's packet timestamp to the value that was
  /// actually written into the transmitted frame, so replies to our own
  /// message resolve by exact-timestamp matching. The visible bubble time uses
  /// receivedAt and is unaffected. An MCOtxt text packet carries no timestamp
  /// of its own and its receivers give the container the packet's, so our
  /// copy's container timestamp moves with it: that is the value a reply to
  /// the message anchors on.
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
    final updated = message.copyWith(
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampSeconds * 1000),
      containerTimestamp:
          MCOtxtAppCodec.inheritsPacketTimestamp(message.rawText)
          ? timestampSeconds
          : message.containerTimestamp,
      packetHash: packetHash,
    );
    channelMessages[index] = updated;
    _recordOwnChannelPacket(channelIndex, updated, timestampSeconds);
    unawaited(_channelMessageStore.saveChannelMessage(channelIndex, updated));
    notifyListeners();
  }

  /// [since] is the last transmission the warning counts from, when the
  /// resend-until-N-hops loop held it back; a period already over marks the
  /// message at once.
  void _scheduleChannelNoRetransmissionWarning(
    String messageId, {
    DateTime? since,
  }) {
    _cancelChannelNoRetransmissionWarning(messageId);
    final seconds =
        _appSettingsService?.settings.noRetransmissionWarningSeconds ?? 0;
    if (seconds <= 0) return;
    final elapsed = since == null
        ? Duration.zero
        : _channelResendNow().difference(since);
    final remaining = Duration(seconds: seconds) - elapsed;
    if (remaining <= Duration.zero) {
      _markChannelMessageNoRetransmission(messageId, seconds);
      return;
    }

    _channelNoRetransmissionTimers[messageId] = Timer(
      remaining,
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
      if (!channelNeedsRetransmissionWarning(
        message,
        hasCoverageShortfall: _channelHopShortfalls.containsKey(messageId),
      )) {
        return;
      }

      final updated = message.copyWith(noRetransmissionWarningSeconds: seconds);
      channelMessages[index] = updated;
      unawaited(_channelMessageStore.saveChannelMessage(entry.key, updated));
      notifyListeners();
      return;
    }
  }

  /// [keepMessages] leaves the conversation in the database, so that the
  /// history comes back if the contact is added again.
  Future<void> removeContact(
    Contact contact, {
    bool waitForAck = false,
    bool keepMessages = false,
  }) async {
    if (!isConnected) {
      if (waitForAck) {
        throw Exception('Not connected to a MeshCore device');
      }
      return;
    }

    try {
      await sendFrame(
        buildRemoveContactFrame(contact.publicKey),
        waitForGenericAck: waitForAck,
      );
    } on CommandFailedException catch (error) {
      // The node does not hold the contact, which is what removing it is
      // for, so the removal is finished here. A contact only the app listed
      // could otherwise never be deleted in a batch.
      if (error.errCode != errCodeNotFound) rethrow;
    }
    _contactsStorageFull = false;

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
    if (!keepMessages) {
      // The history under every key linked to this one goes with it, as the
      // chat showed it. The link itself stays while another node still
      // holds one of the keys.
      await _messageStore.clearMessages(contact.publicKeyHex);
      await _forgetContactIdentityUnlessHeldElsewhere(contact.publicKeyHex);
    }
    notifyListeners();
  }

  /// The histories a chat with [contact] may take over: chat contacts of the
  /// same name under another key that have one, on this node's list and,
  /// with the shared contact history on, on the other nodes' cached lists.
  /// Only the user decides, through [linkContactHistory]: a name proves
  /// nothing.
  Future<List<ContactHistoryCandidate>> contactHistoryCandidates(
    Contact contact,
  ) async {
    final linked = ContactIdentities.instance
        .keysOf(contact.publicKeyHex)
        .toSet();
    final result = ContactHistoryCandidates.sameNameWithHistory(
      contact,
      _contacts,
      excludedKeys: linked,
    );
    if (!_sharedContactsEnabled) return result;
    for (final scope in _otherNodeScopes) {
      final contacts = await (ContactStore()..setPublicKeyHex = scope)
          .loadContacts(allowLegacyMigration: false);
      for (final candidate in ContactHistoryCandidates.sameNameWithHistory(
        contact,
        contacts,
        nodeScope: scope,
        excludedKeys: linked,
      )) {
        if (result.any((c) => c.publicKeyHex == candidate.publicKeyHex)) {
          continue;
        }
        result.add(candidate);
      }
    }
    return result;
  }

  /// Attaches the history under [otherKeyHex] to [contact]: the two keys
  /// become one contact in [ContactIdentities], the contact takes the
  /// settings and the region of the other key where it has none, and its
  /// chat is read again over both keys.
  Future<void> linkContactHistory(Contact contact, String otherKeyHex) async {
    final key = contact.publicKeyHex;
    if (!await ContactIdentities.instance.link(key, otherKeyHex)) return;
    await _contactSettingsStore.copySettings(from: otherKeyHex, to: key);
    await _contactRegionStore.copyRegion(from: otherKeyHex, to: key);
    for (final cache in <Map<String, Object?>>[
      _contactMcmpEnabled,
      _contactMcmpVersion,
      _contactMcmpUseSign,
      _contactMCOtxtEnabled,
      _contactMCOtxtPlainWhenSmaller,
      _contactSmazEnabled,
      _contactCyr2LatEnabled,
      _contactUrlImagesEnabled,
      _contactCyr2LatProfileId,
      _contactSendingDelayEnabled,
      _contactQuickAnswerIds,
    ]) {
      cache.remove(key);
    }
    await _loadContactRegions(selfPublicKeyHex);
    _conversations.remove(key);
    _loadedConversationKeys.remove(key);
    _conversationLoadFutures.remove(key);
    _sharedContactSecondaryMessages.remove(key);
    _contactMessagePreviews.remove(key);
    await _loadMessagesForContact(key);
    await _refreshContactMessageSummaries();
    notifyListeners();
  }

  /// A deleted contact's group goes with its history, unless another node's
  /// list still holds one of its keys: that node reads the others through it.
  Future<void> _forgetContactIdentityUnlessHeldElsewhere(
    String contactKeyHex,
  ) async {
    final keys = ContactIdentities.instance.keysOf(contactKeyHex).toSet();
    if (keys.length < 2) return;
    for (final scope in _otherNodeScopes) {
      final contacts = await (ContactStore()..setPublicKeyHex = scope)
          .loadContacts(allowLegacyMigration: false);
      if (contacts.any((c) => keys.contains(c.publicKeyHex.toLowerCase()))) {
        return;
      }
    }
    await ContactIdentities.instance.forget(contactKeyHex);
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

  /// Deletes [contact] from wherever it is kept: from the node when the node
  /// holds it, otherwise from the app's discovered list, the only place a
  /// node the app has merely heard takes up.
  Future<void> deleteContact(
    Contact contact, {
    bool waitForAck = false,
    bool keepMessages = false,
  }) {
    if (_contacts.byKey(contact.publicKeyHex) != null) {
      return removeContact(
        contact,
        waitForAck: waitForAck,
        keepMessages: keepMessages,
      );
    }
    return removeDiscoveredContact(contact);
  }

  Future<bool> importDiscoveredContact(Contact contact) async {
    if (!isConnected) return false;

    // Manual saves must bypass the firmware's auto-add discovery policy.
    // CMD_IMPORT_CONTACT replays an advert and may remain discovery-only.
    final encodedPathLen = _encodePathLenForWidth(
      contact.pathLength,
      contact.path,
      contact.pathHashWidth,
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
        lastAdvert: contact.lastSeen,
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
        pathHashWidth: contact.pathHashWidth,
        latitude: contact.latitude,
        longitude: contact.longitude,
        lastSeen: contact.lastSeen,
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
              : (_encodePathLenForWidth(
                      existing.pathLength,
                      existing.path,
                      existing.pathHashWidth,
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
        lastAdvert: existing?.lastSeen,
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
        pathHashWidth: existing?.pathHashWidth ?? 1,
        latitude: existing?.latitude,
        longitude: existing?.longitude,
        // The advert time the node now holds, which the next path update
        // sends back; the phone's clock there would break its replay guard.
        lastSeen: existing?.lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0),
        lastModified: existing?.lastModified,
        flags: flags,
      ),
    );
    notifyListeners();
  }

  Future<void> clearContactPath(
    Contact contact, {
    bool waitForAck = false,
  }) async {
    // Serialize path operations to prevent interleaved async calls.
    final prev = _pathOpLock;
    final completer = Completer<void>();
    _pathOpLock = completer.future;
    await prev;
    try {
      if (!isConnected) return;

      // The only path reset the app sends on its own. Logged because the node
      // changes routes by itself too and announces it with
      // PUSH_CODE_PATH_UPDATED; without a line on each side, a path that
      // vanished gives no clue which of the two dropped it.
      appLogger.info(
        'Clearing device path for ${contact.name}: '
        'devicePath=${contact.pathLength}, override=${contact.pathOverride}',
        tag: 'Connector',
      );
      await sendFrame(
        buildResetPathFrame(contact.publicKey),
        waitForGenericAck: waitForAck,
      );
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

  Future<void> resumeQueuedMessageSyncAfterForeground() async {
    if (!PlatformInfo.isIOS || !isConnected || _resumeQueueSyncScheduled) {
      return;
    }
    _resumeQueueSyncScheduled = true;
    try {
      // A command sent just before suspension may still own the next queue
      // item. Let its response or timeout settle before issuing another
      // destructive read after foregrounding.
      if (_isSyncingQueuedMessages || _queuedMessageSyncInFlight) {
        _appDebugLogService?.info(
          'Foreground queue recovery is waiting for the active request',
          tag: 'QueueSync',
        );
        await Future<void>.delayed(
          const Duration(milliseconds: _queueSyncTimeoutMs + 250),
        );
      }
      if (isConnected &&
          !_isSyncingQueuedMessages &&
          !_queuedMessageSyncInFlight) {
        _appDebugLogService?.info(
          'Foreground queue recovery is requesting remaining messages',
          tag: 'QueueSync',
        );
        await syncQueuedMessages();
      }
    } finally {
      _resumeQueueSyncScheduled = false;
    }
  }

  Future<void> _requestNextQueuedMessage() async {
    if (!isConnected) {
      _isSyncingQueuedMessages = false;
      _isInitialBacklogDrain = false;
      _discardInitialSyncNotificationSummary();
      _queuedMessageSyncInFlight = false;
      _queuedMessageRequestWork.finishCurrent();
      return;
    }
    if (_queuedMessageSyncInFlight) return;
    _queuedMessageSyncInFlight = true;
    final requestWork = _queuedMessageRequestWork.begin();

    // Cancel any existing timeout
    _queueSyncTimeout?.cancel();

    // Set up timeout for this request
    _queueSyncTimeout = Timer(Duration(milliseconds: _queueSyncTimeoutMs), () {
      _queuedMessageRequestWork.finish(requestWork);
      _handleQueueSyncTimeout();
    });

    debugPrint('[QueueSync] Requesting next message');
    _appDebugLogService?.info(
      'Requesting next queued message',
      tag: 'QueueSync',
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
      _queuedMessageRequestWork.finishCurrent();
      notifyListeners();
      _continueAfterQueuedMessageSync();
      _maybeFlushInitialSyncNotificationSummary();
    }
  }

  void _handleQueueSyncTimeout() {
    _queuedMessageRequestWork.finishCurrent();
    debugPrint('[QueueSync] Timeout waiting for message; stopping sync');
    _queueSyncTimeout = null;
    _appDebugLogService?.warn(
      'Timed out waiting for queued message; not retrying because firmware '
      'may already have removed it from its queue',
      tag: 'QueueSync',
    );
    _queuedMessageSyncInFlight = false;
    _isSyncingQueuedMessages = false;
    _isInitialBacklogDrain = false;
    _southQueuedFragmentAckTracker.clearAwaitingSyncResponse();
    notifyListeners();
    _continueAfterQueuedMessageSync();
    _maybeFlushInitialSyncNotificationSummary();
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

    _channelSyncWork.begin();
    _isLoadingChannels = true;
    _isSyncingChannels = true;
    _hasLoadedChannels = false;
    _previousChannelsCache = List<Channel>.from(_channels);
    _channels.clear();
    _unconfirmedChannelSlots.clear();
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
        // No cached copy: the slot's contents are unknown, not empty.
        _unconfirmedChannelSlots.add(channelIndex);
      }

      // Move to next channel
      _nextChannelIndexToRequest++;
      _channelSyncRetries = 0;
      _channelSyncInFlight = false;
      notifyListeners();
      unawaited(_requestNextChannel());
    }
  }

  /// The firmware answers GET_CHANNEL with ERR_NOT_FOUND only for an index
  /// past its MAX_GROUP_CHANNELS, so every later index is out of range too:
  /// finish the sync now instead of retrying each one until it times out.
  void _handleChannelSyncNotFound() {
    debugPrint(
      '[ChannelSync] Channel $_nextChannelIndexToRequest not found; '
      'device has $_nextChannelIndexToRequest channel slots',
    );
    _channelSyncTimeout?.cancel();
    _channelSyncInFlight = false;
    _totalChannelsToRequest = _nextChannelIndexToRequest;
    unawaited(_completeChannelSync());
  }

  /// The scopes of the other nodes this app keeps history for.
  Set<String> get _otherNodeScopes {
    final scopes = SharedMessageHistoryHelper.knownScopes();
    scopes.remove(SharedMessageHistoryHelper.scopeFor(selfPublicKeyHex));
    return scopes;
  }

  /// Links the channels another app renamed or rekeyed while this one was
  /// away: the node's list before this sync against the list it read,
  /// compared as sets of key and name (see [ChannelIdentityReconciler]), so
  /// a channel moved to another slot is nothing. A slot whose channel gained
  /// names is read again, since its settings and history were loaded under
  /// its own name alone, and its shared copy is fetched anew.
  Future<void> _reconcileChannelIdentities() async {
    // The first sync of a session has no list before it in memory; the one
    // the last session saved stands in, so an edit made elsewhere while the
    // app was away is seen as well.
    final links = ChannelIdentityReconciler.diff(
      _previousChannelsCache.isNotEmpty ? _previousChannelsCache : _cachedChannels,
      _channels,
    );
    if (links.isEmpty) return;
    final changed = <ChannelIdentity>{};
    for (final link in links) {
      if (await ChannelIdentities.instance.link(link.from, link.to)) {
        changed.add(link.to);
      }
    }
    if (changed.isEmpty) return;
    for (final channel in List<Channel>.of(_channels)) {
      final identity = ChannelIdentity.of(channel);
      if (identity == null || !changed.contains(identity)) continue;
      await _loadChannelSettingsForIndex(channel.index);
      _channelMessages.remove(channel.index);
      await _loadChannelMessages(channel.index, notify: false);
      _sharedChannelSecondaryMessages.remove(channel.index);
      _sharedChannelSecondaryIdentityKeys.remove(channel.index);
    }
  }

  /// What a manual deletion does beyond this node's scope. With [allNodes]
  /// the channel's history, settings and region go under every name of its
  /// group in every other node's scope, and the group with them. Otherwise
  /// the group stays while another node still holds a channel of it, since
  /// that node reads its older names through it.
  Future<void> _clearChannelIdentityData(
    ChannelIdentity identity, {
    required bool allNodes,
  }) async {
    final names = ChannelIdentities.instance.namesOf(identity);
    if (allNodes) {
      for (final scope in _otherNodeScopes) {
        await (ChannelMessageStore()..setPublicKeyHex = scope)
            .clearMessagesForNames(names);
        await (ChannelSettingsStore()..setPublicKeyHex = scope)
            .clearSettingsForNames(names);
        await (ChannelRegionStore()..setPublicKeyHex = scope)
            .clearRegionsForNames(names);
      }
      await ChannelIdentities.instance.forget(identity);
      return;
    }
    for (final scope in _otherNodeScopes) {
      final channels = await (ChannelStore()..setPublicKeyHex = scope)
          .loadChannels(allowLegacyMigration: false);
      if (ChannelIdentities.instance.findInGroup(channels, identity) != null) {
        return;
      }
    }
    await ChannelIdentities.instance.forget(identity);
  }

  Future<void> _clearChannelMessagesOnOtherNodes(List<String> names) async {
    for (final scope in _otherNodeScopes) {
      await (ChannelMessageStore()..setPublicKeyHex = scope)
          .clearMessagesForNames(names);
    }
  }

  /// The IDs the images of [channel] may carry: those of every key its
  /// identity group has had.
  Set<String> _imageChannelIdsOf(Channel? channel) {
    final identity = channel == null ? null : ChannelIdentity.of(channel);
    if (identity == null) return const {};
    return {
      for (final member in ChannelIdentities.instance.membersOf(identity))
        member.pskId,
    };
  }

  Future<void> _completeChannelSync() =>
      _channelSyncWork.run(_completeChannelSyncCore);

  Future<void> _completeChannelSyncCore() async {
    _channelSyncTimeout?.cancel();

    if (_pendingChannelSyncRestart) {
      await _restartPendingChannelSync();
      return;
    }

    debugPrint(
      '[ChannelSync] Sync complete: received ${_channels.length}/$_totalChannelsToRequest channels',
    );

    await _reconcileChannelIdentities();
    // Images written before they carried a channel ID take the ID of the
    // channel their slot holds now, once; the store is app-wide, so the
    // first node synced claims them.
    await _stampImageChannelIds?.call({
      for (final channel in _channels) channel.index: ?channel.storageId,
    });

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
    final channelWork = _channelSyncWork.current;
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
    _channelSyncWork.finish(channelWork);
  }

  Future<void> _restartPendingChannelSync() =>
      _channelSyncWork.run(_restartPendingChannelSyncCore);

  Future<void> _restartPendingChannelSyncCore() async {
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

    _channelSyncWork.finishCurrent();
    await getChannels(maxChannels: maxChannels, force: true);
  }

  void _startPostChannelInitialQueuedMessageSync() {
    // On iOS, resolve contacts before draining the destructive firmware queue.
    // This avoids keeping the entire direct-message backlog only in RAM while
    // the app has a limited background execution window.
    if (PlatformInfo.isIOS && _pendingInitialContactsSync && isConnected) {
      _pendingInitialContactsSync = false;
      unawaited(getContacts(preserveExisting: true));
      return;
    }
    if (_pendingInitialQueuedMessageSync || _pendingQueueSync) {
      final isInitialDrain = _pendingInitialQueuedMessageSync;
      if (isInitialDrain) {
        _beginInitialSyncNotificationSummary();
      }
      _deferQueuedContactMessagesUntilContacts = _pendingInitialContactsSync;
      // This drain replays the backlog accumulated before we connected.
      _isInitialBacklogDrain = isInitialDrain;
      _lastInitialBacklogChannelReceivedAt = null;
      _pendingInitialQueuedMessageSync = false;
      _pendingQueueSync = false;
      unawaited(syncQueuedMessages(force: true));
    }
  }

  Future<void> setChannel(int index, String name, Uint8List psk) async {
    if (!isConnected) return;

    final previous = _findChannelByIndex(index);
    await sendFrame(buildSetChannelFrame(index, name, psk));
    // An edit that keeps the key or the name is the same channel renamed or
    // rekeyed: its history and settings stay with it through the identity
    // table. The sync that follows reads it under both names.
    final link = ChannelIdentityReconciler.linkFor(
      previous,
      Channel(index: index, name: name, psk: psk),
    );
    if (link != null) {
      await ChannelIdentities.instance.link(link.from, link.to);
    }
    // Refresh channels after setting
    await getChannels(force: true);
  }

  /// Removes the channel from the node and its data from this node's scope,
  /// under every name the channel has had; with [allNodes], from every other
  /// node's scope as well (the choice the deletion dialog offers while the
  /// shared channel history is on). A slot emptied by another app clears
  /// nothing: the history comes back when the channel is added again.
  Future<void> deleteChannel(int index, {bool allNodes = false}) async {
    if (!isConnected) return;

    final channel = _findChannelByIndex(index);
    final identity = channel == null ? null : ChannelIdentity.of(channel);
    // Delete by setting empty name and zero PSK
    await sendFrame(buildSetChannelFrame(index, '', Uint8List(16)));
    // Explicit deletion clears all persisted data for this channel name,
    // the names it had before included.
    await _channelMessageStore.clearChannelMessages(index);
    await _channelSettingsStore.clearChannelSettings(index);
    await _channelRegionStore.clearRegion(index);
    await _deleteImagesForChannel?.call(index, _imageChannelIdsOf(channel));
    if (identity != null) {
      await _clearChannelIdentityData(identity, allNodes: allNodes);
    }
    // Clear in-memory messages for this channel
    _channelMessages.remove(index);
    _processedChannelReactions.remove(index);
    // Refresh channels after deleting
    await getChannels(force: true);
  }

  void _handleFrame(List<int> data) {
    if (data.isEmpty) return;
    _lastRxBeforeFrame = _lastRxTime;
    _lastRxTime = DateTime.now();
    if (_activeTransport == MeshCoreTransportType.bluetooth &&
        PlatformInfo.isIOS) {
      _lastBleRxAt = _lastRxTime;
    }
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

  void _handleCompanionFrame(
    Uint8List frame, {
    bool notifyExtensions = true,
    String? localSourceLabel,
  }) {
    if (frame.isEmpty) return;
    _companionFrameSequence++;
    if (notifyExtensions) {
      _settingsSectionsService?.mcoX2(frame);
    }
    _receivedFramesController.add(frame);
    _bleDebugLogService?.logFrame(frame, outgoing: false);
    // A frame another client wrote through us answers none of our commands.
    final completedPendingReply =
        localSourceLabel == null &&
        _pendingGenericAckQueue.completeReply(frame);

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
        _contactSyncWork.ensureStarted();
        _armContactSyncTimeout();
        if (!_preserveContactsOnRefresh &&
            _contactMessageSummarySnapshot.isEmpty) {
          _captureContactMessageSummarySnapshot();
        }
        if (!_preserveContactsOnRefresh) {
          _contacts.clear();
        }
        // A sync filtered by lastmod lists only what changed, so only a full
        // one can tell which listed contacts the node no longer holds.
        _contactsUnconfirmedBySync = _contactSyncUsesSinceFilter
            ? null
            : {for (final contact in _contacts) contact.publicKeyHex};
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
        // A known contact re-advertised. The node has already refreshed its
        // record — coordinates included — but this push carries only the
        // public key, so the new values have to be read back explicitly or the
        // map keeps showing where the node used to be. The request never
        // leaves the device: the node answers it out of its own contact table.
        if (frame.length >= 1 + pubKeySize) {
          unawaited(
            getContactByKey(
              frame.sublist(1, 1 + pubKeySize),
            ).catchError(_logTimerSendError),
          );
        }
        break;
      case pushCodeNewAdvert:
        debugPrint('Got New CONTACT');
        _handleNewAdvert(frame);
        break;
      case respCodeContact:
        // The answer to a GET_CONTACT_BY_KEY is not part of a running sync.
        if (_isLoadingContacts && !completedPendingReply) {
          _armContactSyncTimeout();
        }
        _handleContact(frame, countTowardSync: !completedPendingReply);
        if (!_isLoadingContacts) {
          unawaited(_replayUnknownSenderMessages(onlyResolvable: true));
        }
        break;
      case pushCodeContactDeleted:
        _handleContactDeleted(frame);
        break;
      case pushCodeContactsFull:
        _appDebugLogService?.warn(
          'Firmware contact storage is full; new contact not stored',
          tag: 'Connector',
        );
        _contactsStorageFull = true;
        _contactsFullController.add(null);
        notifyListeners();
        break;
      case respCodeAllowedRepeatFreq:
        _allowedRepeatFreqRanges = List.unmodifiable(
          parseAllowedRepeatFreqFrame(frame),
        );
        notifyListeners();
        break;
      case respCodeEndOfContacts:
        debugPrint('Got END_OF_CONTACTS');
        final contactWork = _contactSyncWork.current;
        _contactSyncTimeout?.cancel();
        _contactSyncTimeout = null;
        _dropContactsMissingFromNode();
        _isLoadingContacts = false;
        if (_contactsStorageFull && _contacts.length < _maxContacts) {
          _contactsStorageFull = false; // capacity freed up since the warning
        }
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
        } else {
          _startPostChannelInitialQueuedMessageSync();
        }
        _continueAfterContactSync();
        _contactSyncWork.finish(contactWork);
        break;
      case respCodeContactMsgRecv:
      case respCodeContactMsgRecvV3:
        if (localSourceLabel == null &&
            _shouldDeferQueuedContactMessage(frame)) {
          _deferredQueuedContactMessageFrames.add(Uint8List.fromList(frame));
          _handleQueuedMessageReceived();
        } else {
          unawaited(
            _handleIncomingMessage(frame, localSourceLabel: localSourceLabel),
          );
        }
        break;
      case respCodeChannelMsgRecv:
      case respCodeChannelMsgRecvV3:
        unawaited(
          _handleIncomingChannelMessage(
            frame,
            localSourceLabel: localSourceLabel,
          ),
        );
        break;
      case respCodeChannelDataRecv:
        unawaited(
          _handleIncomingChannelData(
            frame,
            localSourceLabel: localSourceLabel,
          ),
        );
        break;
      case respCodeDefaultFloodScope:
        // Feature-specific callers listen to receivedFrames for this response.
        break;
      case respCodePrivateKey:
      case respCodeDisabled:
        // Answers to CMD_EXPORT_PRIVATE_KEY; _requestDirectEchoKey listens.
        break;
      case respCodeSent:
        _handleMessageSent(frame);
        break;
      case respCodeExportContact:
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
        _retryService?.handleRxLogFrame(frame);
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

    final failedAck = _pendingGenericAckQueue.takeErr(errCode);
    if (failedAck != null &&
        failedAck.commandCode == cmdGetChannel &&
        errCode == _errCodeNotFound &&
        _isSyncingChannels &&
        _channelSyncInFlight) {
      _handleChannelSyncNotFound();
      return;
    }
    if (failedAck == null ||
        (failedAck.commandCode != cmdSendChannelTxtMsg &&
            failedAck.commandCode != cmdSendChannelData &&
            failedAck.commandCode != cmdSendRawPacket) ||
        failedAck.channelSendQueueId == null) {
      return;
    }
    _pendingChannelSentQueue.remove(failedAck.channelSendQueueId);
    _markPendingChannelMessageFailedById(failedAck.channelSendQueueId!);
  }

  void _handlePathUpdated(Uint8List frame) {
    // Frame format: [0]=code, [1-32]=pub_key
    if (frame.length < 33) return;
    final pubKey = Uint8List.fromList(frame.sublist(1, 33));
    final contact = _contacts.cast<Contact?>().firstWhere(
      (c) => c != null && listEquals(c.publicKey, pubKey),
      orElse: () => null,
    );
    if (contact == null) return;
    // The node's own decision, not ours. The new path arrives with the
    // contact refresh below, which logs it as "Refreshing contact ...";
    // this line is what says who started it.
    appLogger.info(
      'Node announced a path change for ${contact.name}, re-reading it '
      '(override=${contact.pathOverride})',
      tag: 'Connector',
    );
    _pathHistoryService?.handlePathUpdated(
      contact,
      initialWeight: _initialRouteWeight,
    );
    // Refresh just this specific contact instead of all contacts.
    // This avoids race conditions with _preserveContactsOnRefresh flag
    // that can occur when using refreshContactsSinceLastmod(). The re-read
    // is kept with the frame's number: an acknowledgement in the very next
    // frame came inside the same path return (`_recordDeliveryRoute`).
    _lastReturnedRoute = (
      contactKeyHex: contact.publicKeyHex,
      atFrame: _companionFrameSequence,
      contact: _creditReturnedRoute(pubKey),
    );
  }

  /// Re-reads the contact whose route the node just took from the
  /// recipient's answer, and credits that route in the history as having
  /// just worked: the answer came back along the route our packet took to
  /// the recipient. The node reports the route (PUSH_CODE_PATH_UPDATED) and
  /// the acknowledgement in its wake before the re-read returns, so the
  /// credit `_recordPathResult` gives a flood delivery at the acknowledgement
  /// found no route yet. Returns the contact as read back, null when the
  /// node did not answer in time.
  Future<Contact?> _creditReturnedRoute(Uint8List pubKey) async {
    final contact = await _fetchContactSnapshotFromDevice(pubKey);
    if (contact == null || contact.pathLength < 0) return contact;
    _recordPathResult(
      contact.publicKeyHex,
      PathSelection(
        pathBytes: contact.path,
        hopCount: contact.pathLength,
        useFlood: false,
      ),
      true,
      null,
    );
    return contact;
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
      _setSelfPublicKey(reader.readBytes(pubKeySize));
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
      _notificationService.setSelfName(_selfName);

      // The local public key only exists once SELF_INFO has arrived, so the
      // image sender prefix (first 2 bytes, big-endian) is refreshed here.
      final prefix = senderPrefixFromKey(_selfPublicKey);
      if (prefix != null) {
        _imageTransport?.senderPrefix = prefix;
        _onImageSenderPrefix?.call(prefix);
      }
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
      _clearDirectEchoKey('node changed');
      _channelKeyHashCache.clear();
      _directFloodRepeats.clear();
      _heardChannelPackets.clear();
      _contactRegions.clear();
    }

    // A different radio answered (for example after a dropped BLE link):
    // drop the previous radio's history before this radio's stores load.
    if (_messageStateOwnerKey != null &&
        _messageStateOwnerKey != selfPublicKeyHex) {
      _clearSessionMessageState();
    }
    _messageStateOwnerKey = selfPublicKeyHex;

    // A later SELF_INFO of this link session (refreshDeviceInfo after a
    // settings change) answers for the radio whose stores are bound and
    // loaded already; reading them again cost a full reload each time. The
    // name may have changed, so it is written as on the first handshake.
    if (_persistedStateLoadedKey == selfPublicKeyHex) {
      unawaited(_nodeIdentityStore.saveName(_selfName));
      _awaitingSelfInfo = false;
      _hasCompletedSelfInfoHandshake = parsedSelfInfo;
      _selfInfoRetryTimer?.cancel();
      _selfInfoRetryTimer = null;
      _maybeRequestDeviceConfig();
      notifyListeners();
      _maybeStartInitialChannelSync();
      if (_pendingQueueSync && _hasLoadedContacts && !_isLoadingContacts) {
        _pendingQueueSync = false;
        unawaited(syncQueuedMessages(force: true));
      }
      return;
    }

    //set all the stores' public key so they can load the correct data
    _channelMessageStore.setPublicKeyHex = selfPublicKeyHex;
    _messageStore.setPublicKeyHex = selfPublicKeyHex;
    _channelOrderStore.setPublicKeyHex = selfPublicKeyHex;
    _channelSettingsStore.setPublicKeyHex = selfPublicKeyHex;
    _channelRegionStore.setPublicKeyHex = selfPublicKeyHex;
    _contactRegionStore.setPublicKeyHex = selfPublicKeyHex;
    _contactSettingsStore.setPublicKeyHex = selfPublicKeyHex;
    _contactStore.setPublicKeyHex = selfPublicKeyHex;
    _channelStore.setPublicKeyHex = selfPublicKeyHex;
    _nodeIdentityStore.setPublicKeyHex = selfPublicKeyHex;
    _unreadStore.setPublicKeyHex = selfPublicKeyHex;
    _pathHistoryService?.setDevicePublicKey(selfPublicKeyHex);
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
    unawaited(_loadContactRegions(storagePublicKeyHex));
    final contactCacheLoadGeneration = ++_contactCacheLoadGeneration;
    _contactCacheLoadFuture = _loadContactCacheForNode(
      storagePublicKeyHex,
      contactCacheLoadGeneration,
    );
    unawaited(_prepareCachedChannelStorage(storagePublicKeyHex));
    loadUnreadState();
    _persistedStateLoadedKey = selfPublicKeyHex;

    _awaitingSelfInfo = false;
    _hasCompletedSelfInfoHandshake = parsedSelfInfo;
    if (parsedSelfInfo) {
      _reconnectAttempts = 0;
      unawaited(_backgroundService?.setConnectionLost(false));
      unawaited(_requestDirectEchoKey());
    }
    _selfInfoRetryTimer?.cancel();
    _selfInfoRetryTimer = null;
    _maybeRequestDeviceConfig();
    notifyListeners();

    // Start the serialized initial sync pipeline after SELF_INFO.
    _maybeStartInitialChannelSync();

    // A queue sync deferred while this SELF_INFO was awaited (e.g. a later
    // refreshDeviceInfo) has nothing else to resume it.
    if (_pendingQueueSync && _hasLoadedContacts && !_isLoadingContacts) {
      _pendingQueueSync = false;
      unawaited(syncQueuedMessages(force: true));
    }
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
      final mode = (frame[81] & 0xFF).clamp(0, 2);
      _pathHashByteWidth = mode + 1;
    } else {
      _pathHashByteWidth = 1;
    }
    if (_pathHashByteWidth != previousPathHashByteWidth) {
      _directRepeaters.clear();
      _activeRepeaters.clear();
      _bumpRepeaterActivity();
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
    _maybeRequestDeviceConfig();
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
    _queuedMessageRequestWork.finishCurrent();
    debugPrint('[QueueSync] No more messages, sync complete');
    _queueSyncTimeout?.cancel();
    _queueSyncTimeout = null;
    _isSyncingQueuedMessages = false;
    _isInitialBacklogDrain = false;
    _queuedMessageSyncInFlight = false;
    notifyListeners();
    _continueAfterQueuedMessageSync();
    _maybeFlushInitialSyncNotificationSummary();
  }

  void _beginInitialSyncNotificationSummary() {
    _initialSyncNotificationSummaryActive = true;
    _initialSyncMessageNotifications = 0;
    _initialSyncChannelMessageNotifications = 0;
  }

  bool _recordInitialSyncMessageNotification() {
    if (!_initialSyncNotificationSummaryActive) return false;
    _initialSyncMessageNotifications++;
    return true;
  }

  bool _recordInitialSyncChannelMessageNotification() {
    if (!_initialSyncNotificationSummaryActive) return false;
    _initialSyncChannelMessageNotifications++;
    return true;
  }

  void _maybeFlushInitialSyncNotificationSummary() {
    if (!_initialSyncNotificationSummaryActive ||
        _deferQueuedContactMessagesUntilContacts ||
        _isProcessingDeferredQueuedContactMessages) {
      return;
    }
    final messageCount = _initialSyncMessageNotifications;
    final channelMessageCount = _initialSyncChannelMessageNotifications;
    _discardInitialSyncNotificationSummary();
    if (messageCount == 0 && channelMessageCount == 0) return;
    unawaited(
      _notificationService.showSyncSummaryNotification(
        messagesCount: messageCount,
        channelMessagesCount: channelMessageCount,
      ),
    );
  }

  void _discardInitialSyncNotificationSummary() {
    _initialSyncNotificationSummaryActive = false;
    _initialSyncMessageNotifications = 0;
    _initialSyncChannelMessageNotifications = 0;
  }

  /// The node's queued-message frame only carries the sender-controlled packet
  /// timestamp. Preserve FIFO replay order with a local monotonic receive time.
  DateTime _channelMessageReceivedAt(DateTime now) {
    if (!_isInitialBacklogDrain) return now;
    final receivedAt = ChannelMessageTimelineHelper.nextBacklogReceivedAt(
      now: now,
      previous: _lastInitialBacklogChannelReceivedAt,
    );
    _lastInitialBacklogChannelReceivedAt = receivedAt;
    return receivedAt;
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
      unawaited(getContacts(preserveExisting: true));
      return;
    }
    unawaited(_processDeferredQueuedContactMessages());
  }

  Future<void> _processDeferredQueuedContactMessages() =>
      _packetBackgroundWork.replay(_processDeferredQueuedContactMessagesCore);

  Future<void> _processDeferredQueuedContactMessagesCore() async {
    if (!_deferQueuedContactMessagesUntilContacts ||
        _isProcessingDeferredQueuedContactMessages) {
      return;
    }
    if (_deferredQueuedContactMessageFrames.isEmpty) {
      _deferQueuedContactMessagesUntilContacts = false;
      notifyListeners();
      _maybeFlushInitialSyncNotificationSummary();
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
      DateTime? previousReceivedAt;
      while (_deferredQueuedContactMessageFrames.isNotEmpty) {
        final frame = _deferredQueuedContactMessageFrames.removeAt(0);
        final receivedAt = RoomMessageTimelineHelper.nextBacklogReceivedAt(
          now: DateTime.now(),
          previous: previousReceivedAt,
        );
        previousReceivedAt = receivedAt;
        await _handleIncomingMessage(
          frame,
          receivedAt: receivedAt,
          alreadyAdvancedQueueSync: true,
        );
      }
    } finally {
      _deferQueuedContactMessagesUntilContacts = false;
      _isProcessingDeferredQueuedContactMessages = false;
      notifyListeners();
      _maybeFlushInitialSyncNotificationSummary();
    }

    if (_pendingQueueSync && isConnected) {
      _pendingQueueSync = false;
      unawaited(syncQueuedMessages(force: true));
    }
  }

  void _handleQueuedMessageReceived() {
    if (!_isSyncingQueuedMessages) return;
    _queuedMessageRequestWork.finishCurrent();
    debugPrint('[QueueSync] Queued frame fragment received, requesting next');
    _queueSyncTimeout?.cancel(); // Cancel timeout - message arrived
    _queueSyncTimeout = null;
    _queuedMessageSyncInFlight = false;
    notifyListeners();
    unawaited(_requestNextQueuedMessage());
  }

  Future<void> _processPotentialQueuedMessage({
    required String? localSourceLabel,
    required String frameType,
    required Future<void> Function() process,
  }) => _messageProcessingBackgroundWork.run(
    () => _processPotentialQueuedMessageCore(
      localSourceLabel: localSourceLabel,
      frameType: frameType,
      process: process,
    ),
  );

  Future<void> _processPotentialQueuedMessageCore({
    required String? localSourceLabel,
    required String frameType,
    required Future<void> Function() process,
  }) async {
    final completesQueuedRequest =
        localSourceLabel == null &&
        _isSyncingQueuedMessages &&
        _queuedMessageSyncInFlight;
    if (!completesQueuedRequest) {
      await process();
      return;
    }

    // The response arrived, so the transport timeout must no longer run while
    // parsing, signature verification, and durable history storage complete.
    // Keep _queuedMessageSyncInFlight set until then so a simultaneous tickle
    // cannot start another destructive queue request.
    _queueSyncTimeout?.cancel();
    _queueSyncTimeout = null;
    _queuedMessageRequestWork.finishCurrent();
    _appDebugLogService?.info(
      'Queued $frameType frame received; processing before next request',
      tag: 'QueueSync',
    );

    try {
      await process();
    } catch (error, stackTrace) {
      _appDebugLogService?.error(
        'Could not process or persist queued $frameType frame; '
        'queue sync stopped: '
        '$error\n$stackTrace',
        tag: 'QueueSync',
      );
      _queuedMessageSyncInFlight = false;
      _isSyncingQueuedMessages = false;
      _isInitialBacklogDrain = false;
      _southQueuedFragmentAckTracker.clearAwaitingSyncResponse();
      _queuedMessageRequestWork.finishCurrent();
      notifyListeners();
      _continueAfterQueuedMessageSync();
      _maybeFlushInitialSyncNotificationSummary();
      return;
    }

    if (!_isSyncingQueuedMessages || !isConnected) {
      _queuedMessageSyncInFlight = false;
      _queuedMessageRequestWork.finishCurrent();
      return;
    }
    _queuedMessageSyncInFlight = false;
    _appDebugLogService?.info(
      'Queued $frameType frame processed; history write completed when '
      'applicable; requesting next',
      tag: 'QueueSync',
    );
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
    final baseline = _airtimeBaselineSecs;
    _airtimeGrewInLastPoll = baseline != null && total > baseline;
    _airtimeBaselineSecs = total;
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
          maxHops: _autoAddMaxHops,
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

  /// Absolute 120-second ceiling for ML-derived and physics-fallback timeouts.
  static const int _hardMaxTimeoutMs = 120000;

  int _calculatePhysicsMaxTimeout({
    required int pathLength,
    required int pathBytes,
    required int messageBytes,
    required int attempt,
  }) {
    // Match BaseChatMesh::composeMsgPacket(), Utils::encryptThenMAC() and
    // Packet::getRawLength(): timestamp/type, optional extended attempt,
    // AES block padding, address hashes, MAC, packet header and path.
    final plaintextBytes = 5 + messageBytes + (attempt > 3 ? 2 : 0);
    final encryptedBytes = ((plaintextBytes + 15) ~/ 16) * 16;
    final radioPacketBytes = 2 + pathBytes + 2 + 2 + encryptedBytes;
    final airtime = _estimateAirtimeMs(radioPacketBytes);
    return _physicsMaxTimeout(
      pathLength,
      airtime,
    ).clamp(0, _hardMaxTimeoutMs).toInt();
  }

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

  /// Drops the contacts a completed full sync did not list. The node no
  /// longer holds them, deleted there by another app or by the firmware, or
  /// never did, like the discovered nodes older builds merged into the list.
  /// Their conversations stay in the database; their unread counts go, since
  /// nothing left on screen could clear them.
  void _dropContactsMissingFromNode() {
    final missing = _contactsUnconfirmedBySync;
    _contactsUnconfirmedBySync = null;
    if (missing == null || missing.isEmpty) return;
    _contacts.removeWhere((contact) => missing.contains(contact.publicKeyHex));
    _knownContactKeys.removeAll(missing);
    for (final key in missing) {
      final unread = _contactUnreadCount.remove(key) ?? 0;
      _cachedContactsUnreadTotal = (_cachedContactsUnreadTotal - unread).clamp(
        0,
        _cachedContactsUnreadTotal,
      );
    }
    appLogger.info(
      'Contact sync: dropped ${missing.length} contact(s) the node does not '
      'hold',
      tag: 'Connector',
    );
  }

  void _registerContactInActiveSync(String publicKeyHex, int index) {
    if (!_isLoadingContacts || index < 0 || index >= _contacts.length) return;
    _contactSyncIndexes?[publicKeyHex] = index;
  }

  /// PUSH_CODE_NEW_ADVERT carries a contact the firmware did NOT store
  /// (type not auto-added, beyond autoadd_max_hops, or storage full;
  /// BaseChatMesh::onAdvertRecv), so it only feeds the discovered list.
  void _handleNewAdvert(Uint8List frame) {
    final contact = Contact.fromFrame(frame);
    if (contact == null || listEquals(contact.publicKey, _selfPublicKey)) {
      return;
    }
    _handleDiscovery(contact, frame);
    notifyListeners();
  }

  /// PUSH_CODE_CONTACT_DELETED: the firmware overwrote this contact to make
  /// room for a new one (auto-add overwrite-oldest).
  void _handleContactDeleted(Uint8List frame) {
    if (frame.length < 1 + pubKeySize) return;
    final keyHex = pubKeyToHex(
      Uint8List.fromList(frame.sublist(1, 1 + pubKeySize)),
    );
    _appDebugLogService?.info(
      'Firmware deleted contact ${keyHex.substring(0, 8)} to make room',
      tag: 'Connector',
    );
    _contacts.removeWhere((c) => c.publicKeyHex == keyHex);
    _knownContactKeys.remove(keyHex);
    _contactsStorageFull = false;
    unawaited(updateKnownDiscovered());
    unawaited(_persistContacts());
    notifyListeners();
  }

  void _handleContact(Uint8List frame, {bool countTowardSync = true}) {
    final contactTmp = Contact.fromFrame(frame);
    if (contactTmp != null) {
      // Any CONTACT frame, a sync's or not, says the node holds the contact.
      _contactsUnconfirmedBySync?.remove(contactTmp.publicKeyHex);
      final isContactSync = countTowardSync && _isLoadingContacts;
      if (isContactSync) {
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
        // A CONTACT frame is a contact the node stores; its auto-add
        // settings were applied there, before the frame was sent.
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
      }
      _knownContactKeys.add(contact.publicKeyHex);

      // Add path to history if we have a valid path
      if (!isContactSync &&
          _pathHistoryService != null &&
          contact.pathLength >= 0) {
        _pathHistoryService!.handlePathUpdated(
          contact,
          initialWeight: _initialRouteWeight,
        );
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
      _pathHistoryService!.handlePathUpdated(
        contact,
        initialWeight: _initialRouteWeight,
      );
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
    _clearEstimatesOfNewlyLocated(_contacts, _contactEstimatesCleared);
    await _contactStore.saveContacts(_contacts);
  }

  Future<void> _persistDiscoveredContacts() async {
    _clearEstimatesOfNewlyLocated(
      _discoveredContacts,
      _discoveredEstimatesCleared,
    );
    await _discoveryContactStore.saveContacts(_discoveredContacts);
  }

  /// Drops the stored position estimates of the nodes in [contacts] that
  /// have coordinates now and did not at the last save. The map draws an
  /// estimate only for a node without coordinates, so what this keeps out of
  /// the store is a stale guess that would come back the day the node loses
  /// them again. [cleared] remembers the located keys already handed to the
  /// store; a key that drops out of [contacts] leaves it (an advert without
  /// coordinates keeps the known ones, so a node loses them only by leaving
  /// the list), and a node that comes back without them is cleared again
  /// when it reports them. Every save used to clear every located contact,
  /// a rewrite of up to a thousand rows with nothing in them.
  void _clearEstimatesOfNewlyLocated(
    Iterable<Contact> contacts,
    Set<String> cleared,
  ) {
    final located = <String>{
      for (final contact in contacts)
        if (contact.hasLocation) contact.publicKeyHex,
    };
    final fresh = [
      for (final key in located)
        if (!cleared.contains(key)) key,
    ];
    cleared
      ..retainWhere(located.contains)
      ..addAll(fresh);
    if (fresh.isEmpty) return;
    unawaited(_contactLocationEstimateStore.clearEstimatesForKeys(fresh));
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

  Future<void> _handleIncomingMessage(
    Uint8List frame, {
    DateTime? receivedAt,
    String? localSourceLabel,
    bool alreadyAdvancedQueueSync = false,
    bool isUnknownSenderReplay = false,
  }) {
    Future<void> process() => _processIncomingMessage(
      frame,
      receivedAt: receivedAt,
      localSourceLabel: localSourceLabel,
      isUnknownSenderReplay: isUnknownSenderReplay,
    );
    // A deferred frame advanced the queue sync when it arrived; replayed
    // later, it must not be taken for the answer to a request in flight.
    if (alreadyAdvancedQueueSync) return process();
    return _processPotentialQueuedMessage(
      localSourceLabel: localSourceLabel,
      frameType: 'contact message',
      process: process,
    );
  }

  Future<void> _processIncomingMessage(
    Uint8List frame, {
    DateTime? receivedAt,
    String? localSourceLabel,
    DirectEchoContext? echo,
    bool isUnknownSenderReplay = false,
  }) async {
    if (_selfPublicKey == null) return;

    var message = _parseContactMessage(frame);

    // Unknown sender: the firmware has already dropped this message from its
    // offline queue, so hold it until the sender's CONTACT frame arrives
    // rather than re-parsing before the refresh has delivered anything.
    if (message == null && !isUnknownSenderReplay) {
      final senderPrefix = _extractSenderPrefix(frame);
      if (senderPrefix != null &&
          _findContactByPrefix(
                senderPrefix,
                includeDiscoveredFallback: true,
              ) ==
              null) {
        debugPrint('Message from unknown contact; holding until contacts load');
        _holdUnknownSenderMessage(frame);
        if (!_isLoadingContacts) {
          try {
            await refreshContactsSinceLastmod();
          } catch (e) {
            appLogger.warn(
              'Contact refresh for unknown sender failed: $e',
              tag: 'Connector',
            );
          }
        }
        return;
      }
    }

    if (message != null) {
      final effectiveReceivedAt = receivedAt ?? DateTime.now();
      // The hop count of a flood packet, null for one routed to us.
      final floodHops = echo == null ? _floodHopCountOf(frame) : null;
      if (localSourceLabel != null) {
        message = message.copyWith(
          isOutgoing: true,
          status: MessageStatus.sent,
          receivedAt: effectiveReceivedAt,
          sourceLabel: localSourceLabel,
        );
      }
      if (!message.isOutgoing) {
        _lastContactMsgRxTime = effectiveReceivedAt;
      }
      // Ignore messages from self (device hearing its own broadcast)
      // BUT allow repeated messages (pathLength indicates it went through repeater)
      if (_selfPublicKey != null &&
          message.senderKeyHex == pubKeyToHex(_selfPublicKey!) &&
          (message.pathLength == null || message.pathLength == 0)) {
        debugPrint('Ignoring direct message from self');
        return;
      }

      var contact = _findContactByPubKeyHex(
        message.senderKeyHex,
        includeDiscoveredFallback: true,
      );
      if (contact != null) {
        if (getContactByPubKeyHex(contact.publicKeyHex) == null) {
          contact = _restoreDiscoveredContact(contact);
        }
        // A message another client sent through us went out along the route
        // the node holds for the contact, as our own sends do. An incoming
        // message keeps the path of its own packet, read from the frame: the
        // route the node or the user holds for the contact is the route of
        // our sends, and says nothing about how the contact's packet reached
        // us; it used to be written here, so a message received directly
        // showed the pinned route on its path screen.
        if (message.isOutgoing) {
          message = message.copyWith(
            pathLength: contact.pathLength < 0 ? -1 : contact.pathLength,
            pathBytes: contact.pathLength < 0 ? Uint8List(0) : contact.path,
          );
        }
        // receivedAt is the app-local conversation order. During the initial
        // queue drain it preserves the companion's FIFO response sequence.
        if (!message.isOutgoing) {
          message = message.copyWith(receivedAt: effectiveReceivedAt);
        }
      }
      await _loadMessagesForContact(message.senderKeyHex);
      // A contact whose key starts with the byte ours starts with makes our
      // own packets to them look like theirs to us (the hashes and the
      // shared secret are the same both ways): a copy a repeater relays,
      // decoded from the RX log or delivered by a node that forgot it, came
      // up as a message from them. Told apart by content, before anything
      // is verified, counted, stored or acknowledged.
      if (contact != null &&
          !message.isOutgoing &&
          !message.isCli &&
          DirectEchoRecovery.isOwnMessage(
            selfPublicKey: _selfPublicKey!,
            contact: contact,
            timestampSeconds: message.timestamp.millisecondsSinceEpoch ~/ 1000,
            text: message.text,
            conversation: _conversations[message.senderKeyHex] ?? const [],
          )) {
        appLogger.info(
          'Ignoring our own message to ${contact.name} heard back as theirs '
          '(both keys start with the same byte)',
          tag: 'DirectEcho',
        );
        return;
      }
      if (contact != null && !message.isOutgoing && !message.isCli) {
        message = await _applyContactMcmpVerification(message, contact);
      }
      if (contact != null) {
        _updateContactLastMessageAt(contact.publicKeyHex, effectiveReceivedAt);
      }
      if (contact != null && !message.isOutgoing && !message.isCli) {
        message = _resolveContactReplyReference(message, contact);
        message = _resolveContactTextReply(message, contact);
      }
      final incomingMessage = message;
      if (!incomingMessage.isOutgoing) {
        final existing = _conversations[incomingMessage.senderKeyHex];
        final incomingTimestamp =
            incomingMessage.timestamp.millisecondsSinceEpoch;
        if (existing != null && existing.isNotEmpty) {
          final isRoomMessage = contact?.type == advTypeRoom;
          final duplicateIndex = existing.indexWhere(
            (current) =>
                !current.isOutgoing &&
                current.timestamp.millisecondsSinceEpoch == incomingTimestamp &&
                current.text == incomingMessage.text &&
                (!isRoomMessage ||
                    listEquals(
                      current.fourByteRoomContactKey,
                      incomingMessage.fourByteRoomContactKey,
                    )),
          );
          if (duplicateIndex >= 0) {
            _mergeDirectEcho(
              incomingMessage.senderKeyHex,
              existing[duplicateIndex],
              echo?.observation,
            );
            // The sender's retry is a packet of its own: its region is that
            // message's, and its relays are counted from zero, as a retry of
            // our own is.
            if (floodHops != null && contact != null) {
              final original = existing[duplicateIndex];
              final binding = _bindDirectFloodDelivery(
                original,
                contact,
                floodHops,
              );
              if (binding != null) {
                _updateStoredContactMessage(
                  incomingMessage.senderKeyHex,
                  original.messageId,
                  (current) => _withDirectFloodCopy(
                    current.copyWith(repeatCount: 0),
                    relays: binding.relays,
                    transportCode: binding.transportCode,
                    payload: binding.payload,
                    copies: binding.copies,
                    currentAttempt: true,
                  ),
                );
              }
            }
            return;
          }
        }
      }
      if (echo != null) {
        message = DirectEchoRecovery.stampFirstEcho(message, echo.observation);
      }
      if (floodHops != null && !message.isOutgoing) {
        message = message.copyWith(sentByFlood: true);
        final binding = contact == null
            ? null
            : _bindDirectFloodDelivery(message, contact, floodHops);
        if (binding != null) {
          message = _withDirectFloodCopy(
            message,
            relays: binding.relays,
            transportCode: binding.transportCode,
            payload: binding.payload,
            copies: binding.copies,
            currentAttempt: true,
          );
        }
      }
      // The receive-time question is asked once and stamped onto the message.
      final blockedNow = BlockedSenders.instance.isRoomAuthorBlocked(message);
      if (blockedNow) message = message.copyWith(wasBlocked: true);
      await _addMessage(message.senderKeyHex, message);
      if (!blockedNow) _maybeIncrementContactUnread(message);
      notifyListeners();
      if (echo != null) unawaited(_sendDirectEchoAck(echo));

      // Persist first, then enqueue the notification before advancing a
      // destructive firmware queue read. The notification is enqueued here
      // and shown in the background: the queue waits for the history write,
      // never for a picture download or the plugin.
      // A muted room author raises none: it would put the hidden text straight
      // back on screen.
      if (!message.isOutgoing &&
          !message.isCli &&
          !blockedNow &&
          _appSettingsService != null) {
        final settings = _appSettingsService!.settings;
        if (settings.notificationsEnabled && settings.notifyOnNewMessage) {
          if (_recordInitialSyncMessageNotification()) return;
          final msg = message; // capture for closure
          final c = contact; // capture contact reference
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
            _showNotificationInBackground(
              _notificationService.showMessageNotification(
                contactName: c?.name ?? 'Unknown',
                message: resolvedText,
                urlImagesEnabled:
                    c != null && isContactUrlImagesEnabled(c.publicKeyHex),
                contactId: msg.senderKeyHex,
                badgeCount: getTotalUnreadCount(),
              ),
            );
          } else if (c?.type == advTypeRoom) {
            final resolvedText =
                (translationResult != null &&
                    translationResult.status ==
                        MessageTranslationStatus.completed &&
                    translationResult.translatedText.trim().isNotEmpty)
                ? translationResult.translatedText.trim()
                : msg.text.trim();
            _showNotificationInBackground(
              _notificationService.showMessageNotification(
                contactName: c?.name ?? 'Unknown Room',
                message: resolvedText,
                urlImagesEnabled:
                    c != null && isContactUrlImagesEnabled(c.publicKeyHex),
                contactId: msg.senderKeyHex,
                badgeCount: getTotalUnreadCount(),
              ),
            );
          }
        }
      }
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

      // Companion frames carry the raw TXT_TYPE (0..3); legacy firmware sent
      // it shifted into the upper six bits like the over-the-air flags byte.
      final type = txtType <= _txtTypeCliCommand ? txtType : txtType >> 2;
      final isSigned = type == txtTypeSigned;
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

      final isPlain = type == txtTypePlain || isSigned;
      // TXT_TYPE_CLI_COMMAND is a remote CLI command the firmware did not run
      // (sender lacks remote-CLI permission); show it as CLI, never as chat.
      final isCli = type == txtTypeCliData || type == _txtTypeCliCommand;
      if (!isPlain && !isCli) {
        appLogger.warn('Unknown message type received: txtType=$txtType');
        return null;
      }

      if (msgText.isEmpty) {
        appLogger.warn('Received message with empty text, ignoring');
        return null;
      }
      final decodedDetails = isCli
          ? null
          : MessageTextCodec.tryDecodeKnownCompressionDetails(
              msgText,
              inheritedTimestamp: timestampRaw,
            );
      final decodedText = isCli ? msgText : (decodedDetails?.text ?? msgText);
      final compression = isCli
          ? null
          : MessageCompressionMetadata.fromEncodedText(
              encodedText: msgText,
              decodedText: decodedText,
            );

      final contact = _findContactByPrefix(
        senderPrefix,
        includeDiscoveredFallback: true,
      );
      if (contact == null) {
        appLogger.warn(
          'Received message from unknown contact with prefix: ${senderPrefix.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('')}',
        );
        return null;
      }

      final mcmpMessage = decodedDetails?.mcmpMessage;
      final mcotxtMessage = decodedDetails?.mcotxtMessage;
      return Message(
        senderKey: contact.publicKey,
        text: decodedText,
        timestamp: timestamp,
        receivedAt: DateTime.now(),
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
        containerTimestamp:
            mcmpMessage?.timestamp ?? mcotxtMessage?.metadataTimestamp,
        containerSenderName: mcmpMessage?.senderName ?? mcotxtMessage?.senderName,
        mcmpIsSigned: mcmpMessage?.isSigned ?? false,
        mcmpSignature: mcmpMessage?.signature,
        containerReplyAuthorName:
            mcmpMessage?.replyAuthorName ?? mcotxtMessage?.replyAuthorName,
        containerReplyTimestamp:
            mcmpMessage?.replyTimestamp ?? mcotxtMessage?.replyTimestamp,
        // The node writes 0xFF for a packet routed to us, whose route the
        // repeaters consumed on the way, so it is direct with no hops known;
        // a flood packet reports the hops it travelled, the hash width packed
        // into the top two bits. The frame carries no hop bytes either way.
        pathLength: pathLength == 0xFF ? 0 : (pathLength & 0x3F),
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

  void _ensureContactMCOtxtSettingLoaded(String contactKeyHex) {
    if (_contactMCOtxtEnabled.containsKey(contactKeyHex)) return;
    _contactSettingsStore.loadMCOtxtEnabled(contactKeyHex).then((enabled) {
      if (_contactMCOtxtEnabled[contactKeyHex] == enabled) return;
      _contactMCOtxtEnabled[contactKeyHex] = enabled;
      notifyListeners();
    });
  }

  void _ensureContactMCOtxtPlainWhenSmallerLoaded(String contactKeyHex) {
    if (_contactMCOtxtPlainWhenSmaller.containsKey(contactKeyHex)) return;
    _contactSettingsStore.loadMCOtxtPlainWhenSmaller(contactKeyHex).then((
      enabled,
    ) {
      if (_contactMCOtxtPlainWhenSmaller[contactKeyHex] == enabled) return;
      _contactMCOtxtPlainWhenSmaller[contactKeyHex] = enabled;
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

  void _ensureContactUrlImagesSettingLoaded(String contactKeyHex) {
    if (_contactUrlImagesEnabled.containsKey(contactKeyHex)) return;
    _contactSettingsStore.loadUrlImagesEnabled(contactKeyHex).then((enabled) {
      if (_contactUrlImagesEnabled[contactKeyHex] == enabled) return;
      _contactUrlImagesEnabled[contactKeyHex] = enabled;
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
  ///
  /// [allowMarkerPayload] lifts the exclusion of markers and their `del:`
  /// commands. Only the channel send path sets it, and only when the envelope
  /// will actually be signed: those payloads are plain text precisely so any
  /// client can read them, and the one thing worth giving that up for is
  /// proof of authorship. A channel post carries nothing but a display name,
  /// so without it anyone can erase anyone's pin; a direct message is
  /// authenticated by its transport and a room post by the author key prefix
  /// the server attaches, so neither needs the envelope.
  bool _isMcmpSignableText(String text, {bool allowMarkerPayload = false}) {
    if (text.isEmpty) return false;
    final trimmedLeft = text.trimLeft();
    final trimmed = text.trim();
    return !MCOImageV4Codec.isTextPayload(trimmedLeft) &&
        !MCOImageV3Codec.isTextPayload(trimmedLeft) &&
        !trimmedLeft.startsWith(MCOImageCodec.prefix) &&
        !trimmed.startsWith('g:') &&
        (allowMarkerPayload ||
            !SharedMarkerDeletion.isMarkerPayload(trimmed)) &&
        !trimmed.startsWith('V1|') &&
        // Shared contact payloads (<pubkey:type:name>) must travel as plain
        // text so receivers can parse them.
        parseSharedContactText(trimmed) == null &&
        !MeshCompressor.instance.hasPrefix(trimmed) &&
        !McmpAppCodec.isTextPayload(trimmed) &&
        !MCOtxtAppCodec.isTextPayload(trimmed);
  }

  /// The cyr2lat substitution table a channel's outgoing text is
  /// transliterated with — its own profile, else the globally selected one.
  /// Null when the channel does not use cyr2lat.
  Map<String, String>? channelCyr2LatCharMap(int channelIndex) {
    if (!isChannelCyr2LatEnabled(channelIndex)) return null;
    final profileId = getChannelCyr2LatProfileId(channelIndex);
    final profile = profileId != null && _appSettingsService != null
        ? _appSettingsService!.getCyr2LatProfileById(profileId)
        : null;
    return (profile ?? _appSettingsService?.getSelectedCyr2LatProfile())
        ?.charMap;
  }

  /// "Plain when smaller" for a contact or room: both forms travel as the
  /// text of the same packet, so their UTF-8 lengths are the whole
  /// difference. A room post embeds the sender name in the container while
  /// the plain form carries none, which is exactly what the comparison
  /// should see. Plain wins ties, being readable by every client.
  String _contactPlainIfSmallerThanMCOtxt(
    Contact contact,
    String plain,
    String encoded,
  ) {
    if (!isContactMCOtxtPlainWhenSmaller(contact.publicKeyHex)) return encoded;
    return utf8.encode(plain).length <= utf8.encode(encoded).length
        ? plain
        : encoded;
  }

  /// The plain form of a contact or room message that would otherwise go out
  /// as MCOtxt. A reply gets back the quote line the composer leaves out
  /// when the container carries an anchor, as [_channelPlainAlternative]
  /// does for a channel.
  String _contactPlainAlternative(
    Contact contact,
    String text, {
    String? replyToSenderName,
    String? replyToText,
    String? replyToMessageId,
  }) {
    if (replyToSenderName == null) return text;
    final mention = '@[$replyToSenderName] ';
    final hasMention = text.startsWith(mention);
    final rest = hasMention ? text.substring(mention.length) : text;
    if (hasMention && ExactQuoteHelper.splitQuoteLine(rest) != null) {
      return text;
    }
    final settings = _appSettingsService?.settings;
    final enabled = settings?.exactQuote ?? false;
    final fragmentForLatest = settings?.exactQuoteLatest ?? true;
    return ExactQuoteHelper.formatReplyWith(
      senderName: replyToSenderName,
      text: rest,
      quotedText: replyToText,
      quotedMessageId: replyToMessageId,
      // Read only when it decides whether a fragment is due, and merged anew
      // on every call: with the quote off, or spent on the latest message
      // too, the history is not fetched.
      history: enabled && !fragmentForLatest ? getMessages(contact) : const [],
      authorOf: (message) => contactMessageAuthorName(contact, message)?.trim(),
      idOf: (message) => message.messageId,
      enabled: enabled,
      fragmentForLatest: fragmentForLatest,
      maxFragmentBytes: settings?.exactQuoteLimit ?? 0,
      outboundCharMap: contactCyr2LatCharMap(contact),
    );
  }

  String _containerReplyBody(String text, String? replyToSenderName) {
    if (replyToSenderName == null) return text;
    final mention = '@[$replyToSenderName] ';
    return text.startsWith(mention) ? text.substring(mention.length) : text;
  }

  /// What a reply of ours shows: its text without the `@[author]` mention
  /// it was written with and the quote line after it, which only the wire
  /// needs. With a container anchor the composer writes no quote line, so a
  /// leading `>` line there is the author's own.
  String _contactReplyBody(
    Contact contact,
    String text,
    String? replyToSenderName,
  ) {
    if (replyToSenderName == null) return text;
    final replyInfo = ChannelMessage.parseReplyMention(text);
    if (replyInfo == null || replyInfo.mentionedNode != replyToSenderName) {
      return text;
    }
    if (contactReplyCarriesContainerAnchor(contact, text)) {
      return replyInfo.actualMessage;
    }
    return ExactQuoteHelper.splitQuoteLine(replyInfo.actualMessage)?.text ??
        replyInfo.actualMessage;
  }

  /// Whether a reply in a direct or room chat travels with a container
  /// anchor, which pins the quoted message and makes a quote line redundant.
  ///
  /// MCMP v3 and MCOtxt both carry that anchor in service fields, so exact
  /// quote fragments must stay out of their text body.
  bool contactReplyCarriesContainerAnchor(Contact contact, String text) {
    final key = contact.publicKeyHex;
    return _isMcmpSignableText(text) &&
        ((isContactMcmpEnabled(key) && contactMcmpVersion(key) == 3) ||
            isContactMCOtxtEnabled(key));
  }

  /// The cyr2lat table a message to [contact] is transliterated with, or null
  /// when it goes out untransliterated; see [channelCyr2LatCharMap].
  Map<String, String>? contactCyr2LatCharMap(Contact contact) {
    if (!isContactCyr2LatEnabled(contact.publicKeyHex)) return null;
    final profileId = getContactCyr2LatProfileId(contact.publicKeyHex);
    final profile = profileId != null && _appSettingsService != null
        ? _appSettingsService!.getCyr2LatProfileById(profileId)
        : null;
    return (profile ?? _appSettingsService?.getSelectedCyr2LatProfile())
        ?.charMap;
  }

  /// The composer's view of the channel rule: the plain text a message would
  /// go out as, or null when it goes out as MCOtxt (or MCOtxt does not apply).
  String? channelPlainIfSmallerThanMCOtxt(
    int channelIndex,
    String text, {
    String? replyToSenderName,
    String? replyToText,
    String? replyToMessageId,
    int? replyToTimestamp,
  }) {
    final channelIndexInList = _channels.indexWhere(
      (channel) => channel.index == channelIndex,
    );
    if (channelIndexInList < 0) return null;
    if (!isChannelMCOtxtEnabled(channelIndex) || !_isMcmpSignableText(text)) {
      return null;
    }
    return _channelPlainIfSmallerThanMCOtxt(
      _channels[channelIndexInList],
      text,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      replyToSenderName: replyToSenderName,
      replyToText: replyToText,
      replyToMessageId: replyToMessageId,
      replyToTimestamp: replyToTimestamp,
    );
  }

  /// "Plain when smaller" for a channel: the plain text to send instead of
  /// MCOtxt, or null when MCOtxt is the smaller packet, the rule is off, or
  /// the plain text would not fit a text frame. Both packets are costed as
  /// the firmware builds them: GRP_TXT is `timestamp(4) + type(1) +
  /// "Name: text"`, GRP_DATA is `data_type(2) + length(1) + envelope`, and
  /// the encryption around them is the same. Plain wins ties.
  String? _channelPlainIfSmallerThanMCOtxt(
    Channel channel,
    String text, {
    required int timestamp,
    String? replyToSenderName,
    String? replyToText,
    String? replyToMessageId,
    int? replyToTimestamp,
  }) {
    if (!isChannelMCOtxtPlainWhenSmaller(channel.index)) return null;
    final senderName = channelSendName(channel.index);
    final hasReplyPair = replyToSenderName != null && replyToTimestamp != null;
    final replyAuthorName = hasReplyPair ? replyToSenderName : null;
    final replyTimestamp = hasReplyPair ? replyToTimestamp : null;
    final containerText = _containerReplyBody(text, replyToSenderName);
    final int mcotxtBytes;
    if (ChannelBinaryDataHelper.canSend) {
      final envelope = ChannelBinaryDataHelper.mcotxtAppPayloadLength(
        containerText,
        senderName,
        replyAuthorName: replyAuthorName,
        replyTimestamp: replyTimestamp,
      );
      if (envelope == null) return null;
      mcotxtBytes = ChannelBinaryDataHelper.finalBinaryPayloadLength(envelope);
    } else {
      mcotxtBytes = _groupTextPacketBytes(
        MCOtxtAppCodec.encodeTextTransport(
          text: containerText,
          timestamp: timestamp,
          replyAuthorName: replyAuthorName,
          replyTimestamp: replyTimestamp,
        ),
        senderName: senderName,
      );
    }
    final plain = _channelPlainAlternative(
      channel,
      text,
      replyToSenderName: replyToSenderName,
      replyToText: replyToText,
      replyToMessageId: replyToMessageId,
    );
    if (utf8.encode(plain).length > maxChannelTextBytes(channel.index)) {
      return null;
    }
    return _groupTextPacketBytes(plain, senderName: senderName) <= mcotxtBytes
        ? plain
        : null;
  }

  /// The plain-text form of a channel message that would otherwise go out
  /// as MCOtxt. A reply gets its exact-quote fragment back: the composer
  /// leaves it out when the container carries an anchor, and a plain packet
  /// has no anchor to fall back on.
  String _channelPlainAlternative(
    Channel channel,
    String text, {
    String? replyToSenderName,
    String? replyToText,
    String? replyToMessageId,
  }) {
    if (replyToSenderName == null) return text;
    final mention = '@[$replyToSenderName] ';
    final hasMention = text.startsWith(mention);
    final body = hasMention ? text.substring(mention.length) : text;
    if (hasMention && ExactQuoteHelper.splitQuoteLine(body) != null) {
      return text;
    }
    final settings = _appSettingsService?.settings;
    final enabled = settings?.exactQuote ?? false;
    final fragmentForLatest = settings?.exactQuoteLatest ?? true;
    return ExactQuoteHelper.formatReply(
      senderName: replyToSenderName,
      text: body,
      quotedText: replyToText,
      quotedMessageId: replyToMessageId,
      // Read only when it decides whether a fragment is due, and merged anew
      // on every call: with the quote off, or spent on the latest message
      // too, the history is not fetched.
      history: enabled && !fragmentForLatest
          ? getChannelMessages(channel)
          : const [],
      enabled: enabled,
      fragmentForLatest: fragmentForLatest,
      maxFragmentBytes: settings?.exactQuoteLimit ?? 0,
      outboundCharMap: channelCyr2LatCharMap(channel.index),
    );
  }

  /// Plaintext bytes of a GRP_TXT packet before encryption, as
  /// `BaseChatMesh::sendGroupMessage` builds it: timestamp, type byte and
  /// `"Name: text"`, the prefix counted the way the composer counter counts
  /// it ([channelSenderPrefixBytes]).
  int _groupTextPacketBytes(String text, {required String senderName}) =>
      5 + channelSenderPrefixBytes(senderName) + utf8.encode(text).length;

  /// Whether a channel reply will travel with a container reply anchor
  /// (quoted author + timestamp), which pins the quoted message exactly and
  /// makes a plain-text quote fragment redundant.
  ///
  /// MCMP v3 and MCOtxt both carry that anchor in service fields.
  bool channelReplyCarriesContainerAnchor(int channelIndex, String text) {
    return _isMcmpSignableText(text) &&
        ((isChannelMcmpEnabled(channelIndex) &&
                channelMcmpVersion(channelIndex) == 3) ||
            isChannelMCOtxtEnabled(channelIndex));
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
    String? replyToText,
    String? replyToMessageId,
  }) async {
    final hasReplyPair = replyAuthorName != null && replyTimestamp != null;
    final effectiveReplyName = hasReplyPair ? replyAuthorName : null;
    final effectiveReplyTimestamp = hasReplyPair ? replyTimestamp : null;

    // Markers and `del:` commands never enter the envelope here, whatever the
    // chat: a direct message is authenticated by its ECDH transport, and a
    // room post carries the author's 4-byte key prefix, put there by the
    // server and shown next to the name. Only a channel has nothing but a
    // display name to go on, which is what the signed envelope replaces.
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
    if (isContactMCOtxtEnabled(contact.publicKeyHex) &&
        _isMcmpSignableText(text)) {
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return _contactPlainIfSmallerThanMCOtxt(
        contact,
        _contactPlainAlternative(
          contact,
          text,
          replyToSenderName: replyAuthorName,
          replyToText: replyToText,
          replyToMessageId: replyToMessageId,
        ),
        MCOtxtAppCodec.encodeTextTransport(
          text: text,
          timestamp: timestamp,
          senderName: contact.type == advTypeRoom ? _selfName ?? 'Me' : null,
          replyAuthorName: contact.type == advTypeRoom
              ? effectiveReplyName
              : hasReplyPair
              ? ''
              : null,
          replyTimestamp: effectiveReplyTimestamp,
        ),
      );
    }
    return prepareContactOutboundText(
      contact,
      text,
      replyAuthorName: replyAuthorName,
      replyTimestamp: replyTimestamp,
      replyToText: replyToText,
      replyToMessageId: replyToMessageId,
    );
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
    String? replyAuthorName,
    int? replyTimestamp,
    String? replyToText,
    String? replyToMessageId,
  }) {
    // A reply anchor names its author in a room; in a direct chat both ends
    // are known and the author travels empty, as in the async variant.
    final hasReplyPair = replyAuthorName != null && replyTimestamp != null;
    final anchorAuthor = !hasReplyPair
        ? null
        : contact.type == advTypeRoom
        ? replyAuthorName
        : '';
    final anchorTimestamp = hasReplyPair ? replyTimestamp : null;
    final trimmedLeft = text.trimLeft();
    final trimmed = text.trim();
    final isMarkerPayload = SharedMarkerDeletion.isMarkerPayload(trimmed);
    final isStructuredPayload =
        MCOImageV4Codec.isTextPayload(trimmedLeft) ||
        MCOImageV3Codec.isTextPayload(trimmedLeft) ||
        trimmedLeft.startsWith(MCOImageCodec.prefix) ||
        trimmed.startsWith('g:') ||
        isMarkerPayload ||
        trimmed.startsWith('V1|') ||
        parseSharedContactText(trimmed) != null ||
        MeshCompressor.instance.hasPrefix(trimmed) ||
        McmpAppCodec.isTextPayload(trimmed) ||
        MCOtxtAppCodec.isTextPayload(trimmed);
    if (!isStructuredPayload) {
      if (isContactMCOtxtEnabled(contact.publicKeyHex)) {
        return _contactPlainIfSmallerThanMCOtxt(
          contact,
          _contactPlainAlternative(
            contact,
            text,
            replyToSenderName: replyAuthorName,
            replyToText: replyToText,
            replyToMessageId: replyToMessageId,
          ),
          MCOtxtAppCodec.encodeTextTransport(
            text: text,
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            senderName: contact.type == advTypeRoom
                ? _selfName ?? 'Me'
                : null,
            replyAuthorName: anchorAuthor,
            replyTimestamp: anchorTimestamp,
          ),
        );
      }
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
            replyAuthorName: anchorAuthor,
            replyTimestamp: anchorTimestamp,
          );
        }
        return McmpAppCodec.encodeTextTransport(
          text: text,
          timestamp: timestamp,
          replyAuthorName: anchorAuthor,
          replyTimestamp: anchorTimestamp,
        );
      }
      if (isContactSmazEnabled(contact.publicKeyHex)) {
        return Smaz.encodeIfSmaller(text);
      } else if (isContactCyr2LatEnabled(contact.publicKeyHex)) {
        return _encodeContactCyr2Lat(contact, text);
      }
    }
    // See prepareChannelOutboundText: a marker label takes cyr2lat whenever the
    // chat has it on; a `del:` command never does.
    if (SharedMarkerDeletion.isMarker(trimmed) &&
        isContactCyr2LatEnabled(contact.publicKeyHex)) {
      return SharedMarkerDeletion.encodeLabel(
        text,
        (label) => _encodeContactCyr2Lat(contact, label),
      );
    }
    return text;
  }

  String _encodeContactCyr2Lat(Contact contact, String text) {
    final profileId = getContactCyr2LatProfileId(contact.publicKeyHex);
    final profile = profileId != null && _appSettingsService != null
        ? _appSettingsService!.getCyr2LatProfileById(profileId)
        : null;
    if (profile != null) {
      Cyr2Lat.setCharMap(profile.charMap);
    } else {
      final globalProfile = _appSettingsService?.getSelectedCyr2LatProfile();
      if (globalProfile != null) {
        Cyr2Lat.setCharMap(globalProfile.charMap);
      }
    }
    return Cyr2Lat.encode(text);
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
    final isMarkerPayload = SharedMarkerDeletion.isMarkerPayload(trimmed);
    final isStructuredPayload =
        MCOImageV4Codec.isTextPayload(trimmedLeft) ||
        MCOImageV3Codec.isTextPayload(trimmedLeft) ||
        trimmedLeft.startsWith(MCOImageCodec.prefix) ||
        trimmed.startsWith('g:') ||
        isMarkerPayload ||
        parseSharedContactText(trimmed) != null ||
        MeshCompressor.instance.hasPrefix(trimmed) ||
        McmpAppCodec.isTextPayload(trimmed) ||
        MCOtxtAppCodec.isTextPayload(trimmed);
    if (!isStructuredPayload) {
      if (isChannelMCOtxtEnabled(channelIndex)) {
        return MCOtxtAppCodec.encodeTextTransport(
          text: text,
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );
      }
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
        return _encodeChannelCyr2Lat(channelIndex, text);
      }
    }
    // A marker is the one structured payload that still takes cyr2lat, and
    // only across its label: a Cyrillic caption costs twice the bytes, while
    // the coordinates and flags are structure. A `del:` command is excluded on
    // purpose — it must repeat the label byte for byte.
    if (SharedMarkerDeletion.isMarker(trimmed) &&
        isChannelCyr2LatEnabled(channelIndex)) {
      return SharedMarkerDeletion.encodeLabel(
        text,
        (label) => _encodeChannelCyr2Lat(channelIndex, label),
      );
    }
    return text;
  }

  String _encodeChannelCyr2Lat(int channelIndex, String text) {
    final charMap = channelCyr2LatCharMap(channelIndex);
    if (charMap != null) Cyr2Lat.setCharMap(charMap);
    return Cyr2Lat.encode(text);
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
    } else if (isContactMCOtxtEnabled(contact.publicKeyHex) &&
        MCOtxtAppCodec.isTextPayload(outboundText)) {
      type = MessageCompressionType.mcotxt;
      final mcotxtTextBytes = MCOtxtAppCodec.compressedTextBytesFromTextPayload(
        outboundText,
      );
      if (mcotxtTextBytes != null) {
        return MessageCompressionMetadata.fromByteLengths(
          type: type,
          originalBytes: utf8.encode(originalText).length,
          compressedBytes: mcotxtTextBytes,
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
        McmpAppCodec.isTextPayload(text) ||
        MCOtxtAppCodec.isTextPayload(text);
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

  _McmpReplyReference? _resolveAppDataReplyReference(
    int channelIndex,
    ChannelAppDataInbound? appData,
  ) {
    final mcmpReference = _resolveMcmpReplyReference(
      channelIndex,
      appData?.mcmpMessage,
    );
    if (mcmpReference != null) return mcmpReference;
    final mcotxtMessage = appData?.mcotxtMessage;
    if (mcotxtMessage != null && mcotxtMessage.isReply) {
      final mcotxtReference = _resolveChannelReplyAnchor(
        channelIndex,
        mcotxtMessage.replyAuthorName,
        mcotxtMessage.replyTimestamp,
      );
      if (mcotxtReference != null) return mcotxtReference;
    }
    final image = appData?.mcoImageV4;
    if (image == null) return null;
    return _resolveChannelReplyAnchor(
      channelIndex,
      image.targetName,
      image.replyTimestamp,
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
          message.containerTimestamp == replyTimestamp) {
        return _McmpReplyReference(
          messageId: message.messageId,
          senderName: message.senderName,
          text: message.text,
        );
      }
      var delta = (outerTimestamp - replyTimestamp).abs();
      final containerTimestamp = message.containerTimestamp;
      if (containerTimestamp != null) {
        final containerDelta = (containerTimestamp - replyTimestamp).abs();
        if (containerDelta < delta) delta = containerDelta;
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
        message.containerTimestamp == null ||
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
      timestamp: message.containerTimestamp!,
      senderName: message.containerSenderName,
      signature: message.mcmpSignature,
      replyAuthorName: message.containerReplyAuthorName,
      replyTimestamp: message.containerReplyTimestamp,
    );
    final result = await McmpSignatureVerifier.verifyChannelMessage(
      message: decoded,
      // The channel transport name is what the bubble displays. The verifier
      // independently rejects an embedded MCMP name that differs from it.
      senderName: message.senderName,
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
    if (message.containerTimestamp == null) return message;
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
      timestamp: message.containerTimestamp!,
      senderName: message.containerSenderName,
      signature: message.mcmpSignature,
      replyAuthorName: message.containerReplyAuthorName,
      replyTimestamp: message.containerReplyTimestamp,
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
    unawaited(
      _channelMessageStore.saveChannelMessage(channelIndex, reverified),
    );
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
    await _messageStore.saveMessage(contactKeyHex, reverified);
    notifyListeners();
    return reverified.mcmpSignatureStatus;
  }

  /// Resolves the container reply anchor of an inbound DM/room message against
  /// the stored conversation. Room posts match the transmitted "author name +
  /// timestamp" pair; direct messages carry an empty author name (both
  /// identities are known) and resolve by timestamp alone.
  Message _resolveContactReplyReference(Message message, Contact contact) {
    final isRoom = contact.type == advTypeRoom;
    final replySender = message.containerReplyAuthorName?.trim();
    final replyTimestamp = message.containerReplyTimestamp;
    if (replyTimestamp == null) return message;
    if (isRoom && (replySender == null || replySender.isEmpty)) {
      return message;
    }

    String? authorNameFor(Message candidate) =>
        contactMessageAuthorName(contact, candidate);

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
      if (candidate.containerTimestamp == replyTimestamp ||
          outerTimestamp == replyTimestamp) {
        return message.copyWith(
          replyToMessageId: candidate.messageId,
          replyToSenderName: candidateName,
          replyToText: candidate.text,
        );
      }
      var delta = (outerTimestamp - replyTimestamp).abs();
      final containerTimestamp = candidate.containerTimestamp;
      if (containerTimestamp != null) {
        final containerDelta = (containerTimestamp - replyTimestamp).abs();
        if (containerDelta < delta) delta = containerDelta;
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

  /// The author a direct or room conversation gives [message]: the name a
  /// room post carries in its container, us for our own messages, the node
  /// a room post's key prefix points at, saved or only discovered, as the
  /// chat names it, or in a direct chat the contact itself. Reply mentions
  /// and anchors name messages by it, so a reply resolves only while both
  /// ends name the message alike.
  String? contactMessageAuthorName(Contact conversation, Message message) {
    final embedded = message.containerSenderName;
    if (embedded != null) return embedded;
    if (message.isOutgoing) return _selfName;
    final prefix = message.fourByteRoomContactKey;
    if (prefix.isEmpty) return conversation.name;
    for (final contact in _contacts) {
      if (_matchesPrefix(contact.publicKey, prefix)) return contact.name;
    }
    for (final contact in _discoveredContacts) {
      if (_matchesPrefix(contact.publicKey, prefix)) return contact.name;
    }
    return null;
  }

  /// The reply an incoming direct or room message carries in its text,
  /// taken apart as `_addChannelMessage` takes a channel reply apart: the
  /// `@[author]` mention comes off the body, a quote line is matched against
  /// the conversation, and the reply reference is filled from what it found.
  /// A container anchor keeps the answer [_resolveContactReplyReference]
  /// gave it and only loses the mention. A direct chat has two ends, so a
  /// mention of anybody else is no reply there, just a message that starts
  /// with a mention.
  Message _resolveContactTextReply(Message message, Contact contact) {
    final replyInfo = ChannelMessage.parseReplyMention(message.text);
    if (replyInfo == null) return message;
    final mentionedNode = replyInfo.mentionedNode.trim();
    if (contact.type != advTypeRoom &&
        mentionedNode != contact.name.trim() &&
        mentionedNode != _selfName?.trim()) {
      return message;
    }
    final settings = _appSettingsService?.settings;
    final hasContainerAnchor = message.containerReplyTimestamp != null;
    final quotesAsMentions = settings?.incomingQuoteAsMentions ?? false;
    final history = _conversations[contact.publicKeyHex] ?? const <Message>[];
    String? authorOf(Message candidate) =>
        contactMessageAuthorName(contact, candidate)?.trim();
    final exactQuote =
        ExactQuoteHelper.parsesFragment(
          quotesAsMentions: quotesAsMentions,
          exactQuoteEnabled: settings?.exactQuote ?? true,
          hasMcmpAnchor: hasContainerAnchor,
        )
        ? ExactQuoteHelper.resolveReplyWith(
            body: replyInfo.actualMessage,
            mentionedNode: mentionedNode,
            history: history,
            authorOf: authorOf,
            textOf: (candidate) => candidate.text,
            extraCharMaps: [
              for (final profile
                  in settings?.cyr2latProfiles ?? const <Cyr2LatProfile>[])
                profile.charMap,
            ],
          )
        : null;
    final replyIsExact = exactQuote?.quoted != null;
    final body =
        (ExactQuoteHelper.stripsFragment(
              quotesAsMentions: quotesAsMentions,
              fragmentResolved: replyIsExact,
            )
            ? exactQuote?.text
            : null) ??
        replyInfo.actualMessage;

    var replyToMessageId = message.replyToMessageId;
    var replyToText = message.replyToText;
    // Only a bare mention falls back to the author's newest message: an
    // anchor that resolved to nothing stays a name, as in a channel.
    if (!hasContainerAnchor && replyToMessageId == null) {
      var original = exactQuote?.quoted;
      if (exactQuote == null) {
        for (var i = history.length - 1; i >= 0; i--) {
          if (authorOf(history[i]) == mentionedNode) {
            original = history[i];
            break;
          }
        }
      }
      if (original != null) {
        replyToMessageId = original.messageId;
        replyToText = original.text;
      } else if (exactQuote != null) {
        // The quoted message never reached us: the fragment that did stays
        // visible, without an id to scroll to.
        replyToText = exactQuote.fragment;
      }
    }
    return message.copyWith(
      text: body,
      replyToMessageId: replyToMessageId,
      replyToSenderName: message.replyToSenderName ?? mentionedNode,
      replyToText: replyToText,
      replyIsExact: replyIsExact,
    );
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
    if (isChannelMCOtxtEnabled(channelIndex)) {
      final mcotxtTextBytes = MCOtxtAppCodec.compressedTextBytesFromTextPayload(
        outboundText,
      );
      if (mcotxtTextBytes != null) {
        return MessageCompressionMetadata.fromByteLengths(
          type: MessageCompressionType.mcotxt,
          originalBytes: utf8.encode(originalText).length,
          compressedBytes: mcotxtTextBytes,
        );
      }
    }
    if (binaryPayloadBytes != null) {
      final type = isChannelMCOtxtEnabled(channelIndex)
          ? MessageCompressionType.mcotxt
          : MessageCompressionType.mcmp;
      return MessageCompressionMetadata.fromByteLengths(
        type: type,
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
    } else if (isChannelMCOtxtEnabled(channelIndex) &&
        MCOtxtAppCodec.isTextPayload(outboundText)) {
      type = MessageCompressionType.mcotxt;
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
    if (decoded.mcotxtMessage != null) {
      try {
        return MessageCompressionMetadata.fromByteLengths(
          type: MessageCompressionType.mcotxt,
          originalBytes: utf8.encode(decoded.text!).length,
          compressedBytes: MCOtxtAppCodec.compressedTextBytesFromBody(
            decoded.body,
          ),
        );
      } catch (_) {
        return null;
      }
    }
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
    if (decoded.text != null) return decoded.text!;
    if (decoded.version == ChannelAppDataHelper.mcoImageV4Version) {
      return const MCOImageV4Codec().textFromBody(decoded.body);
    }
    return MCOImageV3Codec.textFromBody(decoded.body);
  }

  /// The name blocking rules are matched against — see
  /// `BlockedSenders.ruleFor`. Public so every display site asks with the same
  /// label the receive path used; the screens' own `channel.name` is empty for
  /// an unnamed channel where this says `Channel 3`.
  /// [Channel.storageId] of the channel in radio slot [slot], or null for an
  /// empty or unknown slot; the image store stamps its entries with it.
  String? channelIdForSlot(int slot) => _findChannelByIndex(slot)?.storageId;

  String channelDisplayName(int channelIndex) =>
      _channelDisplayName(channelIndex);

  // Falls back to the cached channel list, which stays populated while a
  // channel refresh has temporarily emptied _channels. The same label keys
  // the channel's mute (`Channel.muteKey`).
  String _channelDisplayName(int channelIndex) {
    final channel = _findChannelByIndex(channelIndex);
    if (channel == null || channel.name.isEmpty) return 'Channel $channelIndex';
    return channel.name;
  }

  /// Whether [text] mentions this node by a name it bears in the channel:
  /// the node's own, or the sender name the channel keeps.
  bool _channelMessageMentionsSelf(int channelIndex, String text) {
    final names = {?_selfName?.trim(), ?channelSenderName(channelIndex)}
      ..removeWhere((name) => name.isEmpty);
    for (final name in names) {
      final mention = RegExp(
        '@\\[\\s*${RegExp.escape(name)}\\s*\\]',
        caseSensitive: false,
      );
      if (mention.hasMatch(text)) return true;
    }
    return false;
  }

  /// Shows a notification off the receive path. The message it names is in
  /// the history already; what remains is the plugin, and for a picture its
  /// download or rendering, which the node's queue must not wait for (see
  /// [_processPotentialQueuedMessage]). The call itself ran up to its first
  /// await, so the service's rate limiter saw the notifications in order.
  void _showNotificationInBackground(Future<void> notification) {
    unawaited(
      notification.catchError((Object error, StackTrace stackTrace) {
        appLogger.warn(
          'Could not show a notification: $error\n$stackTrace',
          tag: 'Notification',
        );
      }),
    );
  }

  /// A mute is kept by name, so a channel renamed under the same key keeps
  /// the mute its former name holds.
  bool _isChannelMutedUnderAnyName(String label, int channelIndex) {
    final settings = _appSettingsService!;
    if (settings.isChannelMuted(label)) return true;
    final channel = _findChannelByIndex(channelIndex);
    final identity = channel == null ? null : ChannelIdentity.of(channel);
    if (identity == null) return false;
    return ChannelIdentities.instance
        .namesOf(identity)
        .any(settings.isChannelMuted);
  }

  Future<void> _maybeNotifyChannelMessage(
    ChannelMessage message, {
    String? channelName,
    TranslationResult? translationResult,
  }) async {
    if (message.isOutgoing || _appSettingsService == null) return;
    final channelIndex = message.channelIndex;
    if (channelIndex == null) return;

    final settings = _appSettingsService!.settings;
    if (!settings.notificationsEnabled || !settings.notifyOnNewChannelMessage) {
      return;
    }

    final label = channelName ?? _channelDisplayName(channelIndex);
    // The chat will hide this body; a notification would put it straight back
    // on screen, so it is not raised at all.
    if (BlockedSenders.instance.isSenderBlocked(message, label)) return;
    final isMuted = _isChannelMutedUnderAnyName(label, channelIndex);
    if (isMuted && !_channelMessageMentionsSelf(channelIndex, message.text)) {
      return;
    }
    if (_recordInitialSyncChannelMessageNotification()) return;

    // Reuse translation result only if completed and non-empty; else use original text
    final resolvedText =
        (translationResult != null &&
            translationResult.status == MessageTranslationStatus.completed &&
            translationResult.translatedText.trim().isNotEmpty)
        ? translationResult.translatedText.trim()
        : message.text.trim();
    _showNotificationInBackground(
      _notificationService.showChannelMessageNotification(
        channelName: label,
        senderName: message.senderName,
        message: resolvedText,
        urlImagesEnabled: isChannelUrlImagesEnabled(channelIndex),
        channelIndex: message.channelIndex,
        badgeCount: getTotalUnreadCount(),
      ),
    );
  }

  Future<void> _handleIncomingChannelMessage(
    Uint8List frame, {
    String? localSourceLabel,
  }) {
    return _processPotentialQueuedMessage(
      localSourceLabel: localSourceLabel,
      frameType: 'channel message',
      process: () => _processIncomingChannelMessage(
        frame,
        localSourceLabel: localSourceLabel,
      ),
    );
  }

  Future<void> _processIncomingChannelMessage(
    Uint8List frame, {
    String? localSourceLabel,
  }) async {
    final parsed = ChannelMessage.fromFrame(
      frame,
      includeSenderNameInCompressionRatio:
          _appSettingsService?.settings.compressionRatioWithSenderName == true,
      isOutgoing: localSourceLabel != null,
      sourceLabel: localSourceLabel,
    );
    if (parsed != null && parsed.channelIndex != null) {
      _lastChannelMsgRxTime = parsed.receivedAt;
      final channelIndex = parsed.channelIndex!;
      final timestampSeconds = parsed.timestamp.millisecondsSinceEpoch ~/ 1000;
      // The node hands over the packet it decrypted; the radio logged the
      // same packet already, so this is usually its second copy.
      final heardKey = _channelCopiesTakeOldPath(channelIndex)
          ? null
          : HeardChannelPackets.textKey(
              channelIndex: channelIndex,
              timestampSeconds: timestampSeconds,
              senderName: parsed.senderName,
              rawText: parsed.rawText ?? parsed.text,
            );
      if (heardKey != null &&
          await _foldHeardChannelCopy(
            heardKey,
            channelIndex,
            receivedAt: DateTime.now(),
            pathBytes: parsed.pathBytes,
            pathLength: parsed.pathLength,
            pathHashWidth: parsed.pathHashWidth,
            snr: parsed.snr,
            sourceLabel: localSourceLabel,
          )) {
        return;
      }
      final contentHash = _computeContentHash(
        channelIndex,
        timestampSeconds,
        '${parsed.senderName}: ${parsed.text}',
      );
      var message = parsed.copyWith(
        packetHash: contentHash,
        // The packet timestamp remains sender metadata. Timeline position is
        // always based on this app's first receipt of the message.
        receivedAt: _channelMessageReceivedAt(parsed.receivedAt),
      );
      final textReplyReference = _resolveChannelReplyAnchor(
        parsed.channelIndex!,
        message.containerReplyAuthorName,
        message.containerReplyTimestamp,
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
      final isNew = await _addChannelMessage(
        message.channelIndex!,
        message,
        heardKey: heardKey,
      );
      _maybeIncrementChannelUnread(message, isNew: isNew);
      notifyListeners();
      if (isNew && !message.isOutgoing) {
        final translationResult = await translateChannelMessage(
          message.channelIndex!,
          message,
        );
        await _maybeNotifyChannelMessage(
          message,
          translationResult: translationResult,
        );
      }
    }
  }

  Future<void> _handleIncomingChannelData(
    Uint8List frame, {
    String? localSourceLabel,
  }) {
    return _processPotentialQueuedMessage(
      localSourceLabel: localSourceLabel,
      frameType: 'channel data',
      process: () => _processIncomingChannelData(
        frame,
        localSourceLabel: localSourceLabel,
      ),
    );
  }

  Future<void> _processIncomingChannelData(
    Uint8List frame, {
    String? localSourceLabel,
  }) async {

    // AEIC and MCOimg both use GRP_DATA but have distinct content types. Give
    // AEIC first refusal; a null outcome means this frame belongs to the
    // existing binary/app-data path below.
    if (_appSettingsService?.settings.imageMessagesEnabled ?? false) {
      final outcome = _imageTransport?.handleFrame(frame);
      if (outcome != null) {
        _lastChannelMsgRxTime = DateTime.now();
        _onImageChunk?.call(outcome);
        notifyListeners();
        return;
      }
    }

    final dataFrame = parseChannelDataReceivedFrame(frame);
    if (dataFrame == null) return;

    final contentHash = _computeChannelDataHash(
      dataFrame.channelIndex,
      dataFrame.dataType,
      dataFrame.payload,
    );
    final heardKey = _channelCopiesTakeOldPath(dataFrame.channelIndex)
        ? null
        : contentHash;
    if (heardKey != null &&
        await _foldHeardChannelCopy(
          heardKey,
          dataFrame.channelIndex,
          receivedAt: DateTime.now(),
          pathLength: dataFrame.pathLength,
          pathHashWidth: dataFrame.pathHashWidth,
          snr: dataFrame.snr,
          sourceLabel: localSourceLabel,
        )) {
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
      final unknown = ChannelBinaryDataHelper.tryDescribeUnknownAppData(
        dataType: dataFrame.dataType,
        payload: dataFrame.payload,
      );
      if (unknown != null) {
        await _addUnknownAppDataMessage(
          unknown,
          dataFrame,
          localSourceLabel: localSourceLabel,
          heardKey: heardKey,
        );
      } else if (heardKey != null) {
        _heardChannelPackets.abandon(heardKey);
      }
      return;
    }
    final appData = appDecoded;

    final channelName = _channelDisplayName(dataFrame.channelIndex);
    final senderName = decoded?.senderName ?? appData!.senderName;

    final receivedAt = DateTime.now();
    _lastChannelMsgRxTime = receivedAt;
    final compression = decoded != null
        ? _incomingBinaryCompression(decoded)
        : _incomingAppDataCompression(appData!);
    final messageText = decoded != null
        ? decoded.text
        : _appDataMessageText(appData!);
    final replyReference = _resolveAppDataReplyReference(
      dataFrame.channelIndex,
      appData,
    );
    final mcmpMessage = appData?.mcmpMessage;
    final mcotxtMessage = appData?.mcotxtMessage;
    final packetTimestamp = mcmpMessage == null && mcotxtMessage == null
        ? decoded?.timestamp ?? receivedAt
        : DateTime.fromMillisecondsSinceEpoch(
            (mcmpMessage?.timestamp ?? mcotxtMessage!.timestamp) * 1000,
          );
    final storedReceivedAt = _channelMessageReceivedAt(receivedAt);
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
      containerTimestamp: mcmpMessage?.timestamp ?? mcotxtMessage?.metadataTimestamp,
      containerSenderName: mcmpMessage?.senderName ?? mcotxtMessage?.senderName,
      mcmpIsSigned: mcmpMessage?.isSigned ?? false,
      mcmpSignature: mcmpMessage?.signature,
      containerReplyAuthorName:
          mcmpMessage?.replyAuthorName ?? mcotxtMessage?.replyAuthorName,
      containerReplyTimestamp:
          mcmpMessage?.replyTimestamp ?? mcotxtMessage?.replyTimestamp,
      wasBinaryTransport: true,
      binaryPacketBytes: dataFrame.payload.length,
      rawPayload: dataFrame.payload,
      timestamp: packetTimestamp,
      receivedAt: storedReceivedAt,
      isOutgoing: localSourceLabel != null,
      status: ChannelMessageStatus.sent,
      pathLength: dataFrame.pathLength,
      pathHashWidth: dataFrame.pathHashWidth,
      snr: dataFrame.snr,
      channelIndex: dataFrame.channelIndex,
      packetHash: contentHash,
      replyToMessageId: replyReference?.messageId,
      replyToSenderName: replyReference?.senderName,
      replyToText: replyReference?.text,
      sourceLabel: localSourceLabel,
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
    final isNew = await _addChannelMessage(
      dataFrame.channelIndex,
      message,
      heardKey: heardKey,
    );
    _maybeIncrementChannelUnread(message, isNew: isNew);
    notifyListeners();
    if (isNew && !message.isOutgoing) {
      final translationResult = await translateChannelMessage(
        message.channelIndex!,
        message,
      );
      await _maybeNotifyChannelMessage(
        message,
        channelName: channelName,
        translationResult: translationResult,
      );
    }
  }

  /// A channel data packet from a namespace this app knows, MCO Advanced's
  /// `0x0120` or MeshCore Open's `0x0100`, that nothing in this build could
  /// read is kept as a message rather than dropped: its text is the sentinel
  /// the screens render as a placeholder (see
  /// [ChannelBinaryDataHelper.unknownAppDataPrefix]) and its `rawPayload` is
  /// the whole payload, so a later build that knows the format has the bytes
  /// to decode from history. No notification is raised: its text would be
  /// the sentinel, and the unread count already says something arrived. The
  /// RX-log copy of such a packet is still ignored, the node hands every
  /// foreign packet over as a frame as well.
  Future<void> _addUnknownAppDataMessage(
    UnknownChannelAppData unknown,
    ChannelDataReceivedFrame dataFrame, {
    String? localSourceLabel,
    String? heardKey,
  }) async {
    final receivedAt = DateTime.now();
    _lastChannelMsgRxTime = receivedAt;
    final message = ChannelMessage(
      senderName: unknown.senderName ?? 'Unknown',
      text: unknown.sentinelText,
      wasBinaryTransport: true,
      binaryPacketBytes: dataFrame.payload.length,
      rawPayload: dataFrame.payload,
      timestamp: receivedAt,
      receivedAt: _channelMessageReceivedAt(receivedAt),
      isOutgoing: localSourceLabel != null,
      status: ChannelMessageStatus.sent,
      pathLength: dataFrame.pathLength,
      pathHashWidth: dataFrame.pathHashWidth,
      snr: dataFrame.snr,
      channelIndex: dataFrame.channelIndex,
      packetHash: _computeChannelDataHash(
        dataFrame.channelIndex,
        dataFrame.dataType,
        dataFrame.payload,
      ),
      sourceLabel: localSourceLabel,
    );
    _updateContactLastMessageAtByName(
      message.senderName,
      message.receivedAt,
      pathHashWidth: message.pathHashWidth,
    );
    final isNew = await _addChannelMessage(
      dataFrame.channelIndex,
      message,
      heardKey: heardKey,
    );
    _maybeIncrementChannelUnread(message, isNew: isNew);
    notifyListeners();
  }

  /// Expected MAC and ciphertext of our recent channel sends, so an echo the
  /// frame limit cut short is still recognised. See [ChannelEchoRecovery].
  final ChannelEchoRecovery _channelEchoRecovery = ChannelEchoRecovery();

  /// The channel packets heard lately, by the identity every copy of one
  /// packet shares, and what each became, so a copy is folded into its
  /// message before decoding, verification and the rest of the receive path
  /// (see [HeardChannelPackets] and [_foldHeardChannelCopy]). The channels
  /// the do-not-filter setting lists never use it: their packets take the
  /// whole path every time, as they always did.
  final HeardChannelPackets _heardChannelPackets = HeardChannelPackets();
  ChannelKeyHashCache _channelKeyHashCache = ChannelKeyHashCache();

  /// Copies folded into their message by the short path.
  @visibleForTesting
  int heardChannelCopiesMerged = 0;

  /// Copies of an applied reaction dropped by the short path.
  @visibleForTesting
  int heardChannelReactionCopiesDropped = 0;

  bool _channelCopiesTakeOldPath(int channelIndex) =>
      _isChannelListedInDoNotFilterSetting(_channelDisplayName(channelIndex));

  /// The data type and payload of a decrypted GRP_DATA packet, or null when
  /// the bytes are shorter than their length byte claims.
  ({int dataType, Uint8List payload})? _groupDataOf(Uint8List decryptedBytes) {
    if (decryptedBytes.length < 3) return null;
    final length = decryptedBytes[2];
    if (3 + length > decryptedBytes.length) return null;
    return (
      dataType: decryptedBytes[0] | (decryptedBytes[1] << 8),
      payload: Uint8List.sublistView(decryptedBytes, 3, 3 + length),
    );
  }

  /// Folds a copy of a channel packet heard before into what its first copy
  /// became: nothing for a reaction, the route, the reading, the region and
  /// one more repeat for a message. Returns false when the packet is new, or
  /// when its message is no longer loaded, and the copy has to take the whole
  /// receive path; that path then settles the claim [key] holds, so a copy
  /// arriving meanwhile waits for it rather than processing the packet again.
  Future<bool> _foldHeardChannelCopy(
    String key,
    int channelIndex, {
    required DateTime receivedAt,
    Uint8List? pathBytes,
    int? pathLength,
    int? pathHashWidth,
    double? snr,
    int? rssi,
    String? packetRegion,
    bool packetRegionInfoAvailable = false,
    bool packetRegionNotMatched = false,
    String? sourceLabel,
  }) async {
    final claimed = _heardChannelPackets.claim(key);
    if (claimed == null) return false;
    switch (await claimed) {
      case null:
        return false;
      case HeardAsReaction():
        heardChannelReactionCopiesDropped++;
        return true;
      case HeardAsMessage(:final messageId):
        final messages = _channelMessages[channelIndex];
        if (messages == null) return false;
        // From the end: a copy follows its packet within seconds.
        final index = messages.lastIndexWhere(
          (message) => message.messageId == messageId,
        );
        if (index < 0) return false;
        final existing = messages[index];
        // Only what a copy can add; the text, the id and the hash are the
        // stored message's own.
        final copy = ChannelMessage(
          senderName: existing.senderName,
          text: existing.text,
          timestamp: existing.timestamp,
          receivedAt: receivedAt,
          isOutgoing: false,
          status: ChannelMessageStatus.sent,
          pathLength: pathLength,
          pathHashWidth: pathHashWidth,
          pathBytes: pathBytes,
          snr: snr,
          rssi: rssi,
          channelIndex: channelIndex,
          packetRegion: packetRegion,
          packetRegionInfoAvailable: packetRegionInfoAvailable,
          packetRegionNotMatched: packetRegionNotMatched,
          packetHash: existing.packetHash,
          sourceLabel: sourceLabel,
        );
        final merged = _mergeChannelRepeat(messages, index, copy);
        _wakeChannelHopCheck(existing.messageId);
        if (merged.receivedAt != existing.receivedAt) {
          messages.sort(_compareChannelMessages);
        }
        heardChannelCopiesMerged++;
        await _channelMessageStore.saveChannelMessage(channelIndex, merged);
        notifyListeners();
        return true;
    }
  }

  /// Records our own packet under the key its copies will carry, so its
  /// first echo folds in by the short path: a text send by the name and the
  /// text the node puts on the air, a data send by the hash of its payload.
  void _recordOwnChannelPacket(
    int channelIndex,
    ChannelMessage message,
    int timestampSeconds,
  ) {
    if (_channelCopiesTakeOldPath(channelIndex)) return;
    final rawText = message.rawText;
    final String? key;
    if (rawText != null) {
      // The name the packet carries is the message's own: the channel's or
      // the node's (see channelSendName).
      key = HeardChannelPackets.textKey(
        channelIndex: channelIndex,
        timestampSeconds: timestampSeconds,
        senderName: message.senderName,
        rawText: rawText,
      );
    } else {
      key = message.packetHash;
    }
    if (key == null) return;
    _heardChannelPackets.record(key, HeardAsMessage(message.messageId));
  }

  bool get _recoverLongPacketEchoes =>
      _appSettingsService?.settings.recoverLongPacketEchoes ?? true;

  Uint8List? _channelPskFor(int channelIndex) {
    final channels = _channels.isNotEmpty ? _channels : _cachedChannels;
    for (final channel in channels) {
      if (channel.index != channelIndex) continue;
      return channel.isEmpty ? null : channel.psk;
    }
    return null;
  }

  /// The frame that sends [text] to [channel] under [senderName]: the node's
  /// own command, which stamps the node's name, or, under a name of the
  /// channel's own, a raw GRP_TXT packet built here (see [ChannelRawPacket]),
  /// scoped with the transport code of [region] (a region's name, '' for
  /// none) and registered with the echo registry, which `_sendFrameDirect`
  /// reads off the node's command only. A resend of the same packet passes
  /// [registerEcho] false, the registry having been fed by the first send.
  Uint8List _channelTextFrame(
    Channel channel,
    String text, {
    required String senderName,
    required Region region,
    int? timestampSeconds,
    bool registerEcho = true,
  }) {
    final timestamp =
        timestampSeconds ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (senderName == (_selfName ?? 'Me')) {
      return buildSendChannelTextMsgFrame(
        channel.index,
        text,
        timestampSeconds: timestamp,
      );
    }
    final plaintext = ChannelEchoRecovery.groupTextPlaintext(
      timestampSeconds: timestamp,
      senderName: senderName,
      textBytes: Uint8List.fromList(utf8.encode(text)),
    );
    final payload = ChannelRawPacket.groupTextPayload(
      psk: channel.psk,
      plaintext: plaintext,
    );
    final scope = region.trim();
    final transportCode = scope.isEmpty
        ? null
        : _computeRegionTransportCode(scope, payloadTypeGRPTXT, payload);
    if (registerEcho && _recoverLongPacketEchoes) {
      _channelEchoRecovery.register(
        channelIndex: channel.index,
        psk: channel.psk,
        plaintext: plaintext,
      );
    }
    return ChannelRawPacket.sendFrame(
      ChannelRawPacket.floodPacket(
        payloadType: payloadTypeGRPTXT,
        payload: payload,
        pathHashWidth: _pathHashByteWidth,
        transportCode: transportCode,
      ),
    );
  }

  /// Every frame written to the radio passes through here; only channel text
  /// and channel data sends are kept, since those are the packets whose bytes
  /// the firmware builds predictably from what we hand it.
  void _registerChannelEchoExpectation(Uint8List frame) {
    if (!_recoverLongPacketEchoes) return;
    try {
      _channelEchoRecovery.registerOutgoingFrame(
        frame,
        pskFor: _channelPskFor,
        senderName: _selfName,
      );
    } catch (e) {
      appLogger.warn('Could not register a channel echo expectation: $e');
    }
  }

  /// [encrypted] is the MAC and ciphertext of a group packet the normal
  /// decode rejected. Returns the full payload of our own packet it is a cut
  /// copy of, so the caller can decode that in its place.
  Uint8List? _recoverTruncatedChannelEcho(
    Channel channel,
    Uint8List encrypted, {
    required int frameLength,
  }) {
    if (!_recoverLongPacketEchoes) return null;
    final recovered = _channelEchoRecovery.recover(encrypted);
    if (recovered == null) return null;
    appLogger.info(
      'Recovered a cut echo of our own packet on channel ${channel.index}: '
      'frame $frameLength bytes, ${recovered.length - encrypted.length} '
      'byte(s) missing',
      tag: 'Connector',
    );
    return recovered;
  }

  // ---- Direct echo recovery (see DirectEchoRecovery) ----------------------

  /// The node's private key, RAM only, for decrypting direct messages heard
  /// before they finish their route. Cleared wherever a session ends.
  final DirectEchoKeyStore _directEchoKeys = DirectEchoKeyStore();
  Future<void>? _directEchoKeyRequest;

  /// Set when the node answered CMD_SEND_RAW_PACKET as a command it does not
  /// know: firmware older than that command cannot inject the ACK, so none
  /// is tried again until the link goes. `disconnect` and
  /// `_handleDisconnection` clear it, since the next connection may reach
  /// another node or new firmware, and `_resetConnectionHandshakeState` does
  /// not run for a native BLE one.
  bool _directEchoAckUnsupported = false;

  bool get _directEchoRecoveryEnabled =>
      _appSettingsService?.settings.directEchoRecovery ?? false;

  void _clearDirectEchoKey(String reason) {
    if (!_directEchoKeys.hasKey) return;
    _directEchoKeys.clear();
    appLogger.info(
      'Node private key wiped from RAM ($reason)',
      tag: 'DirectEcho',
    );
  }

  /// Asks the node for its private key (CMD_EXPORT_PRIVATE_KEY) and keeps
  /// it in RAM. Firmware built without ENABLE_PRIVATE_KEY_EXPORT answers
  /// RESP_CODE_DISABLED, and then the option quietly does nothing; the
  /// ordinary receive path is untouched either way.
  Future<void> _requestDirectEchoKey() {
    if (!_directEchoRecoveryEnabled ||
        !isConnected ||
        !_hasCompletedSelfInfoHandshake ||
        _directEchoKeys.hasKey) {
      return Future.value();
    }
    final pending = _directEchoKeyRequest;
    if (pending != null) return pending;
    final request = _exportDirectEchoKey();
    _directEchoKeyRequest = request;
    return request.whenComplete(() {
      if (identical(_directEchoKeyRequest, request)) {
        _directEchoKeyRequest = null;
      }
    });
  }

  Future<void> _exportDirectEchoKey() async {
    final completer = Completer<void>();
    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    final subscription = receivedFrames.listen((frame) {
      if (frame.isEmpty || completer.isCompleted) return;
      switch (frame[0]) {
        case respCodePrivateKey:
          if (frame.length < 1 + DirectEchoCrypto.privateKeyLength) {
            appLogger.warn(
              'Private key export answered with a short frame; '
              'direct echo recovery stays off',
              tag: 'DirectEcho',
            );
          } else {
            _directEchoKeys.setPrivateKey(
              Uint8List.fromList(
                frame.sublist(1, 1 + DirectEchoCrypto.privateKeyLength),
              ),
            );
            appLogger.info(
              'Node private key exported to RAM for direct echo recovery',
              tag: 'DirectEcho',
            );
          }
          finish();
        case respCodeDisabled:
          appLogger.warn(
            'Node refused to export its private key (disabled in firmware); '
            'direct echo recovery stays off',
            tag: 'DirectEcho',
          );
          finish();
      }
    });
    final timer = Timer(const Duration(seconds: 5), () {
      if (completer.isCompleted) return;
      appLogger.warn(
        'Private key export got no answer; direct echo recovery stays off',
        tag: 'DirectEcho',
      );
      finish();
    });
    try {
      await sendFrame(Uint8List.fromList([cmdExportPrivateKey]));
      await completer.future;
    } catch (error) {
      appLogger.warn('Private key export failed: $error', tag: 'DirectEcho');
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  }

  /// A direct message to us heard on its way through the mesh: decrypted
  /// with the node's key and handed to the ordinary receive path as the
  /// frame the node would have queued at the end of the route, so decoding,
  /// verification, storage, unread counts and notifications are the usual
  /// ones. Repeats and the eventual delivery merge in [_mergeDirectEcho].
  Future<void> _recoverDirectEcho(
    Uint8List frame, {
    required double snr,
    required int rssi,
  }) async {
    if (!_directEchoRecoveryEnabled || !_directEchoKeys.hasKey) return;
    final selfKey = _selfPublicKey;
    if (selfKey == null) return;
    final echo = DirectMessageEcho.tryParse(frame);
    if (echo == null || !DirectEchoRecovery.isCandidate(echo, selfKey)) {
      return;
    }
    final encrypted = DirectEchoRecovery.macAndCiphertext(echo);
    final senders = DirectEchoRecovery.candidateSenders(
      allContactsUnfiltered,
      echo.sourceHash,
    );
    for (final contact in senders) {
      final secret = _directEchoKeys.secretFor(contact);
      if (secret == null) continue;
      final decrypted = _decryptPayload(secret, encrypted);
      if (decrypted == null) continue;
      final plaintext = DirectEchoRecovery.parsePlaintext(decrypted);
      if (plaintext == null) {
        appLogger.info(
          'Direct echo from ${contact.name} is not a plain text message; '
          'left to the node',
          tag: 'DirectEcho',
        );
        return;
      }
      appLogger.info(
        'Direct echo from ${contact.name} decoded with '
        '${echo.remainingHopCount} hop(s) still ahead',
        tag: 'DirectEcho',
      );
      await _processIncomingMessage(
        DirectEchoRecovery.buildContactMessageFrame(
          contact.publicKey,
          plaintext,
          snr: snr,
        ),
        echo: DirectEchoContext(
          contact: contact,
          plaintext: plaintext,
          observation: DirectEchoObservation(
            remainingPath: echo.remainingPath,
            pathHashWidth: echo.pathHashWidth,
            snr: snr,
            rssi: rssi,
          ),
        ),
      );
      return;
    }
    // No candidate verified the MAC: somebody else's message behind the same
    // one-byte hash, or a sender we do not know. Nothing to report.
  }

  /// A further copy of a message the echo already showed, or its ordinary
  /// delivery at the end of the route, folds into the stored message instead
  /// of becoming another one. With no [observation] this is the delivery,
  /// which completes the route bar.
  void _mergeDirectEcho(
    String contactKeyHex,
    Message existing,
    DirectEchoObservation? observation,
  ) {
    final merged = observation != null
        ? DirectEchoRecovery.mergeRepeat(existing, observation)
        : DirectEchoRecovery.completeOnDelivery(existing);
    if (merged == null) return;
    _updateStoredContactMessage(
      contactKeyHex,
      existing.messageId,
      (_) => merged,
    );
  }

  /// The ACK the node sends for a message it receives itself, built for the
  /// one we decoded from its echo and injected through CMD_SEND_RAW_PACKET,
  /// routed as `BaseChatMesh::sendAckTo` routes it. Sent once, for the copy
  /// that created the message; repeats and the ordinary delivery send none
  /// (the node still acknowledges the delivery on its own — that is
  /// firmware behaviour and out of reach). Firmware without the command
  /// answers ERR_CODE_UNSUPPORTED_CMD, after which no ACK is attempted until
  /// the next connection; any other refusal costs only this ACK.
  Future<void> _sendDirectEchoAck(DirectEchoContext echo) async {
    if (_directEchoAckUnsupported || !isConnected) return;
    final contact =
        getContactByPubKeyHex(echo.contact.publicKeyHex) ?? echo.contact;
    final ack = DirectEchoCrypto.ackHash(
      echo.plaintext.bytes,
      echo.plaintext.textLength,
      contact.publicKey,
      randomByte: math.Random.secure().nextInt(256),
    );
    final route = resolvePathSelection(contact);
    int? transportCode;
    // The region our own flood sends to this contact take: its own, none
    // when it is marked unscoped, else the node's default scope.
    final contactRegion = getContactRegion(contact.publicKeyHex);
    final scope = ContactRegionStore.isUnscoped(contactRegion)
        ? ''
        : contactRegion.isNotEmpty
        ? contactRegion
        : _defaultRegionScope?.trim() ?? '';
    if (route.useFlood && scope.isNotEmpty && !scope.startsWith(r'$')) {
      transportCode = _computeRegionTransportCode(scope, payloadTypeACK, ack);
    }
    final packet = DirectEchoRecovery.buildAckPacket(
      ack: ack,
      route: route,
      pathHashWidth: _pathHashByteWidth,
      transportCode: transportCode,
    );
    try {
      await _runChannelCommandLocked(
        () => sendFrame(
          DirectEchoRecovery.buildSendRawPacketFrame(packet),
          waitForGenericAck: true,
        ),
      );
      appLogger.info(
        'ACK for the echoed message from ${contact.name} sent '
        '${route.useFlood ? 'by flood' : 'along ${route.hopCount} hop(s)'}',
        tag: 'DirectEcho',
      );
    } on TimeoutException {
      appLogger.warn(
        'ACK for the echoed message from ${contact.name}: no answer from '
        'the node',
        tag: 'DirectEcho',
      );
    } catch (error) {
      if (!DirectEchoRecovery.meansRawPacketUnsupported(error)) {
        // Most often a full packet pool: the node drops its own ACK the same
        // way when it has no packet for it, and the next echo tries again.
        appLogger.warn(
          'ACK for the echoed message from ${contact.name} was not sent '
          '($error)',
          tag: 'DirectEcho',
        );
        return;
      }
      // The node has no CMD_SEND_RAW_PACKET (firmware before May 2026), so
      // an echoed message is acknowledged only once it arrives in full and
      // the node answers by itself.
      _directEchoAckUnsupported = true;
      appLogger.warn(
        'ACK for echoed messages is not supported by this firmware '
        '($error); none will be sent until the next connection',
        tag: 'DirectEcho',
      );
    }
  }

  // ---- Flood retransmissions of direct messages (see DirectFloodRepeats) --

  /// Relayed copies of flood-routed direct messages, tied to the messages
  /// they carry, so that every further copy counts as one retransmission.
  final DirectFloodRepeats _directFloodRepeats = DirectFloodRepeats();

  /// A flood copy of a TXT_MSG heard in the RX log: one more retransmission
  /// of the direct message it is tied to, if it is tied to one, that
  /// message's region, read off the copy, and the route the copy took.
  void _countDirectFloodCopy(
    _RawPacket packet, {
    required double? snr,
    required int? rssi,
  }) {
    final copy = (
      pathBytes: packet.pathBytes,
      pathHashWidth: packet.pathHashWidth,
      snr: snr,
      rssi: rssi,
    );
    final decrypted = _directFloodIdentity(packet.payload);
    final hit = _directFloodRepeats.observe(
      payload: packet.payload,
      hopCount: packet.hopCount,
      at: DateTime.now(),
      copy: copy,
      transportCode: packet.transportCode1,
      identity: decrypted?.identity,
      attempt: decrypted?.attempt,
    );
    if (hit == null) return;
    _updateStoredContactMessage(
      hit.target.conversationKey,
      hit.target.messageId,
      (current) => _withDirectFloodCopy(
        current,
        relays: 1,
        transportCode: packet.transportCode1,
        payload: packet.payload,
        copies: [copy],
        currentAttempt: hit.currentAttempt,
      ),
    );
  }

  /// Who a flood copy is between and when it was sent, read with the node's
  /// key while direct echo recovery keeps one; null otherwise. Our own copy
  /// is addressed to a contact and a copy to us comes from one, and the
  /// shared secret is the same in both directions.
  ({String identity, int attempt})? _directFloodIdentity(Uint8List payload) {
    if (!_directEchoRecoveryEnabled || !_directEchoKeys.hasKey) return null;
    final self = _selfPublicKey;
    if (self == null || self.isEmpty || payload.length < 4) return null;
    final destinationHash = payload[0];
    final sourceHash = payload[1];
    final peerHashes = [
      if (sourceHash == self[0]) destinationHash,
      if (destinationHash == self[0]) sourceHash,
    ];
    if (peerHashes.isEmpty) return null;
    final encrypted = Uint8List.fromList(payload.sublist(2));
    for (final peerHash in peerHashes) {
      final peers = DirectEchoRecovery.candidateSenders(
        allContactsUnfiltered,
        peerHash,
      );
      for (final peer in peers) {
        final secret = _directEchoKeys.secretFor(peer);
        if (secret == null) continue;
        final plaintext = _decryptPayload(secret, encrypted);
        // The MAC is two bytes long, so a text type out of range means the
        // wrong peer passed it by chance.
        if (plaintext == null ||
            plaintext.length < 5 ||
            (plaintext[4] >> 2) > txtTypeSigned) {
          continue;
        }
        final timestamp =
            plaintext[0] |
            (plaintext[1] << 8) |
            (plaintext[2] << 16) |
            (plaintext[3] << 24);
        return (
          identity: DirectFloodRepeats.identityOf(peer.publicKeyHex, timestamp),
          attempt: _directFloodAttemptOf(plaintext),
        );
      }
    }
    return null;
  }

  /// The attempt number `composeMsgPacket` wrote into a decrypted TXT_MSG:
  /// the low two bits of the flags byte, or, past three, the whole number
  /// the firmware appends after the text's terminator.
  static int _directFloodAttemptOf(Uint8List plaintext) {
    final attempt = plaintext[4] & 0x03;
    final terminator = plaintext.indexOf(0, 5);
    if (terminator >= 0 &&
        terminator + 1 < plaintext.length &&
        plaintext[terminator + 1] > 3) {
      return plaintext[terminator + 1];
    }
    return attempt;
  }

  /// A flood send the node confirmed: its relays will reach the RX log.
  void _expectDirectFloodRelays(({Message message, Contact contact})? sent) {
    final self = _selfPublicKey;
    if (sent == null ||
        self == null ||
        self.isEmpty ||
        sent.contact.publicKey.isEmpty) {
      return;
    }
    final contactKeyHex = sent.contact.publicKeyHex;
    _directFloodRepeats.expectOutgoing(
      target: (
        conversationKey: contactKeyHex,
        messageId: sent.message.messageId,
      ),
      destinationHash: sent.contact.publicKey[0],
      sourceHash: self[0],
      identity: DirectFloodRepeats.identityOf(
        contactKeyHex,
        sent.message.timestamp.millisecondsSinceEpoch ~/ 1000,
      ),
      attempt: sent.message.retryCount,
      at: DateTime.now(),
    );
  }

  /// A flood send the node confirmed goes out under the contact's own region
  /// when one is set, else under the node's default scope. That is the region
  /// the message shows until a relayed copy of the packet says exactly. It
  /// replaces the region of an earlier attempt, but not one already read off
  /// a copy of this attempt, which can arrive while the default scope loads.
  Future<void> _stampDirectFloodSend(
    ({Message message, Contact contact}) sent,
  ) async {
    if (sent.contact.publicKey.isEmpty) return;
    final choice = getContactRegion(sent.contact.publicKeyHex);
    // An unscoped send has no region, and says so, unless the firmware
    // refused the flag and sent the packet under its default scope after all.
    final unscoped =
        ContactRegionStore.isUnscoped(choice) && !_unscopedSendUnsupported;
    final ownRegion = ContactRegionStore.isUnscoped(choice) ? '' : choice;
    if (!unscoped &&
        ownRegion.isEmpty &&
        !_hasLoadedDefaultRegionScope &&
        isConnected) {
      await _refreshDefaultRegionScope();
    }
    final scopeKnown =
        unscoped || ownRegion.isNotEmpty || _hasLoadedDefaultRegionScope;
    final region = unscoped
        ? null
        : _displayPacketRegion(
            ownRegion.isNotEmpty ? ownRegion : _defaultRegionScope ?? '',
          );
    final readOffCopy = _directFloodRepeats.heardCopyOf(
      target: (
        conversationKey: sent.contact.publicKeyHex,
        messageId: sent.message.messageId,
      ),
      attempt: sent.message.retryCount,
    );
    _updateStoredContactMessage(
      sent.contact.publicKeyHex,
      sent.message.messageId,
      (current) {
        final flooded = current.copyWith(sentByFlood: true);
        if (!scopeKnown || readOffCopy) return flooded;
        return flooded.copyWith(
          packetRegion: region,
          packetRegionInfoAvailable: true,
          packetRegionNotMatched: false,
        );
      },
    );
  }

  /// Ties a message the node delivered by flood to the copies of it already
  /// heard: the relays among them, and the packet's region.
  DirectFloodBinding? _bindDirectFloodDelivery(
    Message message,
    Contact contact,
    int hops,
  ) {
    final self = _selfPublicKey;
    if (self == null || self.isEmpty || contact.publicKey.isEmpty) return null;
    return _directFloodRepeats.bindIncoming(
      target: (
        conversationKey: message.senderKeyHex,
        messageId: message.messageId,
      ),
      sourceHash: contact.publicKey[0],
      destinationHash: self[0],
      hopCount: hops,
      identity: DirectFloodRepeats.identityOf(
        contact.publicKeyHex,
        message.timestamp.millisecondsSinceEpoch ~/ 1000,
      ),
      at: DateTime.now(),
    );
  }

  /// [message] with the routes of the heard [copies] added to its
  /// observations and, when they belong to its latest attempt, [relays] more
  /// retransmissions and the region of the packet, resolved from its first
  /// transport code (null for a plain flood) and the [payload] that code was
  /// computed over. The copy is the packet itself, so its region replaces
  /// whatever the message assumed; a copy of an earlier attempt leaves the
  /// count and the region alone, since both describe the latest packet.
  Message _withDirectFloodCopy(
    Message message, {
    required int relays,
    required int? transportCode,
    required Uint8List payload,
    required List<DirectFloodCopy> copies,
    required bool currentAttempt,
  }) {
    var observations = message.floodPathObservations;
    for (final copy in copies) {
      observations = ChannelPathSignalHelper.includeReading(
        observations: observations,
        pathBytes: copy.pathBytes,
        snr: copy.snr,
        rssi: copy.rssi,
      );
    }
    final withRoutes = message.copyWith(
      floodPathObservations: observations,
      floodPathHashWidth:
          message.floodPathHashWidth ??
          (copies.isEmpty ? null : copies.first.pathHashWidth),
    );
    if (!currentAttempt) return withRoutes;
    final region = _resolveTransportCodeRegion(
      transportCode,
      payloadTypeTXTMSG,
      payload,
    );
    return withRoutes.copyWith(
      sentByFlood: true,
      repeatCount: message.repeatCount + relays,
      packetRegion: region.region,
      packetRegionInfoAvailable: true,
      packetRegionNotMatched: region.notMatched,
    );
  }

  /// The hops a CONTACT_MSG_RECV frame reports for a message that came by
  /// flood, or null for one that came along a direct route (path byte 0xFF).
  static int? _floodHopCountOf(Uint8List frame) {
    if (frame.isEmpty) return null;
    final pathOffset = switch (frame[0]) {
      respCodeContactMsgRecvV3 => 10,
      respCodeContactMsgRecv => 7,
      _ => -1,
    };
    if (pathOffset < 0 || frame.length <= pathOffset) return null;
    final pathLength = frame[pathOffset];
    return pathLength == 0xFF ? null : pathLength & 0x3F;
  }

  void _handleLogRxData(Uint8List frame) async {
    await _packetBackgroundWork.receive(() => _handleLogRxDataCore(frame));
  }

  Future<void> _handleLogRxDataCore(Uint8List frame) async {
    if (frame.length < 4) return;
    try {
      final reader = BufferReader(frame);
      reader.skipBytes(1); // push code
      // The only frame that reports both halves of the reading; the
      // channel-message responses carry SNR alone.
      final snr = reader.readInt8() / 4.0;
      final rssi = reader.readInt8();

      final raw = reader.readRemainingBytes();
      final packet = _parseRawPacket(raw);
      if (packet?.payloadType == payloadTypeACK) {
        _noteHeardAck(packet!);
        return;
      }
      if (packet?.payloadType == payloadTypeTXTMSG) {
        if (packet!.isFlood) {
          _countDirectFloodCopy(packet, snr: snr, rssi: rssi);
        }
        await _recoverDirectEcho(frame, snr: snr, rssi: rssi);
        return;
      }
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
          var decryptedBytes = _decryptPayload(channel.psk, encrypted);
          if (decryptedBytes == null) {
            // A copy cut by the frame limit fails the MAC. If it is the head
            // of one of our own packets, decode the packet we sent instead,
            // so path, signal and repeat counting take the ordinary route.
            final recovered = _recoverTruncatedChannelEcho(
              channel,
              encrypted,
              frameLength: frame.length,
            );
            // Another channel may share the one-byte hash.
            if (recovered == null) continue;
            decryptedBytes = _decryptPayload(channel.psk, recovered);
            if (decryptedBytes == null) continue;
          }
          if (packet.payloadType == _payloadTypeGroupData) {
            if (_countImageChunkRepeat(channel.index, decryptedBytes)) return;
            final packetRegion = _resolvePacketRegion(packet);
            final groupData = _groupDataOf(decryptedBytes);
            final heardKey =
                groupData == null || _channelCopiesTakeOldPath(channel.index)
                ? null
                : _computeChannelDataHash(
                    channel.index,
                    groupData.dataType,
                    groupData.payload,
                  );
            if (heardKey != null &&
                await _foldHeardChannelCopy(
                  heardKey,
                  channel.index,
                  receivedAt: DateTime.now(),
                  pathBytes: packet.pathBytes,
                  pathLength: packet.isFlood ? packet.hopCount : 0,
                  pathHashWidth: packet.pathHashWidth,
                  snr: snr,
                  rssi: rssi,
                  packetRegion: packetRegion.region,
                  packetRegionInfoAvailable: true,
                  packetRegionNotMatched: packetRegion.notMatched,
                )) {
              return;
            }
            final parsedMessage = _parseLogRxChannelData(
              packet,
              channel.index,
              decryptedBytes,
              snr: snr,
              rssi: rssi,
              packetRegion: packetRegion.region,
              packetRegionInfoAvailable: true,
              packetRegionNotMatched: packetRegion.notMatched,
            );
            if (parsedMessage == null) {
              if (heardKey != null) _heardChannelPackets.abandon(heardKey);
              return;
            }
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
            final isNew = await _addChannelMessage(
              channel.index,
              message,
              heardKey: heardKey,
            );
            _maybeIncrementChannelUnread(message, isNew: isNew);
            notifyListeners();
            if (isNew) {
              final translationResult = await translateChannelMessage(
                channel.index,
                message,
              );
              final label = channel.name.isEmpty
                  ? 'Channel ${channel.index}'
                  : channel.name;
              await _maybeNotifyChannelMessage(
                message,
                channelName: label,
                translationResult: translationResult,
              );
            }
            return;
          }

          if (decryptedBytes.length < 6) continue;
          final decrypted = BufferReader(decryptedBytes);

          final timestampRaw = decrypted.readUInt32LE();
          final txtType = decrypted.readByte();
          if ((txtType >> 2) != 0) {
            return;
          }

          final text = decrypted.readCString();
          final parsed = _splitSenderText(text);
          final packetRegion = _resolvePacketRegion(packet);
          // Recognised before decoding, by the text as it travelled.
          final heardKey = _channelCopiesTakeOldPath(channel.index)
              ? null
              : HeardChannelPackets.textKey(
                  channelIndex: channel.index,
                  timestampSeconds: timestampRaw,
                  senderName: parsed.senderName,
                  rawText: parsed.text,
                );
          if (heardKey != null &&
              await _foldHeardChannelCopy(
                heardKey,
                channel.index,
                receivedAt: DateTime.now(),
                pathBytes: packet.pathBytes,
                pathLength: packet.isFlood ? packet.hopCount : 0,
                pathHashWidth: packet.pathHashWidth,
                snr: snr,
                rssi: rssi,
                packetRegion: packetRegion.region,
                packetRegionInfoAvailable: true,
                packetRegionNotMatched: packetRegion.notMatched,
              )) {
            return;
          }
          final decoded = MessageTextCodec.tryDecodeKnownCompressionDetails(
            parsed.text,
          );
          final decodedText = decoded?.text ?? parsed.text;
          final compression = _incomingChannelTextCompression(
            parsed.text,
            decodedText,
            parsed.senderName,
          );
          final replyReference =
              _resolveMcmpReplyReference(channel.index, decoded?.mcmpMessage) ??
              _resolveChannelReplyAnchor(
                channel.index,
                decoded?.mcotxtMessage?.replyAuthorName,
                decoded?.mcotxtMessage?.replyTimestamp,
              );
          final contentHash = _computeContentHash(
            channel.index,
            timestampRaw,
            '${parsed.senderName}: $decodedText',
          );

          final logRxMcmpMessage = decoded?.mcmpMessage;
          final logRxMCOtxtMessage = decoded?.mcotxtMessage;
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
            containerTimestamp:
                logRxMcmpMessage?.timestamp ??
                    logRxMCOtxtMessage?.metadataTimestamp,
            containerSenderName: logRxMcmpMessage?.senderName,
            mcmpIsSigned: logRxMcmpMessage?.isSigned ?? false,
            mcmpSignature: logRxMcmpMessage?.signature,
            containerReplyAuthorName:
                logRxMcmpMessage?.replyAuthorName ??
                logRxMCOtxtMessage?.replyAuthorName,
            containerReplyTimestamp:
                logRxMcmpMessage?.replyTimestamp ??
                logRxMCOtxtMessage?.replyTimestamp,
            timestamp: DateTime.fromMillisecondsSinceEpoch(timestampRaw * 1000),
            receivedAt: DateTime.now(),
            isOutgoing: false,
            status: ChannelMessageStatus.sent,
            pathLength: packet.isFlood ? packet.hopCount : 0,
            pathHashWidth: packet.pathHashWidth,
            pathBytes: packet.pathBytes,
            snr: snr,
            rssi: rssi,
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
          final isNew = await _addChannelMessage(
            channel.index,
            message,
            heardKey: heardKey,
          );
          _maybeIncrementChannelUnread(message, isNew: isNew);
          notifyListeners();
          if (isNew) {
            final translationResult = await translateChannelMessage(
              channel.index,
              message,
            );
            final label = channel.name.isEmpty
                ? 'Channel ${channel.index}'
                : channel.name;
            await _maybeNotifyChannelMessage(
              message,
              channelName: label,
              translationResult: translationResult,
            );
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

  /// Hands an AEIC image chunk heard in the RX log to whoever counts repeats,
  /// and reports that the frame was one so the caller stops parsing it as a
  /// message.
  ///
  /// This is the only place a repeat of an image packet can be observed. The
  /// firmware does not deliver our own flood echo through the decoded
  /// channel-data path — it surfaces only here, in `PUSH_CODE_LOG_RX_DATA`,
  /// still encrypted, which is why the transport's own `fromSelf` outcome
  /// never fires for it. The decrypted body is
  /// `[dataType u16][len][payload]`, the same layout [_parseLogRxChannelData]
  /// reads.
  bool _countImageChunkRepeat(int channelIndex, Uint8List decryptedBytes) {
    if (decryptedBytes.length < 3) return false;
    final reader = BufferReader(decryptedBytes);
    final dataType = reader.readByte() | (reader.readByte() << 8);
    if (dataType != dataTypeAeicImage) return false;
    final dataLength = reader.readByte();
    // Claimed as an image frame either way: a truncated one is still not a
    // message, and handing it on would only produce a parse failure.
    if (dataLength > reader.remaining) return true;
    _onImageChunkRepeat?.call(reader.readBytes(dataLength), channelIndex);
    return true;
  }

  ChannelMessage? _parseLogRxChannelData(
    _RawPacket packet,
    int channelIndex,
    Uint8List decryptedBytes, {
    double? snr,
    int? rssi,
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
    final replyReference = _resolveAppDataReplyReference(
      channelIndex,
      appData,
    );
    final mcmpMessage = appData?.mcmpMessage;
    final mcotxtMessage = appData?.mcotxtMessage;
    final timestamp = mcmpMessage == null && mcotxtMessage == null
        ? decoded?.timestamp ?? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(
            (mcmpMessage?.timestamp ?? mcotxtMessage!.timestamp) * 1000,
          );
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
      containerTimestamp: mcmpMessage?.timestamp ?? mcotxtMessage?.metadataTimestamp,
      containerSenderName: mcmpMessage?.senderName ?? mcotxtMessage?.senderName,
      mcmpIsSigned: mcmpMessage?.isSigned ?? false,
      mcmpSignature: mcmpMessage?.signature,
      containerReplyAuthorName:
          mcmpMessage?.replyAuthorName ?? mcotxtMessage?.replyAuthorName,
      containerReplyTimestamp:
          mcmpMessage?.replyTimestamp ?? mcotxtMessage?.replyTimestamp,
      wasBinaryTransport: true,
      binaryPacketBytes: dataPayload.length,
      rawPayload: dataPayload,
      timestamp: timestamp,
      isOutgoing: false,
      status: ChannelMessageStatus.sent,
      pathLength: packet.isFlood ? packet.hopCount : 0,
      pathHashWidth: packet.pathHashWidth,
      pathBytes: packet.pathBytes,
      snr: snr,
      rssi: rssi,
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
      reader.skipBytes(1); // code
      final isFlood = reader.readByte() != 0;
      final ackHash = reader.readUInt32LE();
      final timeoutMs = reader.readUInt32LE();

      if (_handleRepeaterCommandSent(ackHash, timeoutMs)) {
        return;
      }

      final retryService = _retryService;
      if (retryService != null &&
          retryService.updateMessageFromSent(
            ackHash,
            timeoutMs,
            isFlood: isFlood,
          )) {
        if (isFlood) {
          final sent = retryService.sentMessageForAck(ackHash);
          _expectDirectFloodRelays(sent);
          if (sent != null) unawaited(_stampDirectFloodSend(sent));
        }
        return;
      }
      // Nobody claimed it, and it is left alone. A channel send is answered
      // with RESP_CODE_OK, never RESP_CODE_SENT, so an unclaimed SENT answers
      // a login, a request or a CLI command; handed to the oldest pending
      // channel message, it marked that one sent before it went out and
      // dropped it from the replay after a reconnect.
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
        final updated = message.copyWith(status: ChannelMessageStatus.sent);
        channelMessages[i] = updated;
        _retriableChannelMessageSends.remove(messageId);
        _pendingChannelSentQueue.remove(messageId);
        unawaited(_channelMessageStore.saveChannelMessage(entry.key, updated));
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
        final updated = message.copyWith(
          status: ChannelMessageStatus.failed,
          noRetransmissionWarningSeconds: null,
        );
        channelMessages[i] = updated;
        unawaited(_channelMessageStore.saveChannelMessage(entry.key, updated));
        notifyListeners();
        return;
      }
    }
  }

  void _handleOk() {
    final pendingAck = _pendingGenericAckQueue.takeOk();
    // A raw packet with a queue id is a channel text under the channel's
    // own sender name (see _channelTextFrame).
    if (pendingAck == null ||
        (pendingAck.commandCode != cmdSendChannelTxtMsg &&
            pendingAck.commandCode != cmdSendChannelData &&
            pendingAck.commandCode != cmdSendRawPacket) ||
        pendingAck.channelSendQueueId == null) {
      return;
    }

    final queueId = pendingAck.channelSendQueueId!;
    _pendingChannelSentQueue.remove(queueId);
    _syncRadioStatsSendPolling();
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

      if (_handleRepeaterCommandAck(ackHash, tripTimeMs)) {
        return;
      }

      // The acknowledgement packet itself, when the RX log showed it in
      // the frame before, names the attempt from the fifth on.
      final heard = _lastHeardAck;
      final ackAttemptByte =
          heard != null &&
              heard.ackHash == ackHash &&
              heard.atFrame == _companionFrameSequence - 1
          ? heard.attemptByte
          : null;
      // Handle ACK in retry service
      final acknowledged = _retryService?.handleAckReceived(
        ackHash,
        tripTimeMs,
        ackAttemptByte: ackAttemptByte,
      );
      // A send stopped by hand is no longer the retry service's, but its
      // acknowledgement is still worth the double tick.
      final stopped = _stoppedSendAcks.remove(ackHashToHex(ackHash));
      if (stopped != null) {
        _updateStoredContactMessage(
          stopped.contactKeyHex,
          stopped.messageId,
          (current) => current.copyWith(
            status: MessageStatus.delivered,
            deliveredAt: DateTime.now(),
            tripTimeMs: tripTimeMs,
            deliveryProgressCompletedSteps: current.deliveryProgressTotalSteps,
          ),
        );
        appLogger.info(
          'A send stopped by hand was acknowledged after all',
          tag: 'Connector',
        );
      }
      final delivered =
          acknowledged ??
          (stopped == null ? null : _stoppedAttempt(stopped, ackAttemptByte));
      if (delivered != null) {
        unawaited(
          _recordDeliveryRoute(
            delivered,
            confirmedAtFrame: _companionFrameSequence,
          ),
        );
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

  /// The attempt of a stopped send an acknowledgement answers, picked among
  /// the attempts sharing the hash as the retry service picks one.
  AcknowledgedAttempt _stoppedAttempt(
    _StoppedSend stopped,
    int? ackAttemptByte,
  ) {
    final attempts = stopped.attempts;
    final index = MessageRetryService.acknowledgedAttemptIndex(
      [for (final attempt in attempts) attempt.attempt],
      ackAttemptByte,
    );
    return (
      messageId: stopped.messageId,
      contactKeyHex: stopped.contactKeyHex,
      selection: index < attempts.length ? attempts[index].selection : null,
    );
  }

  void _noteHeardAck(_RawPacket packet) {
    final payload = packet.payload;
    if (payload.length < 4) return;
    _lastHeardAck = (
      ackHash:
          payload[0] |
          (payload[1] << 8) |
          (payload[2] << 16) |
          (payload[3] << 24),
      attemptByte: payload.length >= 5 ? payload[4] : null,
      atFrame: _companionFrameSequence,
    );
  }

  /// Writes the route [delivered] was delivered along into the message
  /// (`Message.deliveryPathBytes`), once its acknowledgement named the
  /// attempt. The acknowledgement's carrier decides which route that is.
  /// One that came inside a path return answers a flood: the recipient
  /// returned the path our packet took, the node reports it as
  /// PUSH_CODE_PATH_UPDATED in the frame right before
  /// PUSH_CODE_SEND_CONFIRMED (`onContactPathRecv` writes the two in a row),
  /// and the route is what the re-read that push started brings back. A
  /// bare acknowledgement answers an attempt sent along a route, and the
  /// route is that attempt's, as the retry service kept it under the ACK
  /// hash, not the contact's current one, which may be a later attempt's.
  /// The firmware hashes only the two low bits of the attempt number, so
  /// attempts k and k+4 share a hash: the carrier tells the usual pair
  /// apart, the first attempt from the auto-flood last one, and two routed
  /// attempts four apart, which rotation can produce from the sixth attempt
  /// on, are told apart by the acknowledgement packet's attempt byte, read
  /// from the RX log ([_lastHeardAck]). When nothing can be read, the
  /// message keeps no route rather than a guess.
  Future<void> _recordDeliveryRoute(
    AcknowledgedAttempt delivered, {
    required int confirmedAtFrame,
  }) async {
    final Uint8List route;
    final int width;
    final String source;
    final returned = _lastReturnedRoute;
    if (returned != null &&
        returned.contactKeyHex == delivered.contactKeyHex &&
        returned.atFrame == confirmedAtFrame - 1) {
      final contact = await returned.contact;
      if (contact == null || contact.pathLength < 0) {
        appLogger.info(
          'Delivery confirmed by a path return whose route could not be '
          'read back; the message keeps no delivery route',
          tag: 'Connector',
        );
        return;
      }
      route = Uint8List.fromList(contact.path);
      width = contact.pathHashWidth;
      source = 'the route the recipient returned';
    } else {
      final selection = delivered.selection;
      if (selection == null ||
          selection.useFlood ||
          (selection.hopCount > 0 && selection.pathBytes.isEmpty)) {
        appLogger.info(
          'Delivery confirmed by a bare acknowledgement of an attempt with '
          'no route known; the message keeps no delivery route',
          tag: 'Connector',
        );
        return;
      }
      route = Uint8List.fromList(selection.pathBytes);
      width = selection.hopCount > 0
          ? Contact.inferPathHashWidth(selection.hopCount, route.length)
          : _pathHashByteWidth;
      source = 'the route of the attempt';
    }
    _updateStoredContactMessage(
      delivered.contactKeyHex,
      delivered.messageId,
      (current) => current.deliveryPathBytes != null
          ? current
          : current.copyWith(
              deliveryPathBytes: route,
              deliveryPathHashWidth: width,
            ),
    );
    final hex = route.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final hops = route.isEmpty
        ? 'no repeaters'
        : '${route.length ~/ width} hops, $hex';
    appLogger.info('Delivery confirmed along $source: $hops', tag: 'Connector');
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

  Future<void> _handleChannelInfo(Uint8List frame) =>
      _channelSyncWork.run(() => _handleChannelInfoCore(frame));

  Future<void> _handleChannelInfoCore(Uint8List frame) async {
    final channel = Channel.fromFrame(frame);
    if (channel == null) return;
    _unconfirmedChannelSlots.remove(channel.index);

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

    // A slot that holds another channel now, or none, cannot finish an image
    // the previous one started: its in-progress streams go, so a new image
    // there is never completed with the old channel's chunks.
    final previousAtIndex = _previousChannelsCache.cast<Channel?>().firstWhere(
      (entry) => entry?.index == channel.index,
      orElse: () => null,
    );
    if (previousAtIndex != null &&
        !previousAtIndex.isEmpty &&
        !listEquals(previousAtIndex.psk, channel.psk)) {
      _imageTransport?.reassembler.clearChannel(channel.index);
      _forgetImageSlot?.call(channel.index);
    }

    if (channel.isEmpty) {
      _registerChannelStorageBinding(channel);
      _channelMessages.remove(channel.index);
      _channelMcmpEnabled.remove(channel.index);
      _channelMcmpVersion.remove(channel.index);
      _channelMcmpUseSign.remove(channel.index);
      _channelSenderNames.remove(channel.index);
      _channelMCOtxtEnabled.remove(channel.index);
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

  /// Reached for every contact on each rebuild of the contacts list, through
  /// the unread counts, so it looks the key up instead of scanning.
  bool _shouldTrackUnreadForContactKey(String contactKeyHex) {
    final contact = _contacts.byKey(contactKeyHex);
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

  bool hidesChannelMessageWidget(ChannelMessage message, int channelIndex) {
    return BlockedSenders.instance.hidesMessageWidget(
      message,
      _channelDisplayName(channelIndex),
    );
  }

  bool mcoX4(Uint8List frame) {
    if (frame.isEmpty) return false;
    try {
      ChannelMessage? message;
      int? channelIndex;
      switch (frame.first) {
        case respCodeChannelMsgRecv:
        case respCodeChannelMsgRecvV3:
          message = ChannelMessage.fromFrame(frame);
          channelIndex = message?.channelIndex;
          break;
        case respCodeChannelDataRecv:
          final dataFrame = parseChannelDataReceivedFrame(frame);
          if (dataFrame == null) return false;
          message = _proxyFilterChannelDataMessage(
            dataFrame.channelIndex,
            dataFrame.dataType,
            dataFrame.payload,
          );
          channelIndex = dataFrame.channelIndex;
          break;
        case pushCodeLogRxData:
          return _hidesProxyLogRxFrame(frame);
        default:
          return false;
      }
      if (message == null || channelIndex == null) return false;
      return hidesChannelMessageWidget(message, channelIndex);
    } catch (_) {
      return false;
    }
  }

  ChannelMessage? _proxyFilterChannelDataMessage(
    int channelIndex,
    int dataType,
    Uint8List payload,
  ) {
    final decoded = ChannelBinaryDataHelper.tryDecodeInbound(
      dataType: dataType,
      payload: payload,
    );
    final appDecoded = decoded == null
        ? ChannelBinaryDataHelper.tryDecodeAppData(
            dataType: dataType,
            payload: payload,
          )
        : null;
    if (decoded == null && appDecoded == null) return null;
    final mcmpMessage = appDecoded?.mcmpMessage;
    final mcotxtMessage = appDecoded?.mcotxtMessage;
    final timestamp = mcmpMessage == null && mcotxtMessage == null
        ? decoded?.timestamp ?? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(
            (mcmpMessage?.timestamp ?? mcotxtMessage!.timestamp) * 1000,
          );
    return ChannelMessage(
      senderName: decoded?.senderName ?? appDecoded!.senderName,
      text: '',
      timestamp: timestamp,
      receivedAt: DateTime.now(),
      isOutgoing: false,
      status: ChannelMessageStatus.sent,
      channelIndex: channelIndex,
    );
  }

  bool _hidesProxyLogRxFrame(Uint8List frame) {
    if (frame.length < 4) return false;
    final reader = BufferReader(frame)..skipBytes(3);
    final packet = _parseRawPacket(reader.readRemainingBytes());
    if (packet == null ||
        (packet.payloadType != _payloadTypeGroupText &&
            packet.payloadType != _payloadTypeGroupData)) {
      return false;
    }
    final payload = BufferReader(packet.payload);
    final channelHash = payload.readByte();
    final encrypted = Uint8List.fromList(payload.readRemainingBytes());
    final channelsToSearch = _channels.isNotEmpty ? _channels : _cachedChannels;
    for (final channel in channelsToSearch) {
      if (channel.isEmpty || _computeChannelHash(channel.psk) != channelHash) {
        continue;
      }
      final decryptedBytes = _decryptPayload(channel.psk, encrypted);
      if (decryptedBytes == null) return false;
      ChannelMessage? message;
      if (packet.payloadType == _payloadTypeGroupData) {
        message = _parseLogRxChannelData(packet, channel.index, decryptedBytes);
      } else {
        if (decryptedBytes.length < 6) return false;
        final decrypted = BufferReader(decryptedBytes);
        final timestamp = decrypted.readUInt32LE();
        final txtType = decrypted.readByte();
        if ((txtType >> 2) != 0) return false;
        final sender = _splitSenderText(decrypted.readCString()).senderName;
        message = ChannelMessage(
          senderName: sender,
          text: '',
          timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
          receivedAt: DateTime.now(),
          isOutgoing: false,
          status: ChannelMessageStatus.sent,
          channelIndex: channel.index,
        );
      }
      return message != null &&
          hidesChannelMessageWidget(message, channel.index);
    }
    return false;
  }

  void _handleBlockedSendersChanged() {
    if (BlockedSenders.instance.lastChangeRequiresMessageStamp) {
      unawaited(applyBlockedSenderRules());
    }
    notifyListeners();
  }

  /// Permanently stamps messages reached by a newly created or widened block.
  ///
  /// Whole-row visibility is deliberately absent here: its eye switch is read
  /// dynamically and never rewrites channel history.
  Future<void> applyBlockedSenderRules({int? channelIndex}) async {
    if (BlockedSenders.instance.rules.isEmpty) return;
    var changed = false;
    for (final entry in _channelMessages.entries) {
      if (channelIndex != null && entry.key != channelIndex) continue;
      final label = _channelDisplayName(entry.key);
      final messages = entry.value;
      var touched = false;
      for (var i = 0; i < messages.length; i++) {
        final message = messages[i];
        if (message.wasBlocked) continue;
        if (!BlockedSenders.instance.hidesStoredMessage(message, label)) {
          continue;
        }
        messages[i] = message.copyWith(wasBlocked: true);
        touched = true;
      }
      if (!touched) continue;
      changed = true;
      await _channelMessageStore.saveChannelMessages(entry.key, messages);
    }
    if (changed) notifyListeners();
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
    // The rule, not the flag: this runs before `_addChannelMessage` stamps its
    // own copy. Without it a muted flooder drives a badge that never stops
    // climbing and feeds the app icon through `getTotalUnreadCount`.
    if (BlockedSenders.instance.isSenderBlocked(
      message,
      _channelDisplayName(channelIndex),
    )) {
      _appDebugLogService?.info(
        'Skip unread increment: sender is blocked',
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

  Future<void> _addMessage(String pubKeyHex, Message message) async {
    if (!message.isCli) {
      _updateContactLastMessageAt(
        pubKeyHex,
        message.isOutgoing
            ? message.timestamp
            : message.receivedAt ?? DateTime.now(),
      );
    }
    _conversations.putIfAbsent(pubKeyHex, () => []);
    final messages = _conversations[pubKeyHex]!;

    // Parse reaction info
    final reactionInfo = Message.parseReaction(message.text);
    if (reactionInfo != null) {
      // Check if we've already processed this exact reaction
      _processedContactReactions.putIfAbsent(pubKeyHex, () => {});
      reactionInfo.senderName = _resolveContactSenderName(message, null, false);
      final reactionIdentifier = reactionInfo.identifier();
      final isDuplicate = _processedContactReactions[pubKeyHex]!.contains(
        reactionIdentifier,
      );
      if (isDuplicate) return;

      // New reaction - process it
      // For hashing and dup checking, we use null for sender names in
      // normal 1:1 chats. This way if we and they have different ideas
      // about what their name is, reactions still work. But for reaction
      // reports, we want to know who sent what, rather than infer it later,
      // so we'll add it to the reactionInfo before storing it.
      reactionInfo.senderName ??= message.isOutgoing
          ? selfName
          : getContactByPubKeyHex(pubKeyHex)?.name ?? '???';
      final changedMessage = _processContactReaction(
        messages,
        reactionInfo,
        pubKeyHex,
      );
      if (changedMessage != null) {
        appLogger.info('Adding reaction, id: $reactionIdentifier');
        await _messageStore.saveMessage(pubKeyHex, changedMessage);

        // Mark as processed
        _processedContactReactions[pubKeyHex]!.add(reactionIdentifier);

        notifyListeners();
        return; // Don't add reaction as a visible message
      }

      // Looks like a reaction, but didn't match any message we have.
      // for reactions matching our own format, because those are not very
      // informative on their own, but the MC1 format is useful even if
      // in raw form, so we'll let those through.
      appLogger.info('No match for reaction, id: $reactionIdentifier');
      if (reactionInfo.hashType == HashType.ours) return;
    }

    messages.add(message);
    if (_isRoomConversation(pubKeyHex)) {
      messages.sort(RoomMessageTimelineHelper.compare);
    }
    if (_activeContactKey != pubKeyHex) {
      _trimContactHistoryWindow(pubKeyHex);
    }
    await _messageStore.saveMessage(pubKeyHex, message);
    notifyListeners();
  }

  Message? _processContactReaction(
    List<Message> messages,
    ReactionInfo reactionInfo,
    String contactPubKeyHex,
  ) {
    final contact = getContactByPubKeyHex(contactPubKeyHex);
    final isRoomServer = contact?.type == advTypeRoom;

    Message? changedMessage;
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
        changedMessage = messages[i];
      },
    );
    return changedMessage;
  }

  Message? _processOutgoingContactReaction(
    List<Message> messages,
    ReactionInfo reactionInfo,
    Contact contact,
  ) {
    final isRoomServer = contact.type == advTypeRoom;

    Message? changedMessage;
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
        changedMessage = messages[i];
      },
    );
    return changedMessage;
  }

  Message? _setReactionStatus(
    String pubKeyHex,
    ReactionInfo reactionInfo,
    MessageStatus status,
  ) {
    final messages = _conversations[pubKeyHex];
    if (messages == null) return null;
    final contact = getContactByPubKeyHex(pubKeyHex);
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
        return messages[i];
      }
    }
    return null;
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
      final pathByteLen = decodePathByteLen(pathLenRaw);
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
    return _channelKeyHashCache.hash(psk);
  }

  _PacketRegionResolution _resolvePacketRegion(_RawPacket packet) =>
      _resolveTransportCodeRegion(
        packet.transportCode1,
        packet.payloadType,
        packet.payload,
      );

  /// The region whose transport code for a packet of [payloadType] carrying
  /// [payload] is [transportCode]: one of the known regions, or the node's
  /// default scope, which need not be in that list and is what a flood direct
  /// message goes out under.
  _PacketRegionResolution _resolveTransportCodeRegion(
    int? transportCode,
    int payloadType,
    Uint8List payload,
  ) {
    if (transportCode == null || transportCode == 0) {
      return const _PacketRegionResolution();
    }

    for (final region in [
      ...RegionStore().loadRegions(),
      ?_defaultRegionScope,
    ]) {
      final normalized = region.trim();
      if (normalized.isEmpty || normalized.startsWith(r'$')) continue;
      final regionTransportCode = _computeRegionTransportCode(
        normalized,
        payloadType,
        payload,
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
  ) => ChannelRawPacket.regionTransportCode(region, payloadType, payload);

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

  /// Stores [message], new or merged into the copy of it already there, and
  /// returns whether it was new. Under [heardKey], the claim the copy holds
  /// in the heard map is settled with what the message became, and abandoned
  /// when nothing was stored or applied, a failure included.
  Future<bool> _addChannelMessage(
    int channelIndex,
    ChannelMessage message, {
    bool awaitPersistence = true,
    String? heardKey,
  }) async {
    if (heardKey == null) {
      return _storeChannelMessage(
        channelIndex,
        message,
        awaitPersistence: awaitPersistence,
      );
    }
    final claim = HeardChannelClaim(_heardChannelPackets, heardKey);
    try {
      return await _storeChannelMessage(
        channelIndex,
        message,
        awaitPersistence: awaitPersistence,
        claim: claim,
      );
    } finally {
      claim.abandonIfOpen();
    }
  }

  Future<bool> _storeChannelMessage(
    int channelIndex,
    ChannelMessage message, {
    bool awaitPersistence = true,
    HeardChannelClaim? claim,
  }) async {
    _channelMessages.putIfAbsent(channelIndex, () => []);
    final messages = _channelMessages[channelIndex]!;

    final blockedNow = BlockedSenders.instance.isSenderBlocked(
      message,
      _channelDisplayName(channelIndex),
    );

    // Parse reaction info
    final reactionInfo = message.parseReaction();
    if (reactionInfo != null) {
      // A blocked sender's text never acts. A reaction has no body to hide —
      // it lands on somebody else's message — so it is dropped outright and
      // never stored, which is why unblocking cannot bring it back either.
      if (blockedNow) return false;
      // Check if we've already processed this exact reaction
      _processedChannelReactions.putIfAbsent(channelIndex, () => {});
      final reactionIdentifier = reactionInfo.identifier();

      final isDuplicate = _processedChannelReactions[channelIndex]!.contains(
        reactionIdentifier,
      );

      if (isDuplicate) {
        claim?.settle(const HeardAsReaction());
        return false;
      }

      // New reaction - process it
      final changedMessage = _processReaction(messages, reactionInfo);
      if (changedMessage != null) {
        // Settled before the write: a copy arriving during it is a copy of
        // an applied reaction and has nothing to add.
        claim?.settle(const HeardAsReaction());
        appLogger.info('Adding channel reaction, id: $reactionIdentifier');
        await _channelMessageStore.saveChannelMessage(
          channelIndex,
          changedMessage,
        );

        // Mark as processed
        _processedChannelReactions[channelIndex]!.add(reactionIdentifier);
        return false; // Don't add reaction as a visible message
      }
      // Looks like a reaction, but didn't match any message we have.
      // Old behavior is to silently drop these. We'll continue doing that
      // for reactions matching our own format, because those are not very
      // informative on their own, but the MC1 format is useful even if
      // in raw form, so we'll let those through.
      appLogger.info('No match for reaction, id: $reactionIdentifier');
      if (reactionInfo.hashType == HashType.ours) return false;
    }

    // Parse reply info from message text
    final replyInfo = ChannelMessage.parseReplyMention(message.text);
    // Anything that is stored carries the flag, so a marker or a `del:`
    // command that arrived while its sender was muted stays inert for good.
    ChannelMessage processedMessage = blockedNow
        ? message.copyWith(wasBlocked: true)
        : message;

    if (processedMessage.containerReplyTimestamp != null &&
        processedMessage.replyToMessageId == null &&
        processedMessage.replyToText == null) {
      final containerReference = _resolveChannelReplyAnchor(
        channelIndex,
        processedMessage.containerReplyAuthorName,
        processedMessage.containerReplyTimestamp,
      );
      if (containerReference != null) {
        processedMessage = processedMessage.copyWith(
          replyToMessageId: containerReference.messageId,
          replyToSenderName:
              processedMessage.replyToSenderName ??
              containerReference.senderName,
          replyToText: containerReference.text,
        );
      }
    }

    final hasExplicitReplyContext =
        processedMessage.replyToMessageId != null ||
        processedMessage.replyToSenderName != null ||
        processedMessage.replyToText != null ||
        processedMessage.containerReplyTimestamp != null;
    if (replyInfo != null &&
        (!processedMessage.isOutgoing || hasExplicitReplyContext)) {
      final replySource = processedMessage;
      var replyToMessageId = replySource.replyToMessageId;
      var replyToSenderName = replySource.replyToSenderName;
      var replyToText = replySource.replyToText;

      // Plain-text replies may carry an exact-quote fragment (">first chars"
      // on its own line) so the mention resolves to the message it was
      // written for instead of merely the sender's newest one.
      //
      // ExactQuoteHelper owns every rule about when that line is matched and
      // when it is cut out; the two settings that govern quoting meet there
      // rather than here.
      final quoteSettings = _appSettingsService?.settings;
      final hasContainerAnchor = replySource.containerReplyTimestamp != null;
      final quotesAsMentions =
          !replySource.isOutgoing &&
          (quoteSettings?.incomingQuoteAsMentions ?? false);
      final exactQuote =
          ExactQuoteHelper.parsesFragment(
            quotesAsMentions: quotesAsMentions,
            exactQuoteEnabled: quoteSettings?.exactQuote ?? true,
            hasMcmpAnchor: hasContainerAnchor,
          )
          ? ExactQuoteHelper.resolveReply(
              body: replyInfo.actualMessage,
              mentionedNode: replyInfo.mentionedNode,
              history: messages,
              extraCharMaps: [
                for (final profile
                    in quoteSettings?.cyr2latProfiles ??
                        const <Cyr2LatProfile>[])
                  profile.charMap,
              ],
            )
          : null;
      final replyIsExact = exactQuote?.quoted != null;
      final messageBody =
          (ExactQuoteHelper.stripsFragment(
                quotesAsMentions: quotesAsMentions,
                fragmentResolved: replyIsExact,
              )
              ? exactQuote?.text
              : null) ??
          replyInfo.actualMessage;

      if ((replyToSenderName == null || replyToText == null) &&
          replySource.containerReplyTimestamp == null) {
        // Fallback for incoming/legacy messages where only the @mention
        // exists. Messages with a container reply anchor must never fall back to
        // "most recent from this sender": if the anchor did not resolve, a
        // name-only reply banner is more honest than a wrong quote.
        final originalMessage = exactQuote == null
            ? _findMessageBySender(messages, replyInfo.mentionedNode)
            : exactQuote.quoted;
        if (originalMessage != null) {
          replyToMessageId ??= originalMessage.messageId;
          replyToSenderName ??= originalMessage.senderName;
          replyToText ??= originalMessage.text;
        } else if (exactQuote != null) {
          // The quoted message never reached us. Show the fragment that did,
          // without a message id, so the quote stays visible but is not
          // tappable.
          replyToSenderName ??= replyInfo.mentionedNode;
          replyToText ??= exactQuote.fragment;
        }
      }

      // Create new message with reply metadata
      processedMessage = ChannelMessage(
        senderKey: replySource.senderKey,
        senderName: replySource.senderName,
        text: messageBody,
        originalText: replySource.originalText,
        translatedText: replySource.translatedText,
        translatedLanguageCode: replySource.translatedLanguageCode,
        translationStatus: replySource.translationStatus,
        translationModelId: replySource.translationModelId,
        wasMcmpCompressed: replySource.wasMcmpCompressed,
        compressionType: replySource.compressionType,
        compressionSavingsPercent: replySource.compressionSavingsPercent,
        compressionOriginalBytes: replySource.compressionOriginalBytes,
        compressionPayloadBytes: replySource.compressionPayloadBytes,
        mcmpSignatureStatus: replySource.mcmpSignatureStatus,
        containerTimestamp: replySource.containerTimestamp,
        containerSenderName: replySource.containerSenderName,
        mcmpIsSigned: replySource.mcmpIsSigned,
        mcmpSignature: replySource.mcmpSignature,
        containerReplyAuthorName: replySource.containerReplyAuthorName,
        containerReplyTimestamp: replySource.containerReplyTimestamp,
        verifiedSenderKeyHex: replySource.verifiedSenderKeyHex,
        mcmpNameCollision: replySource.mcmpNameCollision,
        wasBinaryTransport: replySource.wasBinaryTransport,
        wasBlocked: blockedNow || replySource.wasBlocked,
        binaryPacketBytes: replySource.binaryPacketBytes,
        rawText: replySource.rawText,
        rawPayload: replySource.rawPayload,
        timestamp: replySource.timestamp,
        receivedAt: replySource.receivedAt,
        sentByRadioAt: replySource.sentByRadioAt,
        isOutgoing: replySource.isOutgoing,
        status: replySource.status,
        repeats: replySource.repeats,
        repeatCount: replySource.repeatCount,
        pathLength: replySource.pathLength,
        pathHashWidth: replySource.pathHashWidth,
        pathBytes: replySource.pathBytes,
        pathVariants: replySource.pathVariants,
        pathObservations: replySource.pathObservations,
        channelIndex: replySource.channelIndex,
        packetRegion: replySource.packetRegion,
        packetRegionInfoAvailable: replySource.packetRegionInfoAvailable,
        packetRegionNotMatched: replySource.packetRegionNotMatched,
        noRetransmissionWarningSeconds:
            replySource.noRetransmissionWarningSeconds,
        messageId: replySource.messageId,
        packetHash: replySource.packetHash,
        replyToMessageId: replyToMessageId,
        replyToSenderName: replyToSenderName ?? replyInfo.mentionedNode,
        replyToText: replyToText,
        replyIsExact: replyIsExact,
        reactions: replySource.reactions,
        sourceLabel: replySource.sourceLabel,
      );
    }

    final existingIndex = _findChannelRepeatIndex(messages, processedMessage);
    var isNew = true;
    if (existingIndex >= 0) {
      isNew = false;
      _mergeChannelRepeat(messages, existingIndex, processedMessage);
      _wakeChannelHopCheck(messages[existingIndex].messageId);
    } else {
      messages.add(processedMessage);
    }

    final storedMessage = existingIndex >= 0
        ? messages[existingIndex]
        : processedMessage;
    // A reaction that matched nothing is stored as text but not settled, so
    // a later copy still looks for a target that arrived in between.
    if (reactionInfo == null) {
      claim?.settle(HeardAsMessage(storedMessage.messageId));
    }
    messages.sort(_compareChannelMessages);
    if (_activeChannelIndex != channelIndex) {
      _trimChannelHistoryWindow(channelIndex);
    }

    // Save only the row that was inserted or merged. An outgoing radio send
    // must not wait behind an unrelated history-write backlog: its in-memory
    // state is already complete, so persist it in the background and let the
    // send path continue.
    final persistence = _channelMessageStore.saveChannelMessage(
      channelIndex,
      storedMessage,
    );
    if (awaitPersistence) {
      await persistence;
    } else {
      unawaited(
        persistence.catchError((error, stackTrace) {
          appLogger.warn(
            'Could not persist outgoing channel message: '
            '$error\n$stackTrace',
            tag: 'MessageHistory',
          );
        }),
      );
    }
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

  ChannelMessage? _processReaction(
    List<ChannelMessage> messages,
    ReactionInfo reactionInfo,
  ) {
    ChannelMessage? changedMessage;
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
        changedMessage = messages[i];
        notifyListeners();
      },
    );
    return changedMessage;
  }

  /// Folds [incoming], a copy of the message at [existingIndex], into it:
  /// the route, the readings, the region and one more repeat, and the
  /// promotion of a pending send or of a proxied client's message to sent.
  /// Stores the merged message in [messages] and returns it.
  ChannelMessage _mergeChannelRepeat(
    List<ChannelMessage> messages,
    int existingIndex,
    ChannelMessage incoming,
  ) {
    final existing = messages[existingIndex];
    final mergedPathBytes = _selectPreferredPathBytes(
      existing.pathBytes,
      incoming.pathBytes,
    );
    final mergedPathVariants = _mergePathVariants(
      existing.pathVariants,
      incoming.pathVariants,
    );
    final mergedPathObservations = ChannelPathSignalHelper.merge(
      existing.pathObservations,
      incoming.pathObservations,
    );
    // The hash width belongs to the route: a message without one yet (our
    // own send, a message echoed into the history with no path) takes the
    // first copy's, and a route taken from a copy brings its own along. The
    // message's width used to win, and a two-byte route merged into a
    // message that claimed one byte read as twice the hops.
    final mergedWidthSource =
        identical(mergedPathBytes, incoming.pathBytes) &&
            incoming.pathBytes.isNotEmpty
        ? incoming.pathHashWidth ?? existing.pathHashWidth
        : existing.pathHashWidth ?? incoming.pathHashWidth;
    // The path bytes hold one hash per hop, so the observed hop count is the
    // byte count over the hash width the route was learned in.
    final mergedHashWidth = (mergedWidthSource ?? 1).clamp(1, 3).toInt();
    final mergedPathLength = _mergePathLength(
      existing.pathLength,
      incoming.pathLength,
      mergedPathBytes.length ~/ mergedHashWidth,
    );
    final newRepeatCount = existing.repeatCount + 1;
    final promotedFromPending =
        newRepeatCount == 1 && existing.status == ChannelMessageStatus.pending;
    final promotedFromClient =
        incoming.sourceLabel != null && !existing.isOutgoing;
    var merged = existing.copyWith(
      receivedAt: ChannelMessageTimelineHelper.earliestReceivedAt(
        existing,
        incoming,
      ),
      repeatCount: newRepeatCount,
      pathLength: mergedPathLength,
      pathHashWidth: mergedWidthSource,
      pathBytes: mergedPathBytes,
      pathVariants: mergedPathVariants,
      pathObservations: mergedPathObservations,
      packetRegion: existing.packetRegion ?? incoming.packetRegion,
      packetRegionInfoAvailable:
          existing.packetRegionInfoAvailable ||
          incoming.packetRegionInfoAvailable,
      packetRegionNotMatched:
          existing.packetRegionNotMatched || incoming.packetRegionNotMatched,
      packetHash: existing.packetHash ?? incoming.packetHash,
      isOutgoing: existing.isOutgoing || promotedFromClient,
      sourceLabel: existing.sourceLabel ?? incoming.sourceLabel,
      // Mark as sent when first repeat is heard
      status: promotedFromPending || promotedFromClient
          ? ChannelMessageStatus.sent
          : existing.status,
    );
    // Любое эхо снимает обычный warning, но shortfall — только при покрытии.
    if (!_retainChannelShortfallAfterEcho(merged)) {
      _cancelChannelNoRetransmissionWarning(existing.messageId);
      merged = merged.copyWith(noRetransmissionWarningSeconds: null);
    }
    messages[existingIndex] = merged;
    if (promotedFromPending) {
      _retriableChannelMessageSends.remove(existing.messageId);
      _pendingChannelSentQueue.remove(existing.messageId);
    }
    return merged;
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
    // Our message carries the name it went out under, the channel's own or
    // the node's (see channelSendName), and its echo carries the same.
    final isSelfEcho =
        existing.isOutgoing &&
        !incoming.isOutgoing &&
        incoming.senderName == existing.senderName;

    // This repeat detector intentionally does not use
    // AppSettings.defaultChannelResendTimeoutSeconds: manual resend delay and
    // radio self-echo deduplication are separate timing concerns.
    //
    // Another sender's copies all carry the packet's own second, so a
    // same-text message a second or more apart is another packet: a bot
    // answering a ping with the same text twice, a client resending by hand.
    // The thirty-second window that merged those went on 2026-10-13.
    final windowMs = isSelfEcho ? 10 * 60 * 1000 : 999;
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

  // Incoming channel messages under our own name are not filtered: the
  // upstream rule that dropped one arriving without path bytes also dropped
  // every message a node produces itself (TerminalCLI replies, its own
  // keyboard), since companion firmware never forwards path bytes, and our
  // own echo is merged into the outgoing message by _isChannelRepeat. The
  // setting below kept its key and now has only this send-side meaning.
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
    if (PlatformInfo.isIOS &&
        _activeTransport == MeshCoreTransportType.bluetooth) {
      _appDebugLogService?.warn(
        'Unexpected iOS BLE disconnect: '
        '${_iosBleSessionSnapshot(DateTime.now())}',
        tag: 'BLE iOS',
      );
    }
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
    _iosBleCentralSubscription?.cancel();
    _iosBleCentralSubscription = null;
    _usingIosNativeBleCentral = false;

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
    // _awaitingSelfInfo makes _requestDeviceInfo a no-op on the next connect.
    _awaitingSelfInfo = false;
    _hasCompletedSelfInfoHandshake = false;
    _selfInfoRetryTimer?.cancel();
    _selfInfoRetryTimer = null;
    _persistedStateLoadedKey = null;
    _batteryMillivolts = null;
    _batteryRequested = false;
    _pathHashByteWidth = 1;
    _maxContacts = _defaultMaxContacts;
    _maxChannels = _defaultMaxChannels;
    // The node may come back with other firmware, flashed while it was
    // away, and a successful reconnect never passes through disconnect().
    _directEchoAckUnsupported = false;
    _unscopedSendUnsupported = false;
    _resetSyncProgressState();
    _cancelAllChannelNoRetransmissionTimers();
    _pendingChannelSentQueue.clear();
    _pendingGenericAckQueue.clear();
    // Keep pending and already-started channel sends across an unexpected BLE
    // drop. They are replayed only after the replacement session is ready.
    _reactionSendQueueSequence = 0;
    // Conversations are kept for an auto-reconnect to the same radio;
    // _handleSelfInfo drops them if a different radio answers.

    _setState(MeshCoreConnectionState.disconnected);
    _scheduleReconnect();
  }

  /// Drops the conversation and channel history held in memory, so a
  /// different radio never shows or persists another radio's messages.
  void _clearSessionMessageState() {
    _conversations.clear();
    _loadedConversationKeys.clear();
    _channelMessages.clear();
    _processedChannelReactions.clear();
    _processedContactReactions.clear();
    _channelHopChecks.clear();
    _channelHopWakeups.clear();
    _channelHopShortfalls.clear();
    _channelResendRevision++;
    _messageStateOwnerKey = null;
    _persistedStateLoadedKey = null;
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
    if (_disposed) return;
    if (_state != newState) {
      _state = newState;
      _settingsSectionsService?.mcoX3(
        newState == MeshCoreConnectionState.connected,
      );
      if (newState == MeshCoreConnectionState.connected) {
        _isRecoveringConnection = false;
        unawaited(_transportPreferenceStore.save(_activeTransport.name));
        if (_appSettingsService?.settings.notificationsEnabled ?? false) {
          unawaited(_notificationService.requestPermissionsOnce());
        }
      }
      notifyListeners();
    }
  }

  // Служебные listeners читают не только state: доступность соединения/статистики,
  // ручной разрыв, restart, offline и готовность сохраняют прежнее окно 50 мс.
  Object get _notificationConnectionState => (
    _state, isConnected, supportsCompanionRadioStats,
    _activeTransport, _manualDisconnect, _isRecoveringConnection,
    _transportRestartInProgress, _isOfflineMode, _isOfflineSharedMode,
    _offlineHistoryScope, _deviceId, selfPublicKeyHex,
    hasCompletedSelfInfoHandshake, isSessionReady,
  );

  void markNotifyDirty() {
    if (_disposed) return;
    _syncRadioStatsSendPolling();
    final connection = _notificationConnectionState;
    final priority = connection != _lastNotifyConnectionState;
    _lastNotifyConnectionState = connection;
    _uiNotifications.mark(priority: priority);
  }

  void _flushBatchedNotify() {
    if (_disposed) return;
    _uiRevision++;
    super.notifyListeners();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    markNotifyDirty();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!PlatformInfo.isIOS) return;
    final now = DateTime.now();
    final previous = _lastAppLifecycleState;
    final elapsed = _lastAppLifecycleStateAt == null
        ? null
        : now.difference(_lastAppLifecycleStateAt!);
    _lastAppLifecycleState = state;
    _lastAppLifecycleStateAt = now;
    if (_activeTransport == MeshCoreTransportType.bluetooth ||
        _reconnectTransport == MeshCoreTransportType.bluetooth) {
      _appDebugLogService?.info(
        'iOS lifecycle ${previous?.name ?? 'unknown'} -> ${state.name}'
        '${elapsed == null ? '' : ' after ${_formatDebugDuration(elapsed)}'} '
        'state=${_state.name} reconnect=$_shouldAutoReconnect',
        tag: 'BLE iOS',
      );
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_probeIosBleAfterResume(now));
    }
  }

  Future<void> _probeIosBleAfterResume(DateTime resumedAt) async {
    if (!PlatformInfo.isIOS ||
        !isConnected ||
        _activeTransport != MeshCoreTransportType.bluetooth ||
        _iosBleResumeProbeInFlight) {
      return;
    }
    final lastRx = _lastBleRxAt ?? _lastRxTime;
    if (resumedAt.difference(lastRx) < const Duration(seconds: 30)) {
      return;
    }
    _iosBleResumeProbeInFlight = true;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    try {
      if (!isConnected || _activeTransport != MeshCoreTransportType.bluetooth) {
        return;
      }
      final probeStartedAt = DateTime.now();
      _appDebugLogService?.info(
        'iOS BLE resume probe: ${_iosBleSessionSnapshot(probeStartedAt)}',
        tag: 'BLE iOS',
      );
      await sendFrame(buildGetDeviceTimeFrame());
      await Future<void>.delayed(const Duration(seconds: 5));
      final lastRxAfterProbe = _lastBleRxAt ?? _lastRxTime;
      if (isConnected &&
          _activeTransport == MeshCoreTransportType.bluetooth &&
          !lastRxAfterProbe.isAfter(probeStartedAt)) {
        _appDebugLogService?.warn(
          'iOS BLE resume probe got no RX, forcing reconnect: '
          '${_iosBleSessionSnapshot(DateTime.now())}',
          tag: 'BLE iOS',
        );
        unawaited(disconnect(manual: false));
      }
    } catch (error) {
      _appDebugLogService?.warn(
        'iOS BLE resume probe failed, forcing reconnect: $error '
        '${_iosBleSessionSnapshot(DateTime.now())}',
        tag: 'BLE iOS',
      );
      unawaited(disconnect(manual: false));
    } finally {
      _iosBleResumeProbeInFlight = false;
    }
  }

  String _formatDebugDuration(Duration duration) {
    if (duration.inMilliseconds < 1000) {
      return '${duration.inMilliseconds}ms';
    }
    if (duration.inMinutes < 1) {
      return '${duration.inSeconds}s';
    }
    if (duration.inHours < 1) {
      return '${duration.inMinutes}m${duration.inSeconds.remainder(60)}s';
    }
    return '${duration.inHours}h${duration.inMinutes.remainder(60)}m';
  }

  String _formatDebugAge(DateTime? timestamp, DateTime now) {
    if (timestamp == null) return 'never';
    return _formatDebugDuration(now.difference(timestamp));
  }

  String _iosBleSessionSnapshot(DateTime now) {
    return 'lifecycle=${_lastAppLifecycleState?.name ?? 'unknown'} '
        'connectStarted=${_formatDebugAge(_lastBleConnectStartedAt, now)} '
        'connected=${_formatDebugAge(_lastBleConnectedAt, now)} '
        'lastRx=${_formatDebugAge(_lastBleRxAt, now)} '
        'lastTx=${_formatDebugAge(_lastBleTxAt, now)} '
        'autoReconnect=$_shouldAutoReconnect';
  }

  @override
  void dispose() {
    if (PlatformInfo.isIOS) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _appSettingsService?.removeListener(_handleAppSettingsChanged);
    _reconnectPowerSettings?.dispose();
    _appSettingsService?.removeListener(_syncPowerSavingSettings);
    _retryService?.pendingMessageCount.removeListener(_syncRadioStatsSendPolling);
    _radioStatsSendPolling.dispose();
    BlockedSenders.instance.removeListener(_handleBlockedSendersChanged);
    _clearDirectEchoKey('dispose');
    _channelKeyHashCache.clear();
    _disposed = true;
    _selfInfoWork.finishCurrent();
    MessageHistoryStorage.instance.detachBackgroundWorkTracker(_backgroundWork);
    _notificationService.detachBackgroundWorkTracker(_backgroundWork);
    _receivedImageStore?.detachBackgroundWorkTracker(_backgroundWork);
    _backgroundWork.close();
    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _connectionSubscription?.cancel();
    _usbFrameSubscription?.cancel();
    _notifySubscription?.cancel();
    _iosBleCentralSubscription?.cancel();
    _notificationReplySubscription?.cancel();
    _notificationService.releaseReplyPort();
    _uiNotifications.dispose();
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
    _radioStatsPollingOwners.dispose();
    repeaterActivity.dispose();
    _receivedFramesController.close();
    _mcmpSigningFailedController.close();
    _contactsFullController.close();
    _usbManager.dispose();
    _tcpConnector.dispose();
    unawaited(_backgroundService?.stop(reason: _backgroundTcpReason));
    unawaited(_backgroundService?.setTcpWifiLock(false));
    _reviewFrameSubscription?.cancel();
    _reviewRadio?.dispose();

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
      final pathByteLen = decodePathByteLen(pathLenRaw);
      final pathHashWidth = decodePathHashWidth(pathLenRaw);
      final pathBytes = packet.readBytes(pathByteLen);
      final payload = packet.readBytes(packet.remaining);

      if (payloadType == payloadTypeTRACE) {
        _recordTraceRepeaterActivity(pathBytes, payload, snr);
      } else {
        _recordRepeaterActivity(pathBytes, pathHashWidth, snr);
      }

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
      final pathByteLen = decodePathByteLen(pathLenRaw);
      pathHashWidth = decodePathHashWidth(pathLenRaw);
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
        pathHashWidth: pathHashWidth,
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
        pathHashWidth: pathHashWidth,
        latitude: latitude,
        longitude: longitude,
        lastSeen: DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
      );
      // The firmware decides whether to store it: PUSH_CODE_ADVERT (then
      // GET_CONTACT_BY_KEY) adds it to _contacts and notifies.
      final mayAutoAdd =
          (_autoAddUsers && type == advTypeChat) ||
          (_autoAddRepeaters && type == advTypeRepeater) ||
          (_autoAddRoomServers && type == advTypeRoom) ||
          (_autoAddSensors && type == advTypeSensor);
      _handleDiscovery(newContact, rawPacket, noNotify: mayAutoAdd);
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

      // The route stays the node's. An advert never changes the path the
      // node keeps for a contact (BaseChatMesh::onAdvertRecv), while every
      // copy of it, relayed or heard directly, reaches this log: written
      // here, the last copy heard became the route the contact was shown
      // with and the one the next send put on the node, and a copy heard
      // directly, having no path, turned a direct route into a flood. The
      // path the advert came along is still offered in the path history.
      // Every copy of an advert reaches this log, relayed or heard directly,
      // and all but the first carry nothing new for the contact. Replacing it
      // anyway bumped `contactsRevision` and rebuilt every contact row for
      // each copy; replacing only what changed keeps the revision, and the
      // notification that follows it, for a real change.
      final nextLatitude = hasLocation ? latitude : existing.latitude;
      final nextLongitude = hasLocation ? longitude : existing.longitude;
      final nextName = hasName ? name : existing.name;
      final nextLastSeen = DateTime.fromMillisecondsSinceEpoch(
        timestamp * 1000,
      );
      final changed =
          nextName != existing.name ||
          nextLatitude != existing.latitude ||
          nextLongitude != existing.longitude ||
          nextLastSeen != existing.lastSeen ||
          mergedLastMessageAt != existing.lastMessageAt;
      if (changed) {
        _contacts[existingIndex] = existing.copyWith(
          latitude: nextLatitude,
          longitude: nextLongitude,
          name: nextName,
          lastMessageAt: mergedLastMessageAt,
          lastSeen: nextLastSeen,
        );
        notifyListeners();
      }

      if (_pathHistoryService != null && path.isNotEmpty) {
        _pathHistoryService!.handlePathUpdated(
          existing.copyWith(
            path: _reversePathByHop(path, pathHashWidth),
            pathLength: path.length ~/ pathHashWidth,
            pathHashWidth: pathHashWidth,
          ),
          initialWeight: _initialRouteWeight,
        );
      }

      _updateDirectRepeater(
        _contacts[existingIndex],
        snr,
        path,
        pathHashWidth: pathHashWidth,
      );
    }
  }

  /// Registers the repeater that relayed a TRACE packet we just overheard.
  ///
  /// TRACE is the one payload type whose wire `path` field does not hold hop
  /// hashes: firmware keeps the requested route at the end of the payload and
  /// uses `path` to collect one SNR byte per hop that forwarded the packet
  /// (Mesh.cpp, `sendDirect`). Feeding that field to _recordRepeaterActivity
  /// would register an SNR reading as a repeater prefix — that is where the
  /// one-byte phantom repeaters came from, their prefix being SNR x 4.
  ///
  /// Payload layout: [tag(4)][auth(4)][flags(1)][hop hashes...], hop width is
  /// `1 << (flags & 3)`. Every forwarder appends its SNR byte after matching
  /// its own hash, so the node that transmitted what we just heard is the hop
  /// at index `snrPath.length - 1`.
  void _recordTraceRepeaterActivity(
    Uint8List snrPath,
    Uint8List payload,
    double snr,
  ) {
    const traceHeaderLen = 9;
    final hopsCompleted = snrPath.length;
    if (hopsCompleted == 0) return; // nobody has relayed it yet
    if (payload.length <= traceHeaderLen) return;
    final width = 1 << (payload[8] & 0x03);
    // Prefixes wider than 4 bytes cannot be matched against contacts, and
    // recording them would only add unidentifiable entries.
    if (width > 4) return;
    final start = traceHeaderLen + (hopsCompleted - 1) * width;
    if (start + width > payload.length) return;
    _recordRepeaterActivity(payload.sublist(start, start + width), width, snr);
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
    _bumpRepeaterActivity();
  }

  void _bumpRepeaterActivity() => repeaterActivity.value++;

  String? _resolveActivityRepeaterContactKeyHex(List<int> pubkeyPrefix) =>
      _singleRepeaterKeyWithPrefix(pubkeyPrefix);

  /// The one repeater or room server, among the node's contacts and the
  /// discovered nodes [allContacts] would list, whose key starts with
  /// [pubkeyPrefix]; null when none or several do. Walks the two lists in
  /// place and compares bytes: this runs for every relayed packet, and
  /// building [allContacts] plus a hex string per candidate cost more than
  /// the packet itself.
  String? _singleRepeaterKeyWithPrefix(List<int> pubkeyPrefix) {
    String? match;
    for (final contact in _contacts) {
      if (contact.type != advTypeRepeater && contact.type != advTypeRoom) {
        continue;
      }
      if (!KeyPrefixMatch.keyStartsWith(contact.publicKey, pubkeyPrefix)) {
        continue;
      }
      if (match != null) return null;
      match = contact.publicKeyHex;
    }
    final selfHex = selfPublicKeyHex;
    for (final contact in _discoveredContacts) {
      if (contact.isActive || contact.publicKeyHex == selfHex) continue;
      if (contact.type != advTypeRepeater && contact.type != advTypeRoom) {
        continue;
      }
      if (!KeyPrefixMatch.keyStartsWith(contact.publicKey, pubkeyPrefix)) {
        continue;
      }
      if (match != null) return null;
      match = contact.publicKeyHex;
    }
    return match;
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
    _bumpRepeaterActivity();
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
    return _singleRepeaterKeyWithPrefix(pubkeyPrefix);
  }

  bool _contactKeyMatchesPrefix(String contactKeyHex, List<int> pubkeyPrefix) =>
      KeyPrefixMatch.hexStartsWith(contactKeyHex, pubkeyPrefix);

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
      _autoAddMaxHops = frame.length > 2 ? frame[2] : null;
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
      // A copy of an advert already recorded, heard again the same way,
      // changes nothing: replacing the entry would bump `discoveredRevision`,
      // wake every listener and rewrite the store for each copy.
      final unchanged =
          existing.name == contact.name &&
          existing.type == contact.type &&
          existing.pathLength == contact.pathLength &&
          listEquals(existing.path, contact.path) &&
          existing.pathHashWidth == contact.pathHashWidth &&
          existing.latitude == contact.latitude &&
          existing.longitude == contact.longitude &&
          existing.lastSeen == contact.lastSeen &&
          existing.lastMessageAt == messageSummary.lastMessageAt &&
          existing.hasMessages == messageSummary.hasMessages &&
          existing.flags == 0 &&
          existing.isActive == addActive;
      if (unchanged) return;
      _discoveredContacts[existingIndex] = existing.copyWith(
        rawPacket: rawPacket,
        name: contact.name,
        type: contact.type,
        pathLength: contact.pathLength,
        path: contact.path,
        pathHashWidth: contact.pathHashWidth,
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
      pathHashWidth: contact.pathHashWidth,
      latitude: contact.latitude,
      longitude: contact.longitude,
      lastSeen: contact.lastSeen,
      lastMessageAt: contact.lastMessageAt,
      hasMessages: contact.hasMessages,
      isActive: addActive,
      flags: 0,
    );

    if (_discoveredContacts.length >= _discoveredContactsLimit) {
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

  /// Drops the stalest discovered contacts past the cap the setting names
  /// now, after it shrank; a cap that grew leaves the list as it is.
  void _trimDiscoveredContactsToLimit() {
    final limit = _discoveredContactsLimit;
    if (_discoveredContacts.length <= limit) return;
    while (_discoveredContacts.length > limit) {
      _evictStalestDiscoveredContact();
    }
    unawaited(_persistDiscoveredContacts());
    notifyListeners();
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
    unawaited(_messageStore.clearMessages(contactKeyHex));
    markContactRead(contactKeyHex);
    notifyListeners();
  }

  /// Clears the channel's messages in this node's scope, under every name
  /// the channel has had, and hides the other nodes' copies for the session;
  /// with [allNodes], clears those copies as well.
  void clearMessagesForChannel(int channelIndex, {bool allNodes = false}) {
    final messages = _channelMessages.putIfAbsent(
      channelIndex,
      () => <ChannelMessage>[],
    );
    messages.clear();
    _sharedChannelSecondaryMessages.remove(channelIndex);
    _sharedChannelSecondaryIdentityKeys.remove(channelIndex);
    final channel = _findChannelByIndex(channelIndex);
    if (channel != null && !allNodes) {
      _hiddenSharedChannelIdentityKeys[channelIndex] =
          _sharedChannelIdentityKey(channel);
    }
    unawaited(_channelMessageStore.clearChannelMessages(channelIndex));
    unawaited(
      _deleteImagesForChannel?.call(channelIndex, _imageChannelIdsOf(channel)),
    );
    final identity = channel == null ? null : ChannelIdentity.of(channel);
    if (allNodes && identity != null) {
      unawaited(
        _clearChannelMessagesOnOtherNodes(
          ChannelIdentities.instance.namesOf(identity),
        ),
      );
    }
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

bool _isPathLenValidForMode(
  int pathLen,
  List<int> pathBytes,
  int pathHashWidth,
) {
  if (pathLen < 0 || pathLen > 0x3F) return false;
  if (pathHashWidth < 1 || pathHashWidth > 3) return false;
  final width = pathHashWidth;
  final maxHopCountByBytes = maxPathSize ~/ width;
  if (pathLen > maxHopCountByBytes) return false;
  return pathBytes.length <= maxPathSize && pathBytes.length == pathLen * width;
}

Uint8List _reversePathByHop(Uint8List pathBytes, int pathHashWidth) {
  if (pathBytes.isEmpty) return Uint8List(0);
  final width = pathHashWidth.clamp(1, maxPathHashWidth).toInt();
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

/// A send stopped by hand: the message, its recipient and the attempts sent
/// under one ACK hash, newest first, with the route each went by.
typedef _StoppedSend = ({
  String contactKeyHex,
  String messageId,
  List<({int attempt, PathSelection? selection})> attempts,
});

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
  final String? replyToMessageId;
  final String? replyToSenderName;
  final String? replyToText;
  final int? replyToTimestamp;
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
    this.replyToMessageId,
    this.replyToSenderName,
    this.replyToText,
    this.replyToTimestamp,
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
  final String? region;
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
    this.region,
    required this.delaySeconds,
    required this.sendAt,
  });
}

class _DeferredChannelMessageSend {
  final Channel channel;
  final String messageId;
  final String text;

  /// The name the message goes out under (see channelSendName), decided
  /// when the message was made and kept through the deferral.
  final String senderName;
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
  final String? region;

  _DeferredChannelMessageSend({
    required this.channel,
    required this.messageId,
    required this.text,
    required this.senderName,
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
    this.region,
  });
}
