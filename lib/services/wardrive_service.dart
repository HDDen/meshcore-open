import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../helpers/wardrive_coverage_helper.dart';
import '../storage/prefs_manager.dart';
import '../utils/platform_info.dart';
import 'background_service.dart';
import 'wardrive_ignore_store.dart';
import 'wardrive_foreground_service.dart';
import 'wardrive_sample_store.dart';
import 'wardrive_upload_service.dart';

class WardriveDiscoveryResult {
  final DateTime timestamp;
  final int tag;
  final int nodeType;
  final String publicKeyHex;
  final int snr;
  final int rssi;
  final int? responseTimeMs;

  const WardriveDiscoveryResult({
    required this.timestamp,
    required this.tag,
    required this.nodeType,
    required this.publicKeyHex,
    required this.snr,
    required this.rssi,
    this.responseTimeMs,
  });

  String get publicKeyPrefix {
    final length = publicKeyHex.length < 8 ? publicKeyHex.length : 8;
    return publicKeyHex.substring(0, length).toUpperCase();
  }
}

class WardriveService extends ChangeNotifier with WidgetsBindingObserver {
  WardriveService(this._connector, {BackgroundService? backgroundService})
    : _backgroundService = backgroundService {
    WidgetsBinding.instance.addObserver(this);
    _loadSavedSettings();
    _loadSavedSamples();
  }

  final MeshCoreConnector _connector;
  final BackgroundService? _backgroundService;
  final Random _random = Random();
  final WardriveSampleStore _sampleStore = WardriveSampleStore();
  final WardriveIgnoreStore _ignoreStore = WardriveIgnoreStore();
  final WardriveForegroundService _foregroundService =
      WardriveForegroundService();
  final Map<int, _WardriveDiscoveryRequest> _pendingDiscoveryRequests = {};
  final Map<int, int> _discoveryResponsesByTag = {};
  final Map<int, Timer> _discoveryFailureTimers = {};
  final List<WardriveDiscoveryResult> _recentDiscoveries = [];
  final List<WardriveSample> _recentSamples = [];
  final Set<String> _currentDiscoveryPublicKeys = {};
  final Set<String> _ignoredRepeaterKeys = {};
  int? _currentDiscoveryTag;
  static const Duration defaultAutoDiscoveryInterval = Duration(seconds: 25);
  static const Duration _discoveryResponseWindow = Duration(seconds: 10);
  static const Duration _continuousGpsMaxAge = Duration(seconds: 60);
  static const int minAutoDiscoveryIntervalSeconds = 5;
  static const int maxAutoDiscoveryIntervalSeconds = 300;
  static const int _recentSamplesLimit = 3000;
  static const String _autoDiscoveryIntervalSecondsKey =
      'wardrive_auto_discovery_interval_seconds_v1';
  static const String _screenWakelockEnabledKey =
      'wardrive_screen_wakelock_enabled_v1';
  static const String _runInBackgroundEnabledKey =
      'wardrive_run_in_background_enabled_v1';
  static const String _continuousGpsEnabledKey =
      'wardrive_continuous_gps_enabled_v1';
  static const String _followMeEnabledKey = 'wardrive_follow_me_enabled_v1';
  static const String _coveragePrecisionKey = 'wardrive_coverage_precision_v1';

  StreamSubscription<Uint8List>? _framesSubscription;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _autoDiscoveryTimer;
  Timer? _oneShotDiscoveryTimer;
  Timer? _autoUploadTimer;
  bool _isRunning = false;
  bool _acceptOneShotDiscoveryResponses = false;
  bool _showMapState = false;
  bool _usePhoneLocationForDisplay = false;
  bool _isSendingDiscovery = false;
  bool _isUpdatingLocation = false;
  bool _screenWakelockEnabled = false;
  bool _runInBackgroundEnabled = false;
  bool _continuousGpsEnabled = false;
  bool _resumeAfterForegroundPause = false;
  bool _followMeEnabled = false;
  bool _isAutoUploadInProgress = false;
  int _discoveryRequestsSent = 0;
  int _discoveryResponsesReceived = 0;
  DateTime? _lastDiscoveryRequestAt;
  DateTime? _lastDiscoveryResponseAt;
  double? _lastPhoneLatitude;
  double? _lastPhoneLongitude;
  DateTime? _lastPhoneLocationAt;
  String? _lastLocationError;
  String? _lastSampleError;
  String? _lastAutoDiscoveryError;
  DateTime? _nextAutoDiscoveryAt;
  DateTime? _lastSampleSavedAt;
  DateTime? _sessionStartedAt;
  Duration _autoDiscoveryInterval = defaultAutoDiscoveryInterval;
  final WardriveUploadService _uploadService = WardriveUploadService();
  int _savedSamplesCount = 0;
  int _sessionSampleCount = 0;
  int _sessionPingCount = 0;
  int _sessionSuccessCount = 0;
  int _coveragePrecision = WardriveCoverageHelper.defaultCoveragePrecision;

