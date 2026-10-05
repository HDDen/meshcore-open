import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:sqlite3/sqlite3.dart';

import 'data_root_core.dart';

/// The suffix of a folder of the data folder while the transfer fills it;
/// renamed into place once everything is copied.
const String _partial = '.partial';

/// A transfer that failed; [message] is shown to the user.
class DataTransferException implements Exception {
  const DataTransferException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The system folders of an earlier installation on this machine, as the
/// platform's own path providers answer them. None of them is created:
/// the documents folder is only looked up, the rest are read from the
/// environment.
Future<LegacyDataLocations?> currentLegacyDataLocations() async {
  if (!Platform.isWindows && !Platform.isLinux) return null;
  final windows = Platform.isWindows;
  String? documents;
  try {
    documents = windows
        ? await PathProviderWindows().getApplicationDocumentsPath()
        : await PathProviderLinux().getApplicationDocumentsPath();
  } catch (_) {
    documents = null;
  }
  return legacyDataLocations(
    windows: windows,
    environment: Platform.environment,
    systemTemp: Directory.systemTemp.path,
    documents: documents,
    exists: (path) => Directory(path).existsSync(),
    context: p.context,
  );
}

/// The transfer to offer at this start, or null. It is offered when the
/// data folder is portable and new, after what a cut-short transfer left is
/// cleared, and the old support folder holds data. [legacy] stands in for
/// the system folders in tests.
Future<DataTransferOffer?> findDataTransferOffer({
  LegacyDataLocations? legacy,
}) async {
  final root = DataRoot.path;
  if (DataRoot.mode != DataRootMode.portable || root == null) return null;
  clearInterruptedTransfer(root);
  if (!isNewDataFolder(root)) return null;
  final from = legacy ?? await currentLegacyDataLocations();
  if (from == null || !_holdsData(from.support)) return null;
  return DataTransferOffer(
    target: root,
    legacy: from,
    sources: [
      from.support,
      if (from.cache case final cache? when Directory(cache).existsSync())
        cache,
      if (Directory(_tileFolder(from)).existsSync()) _tileFolder(from),
      for (final folder in _modelFolders(from))
        if (Directory(folder).existsSync()) folder,
    ],
    copiedBefore: _readCopiedMarker(from.support),
  );
}

/// Whether [root] is new: missing, or holding nothing but the lock and the
/// window size.
bool isNewDataFolder(String root) {
  final folder = Directory(root);
  if (!folder.existsSync()) return true;
  return folder
      .listSync(followLinks: false)
      .every(
        (entity) =>
            DataRoot.housekeepingFiles.contains(p.basename(entity.path)),
      );
}

/// Clears what a transfer cut short left in [root]: everything but the
/// housekeeping files. Safe because a transfer starts only in a new folder,
/// so all the rest is its own.
void clearInterruptedTransfer(String root) {
  if (readTransferState(root)?['state'] != 'copying') return;
  _clearDataFolder(root);
}

/// The transfer state of [root], or null where there is none.
Map<String, Object?>? readTransferState(String root) {
  try {
    final decoded = jsonDecode(
      File(p.join(root, DataRoot.transferStateFileName)).readAsStringSync(),
    );
    return decoded is Map<String, Object?> ? decoded : null;
  } on Object {
    return null;
  }
}

/// Counts the bytes the transfer would copy, in a background isolate: the
/// tile files alone can be tens of thousands.
Future<int> measureDataTransfer(DataTransferOffer offer) {
  final root = offer.target;
  final from = offer.legacy;
  return Isolate.run(() => _plan(root, from).bytes);
}

/// Copies the old data into the data folder in a background isolate,
/// reporting copied and total bytes. On failure the data folder is left
/// with its housekeeping files only, the old folders untouched, and a
/// [DataTransferException] is thrown.
Future<void> transferData(
  DataTransferOffer offer, {
  void Function(int copied, int total)? onProgress,
}) async {
  final messages = ReceivePort();
  final failures = ReceivePort();
  final finished = Completer<void>();
  void fail(String message) {
    if (!finished.isCompleted) {
      finished.completeError(DataTransferException(message));
    }
  }

  messages.listen((message) {
    if (message case (final int copied, final int total)) {
      onProgress?.call(copied, total);
    } else if (message is String) {
      fail(message);
    } else if (!finished.isCompleted) {
      finished.complete();
    }
  });
  failures.listen((error) => fail(error is List ? '${error.first}' : '$error'));
  try {
    await Isolate.spawn(
      _transferWorker,
      (root: offer.target, from: offer.legacy, port: messages.sendPort),
      onError: failures.sendPort,
    );
    await finished.future;
  } on DataTransferException {
    _clearDataFolder(offer.target);
    rethrow;
  } finally {
    messages.close();
    failures.close();
  }
}

typedef _TransferJob = ({
  String root,
  LegacyDataLocations from,
  SendPort port,
});

Future<void> _transferWorker(_TransferJob job) async {
  try {
    await _transfer(job.root, job.from, (copied, total) {
      job.port.send((copied, total));
    });
    job.port.send(null);
  } on Object catch (error) {
    try {
      _clearDataFolder(job.root);
    } on Object {
      // The next start clears what is left: the state still says copying.
    }
    job.port.send('$error');
  }
}

Future<void> _transfer(
  String root,
  LegacyDataLocations from,
  void Function(int copied, int total) report,
) async {
  final started = DateTime.now().toUtc();
  final sources = <String, Object?>{
    'support': from.support,
    'cache': from.cache,
    'temporary': from.temporary,
    'documents': from.documents,
  };
  _writeTransferState(root, {
    'version': 1,
    'state': 'copying',
    'started': started.toIso8601String(),
    'sources': sources,
  });
  Directory(
    p.join(root, '${DataRoot.supportFolder}$_partial'),
  ).createSync(recursive: true);

  final plan = _plan(root, from);
  final total = plan.bytes;
  var copied = 0;
  final sinceReport = Stopwatch()..start();
  void progress() {
    if (sinceReport.elapsedMilliseconds < 100) return;
    sinceReport.reset();
    report(copied, total);
  }

  report(0, total);
  for (final copy in plan.databases) {
    Directory(p.dirname(copy.target)).createSync(recursive: true);
    await _snapshot(copy.source, copy.target);
    copied += copy.bytes;
    progress();
  }
  for (final copy in plan.files) {
    Directory(p.dirname(copy.target)).createSync(recursive: true);
    File(copy.source).copySync(copy.target);
    copied += copy.bytes;
    progress();
  }
  report(total, total);

  // The support folder goes last: it is what makes the data folder used.
  for (final folder in [
    DataRoot.temporaryFolder,
    DataRoot.cacheFolder,
    DataRoot.documentsFolder,
    DataRoot.supportFolder,
  ]) {
    final partial = Directory(p.join(root, '$folder$_partial'));
    if (partial.existsSync()) partial.renameSync(p.join(root, folder));
  }
  _writeTransferState(root, {
    'version': 1,
    'state': 'done',
    'started': started.toIso8601String(),
    'finished': DateTime.now().toUtc().toIso8601String(),
    'sources': sources,
    'cleanup': 'pending',
  });
  _appendCopiedMarker(from.support, root);
}

class _Copy {
  const _Copy(this.source, this.target, this.bytes);

