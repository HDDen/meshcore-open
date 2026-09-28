import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter_cache_manager/flutter_cache_manager.dart'
    show CacheInfoRepository, CacheObject;
import 'package:path_provider/path_provider.dart';

/// Whether this build keeps the map tile records in a database of its own.
///
/// flutter_cache_manager keeps them in sqflite on Android, iOS and macOS and
/// in one JSON file everywhere else, which it decodes whole at startup and
/// rewrites whole on every change: 30 MB and 370 ms a write at 66 thousand
/// tiles. The database replaces the JSON file only; the sqflite platforms
/// have an indexed store already and keep it.
bool get mapTileCacheUsesDatabase =>
    !kIsWeb && !(Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

/// What moving the JSON index into the database did.
class MapTileCacheImportResult {
  const MapTileCacheImportResult({
    required this.records,
    required this.added,
    required this.skipped,
    this.quarantinedPath,
  });

  /// No index file was there to move.
  const MapTileCacheImportResult.nothing()
    : records = 0,
      added = 0,
      skipped = 0,
      quarantinedPath = null;

  /// Records the file held and the move handed to the table.
  final int records;

  /// Rows the table gained; a key already in the table keeps its row.
  final int added;

  /// Elements of the file that were not records.
  final int skipped;

  /// Where a file that would not decode was renamed to, or null.
  final String? quarantinedPath;

  bool get fileWasCorrupt => quarantinedPath != null;
}

typedef _LegacyTileRecord = ({
  String url,
  String key,
  String relativePath,
  String? eTag,
  int validTillMs,
  int touchedMs,
  int? length,
});

typedef _DecodedLegacyIndex = ({
  List<_LegacyTileRecord> records,
  int skipped,
  bool corrupt,
});

/// Reads and decodes the JSON index in a background isolate: the file is
/// tens of megabytes and `jsonDecode` alone takes a fifth of a second.
/// An element that is not a record is skipped; a file that is not a JSON
/// list is reported as corrupt rather than thrown, so nothing has to cross
/// the isolate boundary as an error.
_DecodedLegacyIndex _decodeLegacyIndex(String path) {
  final Object? decoded;
  try {
    decoded = jsonDecode(File(path).readAsStringSync());
  } on FormatException {
    return (records: const [], skipped: 0, corrupt: true);
  }
  if (decoded is! List) {
    return (records: const [], skipped: 0, corrupt: true);
  }
  final records = <_LegacyTileRecord>[];
  var skipped = 0;
  for (final element in decoded) {
    try {
      final map = element as Map<String, dynamic>;
      final url = map[CacheObject.columnUrl] as String;
      records.add((
        url: url,
        key: map[CacheObject.columnKey] as String? ?? url,
        relativePath: map[CacheObject.columnPath] as String,
        eTag: map[CacheObject.columnETag] as String?,
        validTillMs: map[CacheObject.columnValidTill] as int,
        touchedMs: map[CacheObject.columnTouched] as int? ?? 0,
        length: map[CacheObject.columnLength] as int?,
      ));
    } catch (_) {
      // A TypeError from a field of the wrong type, or a missing one: the
      // element is not a record, and one bad element costs one record.
      skipped++;
    }
  }
  return (records: records, skipped: skipped, corrupt: false);
}

/// The map tile records on Windows and Linux: `map_tile_cache.sqlite` in the
/// application support directory, next to the JSON index it replaces and to
/// the message-history database, but a file of its own, so that the churn
/// of a cache never grows the history database or its vacuum.
///
/// One table, `tile_records`, with the columns of a [CacheObject]; the whole
/// schema is `CREATE TABLE IF NOT EXISTS`, so there is no generated code and
/// no table list. The [MapTileCacheRepository] below is its only client.
class MapTileCacheDatabase extends GeneratedDatabase {
  MapTileCacheDatabase()
    : super(
        driftDatabase(
          name: databaseName,
          native: DriftNativeOptions(
            databaseDirectory: getApplicationSupportDirectory,
            // A cache, so the write-ahead log with synchronous NORMAL:
            // CacheStore writes a record's touch time as a transaction of
            // its own at every first access of a tile in a session, and
            // with the rollback journal each of those cost an fsync, 15 ms
            // measured, against 0.2 ms in the log. A power cut can lose the
            // last commits and nothing else. The closure runs in the
            // database isolate and captures nothing on purpose.
            setup: (db) {
              db.execute('PRAGMA journal_mode = WAL');
              db.execute('PRAGMA synchronous = NORMAL');
              // The log is reused after a checkpoint, never shrunk by
              // itself; this cuts it back to the auto-checkpoint size once
              // it has grown past it, which only the one-time move does.
              db.execute('PRAGMA journal_size_limit = 4194304');
            },
          ),
        ),
      );

  /// A database over any executor, for tests: an in-memory one, or a file
  /// under a temporary directory.
  MapTileCacheDatabase.withExecutor(super.executor);

  static const String databaseName = 'map_tile_cache';
  static const String databaseFileName = '$databaseName.sqlite';

  /// The index flutter_cache_manager wrote before the database existed:
  /// `<cacheKey>.json` in the application support directory.
  static const String legacyIndexFileName = 'map_tile_cache.json';

  static const String _columns =
      'id, url, key, relative_path, e_tag, valid_till_ms, touched_ms, length';

  static const String _insertSql = '''
INSERT INTO tile_records
  (url, key, relative_path, e_tag, valid_till_ms, touched_ms, length)
VALUES (?, ?, ?, ?, ?, ?, ?)
''';

  static const String _insertIgnoreSql = '''
INSERT INTO tile_records
  (url, key, relative_path, e_tag, valid_till_ms, touched_ms, length)
VALUES (?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(key) DO NOTHING
''';

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) => _ensureTable(),
    beforeOpen: (_) => _ensureTable(),
  );

  Future<void> _ensureTable() async {
    await customStatement('''
CREATE TABLE IF NOT EXISTS tile_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  url TEXT NOT NULL,
  key TEXT NOT NULL,
  relative_path TEXT NOT NULL,
  e_tag TEXT NULL,
  valid_till_ms INTEGER NOT NULL,
  touched_ms INTEGER NOT NULL,
  length INTEGER NULL
)
''');
    await customStatement('''
CREATE UNIQUE INDEX IF NOT EXISTS tile_records_key ON tile_records (key)
''');
    await customStatement('''
CREATE INDEX IF NOT EXISTS tile_records_touched ON tile_records (touched_ms)
''');
  }

  static List<Variable<Object>> _variablesOf(Map<String, dynamic> map) => [
    Variable<String>(map[CacheObject.columnUrl] as String),
    Variable<String>(map[CacheObject.columnKey] as String),
    Variable<String>(map[CacheObject.columnPath] as String),
    Variable<String>(map[CacheObject.columnETag] as String?),
    Variable<int>(map[CacheObject.columnValidTill] as int),
    Variable<int>(map[CacheObject.columnTouched] as int),
    Variable<int>(map[CacheObject.columnLength] as int?),
  ];

  static CacheObject _objectOf(QueryRow row) => CacheObject(
    row.read<String>('url'),
    key: row.read<String>('key'),
    id: row.read<int>('id'),
    relativePath: row.read<String>('relative_path'),
    validTill: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('valid_till_ms'),
    ),
    touched: DateTime.fromMillisecondsSinceEpoch(row.read<int>('touched_ms')),
    eTag: row.readNullable<String>('e_tag'),
    length: row.readNullable<int>('length'),
  );

  Future<CacheObject?> findRecord(String key) async {
    final row = await customSelect(
      'SELECT $_columns FROM tile_records WHERE key = ?',
      variables: [Variable<String>(key)],
    ).getSingleOrNull();
    return row == null ? null : _objectOf(row);
  }

  Future<List<CacheObject>> allRecords() async {
    final rows = await customSelect(
      'SELECT $_columns FROM tile_records',
    ).get();
    return [for (final row in rows) _objectOf(row)];
  }

  Future<int> countRecords() async {
    final row = await customSelect(
      'SELECT COUNT(*) AS n FROM tile_records',
    ).getSingle();
    return row.read<int>('n');
  }

  /// Stores [record] under a fresh id and returns it as stored, id and
  /// touch time included; `CacheStore` keeps the id it is handed back.
  Future<CacheObject> insertRecord(
    CacheObject record, {
    required bool setTouchedToNow,
  }) async {
    final map = record.toMap(setTouchedToNow: setTouchedToNow);
    final id = await customInsert(_insertSql, variables: _variablesOf(map));
    return CacheObject.fromMap({...map, CacheObject.columnId: id});
  }

  Future<int> updateRecord(
    CacheObject record, {
    required bool setTouchedToNow,
  }) {
    final map = record.toMap(setTouchedToNow: setTouchedToNow);
    return customUpdate(
      '''
UPDATE tile_records
SET url = ?, key = ?, relative_path = ?, e_tag = ?, valid_till_ms = ?,
    touched_ms = ?, length = ?
WHERE id = ?
''',
      variables: [..._variablesOf(map), Variable<int>(record.id!)],
      updateKind: UpdateKind.update,
    );
  }

  Future<int> deleteRecords(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return 0;
    final removed = await transaction(() async {
      var deleted = 0;
      const chunkSize = 400;
      for (var offset = 0; offset < list.length; offset += chunkSize) {
        final end = offset + chunkSize < list.length
            ? offset + chunkSize
            : list.length;
        final chunk = list.sublist(offset, end);
        final placeholders = List.filled(chunk.length, '?').join(',');
        deleted += await customUpdate(
          'DELETE FROM tile_records WHERE id IN ($placeholders)',
          variables: [for (final id in chunk) Variable<int>(id)],
          updateKind: UpdateKind.delete,
        );
      }
      return deleted;
    });
    await _rebuildAfterDeleting(removed);
    return removed;
  }

  Future<int> clearRecords() async {
    final deleted = await customUpdate(
      'DELETE FROM tile_records',
      updateKind: UpdateKind.delete,
    );
    await _rebuildAfterDeleting(deleted);
    return deleted;
  }

  /// Rebuilds the file once a deletion has removed more records than it
  /// left. SQLite keeps the pages of deleted rows for its own reuse and
  /// never shrinks a file by itself, so the cache screen's clear left a
  /// 38 MB file with nothing in it. VACUUM copies the live rows, fewer than
  /// the deleted ones by then, into a new file, and the checkpoint folds
  /// the copy out of the log and cuts the file to its new size. The
  /// package's eviction of a hundred records from a full cache never gets
  /// here; its pages go to the tiles that come next. Runs after the
  /// deleting transaction, as VACUUM must, and a failure is logged and
  /// costs nothing but the space, since the records are already gone.
  Future<void> _rebuildAfterDeleting(int deleted) async {
    if (deleted == 0 || deleted <= await countRecords()) return;
    try {
      await customStatement('VACUUM');
      await customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (error, stackTrace) {
      developer.log(
        'The tile database was not rebuilt after a deletion: $error',
        name: 'MapTileCacheIndex',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// The least recently touched records beyond [capacity], a hundred at a
  /// time and only those untouched for a day, as the package's sqflite
  /// repository answers it. Counted first: at the cache's ceiling of two
  /// hundred thousand the offset alone would walk the whole index.
  Future<List<CacheObject>> recordsOverCapacity(int capacity) async {
    if (await countRecords() <= capacity) return const [];
    final rows = await customSelect(
      '''
SELECT $_columns FROM tile_records
WHERE touched_ms < ?
ORDER BY touched_ms DESC
LIMIT 100 OFFSET ?
''',
      variables: [
        Variable<int>(
          DateTime.now()
              .subtract(const Duration(days: 1))
              .millisecondsSinceEpoch,
        ),
        Variable<int>(capacity),
      ],
    ).get();
    return [for (final row in rows) _objectOf(row)];
  }

  /// Records untouched for longer than [maxAge], a hundred at a time.
  Future<List<CacheObject>> recordsOlderThan(Duration maxAge) async {
    final rows = await customSelect(
      'SELECT $_columns FROM tile_records WHERE touched_ms < ? LIMIT 100',
      variables: [
        Variable<int>(DateTime.now().subtract(maxAge).millisecondsSinceEpoch),
      ],
    ).get();
    return [for (final row in rows) _objectOf(row)];
  }

  /// Moves the JSON index at [index] into the table, once: every record in
  /// one transaction, a key already in the table keeping its row, and the
  /// file deleted only after the commit, so a move cut short runs again at
  /// the next launch. Ids are not carried over; the cache manager keeps
  /// them for a session only. A file that will not decode is renamed to
  /// `.corrupt-<time>` beside its place and nothing is imported: the
  /// package would have read it as empty and overwritten it at the first
  /// write, which is what made a corrupt index unrecoverable.
  Future<MapTileCacheImportResult> importLegacyIndex(File index) async {
    if (!await index.exists()) return const MapTileCacheImportResult.nothing();
    final decoded = await compute(_decodeLegacyIndex, index.path);
    if (decoded.corrupt) {
      final quarantined =
          '${index.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}';
      await index.rename(quarantined);
      return MapTileCacheImportResult(
        records: 0,
        added: 0,
        skipped: 0,
        quarantinedPath: quarantined,
      );
    }
    final before = await countRecords();
    await batch((batch) {
      for (final record in decoded.records) {
        batch.customStatement(_insertIgnoreSql, [
          record.url,
          record.key,
          record.relativePath,
          record.eTag,
          record.validTillMs,
          record.touchedMs,
          record.length,
        ]);
      }
    });
    final added = await countRecords() - before;
    // The move is one transaction the size of the index, and in WAL mode
    // that leaves a log as large as the database, reused but never shrunk
    // by itself: 39 MB on the first machine. A checkpoint with TRUNCATE
    // folds it into the file and cuts it to nothing; outside WAL it does
    // nothing at all.
    await customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    await index.delete();
    // The temporary file of an atomic write the package never finished.
    final temporary = File('${index.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
    return MapTileCacheImportResult(
      records: decoded.records.length,
      added: added,
      skipped: decoded.skipped,
    );
  }
}

/// The record repository flutter_cache_manager drives on Windows and Linux,
/// over [MapTileCacheDatabase]. It answers what the package's own sqflite
/// repository answers, so `CacheStore` sees no difference between the
/// platforms; the database is owned by whoever created it, and closing the
/// repository only counts connections, as the package's repositories do.
class MapTileCacheRepository implements CacheInfoRepository {
  MapTileCacheRepository(this._database, {this.sweepOrphanedFiles = true});

  /// Opens the database for this platform, moves the JSON index into it
  /// when one is still there, and returns the repository, or null where the
  /// package's own repository is the right one: on Android, iOS, macOS and
  /// the web, and when the database cannot be opened or the move fails, in
  /// which case the index file stays where it was and the package reads it
  /// as before. [onImportStarted] runs before a move, which takes a moment
  /// at tens of thousands of tiles, so the caller can put up a notice.
  static Future<MapTileCacheRepository?> openForThisPlatform({
    Future<void> Function()? onImportStarted,
    // Tests: a database over an in-memory or temporary-file executor, the
    // directory the index file is looked for in, and the platform answer.
    MapTileCacheDatabase Function()? databaseFactory,
    Future<Directory> Function()? supportDirectory,
    bool? useDatabase,
  }) async {
    if (!(useDatabase ?? mapTileCacheUsesDatabase)) return null;
    final database = databaseFactory?.call() ?? MapTileCacheDatabase();
    try {
      final directory =
          await (supportDirectory ?? getApplicationSupportDirectory)();
      final index = File(
        '${directory.path}${Platform.pathSeparator}'
        '${MapTileCacheDatabase.legacyIndexFileName}',
      );
      var sweepOrphanedFiles = true;
      if (await index.exists()) {
        await onImportStarted?.call();
        final result = await database.importLegacyIndex(index);
        // The sweep deletes every file no record names. It stays off for
        // the session that moved the records, in case the move missed one,
        // and for the session that found no records to move at all.
        sweepOrphanedFiles = false;
        final String message;
        if (result.fileWasCorrupt) {
          message =
              'The map tile index would not decode and was set aside as '
              '${result.quarantinedPath}';
        } else {
          final skipped = result.skipped > 0
              ? ', skipped ${result.skipped} unreadable elements'
              : '';
          message =
              'Moved ${result.records} map tile records into the database, '
              '${result.added} new$skipped';
        }
        developer.log(message, name: 'MapTileCacheIndex');
      } else {
        // Fail here rather than under the map, so the fallback below
        // applies: a database that cannot open leaves the index in place.
        await database.countRecords();
      }
      // The app never closes this database, so a session leaves its log
      // behind, recovered at the next open but kept at the size of the
      // largest transaction it ever held. Folding it now, before the map
      // reads anything, cuts it to nothing at every launch.
      await database.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
      return MapTileCacheRepository(
        database,
        sweepOrphanedFiles: sweepOrphanedFiles,
      );
    } catch (error, stackTrace) {
      developer.log(
        'The map tile index stays in its JSON file for now: $error',
        name: 'MapTileCacheIndex',
        error: error,
        stackTrace: stackTrace,
      );
      try {
        await database.close();
      } catch (_) {
        // A database that never opened has nothing to close.
      }
      return null;
    }
  }

  final MapTileCacheDatabase _database;

  /// Whether the inventory may delete the files no record names this
  /// session; false right after the JSON index was moved.
  final bool sweepOrphanedFiles;

  int _connections = 0;

  MapTileCacheDatabase get database => _database;

  @override
  Future<bool> open() async {
    _connections++;
    return true;
  }

  @override
  Future<bool> close() async {
    if (_connections > 0) _connections--;
    return _connections == 0;
  }

  @override
  Future<bool> exists() async => true;

  @override
  Future<void> deleteDataFile() => _database.clearRecords();

  @override
  Future<CacheObject?> get(String key) => _database.findRecord(key);

  @override
  Future<List<CacheObject>> getAllObjects() => _database.allRecords();

  @override
  Future<CacheObject> insert(
    CacheObject cacheObject, {
    bool setTouchedToNow = true,
  }) {
    if (cacheObject.id != null) {
      throw ArgumentError("Inserted objects shouldn't have an existing id.");
    }
    return _database.insertRecord(
      cacheObject,
      setTouchedToNow: setTouchedToNow,
    );
  }

  @override
  Future<int> update(CacheObject cacheObject, {bool setTouchedToNow = true}) {
    if (cacheObject.id == null) {
      throw ArgumentError('Updated objects should have an existing id.');
    }
    return _database.updateRecord(
      cacheObject,
      setTouchedToNow: setTouchedToNow,
    );
  }

  @override
  Future<dynamic> updateOrInsert(CacheObject cacheObject) {
    return cacheObject.id == null ? insert(cacheObject) : update(cacheObject);
  }

  @override
  Future<int> delete(int id) => _database.deleteRecords([id]);

  @override
  Future<int> deleteAll(Iterable<int> ids) => _database.deleteRecords(ids);

  @override
  Future<List<CacheObject>> getObjectsOverCapacity(int capacity) =>
      _database.recordsOverCapacity(capacity);

  @override
  Future<List<CacheObject>> getOldObjects(Duration maxAge) =>
      _database.recordsOlderThan(maxAge);
}