  bool get isRunning => _isRunning;
  bool get hasMapState => _isRunning || _showMapState;
  bool get usesPhoneLocationForDisplay =>
      hasMapState && (_isRunning || _usePhoneLocationForDisplay);
  bool get isSendingDiscovery => _isSendingDiscovery;
  bool get isUpdatingLocation => _isUpdatingLocation;
  bool get screenWakelockEnabled => _screenWakelockEnabled;
  bool get runInBackgroundEnabled => _runInBackgroundEnabled;
  bool get continuousGpsEnabled => _continuousGpsEnabled;
  bool get followMeEnabled => _followMeEnabled;
  int get discoveryRequestsSent => _discoveryRequestsSent;
  int get discoveryResponsesReceived => _discoveryResponsesReceived;
  DateTime? get lastDiscoveryRequestAt => _lastDiscoveryRequestAt;
  DateTime? get lastDiscoveryResponseAt => _lastDiscoveryResponseAt;
  double? get lastPhoneLatitude => _lastPhoneLatitude;
  double? get lastPhoneLongitude => _lastPhoneLongitude;
  DateTime? get lastPhoneLocationAt => _lastPhoneLocationAt;
  String? get lastLocationError => _lastLocationError;
  String? get lastSampleError => _lastSampleError;
  String? get lastAutoDiscoveryError => _lastAutoDiscoveryError;
  DateTime? get nextAutoDiscoveryAt => _nextAutoDiscoveryAt;
  Duration get autoDiscoveryInterval => _autoDiscoveryInterval;
  int get autoDiscoveryIntervalSeconds => _autoDiscoveryInterval.inSeconds;
  DateTime? get lastSampleSavedAt => _lastSampleSavedAt;
  int get savedSamplesCount => _savedSamplesCount;
  int get coveragePrecision => _coveragePrecision;
  List<WardriveDiscoveryResult> get recentDiscoveries =>
      List.unmodifiable(_recentDiscoveries);
  List<WardriveSample> get recentSamples {
    return List.unmodifiable(
      _recentSamples.where(
        (sample) => !WardriveIgnoreStore.containsMatchingKey(
          _ignoredRepeaterKeys,
          sample.publicKeyHex,
        ),
      ),
    );
  }

  Set<String> get currentDiscoveryPublicKeys =>
      Set.unmodifiable(_currentDiscoveryPublicKeys);
  Set<String> get ignoredRepeaterKeys => Set.unmodifiable(_ignoredRepeaterKeys);
  bool get hasDiscoveryRequestWithoutResponses =>
      _lastDiscoveryRequestAt != null && _currentDiscoveryPublicKeys.isEmpty;

  bool isRepeaterIgnored(String publicKeyHex) {
    return WardriveIgnoreStore.containsMatchingKey(
      _ignoredRepeaterKeys,
      publicKeyHex,
    );
  }

  Future<void> setRepeaterIgnored(String publicKeyHex, bool ignored) async {
    await _ignoreStore.setIgnoredRepeater(publicKeyHex, ignored);
    _loadIgnoredRepeaters();
    notifyListeners();
  }

  void showMapState() {
    if (_showMapState) return;
    _showMapState = true;
    notifyListeners();
  }

  void start() {
    if (_isRunning) return;
    _framesSubscription ??= _connector.receivedFrames.listen(_handleFrame);
    _isRunning = true;
    _showMapState = true;
    _syncBackgroundKeepAlive();
    _syncContinuousLocationStream();
    _startSession();
    _lastAutoDiscoveryError = null;
    _loadSavedSamples();
    _scheduleAutoDiscovery(const Duration(milliseconds: 250));
    notifyListeners();
  }

  void _loadSavedSamples() {
    _savedSamplesCount = _sampleStore.count;
    _recentSamples
      ..clear()
      ..addAll(_sampleStore.loadRecent(limit: _recentSamplesLimit));
  }