  final String source;
  final String target;
  final int bytes;
}

class _Plan {
  final List<_Copy> databases = [];
  final List<_Copy> files = [];

  int get bytes =>
      [...databases, ...files].fold(0, (total, copy) => total + copy.bytes);
}

_Plan _plan(String root, LegacyDataLocations from) {
  final plan = _Plan();
  final support = p.join(root, '${DataRoot.supportFolder}$_partial');
  _addFolder(plan, root, from.support, support, skip: _skippedInSupport);
  for (final name in LegacyData.databases) {
    final source = p.join(from.support, name);
    if (!File(source).existsSync()) continue;
    plan.databases.add(
      _Copy(
        source,
        p.join(support, name),
        _length(source) + _length('$source-wal'),
      ),
    );
  }
  final cache = from.cache;
  if (cache != null) {
    _addFolder(
      plan,
      root,
      cache,
      p.join(root, '${DataRoot.cacheFolder}$_partial'),
    );
  }
  final recorded = _recordedTiles(p.join(from.support, LegacyData.tileDatabase));
  _addFolder(
    plan,
    root,
    _tileFolder(from),
    p.join(root, '${DataRoot.temporaryFolder}$_partial', LegacyData.tileFolder),
    keep: recorded?.contains,
  );
  for (final folder in _modelFolders(from)) {
    _addFolder(
      plan,
      root,
      folder,
      p.join(root, '${DataRoot.documentsFolder}$_partial', p.basename(folder)),
    );
  }
  return plan;
}

/// Adds the files under [source] to [plan], to be copied under [target] at
/// the same relative path. Nothing inside the data folder [root] is taken,
/// in case it was made inside an old folder.
void _addFolder(
  _Plan plan,
  String root,
  String source,
  String target, {
  bool Function(String relative)? skip,
  bool Function(String relative)? keep,
}) {
  final folder = Directory(source);
  if (!folder.existsSync()) return;
  for (final entity in folder.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (p.equals(entity.path, root) || p.isWithin(root, entity.path)) continue;
    final relative = p.relative(entity.path, from: source);
    if (skip != null && skip(relative)) continue;
    if (keep != null && !keep(relative)) continue;
    plan.files.add(
      _Copy(entity.path, p.join(target, relative), _length(entity.path)),
    );
  }
}

/// What the support folder keeps out of the file-by-file copy: the marker,
/// the shared image cache index, a lock, and the databases with their logs,
/// which are copied as snapshots.
bool _skippedInSupport(String relative) {
  if (p.split(relative).length != 1) return false;
  if (relative == LegacyData.copiedMarkerFileName ||
      relative == LegacyData.sharedImageCacheIndex ||
      relative == DataRoot.lockFileName) {
    return true;
  }
  for (final database in LegacyData.databases) {
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      if (relative == '$database$suffix') return true;
    }
  }
  return false;
}

