import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../storage/prefs_manager.dart';
import 'wardrive_sample_store.dart';

class WardriveUploadService {
  WardriveUploadService({WardriveSampleStore? sampleStore})
    : _sampleStore = sampleStore ?? WardriveSampleStore();

  static const defaultApiUrl = 'https://meshwar-map.pages.dev/api/samples';
  static const _uploadSitesKey = 'wardrive_upload_sites_v1';
  static const _selectedSitesKey = 'wardrive_upload_selected_sites_v1';
  static const _uploadedSamplesKey = 'wardrive_uploaded_samples_v1';
  static const _autoUploadKey = 'wardrive_auto_upload_enabled_v1';
  static const int autoUploadBatchSize = 100;
  static const _batchSize = autoUploadBatchSize;
  // Manual upload and autoupload can be triggered from different service
  // instances; keep one process-wide upload active to avoid duplicate posts.
  static bool _uploadInProgress = false;

  final WardriveSampleStore _sampleStore;
  String? _appVersion;

  Future<List<WardriveUploadSite>> loadSites() async {
    final raw = PrefsManager.instance.getString(_uploadSitesKey);
    if (raw == null || raw.isEmpty) {
      return const [WardriveUploadSite(name: 'Default', url: defaultApiUrl)];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (entry) =>
                WardriveUploadSite.fromJson(Map<String, Object?>.from(entry)),
          )
          .whereType<WardriveUploadSite>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveSites(List<WardriveUploadSite> sites) async {
    await PrefsManager.instance.setString(
      _uploadSitesKey,
      jsonEncode(sites.map((site) => site.toJson()).toList()),
    );
  }

  Future<List<String>> loadSelectedSiteNames() async {
    final raw = PrefsManager.instance.getString(_selectedSitesKey);
    if (raw == null || raw.isEmpty) return const ['Default'];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map((entry) => entry.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveSelectedSiteNames(List<String> names) async {
    await PrefsManager.instance.setString(_selectedSitesKey, jsonEncode(names));
  }

  bool get isAutoUploadEnabledSync {
    return PrefsManager.instance.getBool(_autoUploadKey) ?? false;
  }

  Future<void> setAutoUploadEnabled(bool enabled) async {
    await PrefsManager.instance.setBool(_autoUploadKey, enabled);
  }

  Future<Map<String, WardriveUploadResult>> uploadToSelectedSites({
    Map<String, String>? repeaterNames,
    void Function(String siteName, int current, int total)? onProgress,
  }) async {
    return _uploadToSelectedSites(
      repeaterNames: repeaterNames,
      onProgress: onProgress,
    );
  }

  Future<Map<String, WardriveUploadResult>> uploadNextBatchToSelectedSites({
    Map<String, String>? repeaterNames,
  }) async {
    return _uploadToSelectedSites(
      repeaterNames: repeaterNames,
      maxSamplesPerSite: _batchSize,
    );
  }

  Future<Map<String, WardriveUploadResult>> _uploadToSelectedSites({
    Map<String, String>? repeaterNames,
    void Function(String siteName, int current, int total)? onProgress,
    int? maxSamplesPerSite,
  }) async {
    if (_uploadInProgress) {
      return {
        'Upload': const WardriveUploadResult(
          success: false,
          message: 'Upload already in progress',
        ),
      };
    }
    _uploadInProgress = true;
    try {
      return await _uploadToSelectedSitesUnlocked(
        repeaterNames: repeaterNames,
        onProgress: onProgress,
        maxSamplesPerSite: maxSamplesPerSite,
      );
    } finally {
      _uploadInProgress = false;
    }
  }

  Future<Map<String, WardriveUploadResult>> _uploadToSelectedSitesUnlocked({
    Map<String, String>? repeaterNames,
    void Function(String siteName, int current, int total)? onProgress,
    int? maxSamplesPerSite,
  }) async {
    final sites = await loadSites();
    final selectedNames = await loadSelectedSiteNames();
    final selectedSites = sites
        .where((site) => selectedNames.contains(site.name))
        .toList();
    if (selectedSites.isEmpty) {
      return {
        'Upload': const WardriveUploadResult(
          success: false,
          message: 'No upload sites selected',
        ),
      };
    }

    final results = <String, WardriveUploadResult>{};
    for (final site in selectedSites) {
      results[site.name] = await _uploadToSite(
        site,
        repeaterNames: repeaterNames,
        onProgress: onProgress,
        maxSamples: maxSamplesPerSite,
      );
    }
    return results;
  }

  Future<WardriveUploadResult> _uploadToSite(
    WardriveUploadSite site, {
    Map<String, String>? repeaterNames,
    void Function(String siteName, int current, int total)? onProgress,
    int? maxSamples,
  }) async {
    final allSamples = _sampleStore.loadAllSamples();
    final uploadedIds = _loadUploadedSampleIds(site.url);
    final samples = allSamples
        .where((sample) => sample.pingSuccess != null)
        .where((sample) => !uploadedIds.contains(sample.id))
        .take(maxSamples ?? allSamples.length)
        .toList();

    if (samples.isEmpty) {
      return const WardriveUploadResult(
        success: true,
        message: 'No new samples to upload',
      );
    }

    final batches = <List<WardriveSample>>[];
    for (var i = 0; i < samples.length; i += _batchSize) {
      final end = i + _batchSize < samples.length
          ? i + _batchSize
          : samples.length;
      batches.add(samples.sublist(i, end));
    }

    var totalCells = 0;
    for (var i = 0; i < batches.length; i++) {
      onProgress?.call(site.name, i + 1, batches.length);
      final batch = batches[i];
      final result = await _postBatch(
        site.url,
        batch,
        repeaterNames: repeaterNames,
      );
      if (!result.success) {
        return WardriveUploadResult(
          success: false,
          message:
              'Failed at batch ${i + 1}/${batches.length}: ${result.message}',
        );
      }
      totalCells = result.totalCount ?? totalCells;
    }

    await _markUploaded(site.url, samples.map((sample) => sample.id));
    return WardriveUploadResult(
      success: true,
      message: 'Upload Complete',
      uploadedCount: samples.length,
      totalCount: totalCells,
    );
  }

  Future<WardriveUploadResult> _postBatch(
    String url,
    List<WardriveSample> samples, {
    Map<String, String>? repeaterNames,
  }) async {
    final appVersion = await _loadAppVersion();
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http
            .post(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'samples': samples
                    .map(
                      (sample) => _sampleToUploadJson(
                        sample,
                        repeaterNames: repeaterNames,
                        appVersion: appVersion,
                      ),
                    )
                    .toList(),
              }),
            )
            .timeout(const Duration(seconds: 60));

        if (response.statusCode == 200) {
          final decoded = response.body.isEmpty
              ? null
              : jsonDecode(response.body);
          return WardriveUploadResult(
            success: true,
            message: 'OK',
            totalCount: decoded is Map
                ? (decoded['totalCells'] as num?)?.toInt()
                : null,
          );
        }
        lastError = 'Server error: ${response.statusCode}';
      } catch (error) {
        lastError = error;
      }

      if (attempt == 0) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }

    return WardriveUploadResult(
      success: false,
      message: lastError?.toString() ?? 'Unknown upload error',
    );
  }

  Map<String, Object?> _sampleToUploadJson(
    WardriveSample sample, {
    Map<String, String>? repeaterNames,
    required String appVersion,
  }) {
    final nodeId = (sample.path == null || sample.path!.isEmpty)
        ? 'Unknown'
        : sample.path!.toUpperCase();
    final repeaterName = repeaterNames?[nodeId] ?? nodeId;
    return {
      'id': sample.id,
      'nodeId': nodeId,
      'repeaterName': repeaterName,
      'latitude': sample.latitude,
      'longitude': sample.longitude,
      'rssi': sample.rssi,
      'snr': sample.snr,
      'pingSuccess': sample.pingSuccess,
      'timestamp': sample.timestamp.toIso8601String(),
      'appVersion': appVersion,
      if (sample.source != null) 'source': sample.source,
    };
  }

  Future<String> _loadAppVersion() async {
    final cached = _appVersion;
    if (cached != null) return cached;
    final info = await PackageInfo.fromPlatform();
    // Original wardrive sends an appVersion string with every uploaded sample.
    _appVersion = info.version;
    return _appVersion!;
  }

  Set<String> _loadUploadedSampleIds(String endpointUrl) {
    final allMarks = _loadUploadedMarks();
    return allMarks[endpointUrl]?.toSet() ?? <String>{};
  }

  Future<void> _markUploaded(String endpointUrl, Iterable<String> ids) async {
    final allMarks = _loadUploadedMarks();
    final nextIds = {...?allMarks[endpointUrl], ...ids}.toList();
    allMarks[endpointUrl] = nextIds;
    await PrefsManager.instance.setString(
      _uploadedSamplesKey,
      jsonEncode(allMarks),
    );
  }

  Map<String, List<String>> _loadUploadedMarks() {
    final raw = PrefsManager.instance.getString(_uploadedSamplesKey);
    if (raw == null || raw.isEmpty) return <String, List<String>>{};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, List<String>>{};
      return decoded.map((key, value) {
        final ids = value is List
            ? value.map((entry) => entry.toString()).toList()
            : <String>[];
        return MapEntry(key.toString(), ids);
      });
    } catch (_) {
      return <String, List<String>>{};
    }
  }
}

class WardriveUploadSite {
  final String name;
  final String url;

  const WardriveUploadSite({required this.name, required this.url});

  Map<String, Object?> toJson() => {'name': name, 'url': url};

  static WardriveUploadSite? fromJson(Map<String, Object?> json) {
    final name = json['name']?.toString().trim();
    final url = json['url']?.toString().trim();
    if (name == null || name.isEmpty || url == null || url.isEmpty) {
      return null;
    }
    return WardriveUploadSite(name: name, url: url);
  }
}

class WardriveUploadResult {
  final bool success;
  final String message;
  final int? uploadedCount;
  final int? totalCount;

  const WardriveUploadResult({
    required this.success,
    required this.message,
    this.uploadedCount,
    this.totalCount,
  });
}
