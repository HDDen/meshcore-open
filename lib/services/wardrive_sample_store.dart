import 'dart:convert';

import '../models/wardrive_sample.dart';
import '../storage/message_history_database.dart' show WardriveSampleRow;
import '../storage/message_history_storage.dart';
import '../storage/prefs_manager.dart';
import 'wardrive_ignore_store.dart';

export '../models/wardrive_sample.dart';

/// Wardrive samples, sessions and the record of what was uploaded where.
///
/// Kept in the message-history database (the auxiliary tables
/// `wardrive_samples`, `wardrive_sessions` and `wardrive_uploads`) wherever
/// that database exists. The web build and a process that never opened it
/// (a unit test) keep the three preference keys the store always used, and
/// `MessageHistoryStorage.initializeAndMigrate` carries those keys over once.
/// Every method is asynchronous, the database living on its own isolate.
///
/// In the database samples are ordered newest first by their own timestamp;
/// the preference list keeps its insertion order, as it always did. At most
/// [maxSamples] are kept, the oldest going as new ones arrive. An upload
/// record dies with its sample: a sample that is gone cannot be uploaded
/// again, so nothing is kept about it.
class WardriveSampleStore {
  static const String _samplesKey = 'wardrive_samples_v1';
  static const String _sessionsKey = 'wardrive_sessions_v1';
  static const String _uploadedSamplesKey = 'wardrive_uploaded_samples_v1';
  static const String _exportFormat = 'meshcore_wardrive_data';
  static const int maxSamples = MessageHistoryStorage.wardriveSampleLimit;
  static const int maxSessions = MessageHistoryStorage.wardriveSessionLimit;

  bool get _usesDatabase => MessageHistoryStorage.instance.hasDatabase;

  static WardriveSampleRow rowOf(WardriveSample sample) => (
    id: sample.id,
    timestampMs: sample.timestamp.millisecondsSinceEpoch,
    publicKeyHex: sample.publicKeyHex,
    pingSuccess: sample.pingSuccess,
    sampleJson: jsonEncode(sample.toStorageJson()),
  );

  /// Stores [sample]. False when the database already holds a sample with
  /// that id (two nodes answering one discovery in the same millisecond at
  /// the same spot share one); the preference form keeps every one.
  Future<bool> add(WardriveSample sample) async {
    if (_usesDatabase) {
      return MessageHistoryStorage.instance.insertWardriveSample(
        rowOf(sample),
        cap: maxSamples,
      );
    }
    final prefs = PrefsManager.instance;
    final samples = prefs.getStringList(_samplesKey) ?? const <String>[];
    final nextSamples = <String>[
      _encodeSample(sample),
      ...samples.take(maxSamples - 1),
    ];
    await prefs.setStringList(_samplesKey, nextSamples);
    return true;
  }

  Future<List<WardriveSample>> loadRecent({int limit = 100}) async {
    if (_usesDatabase) {
      final rows = await MessageHistoryStorage.instance.readWardriveSamples(
        limit: limit,
      );
      return rows.map(_decodeSample).whereType<WardriveSample>().toList();
    }
    final samples = PrefsManager.instance.getStringList(_samplesKey) ?? [];
    return samples
        .take(limit)
        .map(_decodeSample)
        .whereType<WardriveSample>()
        .toList();
  }

  Future<List<WardriveSample>> loadAllSamples() =>
      loadRecent(limit: maxSamples);

  Future<int> count() async {
    if (_usesDatabase) {
      return MessageHistoryStorage.instance.countWardriveSamples();
    }
    return PrefsManager.instance.getStringList(_samplesKey)?.length ?? 0;
  }

  Future<int> removeWhere(bool Function(WardriveSample sample) test) async {
    final samples = await loadAllSamples();
    final removedIds = <String>[];
    final remaining = <WardriveSample>[];
    for (final sample in samples) {
      if (test(sample)) {
        removedIds.add(sample.id);
      } else {
        remaining.add(sample);
      }
    }
    if (removedIds.isEmpty) return 0;

    if (_usesDatabase) {
      await MessageHistoryStorage.instance.deleteWardriveSamples(removedIds);
      return removedIds.length;
    }
    await PrefsManager.instance.setStringList(
      _samplesKey,
      remaining.map(_encodeSample).toList(),
    );
    await _prunePreferenceMarks(remaining.map((sample) => sample.id).toSet());
    return removedIds.length;
  }

