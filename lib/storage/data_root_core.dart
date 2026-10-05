import 'package:path/path.dart' as p;

/// Where this run keeps its data.
enum DataRootMode {
  /// Windows and Linux: a folder of the app's own, `userdata` next to the
  /// executable or the one `--data-dir` names, holding every directory the
  /// app writes to.
  portable,

  /// macOS, Android, iOS and the web: the system directories path_provider
  /// answers.
  system,
}

/// The data folder of this run and the arguments the app was started with,
/// recorded once at startup by `prepareDataRoot`.
abstract final class DataRoot {
  static const String argument = '--data-dir';
  static const String defaultFolderName = 'userdata';
  static const String lockFileName = 'profile.lock';

  /// The window size the Windows runner keeps, read before Dart starts.
  static const String windowStateFileName = 'window_state.txt';

  /// The state of the copy of an earlier installation's data.
  static const String transferStateFileName = 'migration.json';

  /// Files that do not make a data folder used: the lock and the window size
  /// are written before anyone is asked anything.
  static const Set<String> housekeepingFiles = {
    lockFileName,
    windowStateFileName,
  };

  /// The folders of a portable data folder, one per kind of directory the
  /// app asks path_provider for.
  static const String supportFolder = 'support';
  static const String cacheFolder = 'cache';
  static const String temporaryFolder = 'temp';
  static const String documentsFolder = 'documents';

  static DataRootMode mode = DataRootMode.system;

  /// The portable data folder; null in system mode.
  static String? path;

  /// What `main` received, `--data-dir` included, for a restart to hand on.
  static List<String> launchArguments = const [];

  static void resetForTesting() {
    mode = DataRootMode.system;
    path = null;
    launchArguments = const [];
  }
}

/// What the arguments and the executable's place say about the data folder.
class DataRootSelection {
  const DataRootSelection.system()
    : mode = DataRootMode.system,
      path = null,
      missingPath = false;

  const DataRootSelection.portable(String this.path)
    : mode = DataRootMode.portable,
      missingPath = false;

  /// `--data-dir` with nothing after it: the start stops rather than
  /// guessing which folder was meant.
  const DataRootSelection.missingPath()
    : mode = DataRootMode.portable,
      path = null,
      missingPath = true;

  final DataRootMode mode;
  final String? path;
  final bool missingPath;
}

/// The data folder for [args]. A relative `--data-dir` and the default
/// `userdata` count from the folder of [executablePath], not from the working
/// directory, so a shortcut or a terminal elsewhere opens the same folder.
/// [context] is the path style of the platform, handed in so both styles can
/// be tested anywhere. Where [portable] is false the app keeps the system
/// directories and the argument is ignored. The last `--data-dir` wins.
DataRootSelection selectDataRoot({
  required List<String> args,
  required String executablePath,
  required bool portable,
  required p.Context context,
}) {
  if (!portable) return const DataRootSelection.system();
  final appFolder = context.dirname(executablePath);
  String? given;
  for (final arg in args) {
    if (arg == DataRoot.argument) {
      given = '';
    } else if (arg.startsWith('${DataRoot.argument}=')) {
      given = arg.substring(DataRoot.argument.length + 1);
    }
  }
  if (given == null) {
    return DataRootSelection.portable(
      context.join(appFolder, DataRoot.defaultFolderName),
    );
  }
  var value = given.trim();
  // `--data-dir="C:\My Data\"` arrives as `C:\My Data"`, the closing
  // backslash read as an escape of the quote. No Windows name holds a quote.
  if (context.style == p.Style.windows) value = value.replaceAll('"', '');
  if (value.isEmpty) return const DataRootSelection.missingPath();
  return DataRootSelection.portable(
    context.normalize(
      context.isAbsolute(value) ? value : context.join(appFolder, value),
    ),
  );
}

/// How preparing the data folder ended.
sealed class DataRootOutcome {
  const DataRootOutcome();
}

final class DataRootReady extends DataRootOutcome {
  const DataRootReady();
}

/// The app cannot start on this data folder; [path] is shown to the user.
sealed class DataRootProblem extends DataRootOutcome {
  const DataRootProblem(this.path);

  final String path;
}

/// Another running copy of the app holds the folder's lock.
final class DataRootInUse extends DataRootProblem {
  const DataRootInUse(super.path);
}

/// The folder cannot be created or written to, or `--data-dir` named none
/// ([missingPath]).
final class DataRootUnavailable extends DataRootProblem {
  const DataRootUnavailable(super.path, {this.error, this.missingPath = false});

  final Object? error;
  final bool missingPath;
}

/// What the app left in the system folders before it had a data folder, and
/// how its copy into one is done. The names come from
/// `windows/runner/Runner.rc` (CompanyName, ProductName), from
/// `linux/CMakeLists.txt` (APPLICATION_ID, BINARY_NAME) and from the stores;
/// a test keeps them equal.
abstract final class LegacyData {
  static const String windowsCompany = 'com.meshcore';
  static const String windowsProduct = 'meshcore_open (Advanced mod)';
  static const String linuxApplicationId = 'com.monitormx.mcoadvanced';
  static const String linuxExecutableName = 'mco_advanced';

  /// Left in the old support folder by every copy: when, and where to.
  static const String copiedMarkerFileName = 'COPIED_TO_PORTABLE.txt';

