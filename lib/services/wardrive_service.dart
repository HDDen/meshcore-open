import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import 'wardrive_sample_store.dart';

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

class WardriveService extends ChangeNotifier {
  WardriveService(this._connector);

  final MeshCoreConnector _connector;
  final Random _random = Random();
  final WardriveSampleStore _sampleStore = WardriveSampleStore();
  final Map<int, DateTime> _pendingDiscoveryTags = {};
  final List<WardriveDiscoveryResult> _recentDiscoveries = [];
  final Set<String> _currentDiscoveryPublicKeys = {};

  StreamSubscription<Uint8List>? _framesSubscription;
  bool _isRunning = false;
  bool _isSendingDiscovery = false;
  bool _isUpdatingLocation = false;
  int _discoveryRequestsSent = 0;
  int _discoveryResponsesReceived = 0;
  DateTime? _lastDiscoveryRequestAt;
  DateTime? _lastDiscoveryResponseAt;
  double? _lastPhoneLatitude;
  double? _lastPhoneLongitude;
  DateTime? _lastPhoneLocationAt;
  String? _lastLocationError;
  String? _lastSampleError;
  DateTime? _lastSampleSavedAt;
  int _savedSamplesCount = 0;

  bool get isRunning => _isRunning;
  bool get isSendingDiscovery => _isSendingDiscovery;
  bool get isUpdatingLocation => _isUpdatingLocation;
  int get discoveryRequestsSent => _discoveryRequestsSent;
  int get discoveryResponsesReceived => _discoveryResponsesReceived;
  DateTime? get lastDiscoveryRequestAt => _lastDiscoveryRequestAt;
  DateTime? get lastDiscoveryResponseAt => _lastDiscoveryResponseAt;
  double? get lastPhoneLatitude => _lastPhoneLatitude;
  double? get lastPhoneLongitude => _lastPhoneLongitude;
  DateTime? get lastPhoneLocationAt => _lastPhoneLocationAt;
  String? get lastLocationError => _lastLocationError;
  String? get lastSampleError => _lastSampleError;
  DateTime? get lastSampleSavedAt => _lastSampleSavedAt;
  int get savedSamplesCount => _savedSamplesCount;
  List<WardriveDiscoveryResult> get recentDiscoveries =>
      List.unmodifiable(_recentDiscoveries);
  Set<String> get currentDiscoveryPublicKeys =>
      Set.unmodifiable(_currentDiscoveryPublicKeys);

  void start() {
    if (_isRunning) return;
    _framesSubscription ??= _connector.receivedFrames.listen(_handleFrame);
    _isRunning = true;
    _savedSamplesCount = _sampleStore.count;
    notifyListeners();
  }

  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    _pendingDiscoveryTags.clear();
    _currentDiscoveryPublicKeys.clear();
    _lastDiscoveryRequestAt = null;
    _lastLocationError = null;
    _lastSampleError = null;
    notifyListeners();
  }

  Future<void> sendZeroHopDiscoveryRequest() async {
    if (!_connector.isConnected) {
      throw StateError('Not connected to a MeshCore device');
    }
    if (_isSendingDiscovery) return;

    start();
    _isSendingDiscovery = true;
    notifyListeners();

    final previousDiscoveryKeys = Set<String>.from(_currentDiscoveryPublicKeys);
    final previousRequestAt = _lastDiscoveryRequestAt;
    try {
      await _updateNodeLocationFromPhone();

      // Wardrive discovery starts with a local advert so nearby nodes can
      // refresh us before the follow-up discovery request asks who can hear it.
      await _connector.sendSelfAdvert(flood: false);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final tag = _random.nextInt(0x7fffffff);
      final payload = buildDiscoveryRequestPayload(tag, prefixOnly: false);
      final startedAt = DateTime.now();
      _currentDiscoveryPublicKeys.clear();
      _pendingDiscoveryTags[tag] = startedAt;
      await _connector.sendFrame(buildSendControlDataFrame(payload));
      _lastDiscoveryRequestAt = startedAt;
      _discoveryRequestsSent++;
    } catch (_) {
      _currentDiscoveryPublicKeys
        ..clear()
        ..addAll(previousDiscoveryKeys);
      _lastDiscoveryRequestAt = previousRequestAt;
      rethrow;
    } finally {
      _isSendingDiscovery = false;
      notifyListeners();
    }
  }

  Future<void> _updateNodeLocationFromPhone() async {
    _isUpdatingLocation = true;
    _lastLocationError = null;
    notifyListeners();

    try {
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

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      _lastPhoneLatitude = position.latitude;
      _lastPhoneLongitude = position.longitude;
      _lastPhoneLocationAt = DateTime.now();

      // Wardrive samples use the phone position as local measurement context;
      // do not write it into the connected node's advertised coordinates.
    } catch (error) {
      _lastLocationError = error.toString();
    } finally {
      _isUpdatingLocation = false;
      notifyListeners();
    }
  }

  void _handleFrame(Uint8List frame) {
    if (!_isRunning || frame.isEmpty) return;
    if (frame[0] != pushCodeControlData) return;

    final result = _parseDiscoveryResponseFrame(frame);
    if (result == null) return;

    _discoveryResponsesReceived++;
    _lastDiscoveryResponseAt = result.timestamp;
    unawaited(_saveSample(result));
    _currentDiscoveryPublicKeys.add(result.publicKeyHex);
    _recentDiscoveries.removeWhere(
      (entry) => entry.publicKeyHex == result.publicKeyHex,
    );
    _recentDiscoveries.insert(0, result);
    if (_recentDiscoveries.length > 50) {
      _recentDiscoveries.removeRange(50, _recentDiscoveries.length);
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
    final latitude = _lastPhoneLatitude;
    final longitude = _lastPhoneLongitude;
    if (latitude == null || longitude == null) {
      _lastSampleError = 'Phone GPS is not available for this sample';
      notifyListeners();
      return;
    }

    try {
      await _sampleStore.add(
        WardriveSample(
          timestamp: result.timestamp,
          phoneLocationAt: _lastPhoneLocationAt,
          latitude: latitude,
          longitude: longitude,
          tag: result.tag,
          nodeType: result.nodeType,
          publicKeyHex: result.publicKeyHex,
          snr: result.snr,
          rssi: result.rssi,
          responseTimeMs: result.responseTimeMs,
        ),
      );
      _savedSamplesCount = _sampleStore.count;
      _lastSampleSavedAt = result.timestamp;
      _lastSampleError = null;
    } catch (error) {
      _lastSampleError = error.toString();
    }
    notifyListeners();
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

    final startedAt = _pendingDiscoveryTags[tag];
    final responseTimeMs = startedAt == null
        ? null
        : DateTime.now().difference(startedAt).inMilliseconds;

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
    _framesSubscription?.cancel();
    super.dispose();
  }
}