  void _loadSavedSettings() {
    _loadIgnoredRepeaters();
    final seconds = PrefsManager.instance.getInt(
      _autoDiscoveryIntervalSecondsKey,
    );
    if (seconds != null) {
      _autoDiscoveryInterval = Duration(
        seconds: seconds.clamp(
          minAutoDiscoveryIntervalSeconds,
          maxAutoDiscoveryIntervalSeconds,
        ),
      );
    }
    _screenWakelockEnabled =
        PrefsManager.instance.getBool(_screenWakelockEnabledKey) ?? false;
    _runInBackgroundEnabled =
        PrefsManager.instance.getBool(_runInBackgroundEnabledKey) ?? false;
    _continuousGpsEnabled =
        PrefsManager.instance.getBool(_continuousGpsEnabledKey) ?? false;
    _followMeEnabled =
        PrefsManager.instance.getBool(_followMeEnabledKey) ?? false;
    final savedCoveragePrecision = PrefsManager.instance.getInt(
      _coveragePrecisionKey,
    );
    if (savedCoveragePrecision != null) {
      _coveragePrecision = savedCoveragePrecision
          .clamp(
            WardriveCoverageHelper.minCoveragePrecision,
            WardriveCoverageHelper.maxCoveragePrecision,
          )
          .toInt();
    }
  }

  void _loadIgnoredRepeaters() {
    _ignoredRepeaterKeys
      ..clear()
      ..addAll(_ignoreStore.loadIgnoredRepeaters());
  }

  Future<void> setScreenWakelockEnabled(bool enabled) async {
    if (_screenWakelockEnabled == enabled) return;
    _screenWakelockEnabled = enabled;
    await PrefsManager.instance.setBool(_screenWakelockEnabledKey, enabled);
    notifyListeners();
  }

  Future<void> setRunInBackgroundEnabled(bool enabled) async {
    if (_runInBackgroundEnabled == enabled) return;
    if (enabled) {
      await _foregroundService.ensureAndroidRequirements();
    }
    _runInBackgroundEnabled = enabled;
    await PrefsManager.instance.setBool(_runInBackgroundEnabledKey, enabled);
    _syncBackgroundKeepAlive();
    notifyListeners();
  }

  Future<void> setContinuousGpsEnabled(bool enabled) async {
    if (_continuousGpsEnabled == enabled) return;
    _continuousGpsEnabled = enabled;
    await PrefsManager.instance.setBool(_continuousGpsEnabledKey, enabled);
    _syncContinuousLocationStream();
    notifyListeners();
  }

  void _syncBackgroundKeepAlive() {
    if (!PlatformInfo.isAndroid) return;
    // This reason only controls wardrive's extra background keep-alive; the
    // connector keeps its own "connection" reason for normal BLE companion use.
    if (_isRunning && _runInBackgroundEnabled) {
      unawaited(_startAndroidBackgroundServices());
    } else {
      unawaited(_backgroundService?.stop(reason: 'wardrive'));
      unawaited(_foregroundService.stop().catchError((_) {}));
    }
  }

  void _syncContinuousLocationStream() {
    if (_isRunning && _continuousGpsEnabled) {
      unawaited(_startContinuousLocationStream());
    } else {
      unawaited(_stopContinuousLocationStream());
    }
  }