  /// The index of flutter_cache_manager's default cache, whose files lie in
  /// the system temporary folder among those of every other Flutter app:
  /// neither is copied, and the link previews are fetched again.
  static const String sharedImageCacheIndex = 'libCachedImageData.json';

  /// Databases copied as a snapshot, not file by file: an earlier copy of the
  /// app may still have them open and be writing.
  static const List<String> databases = [
    'message_history.sqlite',
    'map_tile_cache.sqlite',
  ];

  /// The map tile files, in the temporary folder, and the database naming
  /// them: flutter_cache_manager before 3.4.2 left files no record named.
  static const String tileFolder = 'map_tile_cache';
  static const String tileDatabase = 'map_tile_cache.sqlite';

  static const List<String> modelFolders = [
    'image_codec_models',
    'translation_models',
  ];
}

/// The system folders an earlier installation kept its data in.
class LegacyDataLocations {
  const LegacyDataLocations({
    required this.support,
    required this.temporary,
    this.cache,
    this.documents,
  });

  final String support;
  final String temporary;
  final String? cache;
  final String? documents;
}

/// The folders the platform's path provider answered before the data
/// folder, from [environment] as that provider read it. [systemTemp] is the
/// Windows temporary folder, [documents] the user's documents folder, and
/// [exists] whether a folder is there: on Linux the plugin used a folder
/// named after the executable when the one named after the application id
/// was missing. Null when the environment names no home.
LegacyDataLocations? legacyDataLocations({
  required bool windows,
  required Map<String, String> environment,
  required String systemTemp,
  required String? documents,
  required bool Function(String path) exists,
  required p.Context context,
}) {
  String? variable(String name) {
    final value = environment[name];
    return value == null || value.isEmpty ? null : value;
  }

  if (windows) {
    final roaming = variable('APPDATA');
    if (roaming == null) return null;
    final local = variable('LOCALAPPDATA');
    return LegacyDataLocations(
      support: context.join(
        roaming,
        LegacyData.windowsCompany,
        LegacyData.windowsProduct,
      ),
      temporary: systemTemp,
      cache: local == null
          ? null
          : context.join(
              local,
              LegacyData.windowsCompany,
              LegacyData.windowsProduct,
            ),
      documents: documents,
    );
  }
  final home = variable('HOME');
  String? base(String name, List<String> fallback) =>
      variable(name) ??
      (home == null ? null : context.joinAll([home, ...fallback]));
  final dataHome = base('XDG_DATA_HOME', ['.local', 'share']);
  if (dataHome == null) return null;
  final byId = context.join(dataHome, LegacyData.linuxApplicationId);
  final byName = context.join(dataHome, LegacyData.linuxExecutableName);
  final cacheHome = base('XDG_CACHE_HOME', ['.cache']);
  return LegacyDataLocations(
    support: !exists(byId) && exists(byName) ? byName : byId,
    temporary: variable('TMPDIR') ?? '/tmp',
    cache: cacheHome == null
        ? null
        : context.join(cacheHome, LegacyData.linuxApplicationId),
    documents: documents,
  );
}

/// One earlier copy of the old data, as the marker records it.
class DataTransferRecord {
  const DataTransferRecord(this.at, this.target);

  final DateTime at;
  final String target;
}

/// The copy offered at this start: from [legacy] into the data folder
/// [target]. [sources] are the folders that exist, for the user to see.
class DataTransferOffer {
  const DataTransferOffer({
    required this.target,
    required this.legacy,
    required this.sources,
    this.copiedBefore = const [],
  });

  final String target;
  final LegacyDataLocations legacy;
  final List<String> sources;
  final List<DataTransferRecord> copiedBefore;
}

/// The marker's opening lines, written when the marker is created.
const String copiedMarkerHeader =
    '# The data in this folder was copied into the data folder of a '
    'portable copy of the app.\n'
    '# This folder can be deleted once that copy works. Removing this file '
    'makes new copies offer the transfer without the note below.\n'
    '# Copies made (UTC time, data folder):\n';

String copiedMarkerLine(DateTime at, String target) =>
    '${at.toUtc().toIso8601String()}\t$target\n';

/// The copies a marker records; lines it cannot read are skipped.
List<DataTransferRecord> parseCopiedMarker(String text) {
  final records = <DataTransferRecord>[];
  for (final line in text.split('\n')) {
    if (line.startsWith('#')) continue;
    final tab = line.indexOf('\t');
    if (tab < 0) continue;
    final at = DateTime.tryParse(line.substring(0, tab));
    final target = line.substring(tab + 1).trimRight();
    if (at == null || target.isEmpty) continue;
    records.add(DataTransferRecord(at, target));
  }
  return records;
}

/// The old data offered for deletion at a start after their copy.
class DataCleanupOffer {
  const DataCleanupOffer({
    required this.target,
    required this.folders,
    required this.copiedFolders,
  });

  /// The data folder the old data were copied into.
  final String target;

  /// Old folders named after the app, deleted whole.
  final List<String> folders;

  /// Old folders others may share, the tiles in the temporary folder and the
  /// models in the documents: only the files with a copy in the data folder
  /// go, and the folder with them when that empties it. Keys are the old
  /// folders, values their copies in the data folder.
  final Map<String, String> copiedFolders;

  /// Every old folder, for the user to see.
  List<String> get items => [...folders, ...copiedFolders.keys];
}