/// The tile files the old tile database names, or null when there is no
/// database to ask, and every file is copied.
Set<String>? _recordedTiles(String database) {
  if (!File(database).existsSync()) return null;
  try {
    final connection = sqlite3.open(database, mode: OpenMode.readOnly);
    try {
      return {
        for (final row in connection.select(
          'SELECT relative_path FROM tile_records',
        ))
          row['relative_path'] as String,
      };
    } finally {
      connection.close();
    }
  } on Object {
    return null;
  }
}

/// A consistent copy of [source] as of one moment, with whatever its log
/// still holds, even while another copy of the app writes to it.
Future<void> _snapshot(String source, String target) async {
  final from = sqlite3.open(source, mode: OpenMode.readOnly);
  try {
    final to = sqlite3.open(target);
    try {
      await from.backup(to, nPage: -1).drain<void>();
    } finally {
      to.close();
    }
  } finally {
    from.close();
  }
}

String _tileFolder(LegacyDataLocations from) =>
    p.join(from.temporary, LegacyData.tileFolder);

List<String> _modelFolders(LegacyDataLocations from) {
  final documents = from.documents;
  if (documents == null) return const [];
  return [for (final name in LegacyData.modelFolders) p.join(documents, name)];
}

bool _holdsData(String support) {
  final folder = Directory(support);
  if (!folder.existsSync()) return false;
  return folder
      .listSync(followLinks: false)
      .any(
        (entity) => p.basename(entity.path) != LegacyData.copiedMarkerFileName,
      );
}

int _length(String path) {
  try {
    return File(path).lengthSync();
  } on FileSystemException {
    return 0;
  }
}

void _clearDataFolder(String root) {
  final folder = Directory(root);
  if (!folder.existsSync()) return;
  for (final entity in folder.listSync(followLinks: false)) {
    if (DataRoot.housekeepingFiles.contains(p.basename(entity.path))) continue;
    entity.deleteSync(recursive: true);
  }
}

void _writeTransferState(String root, Map<String, Object?> state) {
  final file = File(p.join(root, DataRoot.transferStateFileName));
  final temporary = File('${file.path}.tmp');
  temporary.writeAsStringSync(jsonEncode(state), flush: true);
  temporary.renameSync(file.path);
}

List<DataTransferRecord> _readCopiedMarker(String support) {
  try {
    return parseCopiedMarker(
      File(
        p.join(support, LegacyData.copiedMarkerFileName),
      ).readAsStringSync(),
    );
  } on FileSystemException {
    return const [];
  }
}

/// Best effort: the copy is complete without it, and an old folder that
/// cannot be written to must not undo it.
void _appendCopiedMarker(String support, String root) {
  try {
    final marker = File(p.join(support, LegacyData.copiedMarkerFileName));
    final line = copiedMarkerLine(DateTime.now(), root);
    marker.writeAsStringSync(
      marker.existsSync() ? line : '$copiedMarkerHeader$line',
      mode: FileMode.append,
      flush: true,
    );
  } on FileSystemException {
    // Nothing to undo.
  }
}