  Future<void> _startContinuousLocationStream() async {
    if (_positionSubscription != null) return;
    try {
      await _ensureLocationAvailable();
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      ).listen(
        _handleContinuousLocation,
        onError: (Object error) {
          _lastPhoneLatitude = null;
          _lastPhoneLongitude = null;
          _lastPhoneLocationAt = null;
          _lastLocationError = _formatWardriveError(error);
          notifyListeners();
        },
      );
    } catch (error) {
      _lastPhoneLatitude = null;
      _lastPhoneLongitude = null;
      _lastPhoneLocationAt = null;
      _lastLocationError = _formatWardriveError(error);
      notifyListeners();
    }
  }

  Future<void> _stopContinuousLocationStream() async {
    final subscription = _positionSubscription;
    if (subscription == null) return;
    _positionSubscription = null;
    await subscription.cancel();
  }

  void _handleContinuousLocation(Position position) {
    _lastPhoneLatitude = position.latitude;
    _lastPhoneLongitude = position.longitude;
    _lastPhoneLocationAt = DateTime.now();
    _lastLocationError = null;
    notifyListeners();
  }

  Future<void> _startAndroidBackgroundServices() async {
    try {
      await _foregroundService.ensureAndroidRequirements();
      await _backgroundService?.start(reason: 'wardrive');
      await _foregroundService.start();
    } catch (error) {
      _runInBackgroundEnabled = false;
      await PrefsManager.instance.setBool(_runInBackgroundEnabledKey, false);
      await _backgroundService?.stop(reason: 'wardrive');
      await _foregroundService.stop();
      _lastAutoDiscoveryError = _formatWardriveError(error);
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!PlatformInfo.isAndroid || _runInBackgroundEnabled) {
      return;
    }
    if (state == AppLifecycleState.resumed && _resumeAfterForegroundPause) {
      _resumeAfterForegroundPause = false;
      start();
      return;
    }
    if (!_isRunning) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _resumeAfterForegroundPause = true;
      _stop(resetForegroundResume: false);
    }
  }

  Future<void> setFollowMeEnabled(bool enabled) async {
    if (_followMeEnabled == enabled) return;
    _followMeEnabled = enabled;
    await PrefsManager.instance.setBool(_followMeEnabledKey, enabled);
    notifyListeners();
  }

  Future<void> setCoveragePrecision(int precision) async {
    final clamped = precision
        .clamp(
          WardriveCoverageHelper.minCoveragePrecision,
          WardriveCoverageHelper.maxCoveragePrecision,
        )
        .toInt();
    if (_coveragePrecision == clamped) return;
    _coveragePrecision = clamped;
    await PrefsManager.instance.setInt(_coveragePrecisionKey, clamped);
    // The stored samples keep their original high-precision geohash; changing
    // this value only rebuilds coverage aggregation on listeners.
    notifyListeners();
  }

  void stop() {
    _stop(resetForegroundResume: true);
  }

  void _stop({required bool resetForegroundResume}) {
    if (!_isRunning) return;
    if (resetForegroundResume) {
      _resumeAfterForegroundPause = false;
    }
    _finishSession();
    _isRunning = false;
    _syncBackgroundKeepAlive();
    _syncContinuousLocationStream();
    _autoDiscoveryTimer?.cancel();
    _autoDiscoveryTimer = null;
    _oneShotDiscoveryTimer?.cancel();
    _oneShotDiscoveryTimer = null;
    _acceptOneShotDiscoveryResponses = false;
    _clearDiscoveryTracking();
    _lastAutoDiscoveryError = null;
    _nextAutoDiscoveryAt = null;
    notifyListeners();
  }

  void clearMapState() {
    if (_isRunning) return;
    _showMapState = false;
    _usePhoneLocationForDisplay = false;
    _currentDiscoveryPublicKeys.clear();
    _recentDiscoveries.clear();
    _currentDiscoveryTag = null;
    _lastDiscoveryRequestAt = null;
    _lastDiscoveryResponseAt = null;
    _lastLocationError = null;
    _lastSampleError = null;
    _lastAutoDiscoveryError = null;
    _nextAutoDiscoveryAt = null;
    notifyListeners();
  }

  void _scheduleAutoDiscovery(Duration delay) {
    _autoDiscoveryTimer?.cancel();
    if (!_isRunning) {
      _nextAutoDiscoveryAt = null;
      return;
    }

    _nextAutoDiscoveryAt = DateTime.now().add(delay);
    _autoDiscoveryTimer = Timer(delay, () {
      unawaited(_runAutoDiscoveryCycle());
    });
  }

  Future<void> _runAutoDiscoveryCycle() async {
    if (!_isRunning) return;
    if (!_connector.isConnected) {
      stop();
      return;
    }

    try {
      await sendZeroHopDiscoveryRequest();
      _lastAutoDiscoveryError = null;
    } catch (error) {
      final errorText = _formatWardriveError(error);
      // GPS failures are already displayed in the dedicated "Phone GPS" row.
      // Showing the same error again as "Auto discovery" creates noisy panels
      // like "Auto discovery: Bad state: TimeoutException...".
      _lastAutoDiscoveryError =
          _lastLocationError != null && errorText == _lastLocationError
          ? null
          : errorText;
    } finally {
      if (_isRunning) notifyListeners();
    }
  }

  Future<void> sendZeroHopDiscoveryRequest({bool startWardrive = true}) async {
    if (!_connector.isConnected) {
      throw StateError('Not connected to a MeshCore device');
    }
    if (_isSendingDiscovery) {
      if (_isRunning) {
        _scheduleAutoDiscovery(_autoDiscoveryInterval);
        notifyListeners();
      }
      return;
    }

    if (startWardrive) {
      start();
    } else {
      _showMapState = true;
      _framesSubscription ??= _connector.receivedFrames.listen(_handleFrame);
      _acceptOneShotDiscoveryResponses = true;
      _oneShotDiscoveryTimer?.cancel();
    }
    _isSendingDiscovery = true;
    notifyListeners();

    final previousDiscoveryKeys = Set<String>.from(_currentDiscoveryPublicKeys);
    final previousDiscoveries = List<WardriveDiscoveryResult>.from(
      _recentDiscoveries,
    );
    final previousCurrentDiscoveryTag = _currentDiscoveryTag;
    final previousRequestAt = _lastDiscoveryRequestAt;
    int? pendingTag;
    try {
      await _updateNodeLocationFromPhone(reportErrors: startWardrive);
      if (_lastPhoneLatitude == null || _lastPhoneLongitude == null) {
        if (startWardrive) {
          // Wardrive pings are location-bound measurements; skip the radio
          // request if the phone did not provide a fresh GPS fix for this point.
          throw StateError(
            _lastLocationError ?? 'Phone GPS is not available for this request',
          );
        }
      }
      if (!startWardrive &&
          _lastPhoneLatitude != null &&
          _lastPhoneLongitude != null) {
        _usePhoneLocationForDisplay = true;
        notifyListeners();
      }

      // Wardrive discovery starts with a local advert so nearby nodes can
      // refresh us before the follow-up discovery request asks who can hear it.
      await _connector.sendSelfAdvert(flood: false);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final tag = _random.nextInt(0x7fffffff);
      pendingTag = tag;
      final payload = buildDiscoveryRequestPayload(tag, prefixOnly: false);
      final startedAt = DateTime.now();
      _currentDiscoveryPublicKeys.clear();
      _recentDiscoveries.clear();
      _currentDiscoveryTag = tag;
      _pendingDiscoveryRequests[tag] = _WardriveDiscoveryRequest(
        startedAt: startedAt,
        latitude: _lastPhoneLatitude,
        longitude: _lastPhoneLongitude,
        phoneLocationAt: _lastPhoneLocationAt,
      );
      if (_isRunning) {
        _discoveryResponsesByTag[tag] = 0;
        _discoveryFailureTimers[tag]?.cancel();
        _discoveryFailureTimers[tag] = Timer(_discoveryResponseWindow, () {
          unawaited(_saveFailedSampleIfNoResponses(tag));
        });
      }
      await _connector.sendFrame(buildSendControlDataFrame(payload));
      _lastDiscoveryRequestAt = startedAt;
      _discoveryRequestsSent++;
      if (!startWardrive) {
        _oneShotDiscoveryTimer = Timer(const Duration(seconds: 10), () {
          _acceptOneShotDiscoveryResponses = false;
          _clearDiscoveryTracking(tag);
          notifyListeners();
        });
      }
    } catch (_) {
      if (!startWardrive) {
        _acceptOneShotDiscoveryResponses = false;
        _oneShotDiscoveryTimer?.cancel();
        _oneShotDiscoveryTimer = null;
      }
      if (pendingTag != null) {
        _clearDiscoveryTracking(pendingTag);
      }
      _currentDiscoveryPublicKeys
        ..clear()
        ..addAll(previousDiscoveryKeys);
      _recentDiscoveries
        ..clear()
        ..addAll(previousDiscoveries);
      _currentDiscoveryTag = previousCurrentDiscoveryTag;
      _lastDiscoveryRequestAt = previousRequestAt;
      rethrow;
    } finally {
      _isSendingDiscovery = false;
      if (_isRunning) {
        _scheduleAutoDiscovery(_autoDiscoveryInterval);
      }
      notifyListeners();
    }
  }

  void setAutoDiscoveryIntervalSeconds(int seconds) {
    final clamped = seconds.clamp(
      minAutoDiscoveryIntervalSeconds,
      maxAutoDiscoveryIntervalSeconds,
    );
    _autoDiscoveryInterval = Duration(seconds: clamped);
    unawaited(
      PrefsManager.instance.setInt(_autoDiscoveryIntervalSecondsKey, clamped),
    );
    if (_isRunning) {
      _scheduleAutoDiscovery(_autoDiscoveryInterval);
    }
    notifyListeners();
  }

  Future<void> _updateNodeLocationFromPhone({required bool reportErrors}) async {
    _isUpdatingLocation = true;
    _lastLocationError = null;
    notifyListeners();

    try {
      if (_continuousGpsEnabled) {
        await _startContinuousLocationStream();
        if (_hasFreshPhoneLocation()) {
          return;
        }
      }

      await _ensureLocationAvailable();

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      _lastPhoneLatitude = position.latitude;
      _lastPhoneLongitude = position.longitude;
      _lastPhoneLocationAt = DateTime.now();

      // Wardrive samples use the phone position as local measurement context;
      // do not write it into the connected node's advertised coordinates.
    } catch (error) {
      // Do not reuse stale phone coordinates for wardrive samples if iOS/Android
      // fails to provide a fresh GPS fix for the current request.
      _lastPhoneLatitude = null;
      _lastPhoneLongitude = null;
      _lastPhoneLocationAt = null;
      if (reportErrors) {
        _lastLocationError = _formatWardriveError(error);
      }
    } finally {
      _isUpdatingLocation = false;
      notifyListeners();
    }
  }

  bool _hasFreshPhoneLocation() {
    final locationAt = _lastPhoneLocationAt;
    if (_lastPhoneLatitude == null ||
        _lastPhoneLongitude == null ||
        locationAt == null) {
      return false;
    }
    return DateTime.now().difference(locationAt) <= _continuousGpsMaxAge;
  }

  Future<void> _ensureLocationAvailable() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw StateError('Phone location service is disabled');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw StateError('Phone location permission was denied');
    }
    if (permission == LocationPermission.deniedForever) {
      throw StateError('Phone location permission is permanently denied');
    }
  }

  String _formatWardriveError(Object error) {
    if (error is TimeoutException) {
      final duration = error.duration;
      if (duration != null) {
        return 'Timeout after ${duration.inSeconds} seconds';
      }
      return 'Timeout';
    }

    if (error is StateError) {
      return _formatWardriveErrorText(error.message);
    }

    return _formatWardriveErrorText(error.toString());
  }

  String _formatWardriveErrorText(String text) {
    const timeoutPrefix = 'TimeoutException after ';
    if (text.startsWith(timeoutPrefix)) {
      final end = text.indexOf(': Future not completed');
      if (end > timeoutPrefix.length) {
        return 'Timeout after ${text.substring(timeoutPrefix.length, end)}';
      }
      return 'Timeout';
    }

    const badStatePrefix = 'Bad state: ';
    if (text.startsWith(badStatePrefix)) {
      return text.substring(badStatePrefix.length);
    }

    return text;
  }

  void _handleFrame(Uint8List frame) {
    if ((!_isRunning && !_acceptOneShotDiscoveryResponses) || frame.isEmpty) {
      return;
    }
    if (frame[0] != pushCodeControlData) return;

    final result = _parseDiscoveryResponseFrame(frame);
    if (result == null) return;

    final isKnownRequest = _pendingDiscoveryRequests.containsKey(result.tag);
    if (!isKnownRequest) return;
    final isCurrentRequest = result.tag == _currentDiscoveryTag;

    _discoveryResponsesReceived++;
    _lastDiscoveryResponseAt = result.timestamp;
    final isIgnored = isRepeaterIgnored(result.publicKeyHex);
    if (!isIgnored && _discoveryResponsesByTag.containsKey(result.tag)) {
      _discoveryResponsesByTag[result.tag] =
          (_discoveryResponsesByTag[result.tag] ?? 0) + 1;
    }
    if (_isRunning && !isIgnored) {
      unawaited(_saveSample(result));
    }
    if (isCurrentRequest) {
      // Keep the map highlight and panel list scoped to the latest discovery
      // request. Late responses from an older tag may still be saved as samples.
      // Ignored repeaters still stay visible as responders on the live map,
      // but they are excluded from saved coverage statistics and upload.
      _currentDiscoveryPublicKeys.add(result.publicKeyHex);
      _recentDiscoveries.removeWhere(
        (entry) => entry.publicKeyHex == result.publicKeyHex,
      );
      _recentDiscoveries.insert(0, result);
      if (_recentDiscoveries.length > 50) {
        _recentDiscoveries.removeRange(50, _recentDiscoveries.length);
      }
    }

    final pubKeyBytes = _publicKeyBytesFromHex(result.publicKeyHex);
    if (pubKeyBytes.length == pubKeySize) {
      // Ask the node for full contact details; the connector will merge the
      // contact into the normal map/list flow when the response arrives.
      unawaited(_connector.getContactByKey(pubKeyBytes));
    }

    notifyListeners();
  }

  Future<void> _saveSample(WardriveDiscoveryResult result) async {
    final request = _pendingDiscoveryRequests[result.tag];
    final latitude = request?.latitude ?? _lastPhoneLatitude;
    final longitude = request?.longitude ?? _lastPhoneLongitude;
    if (latitude == null || longitude == null) {
      _lastSampleError = 'Phone GPS is not available for this sample';
      notifyListeners();
      return;
    }

    try {
      final sample = WardriveSample.fromDiscovery(
        // Match standalone wardrive: successful sample timestamp is the moment
        // the sample is created/saved, not an earlier packet parsing timestamp.
        timestamp: DateTime.now(),
        phoneLocationAt: request?.phoneLocationAt ?? _lastPhoneLocationAt,
        latitude: latitude,
        longitude: longitude,
        tag: result.tag,
        nodeType: result.nodeType,
        publicKeyHex: result.publicKeyHex,
        snr: result.snr,
        rssi: result.rssi,
        responseTimeMs: result.responseTimeMs,
      );
      await _persistSample(sample);
    } catch (error) {
      _lastSampleError = error.toString();
    }
    notifyListeners();
  }

  Future<void> _saveFailedSampleIfNoResponses(int tag) async {
    final request = _pendingDiscoveryRequests[tag];
    final responseCount = _discoveryResponsesByTag[tag] ?? 0;
    _clearDiscoveryTracking(tag);
    if (!_isRunning || request == null || responseCount > 0) return;

    final latitude = request.latitude;
    final longitude = request.longitude;
    if (latitude == null || longitude == null) {
      _lastSampleError = 'Phone GPS is not available for this sample';
      notifyListeners();
      return;
    }

    try {
      // No discovery responses for this tag means this measurement point is a
      // dead zone; keep it as pingSuccess=false for wardrive coverage exports.
      final sample = WardriveSample.fromDiscoveryFailure(
        timestamp: DateTime.now(),
        phoneLocationAt: request.phoneLocationAt,
        latitude: latitude,
        longitude: longitude,
        tag: tag,
      );
      await _persistSample(sample);
    } catch (error) {
      _lastSampleError = error.toString();
    }
    notifyListeners();
  }

  Future<void> _persistSample(WardriveSample sample) async {
    await _sampleStore.add(sample);
    _recordSessionSample(sample);
    _savedSamplesCount = _sampleStore.count;
    _lastSampleSavedAt = sample.timestamp;
    _lastSampleError = null;
    _recentSamples.insert(0, sample);
    if (_recentSamples.length > _recentSamplesLimit) {
      _recentSamples.removeRange(_recentSamplesLimit, _recentSamples.length);
    }
    _scheduleAutoUpload();
  }

  void _scheduleAutoUpload() {
    if (!_uploadService.isAutoUploadEnabledSync || _autoUploadTimer != null) {
      return;
    }
    _autoUploadTimer = Timer(const Duration(seconds: 2), () {
      _autoUploadTimer = null;
      unawaited(runAutoUpload());
    });
  }

  Future<void> runAutoUpload() async {
    if (_isAutoUploadInProgress || !_uploadService.isAutoUploadEnabledSync) {
      return;
    }
    _isAutoUploadInProgress = true;
    try {
      final results = await _uploadService.uploadNextBatchToSelectedSites(
        repeaterNames: _wardriveUploadRepeaterNames(),
      );
      final uploadedFullBatch = results.values.any(
        (result) =>
            result.success &&
            (result.uploadedCount ?? 0) >=
                WardriveUploadService.autoUploadBatchSize,
      );
      if (uploadedFullBatch && _uploadService.isAutoUploadEnabledSync) {
        _scheduleAutoUpload();
      }
    } finally {
      _isAutoUploadInProgress = false;
    }
  }

  Map<String, String> _wardriveUploadRepeaterNames() {
    final names = <String, String>{};
    for (final contact in _connector.allContactsUnfiltered) {
      final key = contact.publicKeyHex.toUpperCase();
      if (key.isNotEmpty && contact.name.isNotEmpty) {
        names[key] = contact.name;
      }
    }
    return names;
  }

  String exportSamplesJson() {
    return _sampleStore.exportJson(
      activeSession: _activeSessionSnapshot(),
      ignoredRepeaterKeys: _ignoredRepeaterKeys,
    );
  }

  Future<int> importSamplesJson(String rawJson) async {
    final added = await _sampleStore.importJson(rawJson);
    _loadSavedSamples();
    notifyListeners();
    return added;
  }

  Future<void> clearSamples() async {
    await _sampleStore.clear();
    _recentSamples.clear();
    _savedSamplesCount = 0;
    _sessionSampleCount = 0;
    _sessionPingCount = 0;
    _sessionSuccessCount = 0;
    _lastSampleSavedAt = null;
    _lastSampleError = null;
    notifyListeners();
  }

  Future<int> deleteSamplesForCoverageHash({
    required String coverageHash,
    required int coveragePrecision,
  }) async {
    final removed = await _sampleStore.removeWhere(
      (sample) =>
          sample.pingSuccess != null &&
          WardriveCoverageHelper.coverageHashForSample(
                sample,
                precision: coveragePrecision,
              ) ==
              coverageHash,
    );
    if (removed == 0) return 0;

    _loadSavedSamples();
    notifyListeners();
    return removed;
  }

  void _startSession() {
    _sessionStartedAt = DateTime.now();
    _sessionSampleCount = 0;
    _sessionPingCount = 0;
    _sessionSuccessCount = 0;
  }

  void _recordSessionSample(WardriveSample sample) {
    if (_sessionStartedAt == null) return;
    _sessionSampleCount++;
    if (sample.pingSuccess != null) {
      _sessionPingCount++;
    }
    if (sample.pingSuccess == true) {
      _sessionSuccessCount++;
    }
  }

  void _finishSession() {
    final session = _activeSessionSnapshot(endTime: DateTime.now());
    if (session == null) return;
    // Keep session export compatible with the standalone wardrive app. Distance
    // tracking is not ported yet, so distanceMeters intentionally remains 0.
    unawaited(_sampleStore.addSession(session));
    _sessionStartedAt = null;
    _sessionSampleCount = 0;
    _sessionPingCount = 0;
    _sessionSuccessCount = 0;
  }

  WardriveSession? _activeSessionSnapshot({DateTime? endTime}) {
    final startedAt = _sessionStartedAt;
    if (startedAt == null) return null;

    return WardriveSession(
      startTime: startedAt,
      endTime: endTime,
      distanceMeters: 0,
      sampleCount: _sessionSampleCount,
      pingCount: _sessionPingCount,
      successCount: _sessionSuccessCount,
      notes: null,
    );
  }

  WardriveDiscoveryResult? _parseDiscoveryResponseFrame(Uint8List frame) {
    // Firmware writes: [0x8E][snr*4][rssi][path_len][payload...].
    // It currently does not include path bytes after path_len.
    if (frame.length < 10) return null;

    var snrRaw = frame[1];
    if (snrRaw > 127) snrRaw -= 256;
    final snr = (snrRaw / 4.0).round();

    var rssi = frame[2];
    if (rssi > 127) rssi -= 256;

    final payload = Uint8List.fromList(frame.sublist(4));
    if (payload.length < 6) return null;

    final flags = payload[0];
    final subtype = (flags >> 4) & 0x0F;
    if (subtype != controlSubtypeDiscoverResp) return null;

    final nodeType = flags & 0x0F;
    // payload[1] is the responder-side SNR copy; for map samples we keep the
    // companion push SNR/RSSI measured by our own radio.
    final tag =
        payload[2] |
        (payload[3] << 8) |
        (payload[4] << 16) |
        (payload[5] << 24);

    final publicKeyBytes = payload.length > 6
        ? Uint8List.fromList(payload.sublist(6))
        : Uint8List(0);
    if (publicKeyBytes.isEmpty) return null;

    final request = _pendingDiscoveryRequests[tag];
    final responseTimeMs = request == null
        ? null
        : DateTime.now().difference(request.startedAt).inMilliseconds;

    return WardriveDiscoveryResult(
      timestamp: DateTime.now(),
      tag: tag,
      nodeType: nodeType,
      publicKeyHex: _hexFromBytes(publicKeyBytes),
      snr: snr,
      rssi: rssi,
      responseTimeMs: responseTimeMs,
    );
  }

  String _hexFromBytes(Uint8List bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  Uint8List _publicKeyBytesFromHex(String hex) {
    if (hex.length % 2 != 0) return Uint8List(0);
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      final byte = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (byte == null) return Uint8List(0);
      bytes.add(byte);
    }
    return Uint8List.fromList(bytes);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _finishSession();
    unawaited(_backgroundService?.stop(reason: 'wardrive'));
    unawaited(_foregroundService.stop().catchError((_) {}));
    _autoDiscoveryTimer?.cancel();
    _oneShotDiscoveryTimer?.cancel();
    _autoUploadTimer?.cancel();
    _clearDiscoveryTracking();
    final positionSubscription = _positionSubscription;
    if (positionSubscription != null) {
      unawaited(positionSubscription.cancel());
    }
    _framesSubscription?.cancel();
    super.dispose();
  }

  void _clearDiscoveryTracking([int? tag]) {
    if (tag == null) {
      for (final timer in _discoveryFailureTimers.values) {
        timer.cancel();
      }
      _discoveryFailureTimers.clear();
      _discoveryResponsesByTag.clear();
      _pendingDiscoveryRequests.clear();
      _currentDiscoveryTag = null;
      return;
    }

    _discoveryFailureTimers.remove(tag)?.cancel();
    _discoveryResponsesByTag.remove(tag);
    _pendingDiscoveryRequests.remove(tag);
    if (_currentDiscoveryTag == tag) {
      _currentDiscoveryTag = null;
    }
  }
}

class _WardriveDiscoveryRequest {
  final DateTime startedAt;
  final double? latitude;
  final double? longitude;
  final DateTime? phoneLocationAt;

  const _WardriveDiscoveryRequest({
    required this.startedAt,
    required this.latitude,
    required this.longitude,
    required this.phoneLocationAt,
  });
}