  Future<String> exportJson({
    WardriveSession? activeSession,
    Set<String> ignoredRepeaterKeys = const <String>{},
  }) async {
    final sessions = await loadSessions();
    if (activeSession != null &&
        !sessions.any(
          (session) => session.startTime == activeSession.startTime,
        )) {
      sessions.insert(0, activeSession);
    }
    final samples = await loadAllSamples();

    return const JsonEncoder.withIndent('  ').convert({
      '_format': _exportFormat,
      '_version': 1,
      'samples': samples
          .where(
            (sample) => !WardriveIgnoreStore.containsMatchingKey(
              ignoredRepeaterKeys,
              sample.publicKeyHex,
            ),
          )
          .map((sample) => sample.toJson())
          .toList(),
      'sessions': sessions.map((session) => session.toJson()).toList(),
    });
  }

  /// Adds the samples of [rawJson] that are not there yet (by id, a file
  /// naming one twice counting once) and its sessions (by start time), and
  /// returns how many samples were added.
  Future<int> importJson(String rawJson) async {
    final importedSamples = _decodeImport(rawJson);
    await _importSessions(rawJson: rawJson);
    if (importedSamples.isEmpty) return 0;

    if (_usesDatabase) {
      final rows = <String, WardriveSampleRow>{};
      for (final sample in importedSamples) {
        rows.putIfAbsent(sample.id, () => rowOf(sample));
      }
      return MessageHistoryStorage.instance.importWardriveSamples(
        rows.values.toList(),
        cap: maxSamples,
      );
    }

    final prefs = PrefsManager.instance;
    final existingSamples = await loadAllSamples();
    final knownKeys = existingSamples.map((sample) => sample.id).toSet();
    final merged = <WardriveSample>[];
    var added = 0;
    for (final sample in importedSamples) {
      if (knownKeys.add(sample.id)) {
        merged.add(sample);
        added++;
      }
    }
    merged.addAll(existingSamples);
    await prefs.setStringList(
      _samplesKey,
      merged.take(maxSamples).map(_encodeSample).toList(),
    );
    return added;
  }

  /// Forgets every sample, session and upload record. The ignore list is
  /// not data about samples and stays.
  Future<void> clear() async {
    if (_usesDatabase) {
      await MessageHistoryStorage.instance.clearWardriveData();
      return;
    }
    final prefs = PrefsManager.instance;
    await prefs.remove(_samplesKey);
    await prefs.remove(_sessionsKey);
    await prefs.remove(_uploadedSamplesKey);
  }

  Future<void> addSession(WardriveSession session) async {
    if (_usesDatabase) {
      await MessageHistoryStorage.instance.insertWardriveSession(
        startTimeMs: session.startTime.millisecondsSinceEpoch,
        sessionJson: jsonEncode(session.toJson()),
        cap: maxSessions,
      );
      return;
    }
    final prefs = PrefsManager.instance;
    final sessions = prefs.getStringList(_sessionsKey) ?? const <String>[];
    final nextSessions = <String>[
      jsonEncode(session.toJson()),
      ...sessions.take(maxSessions - 1),
    ];
    await prefs.setStringList(_sessionsKey, nextSessions);
  }

  Future<List<WardriveSession>> loadSessions() async {
    if (_usesDatabase) {
      final rows = await MessageHistoryStorage.instance.readWardriveSessions();
      return rows.map(_decodeSession).whereType<WardriveSession>().toList();
    }
    final sessions = PrefsManager.instance.getStringList(_sessionsKey) ?? [];
    return sessions.map(_decodeSession).whereType<WardriveSession>().toList();
  }

  /// The newest samples that carry a reading (`pingSuccess` set) and were
  /// not uploaded to [endpointUrl] yet, at most [limit] of them, the ignore
  /// list applied. With [includeUploaded] the upload records are ignored.
  Future<List<WardriveSample>> pendingUpload({
    required String endpointUrl,
    int? limit,
    bool includeUploaded = false,
    Set<String> ignoredRepeaterKeys = const <String>{},
  }) async {
    final wanted = limit ?? maxSamples;
    if (wanted <= 0) return const [];
    bool ignored(WardriveSample sample) =>
        WardriveIgnoreStore.containsMatchingKey(
          ignoredRepeaterKeys,
          sample.publicKeyHex,
        );

    if (_usesDatabase) {
      // The query leaves out what has no reading and what was sent already;
      // ignored repeaters are a handful, so a page rarely comes up short.
      final result = <WardriveSample>[];
      const page = 200;
      var offset = 0;
      while (result.length < wanted) {
        final rows = await MessageHistoryStorage.instance
            .readWardrivePendingUploads(
              endpointUrl: endpointUrl,
              includeUploaded: includeUploaded,
              limit: page,
              offset: offset,
            );
        if (rows.isEmpty) break;
        offset += rows.length;
        for (final raw in rows) {
          final sample = _decodeSample(raw);
          if (sample == null || ignored(sample)) continue;
          result.add(sample);
          if (result.length == wanted) break;
        }
        if (rows.length < page) break;
      }
      return result;
    }

    final uploaded = includeUploaded
        ? const <String>{}
        : (_preferenceMarks()[endpointUrl]?.toSet() ?? <String>{});
    final samples = await loadAllSamples();
    return samples
        .where((sample) => sample.pingSuccess != null)
        .where((sample) => !ignored(sample))
        .where((sample) => !uploaded.contains(sample.id))
        .take(wanted)
        .toList();
  }

  /// Records that [sampleIds] reached [endpointUrl].
  Future<void> markUploaded(String endpointUrl, Iterable<String> sampleIds) async {
    if (_usesDatabase) {
      await MessageHistoryStorage.instance.markWardriveUploaded(
        endpointUrl: endpointUrl,
        sampleIds: sampleIds,
      );
      return;
    }
    final marks = _preferenceMarks();
    marks[endpointUrl] = {...?marks[endpointUrl], ...sampleIds}.toList();
    await PrefsManager.instance.setString(
      _uploadedSamplesKey,
      jsonEncode(marks),
    );
  }

  Map<String, List<String>> _preferenceMarks() {
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

  /// Drops the upload records of samples that are no longer stored. The
  /// preference form does this on a removal, not on the cap: reading the
  /// whole list for every sample at the cap would cost more than the few
  /// stale ids are worth, and the next removal catches them.
  Future<void> _prunePreferenceMarks(Set<String> liveIds) async {
    final marks = _preferenceMarks();
    if (marks.isEmpty) return;
    var changed = false;
    final pruned = <String, List<String>>{};
    for (final entry in marks.entries) {
      final kept = entry.value.where(liveIds.contains).toList();
      if (kept.length != entry.value.length) changed = true;
      if (kept.isNotEmpty) pruned[entry.key] = kept;
    }
    if (!changed) return;
    await PrefsManager.instance.setString(
      _uploadedSamplesKey,
      jsonEncode(pruned),
    );
  }

  List<WardriveSample> _decodeImport(String rawJson) {
    final decoded = jsonDecode(rawJson);
    final rawSamples = decoded is Map
        ? decoded['samples']
        : decoded is List
        ? decoded
        : null;
    if (rawSamples == null && decoded is Map && decoded['sessions'] is List) {
      return const <WardriveSample>[];
    }
    if (rawSamples is! List) {
      throw const FormatException('Wardrive samples JSON is invalid');
    }

    return rawSamples
        .whereType<Map>()
        .map(
          (entry) => WardriveSample.fromJson(Map<String, Object?>.from(entry)),
        )
        .whereType<WardriveSample>()
        .toList();
  }

  Future<void> _importSessions({required String rawJson}) async {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map || decoded['sessions'] is! List) return;

    final incomingSessions = (decoded['sessions'] as List)
        .whereType<Map>()
        .map(
          (entry) => WardriveSession.fromJson(Map<String, Object?>.from(entry)),
        )
        .whereType<WardriveSession>()
        .toList();
    if (incomingSessions.isEmpty) return;

    if (_usesDatabase) {
      for (final session in incomingSessions) {
        await addSession(session);
      }
      return;
    }

    final existingSessions = await loadSessions();
    final knownStarts = existingSessions
        .map((session) => session.startTime.toIso8601String())
        .toSet();
    final merged = <WardriveSession>[];
    for (final session in incomingSessions) {
      if (knownStarts.add(session.startTime.toIso8601String())) {
        merged.add(session);
      }
    }
    merged.addAll(existingSessions);

    await PrefsManager.instance.setStringList(
      _sessionsKey,
      merged
          .take(maxSessions)
          .map((session) => jsonEncode(session.toJson()))
          .toList(),
    );
  }

  String _encodeSample(WardriveSample sample) =>
      jsonEncode(sample.toStorageJson());

  WardriveSample? _decodeSample(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return WardriveSample.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  WardriveSession? _decodeSession(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return WardriveSession.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return null;
    }
  }
}
